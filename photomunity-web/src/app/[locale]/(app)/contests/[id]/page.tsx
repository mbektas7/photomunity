"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import clsx from "clsx";
import { Check, ChevronLeft, ChevronRight, Star, Trophy, X } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useParams } from "next/navigation";
import { useEffect, useMemo, useRef, useState } from "react";
import { Avatar } from "@/components/Avatar";
import { CommunityLogo, ContestTimeline, MyPhotoPicker, StarRating, StatusBadge } from "@/components/community";
import { Countdown } from "@/components/Countdown";
import { GAP, buildRows } from "@/components/JustifiedWall";
import { ShareButton as SharePill } from "@/components/ShareButton";
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

  const countdown =
    c.status === "open" || c.status === "draft"
      ? { at: c.submission_deadline, label: t("countdown_deadline") }
      : c.status === "judging"
        ? { at: c.voting_end, label: t("countdown_voting") }
        : c.status === "closed"
          ? { at: c.results_at, label: t("countdown_results") }
          : null;
  const publicVoting = c.status === "judging" && c.judging_mode === "public";

  return (
    <div className="mx-auto max-w-[1440px] px-3 sm:px-6 lg:px-10">
      <div className="grid items-start gap-6 lg:grid-cols-[minmax(0,1fr)_320px]">
        <div className="flex min-w-0 flex-col gap-6">
          {/* Yarışma kapak görseli API'de yok; başlık kartı görselsiz. */}
          <header className="flex flex-col gap-5 rounded-card bg-surface p-5 sm:rounded-[28px] sm:p-8">
            <div className="flex flex-wrap items-center gap-2.5">
              <StatusBadge status={c.status} mode={c.judging_mode} />
              <Link href={`/c/${c.community.slug}`} className="inline-flex min-h-8 items-center gap-2 rounded-box text-[14px] text-ink-muted hover:text-ink">
                <CommunityLogo name={c.community.name} url={c.community.logo_url} size={24} />
                {c.community.name}
              </Link>
              <span className="flex-1" />
              <ShareButton c={c} />
            </div>
            <h1 className="text-[34px] font-bold leading-[1] tracking-[-0.04em] sm:text-[44px]">{c.title}</h1>
            <p className="max-w-[64ch] whitespace-pre-line text-[16px] leading-[1.55] text-ink-muted">{c.description}</p>
            <ContestTimeline c={c} />
            {c.my_role === "admin" && (
              <Notice>
                {c.status === "draft" ? t("draft_notice") : t("admin_notice")}{" "}
                <Link href={`/contests/${c.id}/manage`} className="font-semibold text-accent-text underline underline-offset-4">{t("open_manage")}</Link>
              </Notice>
            )}
          </header>

          {c.status === "open" && <EnterPanel c={c} />}
          {publicVoting && <VotingPanel c={c} />}
          {c.status === "judging" && c.judging_mode === "jury" && <JuryWaiting c={c} />}
          {c.status === "closed" && (
            <div className="rounded-card bg-surface px-6 py-10">
              <p className="text-heading">{t("closed_title")}</p>
              <p className="mt-1 text-ink-muted">{t("closed_body", { date: formatDateTime(c.results_at, locale) })}</p>
            </div>
          )}
          {c.status === "finished" && <Results c={c} />}
        </div>

        <aside className="flex flex-col gap-4 lg:sticky lg:top-20">
          {countdown && new Date(countdown.at).getTime() > Date.now() && (
            <section className="flex flex-col gap-3.5 rounded-card bg-surface p-5">
              <Countdown until={countdown.at} label={countdown.label} />
              {publicVoting && (
                <>
                  <a href="#vote" className={buttonClass("large", "h-12 text-[16px]")}>
                    <Star className="h-5 w-5" strokeWidth={1.9} aria-hidden />
                    {t("start_voting")}
                  </a>
                  <p className="text-caption leading-[18px] text-ink-muted">{t("voting_help")}</p>
                </>
              )}
              {me && c.is_judge && c.status === "judging" && (
                <Link href={`/contests/${c.id}/jury`} className={buttonClass("large", "h-12 text-[16px]")}>{t("start_judging")}</Link>
              )}
            </section>
          )}
          {c.prizes.length > 0 && (
            <section className="rounded-card bg-surface p-5">
              <h2 className="text-heading">{t("prizes")}</h2>
              <ol className="mt-2">
                {c.prizes.map((p) => (
                  <li key={p.rank} className="flex items-center gap-3.5 border-t border-line py-3 first:mt-1">
                    <span className="tnum flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-surface-2 text-[13px] font-bold">{p.rank}</span>
                    <span className="text-[15px]">{p.title}</span>
                  </li>
                ))}
              </ol>
            </section>
          )}
          {c.rules && (
            <section className="rounded-card bg-surface p-5">
              <h2 className="text-heading">{t("rules")}</h2>
              <p className="mt-2 whitespace-pre-line text-[15px] leading-[1.55] text-ink-muted">{c.rules}</p>
            </section>
          )}
        </aside>
      </div>
    </div>
  );
}

