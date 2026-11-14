"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import clsx from "clsx";
import { Check, Share2, Trophy } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useParams } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { Avatar } from "@/components/Avatar";
import { CommunityLogo, ContestTimeline, MyPhotoPicker, StarRating, StatusBadge } from "@/components/community";
import { Button, Notice, TextField, buttonClass } from "@/components/ui";
import { Link, usePathname, useRouter } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import { formatDateTime } from "@/lib/dates";
import { useMe } from "@/lib/hooks";
import type { Contest, Entry } from "@/lib/types";

const voterKey = (id: string) => `fg_voter_${id}`;

function readVoter(id: string) {
  try {
    return localStorage.getItem(voterKey(id));
  } catch {
    return null;
  }
}

export default function ContestPage() {
  const { id } = useParams<{ id: string }>();
  const t = useTranslations("contests");
  const locale = useLocale();
  const { data: me } = useMe();
  const q = useQuery({ queryKey: ["contest", id], queryFn: () => api<Contest>(`contests/${id}`) });

  if (q.error) return <div className="mx-auto max-w-[680px] px-4 py-20"><Notice tone="error">{q.error instanceof ApiError ? q.error.message : t("error")}</Notice></div>;
  const c = q.data;
  if (!c) return <div className="h-[70vh]" aria-busy />;

  return (
    <div className="mx-auto max-w-[1200px] px-4 pt-8 sm:px-6 sm:pt-12">
      <header className="max-w-[820px]">
        <Link href={`/c/${c.community.slug}`} className="inline-flex items-center gap-2.5 text-[15px] font-medium hover:underline">
          <CommunityLogo name={c.community.name} url={c.community.logo_url} size={28} />
          {c.community.name}
        </Link>
        <div className="mt-5 flex flex-wrap items-center gap-2">
          <StatusBadge status={c.status} />
          <span className="text-sm text-ink-muted">{t(`mode.${c.judging_mode}`)}</span>
          <span className="tnum text-sm text-ink-muted">· {t("entries_count", { count: c.entry_count })}</span>
        </div>
        <h1 className="mt-3 text-[clamp(2.2rem,5.5vw,4rem)] font-bold leading-[0.98] tracking-[-0.045em]">{c.title}</h1>
      </header>

      <div className="mt-8 grid gap-10 lg:grid-cols-[minmax(0,1fr)_340px]">
        <div className="min-w-0">
          <ContestTimeline c={c} />
          {c.my_role === "admin" && (
            <div className="mt-4">
              <Notice>
                {c.status === "draft" ? t("draft_notice") : t("admin_notice")}{" "}
                <Link href={`/contests/${c.id}/manage`} className="font-semibold text-ink underline underline-offset-4">{t("open_manage")}</Link>
              </Notice>
            </div>
          )}
          <div className="mt-8">
            {c.status === "open" && <EnterPanel c={c} />}
            {c.status === "judging" && c.judging_mode === "public" && <VotingPanel c={c} />}
            {c.status === "judging" && c.judging_mode === "jury" && <JuryWaiting c={c} />}
            {c.status === "closed" && <div className="bg-surface px-6 py-10"><p className="text-lg font-semibold">{t("closed_title")}</p><p className="mt-1 text-ink-muted">{t("closed_body", { date: formatDateTime(c.results_at, locale) })}</p></div>}
            {c.status === "finished" && <Results c={c} />}
          </div>
        </div>

        <aside className="flex flex-col gap-8 lg:sticky lg:top-24 lg:self-start">
          <ShareButton c={c} />
          {c.prizes.length > 0 && (
            <section>
              <h2 className="text-[15px] font-semibold">{t("prizes")}</h2>
              <ol className="mt-3 divide-y divide-line border-y border-line">
                {c.prizes.map((p) => (
                  <li key={p.rank} className="flex items-baseline gap-4 py-3">
                    <span className="tnum w-6 shrink-0 text-lg font-semibold">{p.rank}.</span>
                    <span className="text-[15px]">{p.title}</span>
                  </li>
                ))}
              </ol>
            </section>
          )}
          <section>
            <h2 className="text-[15px] font-semibold">{t("about")}</h2>
            <p className="mt-2 whitespace-pre-line text-[15px] leading-relaxed">{c.description}</p>
          </section>
          {c.rules && (
            <section>
              <h2 className="text-[15px] font-semibold">{t("rules")}</h2>
              <p className="mt-2 whitespace-pre-line text-[15px] leading-relaxed text-ink-muted">{c.rules}</p>
            </section>
          )}
          {me && c.is_judge && c.status === "judging" && (
            <Link href={`/contests/${c.id}/jury`} className={buttonClass("primary")}>{t("start_judging")}</Link>
          )}
        </aside>
      </div>
    </div>
  );
}

