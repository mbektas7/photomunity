"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import clsx from "clsx";
import { Ban, ChevronLeft, Eye, Lock, Search, Trophy, X } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useParams, useSearchParams } from "next/navigation";
import { Suspense, useMemo, useState } from "react";
import { Avatar } from "@/components/Avatar";
import { RankBadge, FilterTabs, StageStepper, entryNumbers, relTime, smallImage } from "@/components/contest-ui";
import { ContestForm, type ContestBody } from "@/components/ContestForm";
import { Button, Notice, TextField, buttonClass } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import type { Contest, ContestSummary, Entry, Judge, ResultRow } from "@/lib/types";

export default function ManageContestPage() {
  return (
    <Suspense>
      <Manage />
    </Suspense>
  );
}

function errorText(e: unknown, fallback: string) {
  return e instanceof ApiError && e.message ? e.message : fallback;
}

/** Jüri üyesinin puanlayabileceği kare sayısı: geçerli katılımlar, kendi karesi hariç. */
function eligibleFor(j: Judge, valid: Entry[]) {
  return valid.length - (j.user && valid.some((e) => e.user?.id === j.user!.id) ? 1 : 0);
}

function Manage() {
  const { id } = useParams<{ id: string }>();
  const t = useTranslations("manage");
  const tf = useTranslations("contestForm");
  const created = useSearchParams().get("created");
  const qc = useQueryClient();
  const q = useQuery({ queryKey: ["contest", id], queryFn: () => api<Contest>(`contests/${id}`) });
  const save = useMutation({
    mutationFn: (b: Partial<ContestBody>) => api<Contest>(`contests/${id}`, { method: "PATCH", body: b }),
    onSuccess: (c) => qc.setQueryData(["contest", id], c),
  });
  const publish = useMutation({
    mutationFn: () => api<Contest>(`contests/${id}/publish`, { method: "POST" }),
    onSuccess: (c) => qc.setQueryData(["contest", id], c),
  });

  const c = q.data;
  if (q.error) return <div className="mx-auto max-w-[680px] px-4 py-20"><Notice tone="error">{errorText(q.error, t("error"))}</Notice></div>;
  if (!c) return <div className="h-[60vh]" aria-busy />;
  if (c.my_role !== "admin") return <div className="mx-auto max-w-[680px] px-4 py-20"><Notice tone="error">{t("forbidden")}</Notice></div>;
  const draft = c.status === "draft";
  const hasResults = c.status === "judging" || c.status === "closed" || c.status === "finished";

  return (
    <div className="pb-6">
      {/* Üst çubuk: geri, başlık, aşama adımları, eylemler */}
      <div className="border-b border-line bg-surface">
        <div className="mx-auto flex max-w-[1440px] flex-wrap items-center gap-x-[18px] gap-y-3 px-4 py-3.5 sm:px-6 lg:px-8 xl:h-[72px] xl:flex-nowrap xl:py-0">
          <Link href={`/contests/${c.id}`} aria-label={t("view_public")} className="inline-flex h-[38px] w-[38px] shrink-0 items-center justify-center rounded-full border border-line hover:bg-surface-2">
            <ChevronLeft className="h-[18px] w-[18px]" aria-hidden />
          </Link>
          <div className="min-w-0 flex-1 xl:flex-none">
            <h1 className="truncate text-[17px] font-bold">{c.title}</h1>
            <p className="truncate text-caption text-ink-muted">{t("panel_subtitle", { community: c.community.name })}</p>
          </div>
          <div className="order-last flex min-w-0 w-full justify-start overflow-x-auto xl:order-none xl:w-auto xl:flex-1 xl:justify-center">
            <StageStepper status={c.status} />
          </div>
          <div className="flex shrink-0 gap-2 max-sm:order-last max-sm:w-full max-sm:[&>*:last-child]:flex-1">
            <Link href={`/contests/${c.id}`} className="inline-flex h-10 items-center gap-[7px] whitespace-nowrap rounded-pill border border-line bg-surface px-4 text-[14px] font-bold hover:bg-surface-2">
              <Eye className="h-4 w-4" aria-hidden />
              <span className="max-sm:sr-only">{t("public_page")}</span>
            </Link>
            {draft ? (
              <Button className="h-10 min-h-10 px-4 text-[14px]" busy={publish.isPending} onClick={() => window.confirm(t("publish_confirm")) && publish.mutate()}>
                {t("publish")}
              </Button>
            ) : hasResults ? (
              <Link href={`/contests/${c.id}/manage/results`} className={buttonClass("primary", "h-10 min-h-10 px-4 text-[14px]")}>
                <Trophy className="h-4 w-4" aria-hidden />
                {c.status === "finished" ? t("results_final") : t("results_preview")}
              </Link>
            ) : null}
          </div>
        </div>
      </div>

      <div className="mx-auto max-w-[1440px] px-4 pt-5 sm:px-6 lg:px-8">
        <div className="flex flex-col gap-3 empty:hidden">
          {created && <Notice tone="success">{t("created")}</Notice>}
          {draft && (
            <div className="rounded-card bg-surface px-5 py-4">
              <p className="font-semibold">{t("publish_title")}</p>
              <p className="mt-1 text-[15px] text-ink-muted">{c.judging_mode === "jury" ? t("publish_body_jury") : t("publish_body")}</p>
              {publish.error && <div className="mt-3"><Notice tone="error">{errorText(publish.error, t("error"))}</Notice></div>}
            </div>
          )}
        </div>

        <Dashboard c={c} />

        <section id="details" className="mt-5 scroll-mt-24 rounded-card bg-surface p-5 sm:p-6">
          <h2 className="text-heading">{t("details")}</h2>
          {!draft && <p className="mt-1 max-w-[64ch] text-[14.5px] text-ink-muted">{t("details_locked")}</p>}
          <div className="mt-5">
            <ContestForm
              key={c.id + String(draft)}
              initial={c}
              locked={!draft}
              busy={save.isPending}
              error={save.error ? errorText(save.error, t("error")) : null}
              submitLabel={tf("save")}
              onSubmit={(b) => save.mutate(draft ? b : { title: b.title, description: b.description, rules: b.rules, ...(c.status === "open" ? { prizes: b.prizes } : {}) })}
            />
            {save.isSuccess && <div className="mt-4"><Notice tone="success">{t("saved")}</Notice></div>}
          </div>
        </section>
      </div>
    </div>
  );
}