function ShareButton({ c }: { c: Contest }) {
  return <SharePill url={c.share_url} title={c.title} />;
}

function EntryImage({ e, className }: { e: Entry; className?: string }) {
  const img = e.images.feed ?? e.images.full ?? e.images.thumb;
  if (!img) return null;
  return (
    <span className={clsx("print-placeholder block overflow-hidden rounded-photo", className)} style={{ aspectRatio: `${img.width} / ${img.height}` }}>
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
      <div className="grid gap-6 rounded-card bg-surface p-4 sm:grid-cols-[minmax(0,1fr)_260px] sm:p-6">
        <EntryImage e={c.my_entry} />
        <div>
          <p className="inline-flex items-center gap-2 font-semibold"><Check className="h-4 w-4 text-accent-text" strokeWidth={3} /> {t("you_entered")}</p>
          <p className="mt-2 text-[15px] leading-relaxed text-ink-muted">{t("entered_body")}</p>
          <Button variant="danger" className="mt-4 -ml-3" busy={withdraw.isPending} onClick={() => window.confirm(t("withdraw_confirm")) && withdraw.mutate()}>
            {t("withdraw")}
          </Button>
        </div>
      </div>
    );
  }
  return (
    <div className="rounded-card bg-surface px-6 py-8">
      <h2 className="text-title">{t("enter_title")}</h2>
      <p className="mt-2 max-w-[56ch] leading-relaxed text-ink-muted">{t("enter_body")}</p>
      <Button variant="large" className="mt-6 sm:w-auto" onClick={() => (me ? setPicker(true) : router.push(`/login?next=${encodeURIComponent(pathname)}`))}>
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
    <div className="rounded-card bg-surface px-6 py-8">
      <p className="text-heading">{t("jury_title")}</p>
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
    <div className="rounded-card bg-surface px-5 py-6 sm:px-6">
      <h2 className="text-heading">{t("guest_title")}</h2>
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
          <button type="button" className="h-11 rounded-pill px-3 text-sm font-semibold text-ink-muted hover:bg-surface-2 hover:text-ink" onClick={() => { setSent(false); setCode(""); }}>{t("change_email")}</button>
        </form>
      )}
      {err && <div className="mt-4"><Notice tone="error">{err instanceof ApiError ? err.message : t("error")}</Notice></div>}
      <p className="mt-5 text-sm text-ink-muted">
        {t("or_login")}{" "}
        <Link href={`/login?next=${encodeURIComponent(pathname)}`} className="font-semibold text-accent-text underline underline-offset-4">{t("login")}</Link>
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
  const [open, setOpen] = useState<number | null>(null);

  // "Oylamaya başla" (#vote): ilk puanlanmamış kareden görüntüleyiciyi açar
  useEffect(() => {
    const onHash = () => {
      if (window.location.hash !== "#vote") return;
      if (canVote && votable.length) {
        const first = votable.findIndex((e) => !e.my_stars);
        setOpen(list.indexOf(votable[first === -1 ? 0 : first]!));
      }
      document.getElementById("vote")?.scrollIntoView({ behavior: "smooth", block: "start" });
      history.replaceState(null, "", window.location.pathname + window.location.search);
    };
    onHash();
    window.addEventListener("hashchange", onHash);
    return () => window.removeEventListener("hashchange", onHash);
  });

  return (
    <section id="vote" aria-labelledby="entries-title" className="flex scroll-mt-24 flex-col gap-4">
      {!isLoading && !canVote && <GuestVerify c={c} onVerified={setToken} />}
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 id="entries-title" className="text-title">{t("entries_title")}</h2>
        <span className="tnum text-[14.5px] text-ink-muted">
          {t("entries_count", { count: list.length })}
          {canVote && `, ${t("my_votes", { count: rated })}`}
        </span>
      </div>
      {vote.error && !(vote.error instanceof ApiError && vote.error.code === "voter_required") && (
        <Notice tone="error">{vote.error instanceof ApiError ? vote.error.message : t("error")}</Notice>
      )}
      <EntryWall
        entries={list}
        onOpen={(i) => setOpen(i)}
        badge={(e) =>
          e.mine ? (
            <span className="scrim inline-flex h-8 items-center rounded-pill px-3 text-[13px] font-bold">{t("your_entry")}</span>
          ) : e.my_stars ? (
            <span className="inline-flex h-8 items-center gap-1 rounded-pill bg-accent px-2.5 text-[13px] font-bold text-accent-ink">
              <Star className="h-3.5 w-3.5" fill="currentColor" strokeWidth={0} aria-hidden />
              <span className="tnum">{e.my_stars}</span>
            </span>
          ) : canVote ? (
            <span className="scrim inline-flex h-8 items-center rounded-pill px-3 text-[13px] font-bold">{t("vote_cta")}</span>
          ) : null
        }
        label={(e) => (e.mine ? t("your_entry") : e.my_stars ? t("stars", { count: e.my_stars }) : t("vote_cta"))}
      />
      {entries.isSuccess && list.length === 0 && <p className="text-ink-muted">{t("no_entries")}</p>}
      {open !== null && list[open] && (
        <VoteViewer
          entries={list}
          index={open}
          canVote={canVote}
          progress={t("rated_progress", { done: rated, total: votable.length })}
          onIndex={setOpen}
          onClose={() => setOpen(null)}
          onVote={(entry, stars) => vote.mutate({ entry, stars })}
        />
      )}
    </section>
  );
}