function ShareButton({ c }: { c: Contest }) {
  const t = useTranslations("contests");
  const [copied, setCopied] = useState(false);
  async function share() {
    if (navigator.share) {
      try {
        await navigator.share({ title: c.title, url: c.share_url });
        return;
      } catch {
        /* kullanıcı vazgeçti */
      }
    }
    await navigator.clipboard.writeText(c.share_url);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }
  return (
    <Button variant="secondary" onClick={share} className="self-start">
      {copied ? <Check className="h-4 w-4" /> : <Share2 className="h-4 w-4" />}
      {copied ? t("link_copied") : c.status === "judging" && c.judging_mode === "public" ? t("share_vote") : t("share")}
    </Button>
  );
}

function EntryImage({ e, className }: { e: Entry; className?: string }) {
  const img = e.images.feed ?? e.images.full ?? e.images.thumb;
  if (!img) return null;
  return (
    <span className={clsx("print-placeholder block", className)} style={{ aspectRatio: `${img.width} / ${img.height}` }}>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={img.url} alt={e.title ?? ""} loading="lazy" className="fade-in block h-full w-full" />
    </span>
  );
}

function EnterPanel({ c }: { c: Contest }) {
  const t = useTranslations("contests");
  const { data: me } = useMe();
  const router = useRouter();
  const pathname = usePathname();
  const qc = useQueryClient();
  const [picker, setPicker] = useState(false);
  const refresh = () => qc.invalidateQueries({ queryKey: ["contest", c.id] });
  const enter = useMutation({
    mutationFn: (photoId: string) => api(`contests/${c.id}/entries`, { method: "POST", body: { photo_id: photoId } }),
    onSuccess: () => { setPicker(false); refresh(); },
  });
  const withdraw = useMutation({ mutationFn: () => api(`contests/${c.id}/entries/me`, { method: "DELETE" }), onSuccess: refresh });

  if (c.my_entry) {
    return (
      <div className="grid gap-6 bg-surface p-4 sm:grid-cols-[minmax(0,1fr)_260px] sm:p-6">
        <EntryImage e={c.my_entry} />
        <div>
          <p className="inline-flex items-center gap-2 font-semibold"><Check className="h-4 w-4 text-accent-text" strokeWidth={3} /> {t("you_entered")}</p>
          <p className="mt-2 text-[15px] leading-relaxed text-ink-muted">{t("entered_body")}</p>
          <Button variant="ghost" className="mt-4 -ml-4" busy={withdraw.isPending} onClick={() => window.confirm(t("withdraw_confirm")) && withdraw.mutate()}>
            {t("withdraw")}
          </Button>
        </div>
      </div>
    );
  }
  return (
    <div className="bg-surface px-6 py-10">
      <h2 className="text-2xl font-semibold tracking-[-0.02em]">{t("enter_title")}</h2>
      <p className="mt-2 max-w-[56ch] leading-relaxed text-ink-muted">{t("enter_body")}</p>
      <Button className="mt-6 h-12 text-base" onClick={() => (me ? setPicker(true) : router.push(`/login?next=${encodeURIComponent(pathname)}`))}>
        {t("enter_cta")}
      </Button>
      {enter.error && <div className="mt-4"><Notice tone="error">{enter.error instanceof ApiError ? enter.error.message : t("error")}</Notice></div>}
      <MyPhotoPicker open={picker} onClose={() => setPicker(false)} title={t("pick_entry")} busy={enter.isPending} onPick={(p) => enter.mutate(p.id)} />
    </div>
  );
}

function JuryWaiting({ c }: { c: Contest }) {
  const t = useTranslations("contests");
  return (
    <div className="bg-surface px-6 py-10">
      <p className="text-lg font-semibold">{t("jury_title")}</p>
      <p className="mt-1 text-ink-muted">{t("jury_body")}</p>
      {c.is_judge && <Link href={`/contests/${c.id}/jury`} className={buttonClass("primary", "mt-6")}>{t("start_judging")}</Link>}
    </div>
  );
}