function Dashboard({ c }: { c: Contest }) {
  const t = useTranslations("manage");
  const qc = useQueryClient();
  const jury = c.judging_mode === "jury";
  const summary = useQuery({ queryKey: ["contest-summary", c.id], queryFn: () => api<ContestSummary>(`contests/${c.id}/summary`), refetchInterval: 30_000 });
  const entriesKey = ["contest-entries", c.id, "admin"];
  const entries = useQuery({ queryKey: entriesKey, enabled: c.status !== "draft", queryFn: () => api<Entry[]>(`contests/${c.id}/entries?view=admin`) });
  const judgesKey = ["contest-judges", c.id];
  const judges = useQuery({ queryKey: judgesKey, enabled: jury, queryFn: () => api<Judge[]>(`contests/${c.id}/judges`), refetchInterval: 30_000 });
  // Kare başına jüri/oy sayısı: yöneticinin ara sonuç önizlemesinden
  const preview = useQuery({
    queryKey: ["contest-preview", c.id],
    enabled: c.status === "judging" || c.status === "closed",
    queryFn: () => api<ResultRow[]>(`contests/${c.id}/results`),
    refetchInterval: 30_000,
  });
  const dq = useMutation({
    mutationFn: ({ id, reason }: { id: string; reason: string }) => api(`contests/${c.id}/entries/${id}/disqualify`, { method: "POST", body: { reason } }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: entriesKey });
      qc.invalidateQueries({ queryKey: ["contest-summary", c.id] });
      qc.invalidateQueries({ queryKey: ["contest-preview", c.id] });
    },
  });

  const list = entries.data ?? [];
  const valid = list.filter((e) => !e.disqualified);
  const accepted = (judges.data ?? []).filter((j) => !j.pending);
  const counts = new Map((preview.data ?? []).map((r) => [r.entry.id, r.count]));

  return (
    <div className="mt-5 grid grid-cols-[minmax(0,1fr)] items-start gap-5 lg:grid-cols-[minmax(0,1fr)_380px]">
      <div className="flex min-w-0 flex-col gap-4">
        <Stats c={c} summary={summary.data} valid={valid} judges={accepted} />
        {summary.data && summary.data.suspicious_ips > 0 && <Notice tone="error">{t("suspicious", { count: summary.data.suspicious_ips })}</Notice>}
        {dq.error && <Notice tone="error">{errorText(dq.error, t("error"))}</Notice>}
        {c.status !== "draft" && (
          <Entries
            c={c}
            list={list}
            loading={entries.isLoading}
            counts={preview.data ? counts : null}
            judgeTotal={accepted.length}
            onDisqualify={(id, reason) => dq.mutate({ id, reason })}
          />
        )}
      </div>
      <div className="flex flex-col gap-4">
        {jury && <JuryBoard c={c} judges={judges.data ?? []} valid={valid} judgesKey={judgesKey} />}
        <Prizes c={c} />
      </div>
    </div>
  );
}

