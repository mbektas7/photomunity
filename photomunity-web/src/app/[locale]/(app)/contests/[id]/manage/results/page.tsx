"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import clsx from "clsx";
import { AlertTriangle, CheckCircle2, ChevronLeft, Download, Info, Megaphone } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useParams } from "next/navigation";
import { useMemo } from "react";
import { RankBadge, StageStepper, entryNumbers, smallImage } from "@/components/contest-ui";
import { Button, Notice } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import { formatDateTime } from "@/lib/dates";
import type { Contest, ContestSummary, Entry, Judge, ResultRow } from "@/lib/types";

function errorText(e: unknown, fallback: string) {
  return e instanceof ApiError && e.message ? e.message : fallback;
}

const same = (a: number | null, b: number | null) => a !== null && b !== null && Math.abs(a - b) < 0.005;

/** Ortalama ikili fark: bir karede jüri üyelerinin puanları birbirinden ne kadar uzak. */
function pairwiseGap(s: number[]) {
  let sum = 0;
  let n = 0;
  for (let i = 0; i < s.length; i++) for (let j = i + 1; j < s.length; j++) {
    sum += Math.abs(s[i]! - s[j]!);
    n++;
  }
  return n ? sum / n : 0;
}

export default function ResultsPreviewPage() {
  const { id } = useParams<{ id: string }>();
  const t = useTranslations("contestResults");
  const tm = useTranslations("manage");
  const locale = useLocale();
  const qc = useQueryClient();
  const q = useQuery({ queryKey: ["contest", id], queryFn: () => api<Contest>(`contests/${id}`) });
  const c = q.data;
  const admin = c?.my_role === "admin";
  const ready = !!c && admin && (c.status === "judging" || c.status === "closed" || c.status === "finished");
  const jury = c?.judging_mode === "jury";

  const results = useQuery({ queryKey: ["contest-preview", id], enabled: ready, queryFn: () => api<ResultRow[]>(`contests/${id}/results`), refetchInterval: c?.status === "finished" ? false : 30_000 });
  const entries = useQuery({ queryKey: ["contest-entries", id, "admin"], enabled: ready, queryFn: () => api<Entry[]>(`contests/${id}/entries?view=admin`) });
  const judges = useQuery({ queryKey: ["contest-judges", id], enabled: ready && jury, queryFn: () => api<Judge[]>(`contests/${id}/judges`) });
  const summary = useQuery({ queryKey: ["contest-summary", id], enabled: ready, queryFn: () => api<ContestSummary>(`contests/${id}/summary`) });

  const announce = useMutation({
    mutationFn: () => api<Contest>(`contests/${id}/announce`, { method: "POST" }),
    onSuccess: (next) => {
      qc.setQueryData(["contest", id], next);
      qc.invalidateQueries({ queryKey: ["contest-preview", id] });
      qc.invalidateQueries({ queryKey: ["contest-entries", id] });
    },
  });

  const numbers = useMemo(() => entryNumbers(entries.data), [entries.data]);
  const rows = useMemo(() => results.data ?? [], [results.data]);
  const fmt = useMemo(() => new Intl.NumberFormat(locale, { minimumFractionDigits: 2, maximumFractionDigits: 2 }), [locale]);
  const fmt1 = useMemo(() => new Intl.NumberFormat(locale, { minimumFractionDigits: 1, maximumFractionDigits: 1 }), [locale]);

  if (q.error) return <div className="mx-auto max-w-[680px] px-4 py-20"><Notice tone="error">{errorText(q.error, tm("error"))}</Notice></div>;
  if (!c) return <div className="h-[60vh]" aria-busy />;
  if (!admin) return <div className="mx-auto max-w-[680px] px-4 py-20"><Notice tone="error">{tm("forbidden")}</Notice></div>;
  if (!ready) return <div className="mx-auto max-w-[680px] px-4 py-20"><Notice>{t("not_yet")}</Notice></div>;

  const accepted = (judges.data ?? []).filter((j) => !j.pending);
  const pending = (judges.data ?? []).filter((j) => j.pending);
  const tieWith = (i: number) => (i > 0 && same(rows[i - 1]!.score, rows[i]!.score)) || (i < rows.length - 1 && same(rows[i + 1]!.score, rows[i]!.score));

  // Eşitlik grupları ("4. ve 5. sıra")
  const ties: number[][] = [];
  rows.forEach((r, i) => {
    if (!r.rank || i === 0 || !same(rows[i - 1]!.score, r.score) || !rows[i - 1]!.rank) return;
    const last = ties.at(-1);
    if (last && last.at(-1) === rows[i - 1]!.rank) last.push(r.rank);
    else ties.push([rows[i - 1]!.rank!, r.rank]);
  });

  // Jüri tutarlılığı (yalnızca jüri modunda tek tek puanlar gelir)
  const spread = rows.filter((r) => (r.scores?.length ?? 0) >= 2).map((r) => ({ r, gap: pairwiseGap(r.scores!) }));
  const avgGap = spread.length ? spread.reduce((s, x) => s + x.gap, 0) / spread.length : null;
  const widest = spread.reduce<(typeof spread)[number] | null>((m, x) => (!m || x.gap > m.gap ? x : m), null);

  const validCount = summary.data ? summary.data.entries - summary.data.disqualified : null;
  const finishedJudges = accepted.filter((j) => {
    const own = entries.data?.some((e) => !e.disqualified && j.user && e.user?.id === j.user.id) ? 1 : 0;
    return validCount !== null && j.scored >= validCount - own;
  }).length;
  const unranked = rows.filter((r) => r.rank === null).length;

  type Check = { tone: "ok" | "warn" | "info"; text: string };
  const checks: Check[] = [];
  if (jury) {
    checks.push(
      accepted.length && finishedJudges === accepted.length
        ? { tone: "ok", text: t("check_jury_done", { done: finishedJudges, total: accepted.length }) }
        : { tone: "warn", text: t("check_jury_open", { done: finishedJudges, total: accepted.length }) },
    );
    if (pending.length) checks.push({ tone: "warn", text: t("check_pending", { count: pending.length }) });
  } else if (summary.data) {
    checks.push({ tone: "info", text: t("check_votes", { voters: summary.data.voters, votes: summary.data.votes }) });
    if (summary.data.suspicious_ips > 0) checks.push({ tone: "warn", text: tm("suspicious", { count: summary.data.suspicious_ips }) });
  }
  if (unranked) checks.push({ tone: "warn", text: t("check_unranked", { count: unranked, min: c.min_votes }) });
  checks.push(
    ties.length
      ? { tone: "info", text: t(jury ? "check_ties_jury" : "check_ties_public", { ranks: ties.map((g) => g.join("–")).join(", ") }) }
      : { tone: "ok", text: t("check_no_ties") },
  );
  if (summary.data && summary.data.disqualified > 0) checks.push({ tone: "ok", text: t("check_dq", { count: summary.data.disqualified }) });

  function downloadCsv() {
    const head = [t("col_rank"), t("col_number"), t("col_title"), t("col_photographer"), t("col_score"), jury ? t("col_judges") : t("col_votes"), t("col_prize"), ...(jury ? [t("col_scores")] : [])];
    const body = rows.map((r) => [
      r.rank ?? "",
      numbers.get(r.entry.id) ?? "",
      r.entry.title ?? "",
      r.entry.user ? `${r.entry.user.display_name} (@${r.entry.user.username})` : "",
      r.score !== null ? r.score.toFixed(2) : "",
      r.count,
      r.prize ?? "",
      ...(jury ? [(r.scores ?? []).join(" ")] : []),
    ]);
    const esc = (v: unknown) => {
      const s = String(v);
      return /[",;\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
    };
    const csv = "﻿" + [head, ...body].map((line) => line.map(esc).join(",")).join("\n");
    const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
    const a = document.createElement("a");
    a.href = url;
    a.download = `${c!.title.replace(/[^\p{L}\p{N}]+/gu, "-").replace(/^-|-$/g, "").toLowerCase() || "results"}.csv`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  return (
    <div className="pb-6">
      <div className="border-b border-line bg-surface">
        <div className="mx-auto flex max-w-[1440px] flex-wrap items-center gap-x-[18px] gap-y-3 px-4 py-3.5 sm:px-6 lg:px-8 xl:h-[72px] xl:flex-nowrap xl:py-0">
          <Link href={`/contests/${c.id}/manage`} aria-label={t("back")} className="inline-flex h-[38px] w-[38px] shrink-0 items-center justify-center rounded-full border border-line hover:bg-surface-2">
            <ChevronLeft className="h-[18px] w-[18px]" aria-hidden />
          </Link>
          <div className="min-w-0 flex-1 xl:flex-none">
            <h1 className="truncate text-[17px] font-bold">{c.title}</h1>
            <p className="truncate text-caption text-ink-muted">{c.status === "finished" ? t("subtitle_final") : t("subtitle")}</p>
          </div>
          <div className="order-last flex min-w-0 w-full overflow-x-auto xl:order-none xl:w-auto xl:flex-1 xl:justify-center">
            <StageStepper status={c.status} />
          </div>
          <div className="flex shrink-0 gap-2 max-sm:order-last max-sm:w-full max-sm:[&>*:last-child]:flex-1">
            <button
              type="button"
              onClick={downloadCsv}
              disabled={!rows.length}
              className="inline-flex h-10 items-center gap-[7px] whitespace-nowrap rounded-pill border border-line bg-surface px-4 text-[14px] font-bold hover:bg-surface-2 disabled:opacity-50"
            >
              <Download className="h-4 w-4" aria-hidden /> {t("csv")}
            </button>
            {c.status === "finished" ? (
              <Link href={`/contests/${c.id}`} className="inline-flex h-10 items-center gap-[7px] whitespace-nowrap rounded-pill bg-accent px-4 text-[14px] font-bold text-accent-ink hover:brightness-110">
                <Megaphone className="h-4 w-4" aria-hidden /> {t("view_announcement")}
              </Link>
            ) : (
              <Button
                className="h-10 min-h-10 px-4 text-[14px]"
                disabled={c.status !== "closed"}
                title={c.status !== "closed" ? t("announce_after_voting") : undefined}
                busy={announce.isPending}
                onClick={() => window.confirm(t("announce_confirm")) && announce.mutate()}
              >
                <Megaphone className="h-4 w-4" aria-hidden /> {t("announce")}
              </Button>
            )}
          </div>
        </div>
      </div>

      <div className="mx-auto max-w-[1440px] px-4 pt-5 sm:px-6 lg:px-8">
        {announce.error && <div className="mb-4"><Notice tone="error">{errorText(announce.error, tm("error"))}</Notice></div>}
        {announce.isSuccess && (
          <div className="mb-4">
            <Notice tone="success">
              {t("announced")}{" "}
              <Link href={`/contests/${c.id}`} className="font-semibold text-accent-text underline underline-offset-4">{t("view_announcement")}</Link>
            </Notice>
          </div>
        )}
        <div className="grid grid-cols-[minmax(0,1fr)] items-start gap-5 lg:grid-cols-[minmax(0,1fr)_340px]">
          <section aria-labelledby="table-h" className="min-w-0 rounded-card bg-surface px-1.5 py-2">
            <div className="flex flex-wrap items-center justify-between gap-2 px-3.5 pb-1 pt-2.5">
              <h2 id="table-h" className="text-[17px] font-bold">{jury ? t("table_jury") : t("table_public")}</h2>
              <span className="rounded-pill bg-accent-tint px-[9px] py-1 text-[12px] font-bold text-accent-text">{jury ? t("scale_jury") : t("scale_public")}</span>
            </div>
            {results.isLoading && <div className="h-40" aria-busy />}
            {results.error && <div className="p-3"><Notice tone="error">{errorText(results.error, tm("error"))}</Notice></div>}
            {results.isSuccess && rows.length === 0 && <p className="px-3.5 py-8 text-ink-muted">{t("empty")}</p>}
            {rows.length > 0 && (
              <div className="overflow-x-auto">
                <table className="w-full min-w-[720px] border-collapse text-left">
                  <thead>
                    <tr className="text-[12px] font-bold text-ink-muted">
                      <th scope="col" className="w-[7%] border-b border-line px-3.5 py-3">{t("col_rank")}</th>
                      <th scope="col" className="w-[33%] border-b border-line px-3.5 py-3">{t("col_entry")}</th>
                      <th scope="col" className="w-[12%] border-b border-line px-3.5 py-3">{t("col_score")}</th>
                      <th scope="col" className="w-[8%] border-b border-line px-3.5 py-3">{jury ? t("col_judges") : t("col_votes")}</th>
                      {jury && <th scope="col" className="w-[20%] border-b border-line px-3.5 py-3">{t("col_spread")}</th>}
                      <th scope="col" className="border-b border-line px-3.5 py-3">{t("col_prize")}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((r, i) => {
                      const th = smallImage(r.entry);
                      const n = numbers.get(r.entry.id);
                      return (
                        <tr key={r.entry.id} className="text-[14px]">
                          <td className="border-b border-line px-3.5 py-3 align-middle"><RankBadge rank={r.rank} /></td>
                          <td className="border-b border-line px-3.5 py-3 align-middle">
                            <div className="flex items-center gap-3">
                              <span className="print-placeholder block h-11 w-16 shrink-0 overflow-hidden rounded-[8px]">
                                {th && (
                                  // eslint-disable-next-line @next/next/no-img-element
                                  <img src={th.url} alt="" loading="lazy" className="h-full w-full object-contain" />
                                )}
                              </span>
                              <div className="min-w-0">
                                <b className="tnum">{n ? `#${n}` : "–"}</b>
                                <p className="truncate text-[12.5px] text-ink-muted">{[r.entry.title, r.entry.user?.display_name].filter(Boolean).join(" · ")}</p>
                              </div>
                            </div>
                          </td>
                          <td className="border-b border-line px-3.5 py-3 align-middle">
                            <b className="tnum text-[17px]">{r.score !== null ? fmt.format(r.score) : "–"}</b>
                            {r.rank && tieWith(i) && <p className="text-[11.5px] leading-tight text-ink-muted">{jury ? t("tie_jury") : t("tie_public")}</p>}
                          </td>
                          <td className="tnum border-b border-line px-3.5 py-3 align-middle">{jury ? `${r.count}/${accepted.length || r.count}` : r.count}</td>
                          {jury && (
                            <td className="border-b border-line px-3.5 py-3 align-middle">
                              <Dots scores={r.scores ?? []} label={t("spread_label", { scores: (r.scores ?? []).join(", ") })} />
                            </td>
                          )}
                          <td className="border-b border-line px-3.5 py-3 align-middle">
                            {r.prize ? (
                              <span className="inline-block max-w-full truncate rounded-pill bg-accent-tint px-[9px] py-1 text-[12px] font-bold text-accent-text">{r.prize}</span>
                            ) : (
                              <span className="text-ink-subtle">—</span>
                            )}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </section>

          <aside className="flex flex-col gap-4">
            <section aria-labelledby="check-h" className="rounded-card bg-surface p-[18px]">
              <h2 id="check-h" className="text-[15px] font-bold">{c.status === "finished" ? t("check_title_final") : t("check_title")}</h2>
              <ul>
                {checks.map((x) => (
                  <li key={x.text} className="flex gap-2.5 border-b border-line py-[9px] text-[13.5px] last:border-b-0">
                    {x.tone === "ok" ? (
                      <CheckCircle2 className="mt-px h-4 w-4 shrink-0 text-emerald-600" aria-hidden />
                    ) : x.tone === "warn" ? (
                      <AlertTriangle className="mt-px h-4 w-4 shrink-0 text-amber-600" aria-hidden />
                    ) : (
                      <Info className="mt-px h-4 w-4 shrink-0 text-accent-text" aria-hidden />
                    )}
                    <span>{x.text}</span>
                  </li>
                ))}
              </ul>
              <p className="mt-2.5 text-[12.5px] leading-[18px] text-ink-muted">
                {c.status === "closed"
                  ? t("announce_note", { date: formatDateTime(c.results_at, locale) })
                  : c.status === "judging"
                    ? t("judging_note", { end: formatDateTime(c.voting_end, locale), date: formatDateTime(c.results_at, locale) })
                    : t("final_note")}
              </p>
            </section>
            {jury && avgGap !== null && (
              <section aria-labelledby="consistency-h" className="rounded-card bg-[linear-gradient(150deg,#1a2050,#0d1130)] p-[18px] text-white">
                <h2 id="consistency-h" className="text-[12px] font-bold uppercase tracking-[.4px] text-white/60">{t("consistency")}</h2>
                <p className="mt-1.5 text-[15px] leading-[1.45]">
                  {t.rich("consistency_avg", { gap: fmt1.format(avgGap), b: (ch) => <b>{ch}</b> })}
                  {widest && widest.gap > 0 && (
                    <>
                      {" "}
                      {t("consistency_widest", {
                        n: numbers.get(widest.r.entry.id) ?? "–",
                        min: Math.min(...widest.r.scores!),
                        max: Math.max(...widest.r.scores!),
                      })}
                    </>
                  )}
                </p>
              </section>
            )}
          </aside>
        </div>
      </div>
    </div>
  );
}

/** 1–10 çizgisinde tek tek jüri puanları; üst üste binen noktalar koyulaşır. */
function Dots({ scores, label }: { scores: number[]; label: string }) {
  return (
    <div role="img" aria-label={label} className="relative h-3 w-[150px] max-w-full">
      <span className="absolute inset-x-0 top-[5px] h-0.5 bg-line" />
      {scores.map((s, k) => (
        <span
          key={k}
          className={clsx("absolute top-0.5 h-2 w-2 -translate-x-1/2 rounded-full bg-accent", scores.length > 1 && "opacity-70")}
          style={{ left: `${((s - 1) / 9) * 100}%` }}
        />
      ))}
    </div>
  );
}