/** Misafir seçmen: e-postasına gelen kodla doğrulanır; token bu tarayıcıda oylama bitene kadar saklanır. */
function GuestVerify({ c, onVerified }: { c: Contest; onVerified: (token: string) => void }) {
  const t = useTranslations("contests");
  const pathname = usePathname();
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [sent, setSent] = useState(false);
  const request = useMutation({
    mutationFn: () => api(`contests/${c.id}/vote/request-code`, { method: "POST", body: { email } }),
    onSuccess: () => setSent(true),
  });
  const verify = useMutation({
    mutationFn: () => api<{ voter_token: string }>(`contests/${c.id}/vote/verify`, { method: "POST", body: { email, code } }),
    onSuccess: (r) => {
      try { localStorage.setItem(voterKey(c.id), r.voter_token); } catch { /* özel mod */ }
      onVerified(r.voter_token);
    },
  });
  const err = request.error ?? verify.error;
  return (
    <div className="bg-surface px-5 py-6 sm:px-6">
      <h2 className="text-xl font-semibold tracking-[-0.02em]">{t("guest_title")}</h2>
      <p className="mt-1.5 max-w-[60ch] text-[15px] leading-relaxed text-ink-muted">{t("guest_body")}</p>
      {!sent ? (
        <form className="mt-5 flex flex-wrap items-end gap-3" onSubmit={(e) => { e.preventDefault(); request.mutate(); }}>
          <TextField label={t("email")} name="voter_email" type="email" autoComplete="email" required value={email} onChange={(e) => setEmail(e.target.value)} className="min-w-[240px] flex-1" />
          <Button type="submit" busy={request.isPending}>{t("send_code")}</Button>
        </form>
      ) : (
        <form className="mt-5 flex flex-wrap items-end gap-3" onSubmit={(e) => { e.preventDefault(); verify.mutate(); }}>
          <TextField label={t("code_label", { email })} name="code" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" maxLength={6} required value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))} className="w-[220px]" />
          <Button type="submit" busy={verify.isPending}>{t("verify")}</Button>
          <button type="button" className="h-11 text-sm text-ink-muted hover:text-ink" onClick={() => { setSent(false); setCode(""); }}>{t("change_email")}</button>
        </form>
      )}
      {err && <div className="mt-4"><Notice tone="error">{err instanceof ApiError ? err.message : t("error")}</Notice></div>}
      <p className="mt-5 text-sm text-ink-muted">
        {t("or_login")}{" "}
        <Link href={`/login?next=${encodeURIComponent(pathname)}`} className="font-semibold text-ink underline underline-offset-4">{t("login")}</Link>
      </p>
    </div>
  );
}

function VotingPanel({ c }: { c: Contest }) {
  const t = useTranslations("contests");
  const { data: me, isLoading } = useMe();
  const qc = useQueryClient();
  const [token, setToken] = useState<string | null>(null);
  useEffect(() => setToken(readVoter(c.id)), [c.id]);
  const headers = useMemo(() => (token && !me ? { "x-voter-token": token } : undefined), [token, me]);
  const canVote = !!me || !!token;
  const key = ["contest-entries", c.id, me?.id ?? token ?? "anon"];

  const entries = useQuery({ queryKey: key, enabled: !isLoading, queryFn: () => api<Entry[]>(`contests/${c.id}/entries`, { headers }) });
  const vote = useMutation({
    mutationFn: ({ entry, stars }: { entry: string; stars: number }) => api(`contests/${c.id}/votes`, { method: "POST", body: { entry_id: entry, stars }, headers }),
    onMutate: ({ entry, stars }) => {
      const prev = qc.getQueryData<Entry[]>(key);
      qc.setQueryData<Entry[]>(key, (list) => list?.map((e) => (e.id === entry ? { ...e, my_stars: stars } : e)));
      return { prev };
    },
    onError: (err, _v, ctx) => {
      qc.setQueryData(key, ctx?.prev);
      if (err instanceof ApiError && err.code === "voter_required") {
        try { localStorage.removeItem(voterKey(c.id)); } catch { /* */ }
        setToken(null);
      }
    },
  });

  const list = entries.data ?? [];
  const votable = list.filter((e) => !e.mine);
  const rated = votable.filter((e) => e.my_stars).length;

  return (
    <div className="flex flex-col gap-6">
      {!isLoading && !canVote && <GuestVerify c={c} onVerified={setToken} />}
      {canVote && list.length > 0 && (
        <div className="sticky top-16 z-10 -mx-4 border-b border-line bg-bg/90 px-4 py-3 backdrop-blur sm:mx-0 sm:px-0">
          <div className="flex items-center justify-between gap-4 text-sm">
            <span className="tnum font-medium">{t("rated_progress", { done: rated, total: votable.length })}</span>
            <span className="text-ink-muted">{t("vote_hint")}</span>
          </div>
          <div className="mt-2 h-1 bg-line"><div className="h-full bg-accent transition-[width]" style={{ width: `${votable.length ? (rated / votable.length) * 100 : 0}%` }} /></div>
        </div>
      )}
      {vote.error && !(vote.error instanceof ApiError && vote.error.code === "voter_required") && (
        <Notice tone="error">{vote.error instanceof ApiError ? vote.error.message : t("error")}</Notice>
      )}
      {/* Sütun düzeni: kareler kendi oranlarında, kırpılmadan */}
      <div className="columns-1 gap-4 sm:columns-2 xl:columns-3">
        {list.map((e) => (
          <figure key={e.id} className="mb-4 break-inside-avoid bg-surface p-2.5">
            <EntryImage e={e} />
            <figcaption className="flex flex-wrap items-center justify-between gap-2 px-1 pt-2">
              <span className="min-w-0 truncate text-sm text-ink-muted">{e.user ? e.user.display_name : e.title}</span>
              {e.mine ? (
                <span className="rounded-full bg-ink/[0.06] px-3 py-1.5 text-sm font-medium">{t("your_entry")}</span>
              ) : (
                <StarRating value={e.my_stars} disabled={!canVote} onChange={(stars) => vote.mutate({ entry: e.id, stars })} />
              )}
            </figcaption>
          </figure>
        ))}
      </div>
      {entries.isSuccess && list.length === 0 && <p className="text-ink-muted">{t("no_entries")}</p>}
    </div>
  );
}