function StatCard({ label, value, sub, tone }: { label: string; value: React.ReactNode; sub?: React.ReactNode; tone?: "accent" }) {
  return (
    <div className="flex min-w-0 flex-col rounded-[18px] bg-surface px-[18px] py-4">
      <dt className="text-caption font-semibold text-ink-muted">{label}</dt>
      <dd className={clsx("tnum truncate text-[26px] font-bold leading-tight tracking-[-0.02em] sm:text-[30px]", tone === "accent" && "text-accent-text")}>{value}</dd>
      {sub && <dd className="truncate text-caption text-ink-muted">{sub}</dd>}
    </div>
  );
}

function Stats({ c, summary, valid, judges }: { c: Contest; summary?: ContestSummary; valid: Entry[]; judges: Judge[] }) {
  const t = useTranslations("manage");
  const locale = useLocale();
  const now = Date.now();
  const jury = c.judging_mode === "jury";
  const entryCount = summary ? summary.entries - summary.disqualified : c.entry_count;

  // Jüri ilerlemesi: verilen puanlar / puanlanabilir kareler (hesabı bağlı jüriler)
  const possible = judges.reduce((s, j) => s + eligibleFor(j, valid), 0);
  const scored = judges.reduce((s, j) => s + Math.min(j.scored, eligibleFor(j, valid)), 0);
  const finished = judges.filter((j) => eligibleFor(j, valid) > 0 && j.scored >= eligibleFor(j, valid)).length;
  const pct = possible ? Math.round((scored / possible) * 100) : 0;

  const deadlinePassed = new Date(c.submission_deadline).getTime() <= now;
  const votingPassed = new Date(c.voting_end).getTime() <= now;
  const day = new Intl.DateTimeFormat(locale, { day: "numeric", month: "long" }).format(new Date(c.results_at));
  const hour = new Intl.DateTimeFormat(locale, { hour: "2-digit", minute: "2-digit" }).format(new Date(c.results_at));

  return (
    <dl className="grid grid-cols-[repeat(2,minmax(0,1fr))] gap-3 xl:grid-cols-[repeat(4,minmax(0,1fr))]">
      <StatCard
        label={t("stat_entries")}
        value={entryCount}
        sub={summary && summary.disqualified > 0 ? t("stat_disqualified", { count: summary.disqualified }) : t("stat_no_disqualified")}
      />
      {jury ? (
        <StatCard
          label={t("stat_jury_progress")}
          value={`%${pct}`}
          tone="accent"
          sub={judges.length ? t("stat_jury_finished", { done: finished, total: judges.length }) : t("stat_no_judges")}
        />
      ) : (
        <StatCard label={t("stat_votes")} value={summary?.votes ?? "–"} tone="accent" sub={t("stat_voters_n", { count: summary?.voters ?? 0 })} />
      )}
      <StatCard
        label={deadlinePassed ? t("stat_entries_closed") : t("stat_entries_close")}
        value={relTime(c.submission_deadline, locale, now)}
        sub={
          !deadlinePassed
            ? t("stat_then_judging")
            : votingPassed
              ? t("stat_judging_over")
              : t("stat_judging_left", { time: relTime(c.voting_end, locale, now) })
        }
      />
      <StatCard
        label={t("stat_results")}
        value={day}
        sub={c.status === "finished" ? t("stat_announced") : t("stat_results_auto", { time: hour })}
      />
    </dl>
  );
}

type Filter = "all" | "incomplete" | "disqualified";