/** Katılımlar: satır düzeni, her kare kendi oranında (kırpma yok); sol altta oy hapı. */
function EntryWall({ entries, onOpen, badge, label }: { entries: Entry[]; onOpen: (i: number) => void; badge: (e: Entry) => React.ReactNode; label: (e: Entry) => string }) {
  const ref = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const ro = new ResizeObserver(([en]) => setWidth(Math.floor(en!.contentRect.width)));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  const rows = useMemo(() => (width ? buildRows(entries, width, width < 640 ? 200 : 280) : []), [entries, width]);
  return (
    <div ref={ref} className="flex flex-col" style={{ gap: GAP }}>
      {rows.map((row, i) => (
        <div key={i} className="flex" style={{ gap: GAP, height: row.height }}>
          {row.items.map(({ photo: e, width: w }) => {
            const src = (row.height > 360 ? e.images.feed : e.images.thumb) ?? e.images.feed;
            return (
              <button
                key={e.id}
                type="button"
                onClick={() => onOpen(entries.indexOf(e))}
                aria-label={[e.title, label(e)].filter(Boolean).join(", ")}
                className="print-placeholder relative block shrink-0 overflow-hidden rounded-photo text-left"
                style={{ width: w, height: row.height }}
              >
                {src && (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={src.url} alt="" loading="lazy" className="fade-in h-full w-full object-cover" />
                )}
                <span className="absolute bottom-2.5 left-2.5">{badge(e)}</span>
              </button>
            );
          })}
        </div>
      ))}
    </div>
  );
}