function Results({ c }: { c: Contest }) {
  const t = useTranslations("contests");
  const q = useQuery({ queryKey: ["contest-entries", c.id, "final"], queryFn: () => api<Entry[]>(`contests/${c.id}/entries`) });
  const list = q.data ?? [];
  const podium = list.filter((e) => e.rank && e.rank <= 3);
  const rest = list.filter((e) => !e.rank || e.rank > 3);
  return (
    <div className="flex flex-col gap-10">
      <h2 className="inline-flex items-center gap-2 text-2xl font-semibold tracking-[-0.02em]"><Trophy className="h-6 w-6 text-accent-text" /> {t("results")}</h2>
      {podium.map((e) => (
        <article key={e.id} className={clsx("bg-surface p-3 sm:p-5", e.rank === 1 && "ring-2 ring-accent")}>
          {/* Dikey kareler ekrandan taşmasın: yükseklik sınırlı, kırpma yok */}
          <div className="flex justify-center bg-bg">
            {(() => {
              const img = e.images.full ?? e.images.feed;
              return img ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={img.url} alt={e.title ?? ""} width={img.width} height={img.height} loading="lazy" className="fade-in block h-auto max-h-[78vh] w-auto max-w-full" />
              ) : null;
            })()}
          </div>
          <div className="flex flex-wrap items-center gap-4 px-1 pt-4">
            <span className="tnum text-[44px] font-bold leading-none tracking-[-0.04em]">{e.rank}.</span>
            {e.user && (
              <Link href={`/u/${e.user.username}`} className="flex min-w-0 items-center gap-3">
                <Avatar name={e.user.display_name} url={e.user.avatar_url} size={40} />
                <span className="min-w-0">
                  <span className="block truncate font-semibold">{e.user.display_name}</span>
                  {e.title && <span className="block truncate text-sm text-ink-muted">{e.title}</span>}
                </span>
              </Link>
            )}
            <span className="ml-auto text-right">
              {e.prize && <span className="block font-semibold text-accent-text">{e.prize}</span>}
              {e.score !== null && <span className="tnum block text-sm text-ink-muted">{t("score", { score: e.score.toFixed(2) })}</span>}
            </span>
          </div>
        </article>
      ))}
      {rest.length > 0 && (
        <div className="columns-2 gap-3 md:columns-3">
          {rest.map((e) => (
            <figure key={e.id} className="mb-3 break-inside-avoid bg-surface p-2">
              <EntryImage e={e} />
              <figcaption className="flex items-center justify-between gap-2 px-1 pt-2 text-sm">
                <span className="min-w-0 truncate">{e.user?.display_name}</span>
                <span className="tnum shrink-0 text-ink-muted">{e.rank ? `${e.rank}.` : "–"}</span>
              </figcaption>
            </figure>
          ))}
        </div>
      )}
    </div>
  );
}