function Entries({
  c,
  list,
  loading,
  counts,
  judgeTotal,
  onDisqualify,
}: {
  c: Contest;
  list: Entry[];
  loading: boolean;
  counts: Map<string, number> | null;
  judgeTotal: number;
  onDisqualify: (id: string, reason: string) => void;
}) {
  const t = useTranslations("manage");
  const [filter, setFilter] = useState<Filter>("all");
  const [query, setQuery] = useState("");
  const numbers = useMemo(() => entryNumbers(list), [list]);
  const jury = c.judging_mode === "jury";
  const hideNames = c.anonymous && c.status !== "finished";
  const showIncomplete = jury && counts !== null && judgeTotal > 0;
  const incomplete = (e: Entry) => !e.disqualified && (counts?.get(e.id) ?? 0) < judgeTotal;
  const dqCount = list.filter((e) => e.disqualified).length;

  const shown = list.filter((e) => {
    if (filter === "incomplete" && !incomplete(e)) return false;
    if (filter === "disqualified" && !e.disqualified) return false;
    const q = query.trim().replace(/^#/, "");
    if (q && !String(numbers.get(e.id)).startsWith(q)) return false;
    return true;
  });

  return (
    <section aria-labelledby="entries-h" className="flex flex-col rounded-card bg-surface px-4 py-4 sm:px-[18px]">
      <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
        <h2 id="entries-h" className="text-[17px] font-bold">{t("entries_title")}</h2>
        <div className="flex flex-wrap items-center gap-2">
          <FilterTabs<Filter>
            label={t("entries_filter")}
            value={filter}
            onChange={setFilter}
            items={[
              { key: "all", label: t("filter_all"), count: list.length },
              ...(showIncomplete ? [{ key: "incomplete" as const, label: t("filter_incomplete"), count: list.filter(incomplete).length }] : []),
              { key: "disqualified", label: t("filter_disqualified"), count: dqCount },
            ]}
          />
          <label className="flex h-9 w-[150px] items-center gap-2 rounded-pill border border-line bg-surface px-3.5 text-[14px] text-ink-muted focus-within:border-accent">
            <Search className="h-4 w-4 shrink-0" aria-hidden />
            <span className="sr-only">{t("search_number")}</span>
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              inputMode="numeric"
              placeholder={t("search_number")}
              className="w-full min-w-0 bg-transparent text-ink outline-none placeholder:text-ink-muted"
            />
          </label>
        </div>
      </div>
      {c.status === "open" && <p className="mb-3 text-[14px] text-ink-muted">{t("entries_private")}</p>}
      {!loading && list.length === 0 && <p className="py-6 text-ink-muted">{t("no_entries")}</p>}
      {list.length > 0 && shown.length === 0 && <p className="py-6 text-ink-muted">{t("no_match")}</p>}

      <ul className="grid grid-cols-2 gap-2.5 sm:grid-cols-3 md:grid-cols-4 xl:grid-cols-6">
        {shown.map((e) => {
          const n = numbers.get(e.id);
          const th = smallImage(e);
          const count = counts?.get(e.id) ?? 0;
          return (
            <li key={e.id} className="group relative overflow-hidden rounded-photo bg-surface-2">
              <div className="print-placeholder relative h-[118px] w-full">
                {th && (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={th.url} alt={e.title ?? t("entry_n", { n: n ?? 0 })} loading="lazy" className="h-full w-full object-contain" />
                )}
                {e.disqualified && (
                  <div title={e.disqualify_reason ?? undefined} className="absolute inset-0 flex flex-col items-center justify-center gap-1 bg-danger/40 px-2 text-center text-white">
                    <span className="inline-flex items-center gap-1.5 text-[12.5px] font-bold"><Ban className="h-4 w-4 shrink-0" aria-hidden /> {t("disqualified")}</span>
                    {e.disqualify_reason && <span className="line-clamp-2 text-[11.5px] font-medium opacity-90">{e.disqualify_reason}</span>}
                  </div>
                )}
                {!e.disqualified && c.status !== "finished" && (
                  <button
                    type="button"
                    aria-label={t("disqualify_n", { n: n ?? 0 })}
                    title={t("disqualify")}
                    onClick={() => {
                      const reason = window.prompt(t("disqualify_reason"));
                      if (reason?.trim()) onDisqualify(e.id, reason.trim());
                    }}
                    className="scrim absolute right-1.5 top-1.5 inline-flex h-8 w-8 items-center justify-center rounded-full text-ink opacity-100 transition-opacity hover:text-danger focus-visible:opacity-100 md:opacity-0 md:group-hover:opacity-100"
                  >
                    <Ban className="h-4 w-4" aria-hidden />
                  </button>
                )}
              </div>
              <div className="flex items-center justify-between gap-2 px-[9px] py-[7px] text-[12px]">
                <b className="tnum">#{n}</b>
                {e.disqualified ? (
                  <span className="font-bold text-danger">{t("disqualified")}</span>
                ) : counts && jury ? (
                  <span className="tnum font-medium text-ink-muted">{t("jury_count", { done: count, total: judgeTotal })}</span>
                ) : counts ? (
                  <span className="tnum font-medium text-ink-muted">{t("votes_count", { count })}</span>
                ) : null}
              </div>
              {!hideNames && e.user && <p className="-mt-1 truncate px-[9px] pb-[7px] text-[12px] text-ink-muted">{e.user.display_name}</p>}
            </li>
          );
        })}
      </ul>
      {hideNames && (
        <p className="mt-3 flex items-center gap-1.5 text-caption text-ink-muted">
          <Lock className="h-3.5 w-3.5" aria-hidden /> {t("anonymous_note")}
        </p>
      )}
    </section>
  );
}

function JuryBoard({ c, judges, valid, judgesKey }: { c: Contest; judges: Judge[]; valid: Entry[]; judgesKey: unknown[] }) {
  const t = useTranslations("manage");
  const qc = useQueryClient();
  const [adding, setAdding] = useState(false);
  const [who, setWho] = useState("");
  const [weight, setWeight] = useState("1");
  const locked = c.status === "closed" || c.status === "finished";
  const set = (data: Judge[]) => qc.setQueryData(judgesKey, data);
  const add = useMutation({
    mutationFn: () => {
      const v = who.trim();
      const body = v.includes("@") && !v.startsWith("@") ? { email: v, weight: Number(weight) } : { username: v.replace(/^@/, ""), weight: Number(weight) };
      return api<Judge[]>(`contests/${c.id}/judges`, { method: "POST", body });
    },
    onSuccess: (d) => {
      set(d);
      setWho("");
      setWeight("1");
      setAdding(false);
    },
  });
  const update = useMutation({ mutationFn: ({ id, w }: { id: string; w: number }) => api<Judge[]>(`contests/${c.id}/judges/${id}`, { method: "PATCH", body: { weight: w } }), onSuccess: set });
  const remove = useMutation({ mutationFn: (id: string) => api(`contests/${c.id}/judges/${id}`, { method: "DELETE" }), onSuccess: () => qc.invalidateQueries({ queryKey: judgesKey }) });
  const err = add.error ?? update.error ?? remove.error;

  return (
    <section aria-labelledby="jury-h" className="rounded-card bg-surface px-[18px] py-4">
      <div className="flex items-center justify-between gap-3">
        <h2 id="jury-h" className="text-[17px] font-bold">{t("jury_board")}</h2>
        {!locked && (
          <button
            type="button"
            aria-expanded={adding}
            onClick={() => setAdding((v) => !v)}
            className="inline-flex h-[34px] items-center rounded-pill border border-line px-3 text-[13px] font-bold hover:bg-surface-2"
          >
            {adding ? t("cancel") : t("add_judge")}
          </button>
        )}
      </div>
      {adding && !locked && (
        <form className="mt-3 flex flex-col gap-3 rounded-box bg-surface-2 p-3" onSubmit={(e) => { e.preventDefault(); add.mutate(); }}>
          <TextField label={t("judge_who")} name="judge" placeholder={t("judge_placeholder")} required value={who} onChange={(e) => setWho(e.target.value)} autoFocus />
          <div className="flex items-end gap-3">
            <TextField label={t("weight")} name="weight" type="number" min={0.1} max={10} step={0.5} value={weight} onChange={(e) => setWeight(e.target.value)} className="w-24" />
            <Button type="submit" busy={add.isPending} className="flex-1">{t("add_judge_submit")}</Button>
          </div>
          <p className="text-caption text-ink-muted">{t("judges_lead")}</p>
        </form>
      )}
      {judges.length === 0 && <p className="mt-3 text-[14px] text-ink-muted">{t("no_judges")}</p>}
      <ul className="mt-1">
        {judges.map((j) => {
          const total = eligibleFor(j, valid);
          const done = j.pending ? 0 : Math.min(j.scored, total);
          const complete = !j.pending && total > 0 && done >= total;
          const name = j.user ? j.user.display_name : j.email ?? "";
          return (
            <li key={j.id} className="flex items-center gap-3 border-b border-line py-[11px] last:border-b-0">
              {j.user ? (
                <Avatar name={j.user.display_name} url={j.user.avatar_url} size={36} />
              ) : (
                <span aria-hidden className="h-9 w-9 shrink-0 rounded-full border border-dashed border-ring-idle" />
              )}
              <div className="min-w-0 flex-1">
                <div className="flex items-baseline justify-between gap-2 text-[14px]">
                  <b className="truncate">{name}</b>
                  <span className="tnum shrink-0 text-[12.5px] text-ink-muted">{j.pending ? t("invite_pending") : `${done}/${total}`}</span>
                </div>
                <p className="mb-1.5 truncate text-[12px] text-ink-muted">{j.user ? `@${j.user.username}` : t("invite_no_account")}</p>
                <div
                  className="h-1.5 overflow-hidden rounded-pill bg-surface-2"
                  role="progressbar"
                  aria-label={t("judge_progress", { name })}
                  aria-valuemin={0}
                  aria-valuemax={total}
                  aria-valuenow={done}
                >
                  <div className={clsx("h-full rounded-pill", complete ? "bg-emerald-600" : "bg-accent")} style={{ width: `${total ? (done / total) * 100 : 0}%` }} />
                </div>
              </div>
              {locked ? (
                <span className="tnum shrink-0 rounded-pill bg-surface-2 px-[9px] py-1 text-[12px] font-bold">×{j.weight}</span>
              ) : (
                <label className="tnum flex shrink-0 items-center rounded-pill bg-surface-2 pl-[9px] text-[12px] font-bold">
                  <span aria-hidden>×</span>
                  <span className="sr-only">{t("weight_of", { name })}</span>
                  <input
                    type="number"
                    min={0.1}
                    max={10}
                    step={0.5}
                    defaultValue={j.weight}
                    onBlur={(e) => Number(e.target.value) !== j.weight && update.mutate({ id: j.id, w: Number(e.target.value) })}
                    className="h-7 w-11 bg-transparent pr-1 text-[12px] font-bold outline-none [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none"
                  />
                </label>
              )}
              {!locked && (
                <button type="button" onClick={() => remove.mutate(j.id)} className="-mr-1.5 shrink-0 rounded-full p-1.5 text-ink-muted hover:bg-surface-2 hover:text-ink" aria-label={t("remove_judge_n", { name })}>
                  <X className="h-4 w-4" aria-hidden />
                </button>
              )}
            </li>
          );
        })}
      </ul>
      {err && <div className="mt-3"><Notice tone="error">{errorText(err, t("error"))}</Notice></div>}
      <p className="mt-2.5 text-[12px] leading-[17px] text-ink-muted">{t("jury_board_hint")}</p>
    </section>
  );
}

/** Ödüller kartı: bilerek koyu (tasarımdaki vurgu kartı), derece renkli sıra rozetleri. */
function Prizes({ c }: { c: Contest }) {
  const t = useTranslations("manage");
  return (
    <section aria-labelledby="prizes-h" className="rounded-card bg-[#14161b] px-[18px] py-4 text-white ring-1 ring-white/[.06]">
      <h2 id="prizes-h" className="text-[15px] font-bold">{t("prizes")}</h2>
      {c.prizes.length === 0 ? (
        <p className="mt-2 text-[13.5px] text-white/65">
          {t("no_prizes")}{" "}
          {(c.status === "draft" || c.status === "open") && (
            <a href="#details" className="font-semibold text-white underline underline-offset-4">{t("add_prizes")}</a>
          )}
        </p>
      ) : (
        <ol>
          {c.prizes.map((p) => (
            <li key={p.rank} className="flex items-center gap-2.5 border-b border-white/10 py-2 last:border-b-0">
              <RankBadge rank={p.rank} size={26} tone="dark" />
              <span className="flex-1 text-[14px]">{p.title}</span>
            </li>
          ))}
        </ol>
      )}
    </section>
  );
}