/** Oylama görüntüleyicisi: kare kendi oranında, altında 1–5 yıldız; önceki / sonraki. */
function VoteViewer({
  entries,
  index,
  canVote,
  progress,
  onIndex,
  onClose,
  onVote,
}: {
  entries: Entry[];
  index: number;
  canVote: boolean;
  progress: string;
  onIndex: (i: number) => void;
  onClose: () => void;
  onVote: (entry: string, stars: number) => void;
}) {
  const t = useTranslations("contests");
  const tu = useTranslations("ui");
  const dialog = useRef<HTMLDialogElement>(null);
  const e = entries[index]!;
  const img = e.images.full ?? e.images.feed;
  useEffect(() => {
    if (!dialog.current?.open) dialog.current?.showModal();
  }, []);
  useEffect(() => {
    const onKey = (ev: KeyboardEvent) => {
      if (ev.key === "ArrowRight" && index < entries.length - 1) onIndex(index + 1);
      if (ev.key === "ArrowLeft" && index > 0) onIndex(index - 1);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [index, entries.length, onIndex]);
  return (
    <dialog
      ref={dialog}
      onClose={onClose}
      aria-label={e.title ?? t("entries_title")}
      className="m-auto max-h-[94dvh] w-[min(1100px,calc(100vw-1.5rem))] rounded-sheet bg-surface p-0 text-ink shadow-float backdrop:bg-black/70"
    >
      <div className="flex items-center gap-3 px-4 pt-4 sm:px-5">
        <span className="tnum text-[14px] font-semibold text-ink-muted">{progress}</span>
        <span className="flex-1" />
        <button type="button" onClick={() => dialog.current?.close()} aria-label={tu("close")} className="inline-flex h-11 w-11 items-center justify-center rounded-full bg-surface-2 hover:bg-line">
          <X className="h-5 w-5" strokeWidth={1.8} aria-hidden />
        </button>
      </div>
      <div className="flex justify-center px-4 pt-3 sm:px-5">
        {img && (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={img.url} alt={e.title ?? ""} width={img.width} height={img.height} className="block h-auto max-h-[64dvh] w-auto max-w-full rounded-photo" />
        )}
      </div>
      <div className="flex flex-wrap items-center gap-3 px-4 py-4 sm:px-5">
        <button type="button" disabled={index === 0} onClick={() => onIndex(index - 1)} aria-label={t("prev_entry")} className="inline-flex h-11 w-11 items-center justify-center rounded-full bg-surface-2 hover:bg-line disabled:opacity-40">
          <ChevronLeft className="h-5 w-5" strokeWidth={1.8} aria-hidden />
        </button>
        <span className="min-w-0 flex-1 text-center">
          {e.mine ? (
            <span className="text-[15px] font-semibold">{t("your_entry")}</span>
          ) : (
            <span className="inline-flex">
              <StarRating value={e.my_stars} disabled={!canVote} size={30} onChange={(stars) => {
                onVote(e.id, stars);
                if (index < entries.length - 1) setTimeout(() => onIndex(index + 1), 250);
              }} />
            </span>
          )}
        </span>
        <button type="button" disabled={index === entries.length - 1} onClick={() => onIndex(index + 1)} aria-label={t("next_entry")} className="inline-flex h-11 w-11 items-center justify-center rounded-full bg-surface-2 hover:bg-line disabled:opacity-40">
          <ChevronRight className="h-5 w-5" strokeWidth={1.8} aria-hidden />
        </button>
      </div>
      <p className="px-5 pb-4 text-center text-caption text-ink-muted">{t("vote_hint")}</p>
    </dialog>
  );
}

function Results({ c }: { c: Contest }) {
  const t = useTranslations("contests");
  const q = useQuery({ queryKey: ["contest-entries", c.id, "final"], queryFn: () => api<Entry[]>(`contests/${c.id}/entries`) });
  const list = q.data ?? [];
  const podium = list.filter((e) => e.rank && e.rank <= 3);
  const rest = list.filter((e) => !e.rank || e.rank > 3);
  return (
    <div className="flex flex-col gap-6">
      <h2 className="inline-flex items-center gap-2 text-title"><Trophy className="h-6 w-6 text-accent-text" strokeWidth={1.8} aria-hidden /> {t("results")}</h2>
      {podium.map((e) => (
        <article key={e.id} className={clsx("rounded-card bg-surface p-3 sm:p-5", e.rank === 1 && "ring-2 ring-accent")}>
          {/* Dikey kareler ekrandan taşmasın: yükseklik sınırlı, kırpma yok */}
          <div className="flex justify-center">
            {(() => {
              const img = e.images.full ?? e.images.feed;
              return img ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={img.url} alt={e.title ?? ""} width={img.width} height={img.height} loading="lazy" className="fade-in block h-auto max-h-[78vh] w-auto max-w-full rounded-photo" />
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
            <figure key={e.id} className="mb-3 break-inside-avoid rounded-card bg-surface p-2.5">
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
