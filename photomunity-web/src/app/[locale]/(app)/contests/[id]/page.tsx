"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import clsx from "clsx";
import { Check, ChevronLeft, ChevronRight, Images, Mail, Medal, Sparkles, Star, X } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Avatar } from "@/components/Avatar";
import { CommunityLogo, ContestTimeline, MyPhotoPicker, StarRating, StatusBadge } from "@/components/community";
import { BlurredPhoto, FilterTabs, MEDAL, RankBadge, exifLine, isTypingTarget, largestImage, smallImage } from "@/components/contest-ui";
import { Countdown } from "@/components/Countdown";
import { buildRows } from "@/components/JustifiedWall";
import { ShareButton as SharePill } from "@/components/ShareButton";
import { Button, Notice, TextField, buttonClass } from "@/components/ui";
import { Link, usePathname, useRouter } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import { formatDateTime } from "@/lib/dates";
import { useMe } from "@/lib/hooks";
import type { Contest, Entry, ResultRow } from "@/lib/types";
import { HowItWorks } from "@/components/intro";

const voterKey = (id: string) => `fg_voter_${id}`;
const voterEmailKey = (id: string) => `fg_voter_email_${id}`;

function readStore(key: string) {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

/** "mirac@gmail.com" → "m***@gmail.com" */
function maskEmail(email: string) {
  const [user, domain] = email.split("@");
  if (!user || !domain) return email;
  return `${user[0]}***@${domain}`;
}

/** Sunucu ve istemci aynı ilk çıktıyı versin diye saat yalnızca istemcide işler. */
function useNow(ms: number) {
  const [now, setNow] = useState<number | null>(null);
  useEffect(() => {
    setNow(Date.now());
    const id = setInterval(() => setNow(Date.now()), ms);
    return () => clearInterval(id);
  }, [ms]);
  return now;
}

export default function ContestPage() {
  const { id } = useParams<{ id: string }>();
  const t = useTranslations("contests");
  const q = useQuery({ queryKey: ["contest", id], queryFn: () => api<Contest>(`contests/${id}`) });

  if (q.error) return <div className="mx-auto max-w-[680px] px-4 py-20"><Notice tone="error">{q.error instanceof ApiError ? q.error.message : t("error")}</Notice></div>;
  const c = q.data;
  if (!c) return <div className="h-[70vh]" aria-busy />;

  if (c.status === "judging" && c.judging_mode === "public") return <PublicVote c={c} />;
  if (c.status === "finished") return <Winners c={c} />;
  return <ContestOverview c={c} />;
}

function AdminNotice({ c }: { c: Contest }) {
  const t = useTranslations("contests");
  if (c.my_role !== "admin") return null;
  return (
    <Notice>
      {c.status === "draft" ? t("draft_notice") : t("admin_notice")}{" "}
      <Link href={`/contests/${c.id}/manage`} className="font-semibold text-accent-text underline underline-offset-4">{t("open_manage")}</Link>
    </Notice>
  );
}

function CommunityLink({ c, tone = "light" }: { c: Contest; tone?: "light" | "dark" }) {
  return (
    <Link
      href={`/c/${c.community.slug}`}
      className={clsx("inline-flex min-h-8 items-center gap-2 rounded-box text-[14px]", tone === "dark" ? "text-white/75 hover:text-white" : "text-ink-muted hover:text-ink")}
    >
      <CommunityLogo name={c.community.name} url={c.community.logo_url} size={24} />
      {c.community.name}
    </Link>
  );
}

function PrizesList({ c }: { c: Contest }) {
  const t = useTranslations("contests");
  if (!c.prizes.length) return null;
  return (
    <section className="rounded-card bg-surface p-5">
      <h2 className="text-heading">{t("prizes")}</h2>
      <ol className="mt-2">
        {c.prizes.map((p) => (
          <li key={p.rank} className="flex items-center gap-3.5 border-t border-line py-3 first:mt-1">
            <RankBadge rank={p.rank} size={32} />
            <span className="text-[15px]">{p.title}</span>
          </li>
        ))}
      </ol>
    </section>
  );
}

function RulesCard({ c }: { c: Contest }) {
  const t = useTranslations("contests");
  if (!c.rules) return null;
  return (
    <section className="rounded-card bg-surface p-5">
      <h2 className="text-heading">{t("rules")}</h2>
      <p className="mt-2 whitespace-pre-line text-[15px] leading-[1.55] text-ink-muted">{c.rules}</p>
    </section>
  );
}

/* ------------------------------------------------------------------ katılım, jüri bekleniyor, sonuç bekleniyor */

function ContestOverview({ c }: { c: Contest }) {
  const t = useTranslations("contests");
  const locale = useLocale();
  const { data: me } = useMe();
  const countdown =
    c.status === "open" || c.status === "draft"
      ? { at: c.submission_deadline, label: t("countdown_deadline") }
      : c.status === "judging"
        ? { at: c.voting_end, label: t("countdown_voting") }
        : c.status === "closed"
          ? { at: c.results_at, label: t("countdown_results") }
          : null;

  return (
    <div className="mx-auto max-w-[1440px] px-3 sm:px-6 lg:px-10">
      <div className="grid items-start gap-6 lg:grid-cols-[minmax(0,1fr)_320px]">
        <div className="flex min-w-0 flex-col gap-6">
          {/* Yarışma kapak görseli API'de yok; başlık kartı görselsiz. */}
          <header className="flex flex-col gap-5 rounded-card bg-surface p-5 sm:rounded-[28px] sm:p-8">
            <div className="flex flex-wrap items-center gap-2.5">
              <StatusBadge status={c.status} mode={c.judging_mode} />
              <CommunityLink c={c} />
              <span className="flex-1" />
              <SharePill url={c.share_url} title={c.title} />
            </div>
            <h1 className="flex items-center gap-3 text-[34px] font-bold leading-[1] tracking-[-0.04em] sm:text-[44px]">{c.title} <HowItWorks module="contests" /></h1>
            <p className="max-w-[64ch] whitespace-pre-line text-[16px] leading-[1.55] text-ink-muted">{c.description}</p>
            <ContestTimeline c={c} />
            <AdminNotice c={c} />
          </header>

          {c.status === "open" && <EnterPanel c={c} />}
          {c.status === "judging" && c.judging_mode === "jury" && <JuryWaiting c={c} />}
          {c.status === "closed" && (
            <div className="rounded-card bg-surface px-6 py-10">
              <p className="text-heading">{t("closed_title")}</p>
              <p className="mt-1 text-ink-muted">{t("closed_body", { date: formatDateTime(c.results_at, locale) })}</p>
            </div>
          )}
        </div>

        <aside className="flex flex-col gap-4 lg:sticky lg:top-20">
          {countdown && new Date(countdown.at).getTime() > Date.now() && (
            <section className="flex flex-col gap-3.5 rounded-card bg-surface p-5">
              <Countdown until={countdown.at} label={countdown.label} />
              {me && c.is_judge && c.status === "judging" && (
                <Link href={`/contests/${c.id}/jury`} className={buttonClass("large", "h-12 text-[16px]")}>{t("start_judging")}</Link>
              )}
            </section>
          )}
          <PrizesList c={c} />
          <RulesCard c={c} />
        </aside>
      </div>
    </div>
  );
}

function EntryImage({ e, className }: { e: Entry; className?: string }) {
  const img = e.images.feed ?? e.images.full ?? e.images.thumb;
  if (!img) return null;
  return (
    <span className={clsx("print-placeholder block overflow-hidden rounded-photo", className)} style={{ aspectRatio: `${img.width} / ${img.height}` }}>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={img.url} alt={e.title ?? ""} loading="lazy" className="fade-in block h-full w-full object-contain" />
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
          {withdraw.error && <div className="mt-3"><Notice tone="error">{withdraw.error instanceof ApiError ? withdraw.error.message : t("error")}</Notice></div>}
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

/* ------------------------------------------------------------------ halk oylaması */

/** Misafir seçmen: e-postasına gelen kodla doğrulanır; token bu tarayıcıda oylama bitene kadar saklanır. */
function GuestVerify({ c, onVerified }: { c: Contest; onVerified: (token: string, email: string) => void }) {
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
      try {
        localStorage.setItem(voterKey(c.id), r.voter_token);
        localStorage.setItem(voterEmailKey(c.id), email.trim());
      } catch { /* özel mod */ }
      onVerified(r.voter_token, email.trim());
    },
  });
  const err = request.error ?? verify.error;
  return (
    <div id="verify" className="scroll-mt-24 rounded-card bg-surface px-5 py-6 sm:px-6">
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

/** Koyu kalan süre kutusu: "3g 14s 22d". */
function CompactCountdown({ until, label }: { until: string; label: string }) {
  const t = useTranslations("contests");
  const tu = useTranslations("ui");
  const now = useNow(1000);
  const ms = Math.max(0, new Date(until).getTime() - (now ?? 0));
  const d = Math.floor(ms / 86_400_000);
  const h = Math.floor((ms % 86_400_000) / 3_600_000);
  const m = Math.floor((ms % 3_600_000) / 60_000);
  const s = Math.floor((ms % 60_000) / 1000);
  return (
    <div className="shrink-0 rounded-[18px] bg-[#14161b] px-[18px] py-3.5 text-center text-white">
      <p className="text-[12px] text-white/65">{label}</p>
      <p className="tnum text-[24px] font-bold tracking-[-0.02em]" aria-hidden>
        {now === null ? "--" : d > 0 ? t("cd_dhm", { d, h, m }) : t("cd_hms", { h, m, s })}
      </p>
      <p className="sr-only">{now === null ? "" : tu("countdown_sr", { label, days: d, hours: h, minutes: m })}</p>
    </div>
  );
}

type VoteFilter = "mixed" | "todo" | "rated";

function PublicVote({ c }: { c: Contest }) {
  const t = useTranslations("contests");
  const { data: me, isLoading } = useMe();
  const qc = useQueryClient();
  const [token, setToken] = useState<string | null>(null);
  const [voterEmail, setVoterEmail] = useState<string | null>(null);
  useEffect(() => {
    setToken(readStore(voterKey(c.id)));
    setVoterEmail(readStore(voterEmailKey(c.id)));
  }, [c.id]);
  const headers = useMemo(() => (token && !me ? { "x-voter-token": token } : undefined), [token, me]);
  const canVote = !!me || !!token;
  const key = useMemo(() => ["contest-entries", c.id, me?.id ?? token ?? "anon"], [c.id, me?.id, token]);

  const entries = useQuery({ queryKey: key, enabled: !isLoading, queryFn: () => api<Entry[]>(`contests/${c.id}/entries`, { headers }) });
  const [saved, setSaved] = useState<{ entry: string; stars: number; at: number } | null>(null);
  const vote = useMutation({
    mutationFn: ({ entry, stars }: { entry: string; stars: number }) => api(`contests/${c.id}/votes`, { method: "POST", body: { entry_id: entry, stars }, headers }),
    onMutate: ({ entry, stars }) => {
      const prev = qc.getQueryData<Entry[]>(key);
      qc.setQueryData<Entry[]>(key, (list) => list?.map((e) => (e.id === entry ? { ...e, my_stars: stars } : e)));
      return { prev };
    },
    onSuccess: (_d, v) => setSaved({ entry: v.entry, stars: v.stars, at: Date.now() }),
    onError: (err, _v, ctx) => {
      qc.setQueryData(key, ctx?.prev);
      if (err instanceof ApiError && err.code === "voter_required") {
        try {
          localStorage.removeItem(voterKey(c.id));
          localStorage.removeItem(voterEmailKey(c.id));
        } catch { /* */ }
        setToken(null);
      }
    },
  });

  const list = useMemo(() => entries.data ?? [], [entries.data]);
  const votable = list.filter((e) => !e.mine);
  const rated = votable.filter((e) => e.my_stars).length;
  const [filter, setFilter] = useState<VoteFilter>("mixed");
  const shown = filter === "todo" ? list.filter((e) => !e.mine && !e.my_stars) : filter === "rated" ? list.filter((e) => e.my_stars) : list;

  // Odak görünümü açıldığı andaki listenin sırasıyla gezinir (puanlanan kare filtreden düşse de kaymaz)
  const [focus, setFocus] = useState<{ ids: string[]; index: number } | null>(null);
  const openFocus = useCallback((ids: string[], index: number) => setFocus({ ids, index }), []);
  const startVoting = useCallback(() => {
    if (!canVote) {
      document.getElementById("verify")?.scrollIntoView({ behavior: "smooth", block: "start" });
      return;
    }
    const ids = list.map((e) => e.id);
    const first = list.findIndex((e) => !e.mine && !e.my_stars);
    if (ids.length) openFocus(ids, first === -1 ? 0 : first);
  }, [canVote, list, openFocus]);

  // Paylaşılan "#vote" bağlantısı: ilk puanlanmamış kareden odak görünümünü açar
  useEffect(() => {
    if (!entries.isSuccess || isLoading) return;
    const onHash = () => {
      if (window.location.hash !== "#vote") return;
      startVoting();
      history.replaceState(null, "", window.location.pathname + window.location.search);
    };
    onHash();
    window.addEventListener("hashchange", onHash);
    return () => window.removeEventListener("hashchange", onHash);
  }, [entries.isSuccess, isLoading, startVoting]);

  const email = me ? me.email : voterEmail;

  return (
    <div className="mx-auto max-w-[1440px] px-3 sm:px-6 lg:px-10">
      {/* Seçmen satırı */}
      <div className="flex flex-wrap items-center gap-3 rounded-card bg-surface px-4 py-3 sm:px-5">
        <CommunityLink c={c} />
        <span className="flex-1" />
        {canVote && email && (
          <span className="inline-flex items-center gap-1.5 text-[13.5px] text-ink-muted">
            <Mail className="h-4 w-4" aria-hidden /> {t("voting_as", { email: maskEmail(email) })}
          </span>
        )}
        {canVote && (
          <button
            type="button"
            onClick={() => {
              setFilter("rated");
              document.getElementById("vote")?.scrollIntoView({ behavior: "smooth", block: "start" });
            }}
            className="inline-flex h-10 items-center gap-[7px] whitespace-nowrap rounded-pill bg-ink px-4 text-[14px] font-bold text-bg hover:opacity-90"
          >
            {t("my_votes_btn")} · <span className="tnum">{rated}</span>
          </button>
        )}
        <SharePill url={c.share_url} title={c.title} />
      </div>

      {/* Başlık ve kalan süre */}
      <header className="flex flex-col gap-5 px-1 pt-6 sm:flex-row sm:items-end sm:gap-6">
        <div className="min-w-0 flex-1">
          <div className="mb-2 flex flex-wrap gap-2">
            <span className="rounded-pill bg-accent-tint px-[9px] py-1 text-[12px] font-bold text-accent-text">{t("mode.public")}</span>
            <span className="tnum rounded-pill bg-surface px-[9px] py-1 text-[12px] font-bold text-ink-muted">{t("photos_count", { count: list.length || c.entry_count })}</span>
          </div>
          <h1 className="flex items-center gap-3 text-[32px] font-bold leading-[1.05] tracking-[-0.03em] sm:text-[38px]">{c.title} <HowItWorks module="voting" publicOk /></h1>
          <p className="mt-1.5 max-w-[72ch] text-[15px] text-ink-muted">{t("vote_lead")}</p>
        </div>
        <div className="flex items-end gap-3">
          {canVote && votable.length > 0 && (
            <Button className="h-12" onClick={startVoting}>
              <Star className="h-[18px] w-[18px]" strokeWidth={1.9} aria-hidden /> {rated ? t("continue_voting") : t("start_voting")}
            </Button>
          )}
          {new Date(c.voting_end).getTime() > Date.now() && <CompactCountdown until={c.voting_end} label={t("voting_ends")} />}
        </div>
      </header>

      <div className="mt-4 flex flex-col gap-4">
        <AdminNotice c={c} />
        {!isLoading && !canVote && <GuestVerify c={c} onVerified={(tok, em) => { setToken(tok); setVoterEmail(em); }} />}
        {vote.error && !(vote.error instanceof ApiError && vote.error.code === "voter_required") && (
          <Notice tone="error">{vote.error instanceof ApiError ? vote.error.message : t("error")}</Notice>
        )}
      </div>

      <section id="vote" aria-labelledby="entries-title" className="scroll-mt-24 pt-4">
        <h2 id="entries-title" className="sr-only">{t("entries_title")}</h2>
        <div className="flex flex-wrap items-center gap-x-4 gap-y-2 pb-3">
          <FilterTabs<VoteFilter>
            label={t("vote_filter")}
            value={filter}
            onChange={setFilter}
            items={[
              { key: "mixed", label: t("filter_mixed") },
              ...(canVote
                ? [
                    { key: "todo" as const, label: t("filter_todo"), count: votable.length - rated },
                    { key: "rated" as const, label: t("filter_rated"), count: rated },
                  ]
                : []),
            ]}
          />
          <span className="text-caption text-ink-muted sm:ml-auto">{t("shuffle_note")}</span>
        </div>
        {entries.isSuccess && list.length === 0 && <p className="py-6 text-ink-muted">{t("no_entries")}</p>}
        {entries.isSuccess && list.length > 0 && shown.length === 0 && <p className="py-6 text-ink-muted">{filter === "todo" ? t("all_rated") : t("none_rated")}</p>}
        <VoteGrid
          entries={shown}
          canVote={canVote}
          onOpen={(i) => openFocus(shown.map((e) => e.id), i)}
          onVote={(entry, stars) => vote.mutate({ entry, stars })}
        />
      </section>

      <section className="mt-10 grid gap-4 md:grid-cols-3">
        <div className="rounded-card bg-surface p-5">
          <h2 className="text-heading">{t("about")}</h2>
          <p className="mt-2 whitespace-pre-line text-[15px] leading-[1.55] text-ink-muted">{c.description}</p>
        </div>
        <PrizesList c={c} />
        <RulesCard c={c} />
      </section>

      {focus && (
        <VoteFocus
          c={c}
          ids={focus.ids}
          index={focus.index}
          byId={new Map(list.map((e) => [e.id, e]))}
          canVote={canVote}
          saved={saved}
          onIndex={(index) => setFocus((f) => (f ? { ...f, index } : f))}
          onClose={() => setFocus(null)}
          onVote={(entry, stars) => vote.mutate({ entry, stars })}
        />
      )}
    </div>
  );
}

const CARD_FOOTER = 40;

/** Katılımlar: satır düzeni, her kare kendi oranında (kırpma yok); altında 1–5 yıldız. */
function VoteGrid({ entries, canVote, onOpen, onVote }: { entries: Entry[]; canVote: boolean; onOpen: (i: number) => void; onVote: (entry: string, stars: number) => void }) {
  const t = useTranslations("contests");
  const ref = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);
  const gap = 12;
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const ro = new ResizeObserver(([en]) => setWidth(Math.floor(en!.contentRect.width)));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  const rows = useMemo(() => (width ? buildRows(entries, width, width < 640 ? 180 : 240, gap) : []), [entries, width]);
  const index = useMemo(() => new Map(entries.map((e, i) => [e.id, i])), [entries]);
  return (
    <div ref={ref} className="flex flex-col" style={{ gap }}>
      {rows.map((row, r) => (
        <div key={r} className="flex" style={{ gap }}>
          {row.items.map(({ photo: e, width: w }) => {
            const src = (row.height > 300 ? e.images.feed : e.images.thumb) ?? e.images.feed ?? e.images.full;
            const i = index.get(e.id) ?? 0;
            return (
              <div key={e.id} className="flex shrink-0 flex-col overflow-hidden rounded-box bg-surface" style={{ width: w }}>
                <button
                  type="button"
                  onClick={() => onOpen(i)}
                  aria-label={t("open_entry", { title: e.title || `#${e.number ?? i + 1}` })}
                  className="print-placeholder block"
                  style={{ height: row.height }}
                >
                  {src && (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={src.url} alt="" loading="lazy" className="fade-in h-full w-full object-contain" />
                  )}
                </button>
                <div className="flex items-center justify-between gap-2 px-2.5" style={{ height: CARD_FOOTER }}>
                  <span className="min-w-0 truncate text-[12.5px] font-bold text-ink-muted">{e.title || `#${e.number ?? i + 1}`}</span>
                  {e.mine ? (
                    <span className="shrink-0 text-[12.5px] font-semibold text-ink-muted">{t("your_entry")}</span>
                  ) : canVote ? (
                    <span className="shrink-0 [&_button]:p-0.5">
                      <StarRating value={e.my_stars} size={17} onChange={(s) => onVote(e.id, s)} />
                    </span>
                  ) : null}
                </div>
              </div>
            );
          })}
        </div>
      ))}
    </div>
  );
}

/** Odak görünümü (her iki temada koyu): büyük kare, bulanık zemin, büyük yıldızlar; 1–5 tuşları, ← →. */
function VoteFocus({
  c,
  ids,
  index,
  byId,
  canVote,
  saved,
  onIndex,
  onClose,
  onVote,
}: {
  c: Contest;
  ids: string[];
  index: number;
  byId: Map<string, Entry>;
  canVote: boolean;
  saved: { entry: string; stars: number; at: number } | null;
  onIndex: (i: number) => void;
  onClose: () => void;
  onVote: (entry: string, stars: number) => void;
}) {
  const t = useTranslations("contests");
  const locale = useLocale();
  const dialog = useRef<HTMLDialogElement>(null);
  const e = byId.get(ids[index]!);
  const img = e ? largestImage(e) : undefined;
  const [hover, setHover] = useState<number | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (!dialog.current?.open) dialog.current?.showModal();
    return () => {
      if (timer.current) clearTimeout(timer.current);
    };
  }, []);

  const rate = useCallback(
    (stars: number) => {
      if (!e || e.mine || !canVote) return;
      onVote(e.id, stars);
      if (timer.current) clearTimeout(timer.current);
      if (index < ids.length - 1) timer.current = setTimeout(() => onIndex(index + 1), 650);
    },
    [e, canVote, onVote, index, ids.length, onIndex],
  );

  useEffect(() => {
    const onKey = (ev: KeyboardEvent) => {
      if (ev.metaKey || ev.ctrlKey || ev.altKey || isTypingTarget(ev.target)) return;
      if (ev.key === "ArrowRight" && index < ids.length - 1) onIndex(index + 1);
      else if (ev.key === "ArrowLeft" && index > 0) onIndex(index - 1);
      else if (/^[1-5]$/.test(ev.key)) rate(Number(ev.key));
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [index, ids.length, onIndex, rate]);

  // "Kaydedildi" geri bildirimi birkaç saniye sonra kaybolsun
  const [, tick] = useState(0);
  useEffect(() => {
    if (!saved) return;
    const id = setTimeout(() => tick((x) => x + 1), 2600);
    return () => clearTimeout(id);
  }, [saved]);

  const shown = hover ?? e?.my_stars ?? 0;
  const justSaved = saved && Date.now() - saved.at < 2500 ? saved : null;
  const meta = e ? exifLine(e.exif, locale) : "";

  return (
    <dialog
      ref={dialog}
      onClose={onClose}
      aria-label={e?.title || t("entries_title")}
      className="fixed inset-0 m-0 h-dvh max-h-none w-screen max-w-none overflow-hidden bg-[#07080d] p-0 text-white backdrop:bg-black"
    >
      {img && (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={img.url} alt="" aria-hidden className="absolute inset-0 h-full w-full scale-110 object-cover" style={{ filter: "blur(70px) brightness(.3)" }} />
      )}
      <div className="relative flex h-full flex-col">
        <div className="flex h-16 shrink-0 items-center gap-3 px-4 sm:px-8">
          <button type="button" onClick={() => dialog.current?.close()} aria-label={t("close")} className="inline-flex h-10 w-10 items-center justify-center rounded-full bg-white/10 hover:bg-white/20">
            <X className="h-5 w-5" aria-hidden />
          </button>
          <b className="min-w-0 truncate text-[15px]">{c.title}</b>
          <span className="tnum shrink-0 text-[13.5px] text-white/60">· {index + 1} / {ids.length}</span>
          <span className="flex-1" />
          <span className="hidden text-[13px] text-white/70 md:inline">{t("focus_keys")}</span>
        </div>

        <div className="relative flex min-h-0 flex-1 items-center justify-center px-4 sm:px-[100px]">
          {img && e && (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              key={e.id}
              src={img.url}
              alt={e.title ?? ""}
              width={img.width}
              height={img.height}
              className="fade-in block h-auto max-h-full w-auto max-w-full rounded-[6px] object-contain shadow-[0_30px_90px_rgba(0,0,0,.7)]"
            />
          )}
          <button type="button" disabled={index === 0} onClick={() => onIndex(index - 1)} aria-label={t("prev_entry")} className="absolute left-3 inline-flex h-[52px] w-[52px] items-center justify-center rounded-full bg-white/10 hover:bg-white/20 disabled:opacity-0 sm:left-[30px]">
            <ChevronLeft className="h-6 w-6" aria-hidden />
          </button>
          <button type="button" disabled={index === ids.length - 1} onClick={() => onIndex(index + 1)} aria-label={t("next_entry")} className="absolute right-3 inline-flex h-[52px] w-[52px] items-center justify-center rounded-full bg-white/10 hover:bg-white/20 disabled:opacity-0 sm:right-[30px]">
            <ChevronRight className="h-6 w-6" aria-hidden />
          </button>
        </div>

        <div className="flex shrink-0 flex-col items-center justify-center gap-3 px-4 py-5 sm:min-h-[130px] md:flex-row md:gap-7">
          <div className="min-w-0 text-center md:max-w-[34%] md:text-right">
            <p className="truncate text-[18px] font-bold sm:text-[20px]">{e?.title || `#${e?.number ?? index + 1}`}</p>
            {meta && <p className="tnum truncate text-[13px] text-white/60">{meta}</p>}
          </div>
          {e?.mine ? (
            <p className="rounded-[16px] bg-white/[.07] px-5 py-4 text-[15px] font-semibold">{t("your_entry")}</p>
          ) : (
            <div role="radiogroup" aria-label={t("rate")} className="flex gap-2" onMouseLeave={() => setHover(null)}>
              {[1, 2, 3, 4, 5].map((n) => (
                <button
                  key={n}
                  type="button"
                  role="radio"
                  aria-checked={e?.my_stars === n}
                  aria-label={t("stars", { count: n })}
                  disabled={!canVote}
                  onMouseEnter={() => setHover(n)}
                  onClick={() => rate(n)}
                  className="inline-flex h-[52px] w-[52px] items-center justify-center rounded-[16px] transition-transform active:scale-90 disabled:opacity-40 sm:h-[58px] sm:w-[58px]"
                  style={{ background: n <= shown ? "rgba(226,179,60,.18)" : "rgba(255,255,255,.07)" }}
                >
                  <Star className="h-7 w-7" strokeWidth={1.7} fill={n <= shown ? MEDAL[1] : "none"} color={n <= shown ? MEDAL[1] : "rgba(255,255,255,.55)"} aria-hidden />
                </button>
              ))}
            </div>
          )}
          <p role="status" className="flex min-w-[150px] items-center gap-1.5 text-[13px] text-[#7fe0c0]">
            {justSaved && (
              <>
                <Check className="h-4 w-4" aria-hidden /> {t("stars_saved", { count: justSaved.stars })}
              </>
            )}
            {!canVote && <span className="text-white/70">{t("verify_to_vote")}</span>}
          </p>
        </div>
      </div>
    </dialog>
  );
}

/* ------------------------------------------------------------------ kazananlar */

const PLACE_KEYS: Record<number, "place_1" | "place_2" | "place_3"> = { 1: "place_1", 2: "place_2", 3: "place_3" };
const same = (a: number | null | undefined, b: number | null | undefined) => a != null && b != null && Math.abs(a - b) < 0.005;

function Winners({ c }: { c: Contest }) {
  const t = useTranslations("contests");
  const locale = useLocale();
  const q = useQuery({ queryKey: ["contest-results", c.id], queryFn: () => api<ResultRow[]>(`contests/${c.id}/results`) });
  const rows = useMemo(() => q.data ?? [], [q.data]);
  const jury = c.judging_mode === "jury";
  const fmt = useMemo(() => new Intl.NumberFormat(locale, { minimumFractionDigits: 2, maximumFractionDigits: 2 }), [locale]);
  const nf = useMemo(() => new Intl.NumberFormat(locale), [locale]);
  const podium = [1, 2, 3].map((r) => rows.find((x) => x.rank === r)).filter((x): x is ResultRow => !!x);
  const mentions = rows.filter((r) => r.rank && r.rank > 3 && r.prize);
  const tied = (r: ResultRow) => {
    const i = rows.indexOf(r);
    return same(rows[i - 1]?.score, r.score) || same(rows[i + 1]?.score, r.score);
  };
  const date = new Intl.DateTimeFormat(locale, { day: "numeric", month: "long", year: "numeric" }).format(new Date(c.results_at));
  const stats = [
    t("entries_count", { count: c.entry_count }),
    jury && c.judge_count ? t("judges_n", { count: c.judge_count }) : null,
    !jury && c.vote_count ? t("votes_n", { count: c.vote_count, formatted: nf.format(c.vote_count) }) : null,
    c.community.name,
  ].filter(Boolean);

  return (
    <div className="mx-auto max-w-[1440px] px-3 sm:px-6 lg:px-10">
      {/* Bilerek koyu: gece gökyüzü zemini, her iki temada aynı */}
      <section aria-labelledby="winners-h" className="relative overflow-hidden rounded-[28px] bg-[#07080d] pb-8 text-white sm:pb-10">
        <div aria-hidden className="absolute inset-0 bg-[radial-gradient(ellipse_at_50%_-10%,#2b2370_0%,#0d0f1a_55%,#07080d_100%)]" />
        <div aria-hidden className="absolute inset-0 opacity-[.06] [background-image:radial-gradient(#fff_1px,transparent_1.2px)] [background-size:46px_46px]" />

        <div className="relative flex flex-wrap items-center gap-3 px-4 pt-4 sm:px-8 sm:pt-5 lg:px-12">
          <CommunityLink c={c} tone="dark" />
          <span className="flex-1" />
          <SharePill url={c.share_url} title={c.title} tone="surface" />
          <a href="#all-entries" className="inline-flex h-10 items-center gap-[7px] whitespace-nowrap rounded-pill bg-accent px-4 text-[14px] font-bold text-accent-ink hover:brightness-110">
            <Images className="h-4 w-4" aria-hidden /> {t("all_entries_btn")}
          </a>
        </div>

        <div className="relative px-4 pb-6 pt-4 text-center sm:pb-[22px]">
          <p className="inline-flex items-center gap-2 rounded-pill px-3.5 py-1.5 text-[12.5px] font-bold uppercase tracking-[.5px]" style={{ background: "rgba(226,179,60,.15)", color: MEDAL[1] }}>
            <Sparkles className="h-3.5 w-3.5" aria-hidden /> {t("results_announced", { date: date.toLocaleUpperCase(locale) })}
          </p>
          <h1 id="winners-h" className="mt-2.5 text-[32px] font-bold leading-[1.05] tracking-[-0.03em] sm:text-[46px]">{t("winners_title", { title: c.title })}</h1>
          <p className="tnum mt-1.5 text-[15px] text-white/65">{stats.join(" · ")}</p>
        </div>

        {q.error && <div className="relative mx-auto max-w-[680px] px-4"><Notice tone="error">{q.error instanceof ApiError ? q.error.message : t("error")}</Notice></div>}
        {q.isSuccess && podium.length === 0 && <p className="relative text-center text-white/70">{t("no_winners")}</p>}

        {podium.length > 0 && (
          <div className="relative flex flex-col items-center gap-8 px-4 sm:px-8 lg:flex-row lg:items-end lg:justify-center lg:gap-7 lg:px-12">
            {podium.map((r) => (
              <PodiumCard key={r.entry.id} r={r} jury={jury} score={r.score !== null ? fmt.format(r.score) : null} tied={tied(r)} />
            ))}
          </div>
        )}

        {mentions.length > 0 && (
          <div className="relative flex flex-col gap-3 px-4 pt-8 sm:px-8 lg:flex-row lg:items-center lg:px-12">
            <h2 className="shrink-0 text-[14px] font-bold">{mentions.length === 1 ? t("mentions_one", { rank: mentions[0]!.rank! }) : t("mentions", { from: mentions[0]!.rank!, to: mentions.at(-1)!.rank! })}</h2>
            <ul className="grid flex-1 grid-cols-1 gap-2.5 sm:grid-cols-2 xl:grid-cols-4">
              {mentions.map((r) => {
                const th = smallImage(r.entry);
                return (
                  <li key={r.entry.id}>
                    <Link href={`/p/${r.entry.photo_id}`} className="flex items-center gap-2.5 rounded-[14px] bg-white/[.05] p-2 hover:bg-white/10">
                      <span className="block h-11 w-16 shrink-0 overflow-hidden rounded-[8px] bg-black">
                        {th && (
                          // eslint-disable-next-line @next/next/no-img-element
                          <img src={th.url} alt="" loading="lazy" className="h-full w-full object-contain" />
                        )}
                      </span>
                      <span className="min-w-0">
                        <span className="block truncate text-[13.5px] font-bold">{r.entry.title || `${r.rank}.`}</span>
                        <span className="block truncate text-[12px] text-white/60">{[r.entry.user && `@${r.entry.user.username}`, r.prize].filter(Boolean).join(" · ")}</span>
                      </span>
                    </Link>
                  </li>
                );
              })}
            </ul>
          </div>
        )}
      </section>

      <div className="mt-6 flex flex-col gap-4">
        <AdminNotice c={c} />
      </div>

      <section id="all-entries" aria-labelledby="all-h" className="scroll-mt-24 pt-6">
        <div className="mb-3 flex items-baseline justify-between gap-3">
          <h2 id="all-h" className="text-title">{t("all_entries")}</h2>
          <span className="tnum text-[14.5px] text-ink-muted">{t("entries_count", { count: rows.length })}</span>
        </div>
        <RankedWall rows={rows} />
      </section>

      <section className="mt-10 grid gap-4 md:grid-cols-3">
        <div className="rounded-card bg-surface p-5">
          <h2 className="text-heading">{t("about")}</h2>
          <p className="mt-2 whitespace-pre-line text-[15px] leading-[1.55] text-ink-muted">{c.description}</p>
        </div>
        <PrizesList c={c} />
        <RulesCard c={c} />
      </section>
    </div>
  );
}

function PodiumCard({ r, jury, score, tied }: { r: ResultRow; jury: boolean; score: string | null; tied: boolean }) {
  const t = useTranslations("contests");
  const first = r.rank === 1;
  const color = MEDAL[r.rank!]!;
  const e = r.entry;
  return (
    <article
      className={clsx("w-full", first ? "max-w-[520px] lg:order-2 lg:w-[520px]" : "max-w-[330px] lg:w-[330px]", r.rank === 2 && "lg:order-1", r.rank === 3 && "lg:order-3")}
    >
      <Link href={`/p/${e.photo_id}`} className="block rounded-[18px] shadow-[0_20px_60px_rgba(0,0,0,.45)]">
        <BlurredPhoto img={largestImage(e)} alt={e.title ?? ""} blur={30} dim={0.5} className={clsx("rounded-[18px]", first ? "h-[300px] sm:h-[346px]" : "h-[230px] sm:h-[250px]")}>
          <span className="absolute left-3.5 top-3.5 inline-flex items-center gap-[7px] rounded-pill py-1.5 pl-2 pr-3 text-[12.5px] font-bold uppercase tracking-[.4px] text-[#14161b]" style={{ background: color }}>
            <Medal className="h-4 w-4" aria-hidden /> {t(PLACE_KEYS[r.rank!]!)}
          </span>
        </BlurredPhoto>
      </Link>
      <div className="mt-3 flex items-center gap-2.5">
        {e.user ? (
          <Link href={`/u/${e.user.username}`} className="shrink-0 rounded-full p-[2px]" style={{ background: color }} aria-label={e.user.display_name}>
            <Avatar name={e.user.display_name} url={e.user.avatar_url} size={36} />
          </Link>
        ) : (
          <RankBadge rank={r.rank} size={38} />
        )}
        <div className="min-w-0 flex-1">
          <p className={clsx("truncate font-bold", first ? "text-[19px]" : "text-[16px]")}>{e.title || e.user?.display_name}</p>
          <p className="truncate text-[13px] text-white/65">{[e.user && `@${e.user.username}`, r.prize].filter(Boolean).join(" · ")}</p>
        </div>
        {score && (
          <div className="shrink-0 text-right">
            <p className="tnum text-[18px] font-bold">{score}</p>
            <p className="text-[11px] text-white/55">{jury ? t("jury_score") : t("avg_stars")}</p>
          </div>
        )}
      </div>
      {tied && <p className="mt-1.5 text-right text-[11.5px] text-white/55">{jury ? t("tie_jury") : t("tie_public")}</p>}
    </article>
  );
}

/** Tüm katılımlar sıralarıyla; satır düzeni, kırpma yok. */
function RankedWall({ rows }: { rows: ResultRow[] }) {
  const ref = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const ro = new ResizeObserver(([en]) => setWidth(Math.floor(en!.contentRect.width)));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  const entries = useMemo(() => rows.map((r) => ({ ...r.entry, rank: r.rank })), [rows]);
  const lines = useMemo(() => (width ? buildRows(entries, width, width < 640 ? 180 : 260) : []), [entries, width]);
  return (
    <div ref={ref} className="flex flex-col gap-2.5">
      {lines.map((row, i) => (
        <div key={i} className="flex gap-2.5" style={{ height: row.height }}>
          {row.items.map(({ photo: e, width: w }) => {
            const src = (row.height > 360 ? e.images.feed : e.images.thumb) ?? e.images.feed;
            return (
              <Link
                key={e.id}
                href={`/p/${e.photo_id}`}
                aria-label={[e.rank ? `${e.rank}.` : null, e.title, e.user?.display_name].filter(Boolean).join(" ")}
                className="print-placeholder group relative block shrink-0 overflow-hidden rounded-photo"
                style={{ width: w, height: row.height }}
              >
                {src && (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={src.url} alt="" loading="lazy" className="fade-in h-full w-full object-contain" />
                )}
                <span className="absolute left-2.5 top-2.5"><RankBadge rank={e.rank} size={28} /></span>
                {e.user && (
                  <span className="pointer-events-none absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/60 to-transparent px-3 pb-2.5 pt-8 text-sm font-medium text-white opacity-0 transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100">
                    {e.user.display_name}
                  </span>
                )}
              </Link>
            );
          })}
        </div>
      ))}
    </div>
  );
}
