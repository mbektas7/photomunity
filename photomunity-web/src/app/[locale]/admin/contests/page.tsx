"use client";

import { useQuery } from "@tanstack/react-query";
import clsx from "clsx";
import { CalendarClock, Check, ExternalLink, EyeOff, X } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useState } from "react";
import {
  ActionButton, Card, Chip, CommunityBadge, Empty, Failed, Loading, PageHeader, Pills, Row, SearchInput, Td, Th, errorText, fmtDate,
  useAdminAction, useConfirm, useDebounced,
} from "@/components/admin";
import { Notice } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import type { AdminContest, AdminContestDetail, Paged } from "@/lib/admin-types";
import { api } from "@/lib/api";

const TABS = ["running", "judging", "closed", "finished", "hidden"] as const;
const TONE = { draft: "muted", open: "ok", judging: "acc", closed: "warn", finished: "muted", cancelled: "danger" } as const;

export default function AdminContests() {
  const t = useTranslations("admin");
  const locale = useLocale();
  const [tab, setTab] = useState<(typeof TABS)[number]>("running");
  const [q, setQ] = useState("");
  const dq = useDebounced(q.trim());
  const [picked, setPicked] = useState<string | null>(null);
  const params = new URLSearchParams({ tab });
  if (dq) params.set("q", dq);
  const list = useQuery({ queryKey: ["admin", "contests", tab, dq], queryFn: () => api<Paged<AdminContest>>(`admin/contests?${params}`) });
  const stats = useQuery({ queryKey: ["admin", "contests", "counts"], queryFn: async () => {
    const [r, f] = await Promise.all([api<Paged<AdminContest>>("admin/contests?tab=running"), api<Paged<AdminContest>>("admin/contests?tab=finished")]);
    return { running: r.total, finished: f.total };
  } });
  const items = list.data?.items ?? [];
  const sel = picked && items.some((c) => c.id === picked) ? picked : items[0]?.id ?? null;

  return (
    <>
      <PageHeader title={t("nav_contests")} sub={stats.data && t("contests_sub", stats.data)}
        right={<SearchInput value={q} onChange={setQ} placeholder={t("search_contests_ph")} className="w-full sm:w-[320px]" />} />
      <div className="mb-3.5">
        <Pills value={tab} onChange={(v) => { setTab(v); setPicked(null); }} items={TABS.map((k) => ({ key: k, label: t(`ct_${k}` as "ct_running") }))} />
      </div>
      {list.error && <Failed error={list.error} />}
      <div className="flex flex-col items-start gap-3.5 xl:flex-row">
        <Card pad="p-2" className="w-full min-w-0 flex-1 overflow-x-auto">
          {list.isLoading ? <Loading /> : !items.length ? <Empty /> : (
            <table className="w-full min-w-[760px] border-collapse">
              <thead><tr><Th>{t("col_contest")}</Th><Th>{t("col_community")}</Th><Th>{t("col_stage")}</Th><Th>{t("col_entries")}</Th><Th>{t("col_deadline")}</Th><Th>{t("col_results")}</Th><Th>{t("col_status")}</Th></tr></thead>
              <tbody>
                {items.map((c) => (
                  <tr key={c.id} onClick={() => setPicked(c.id)} className={clsx("cursor-pointer", c.id === sel ? "bg-accent-tint" : "hover:bg-surface-2/60")}>
                    <Td className="max-w-[220px]"><button type="button" onClick={() => setPicked(c.id)} className="w-full truncate text-left font-bold">{c.title}</button></Td>
                    <Td className="max-w-[240px]">
                      <span className="flex min-w-0 items-center gap-2.5">
                        <CommunityBadge c={c.community} />
                        <span className="min-w-0"><span className="block truncate font-semibold">{c.community.name}</span><span className="block truncate text-[12.5px] text-ink-muted">{t(`mode_${c.judging_mode}` as "mode_jury")}</span></span>
                      </span>
                    </Td>
                    <Td><Chip tone={TONE[c.status]}>{t(`cs_${c.status}` as "cs_open")}</Chip></Td>
                    <Td className="tabular-nums">{c.entry_count}</Td>
                    <Td>{fmtDate(c.submission_deadline, locale)}</Td>
                    <Td>{fmtDate(c.results_at, locale)}</Td>
                    <Td>{c.hidden ? <Chip tone="warn">{t("st_hidden")}</Chip> : <Chip tone="ok">{t("status_active")}</Chip>}</Td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </Card>
        <div className="w-full xl:sticky xl:top-6 xl:w-[330px] xl:shrink-0">
          {sel ? <ContestDetail id={sel} locale={locale} /> : <Card><Empty>{t("select_contest")}</Empty></Card>}
        </div>
      </div>
    </>
  );
}

const toLocal = (iso: string) => {
  const d = new Date(iso);
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
};

function ContestDetail({ id, locale }: { id: string; locale: string }) {
  const t = useTranslations("admin");
  const [dialog, confirm] = useConfirm();
  const [editing, setEditing] = useState(false);
  const q = useQuery({ queryKey: ["admin", "contest", id], queryFn: () => api<AdminContestDetail>(`admin/contests/${id}`) });
  const hidden = useAdminAction((v: { hidden: boolean; note: string }) => api(`admin/contests/${id}/hidden`, { method: "POST", body: { hidden: v.hidden, note: v.note || null } }));
  const cancel = useAdminAction((note: string) => api(`admin/contests/${id}/cancel`, { method: "POST", body: { note: note || null } }));
  const dates = useAdminAction((v: { submission_deadline: string; voting_end: string; results_at: string }) => api(`admin/contests/${id}/dates`, { method: "POST", body: v }), () => setEditing(false));
  const c = q.data;
  if (q.error) return <Failed error={q.error} />;
  if (!c) return <Card><Loading /></Card>;
  const err = hidden.error ?? cancel.error ?? dates.error;
  const stage = { draft: -1, open: 0, judging: 1, closed: 2, finished: 3, cancelled: -1 }[c.status];
  const editable = c.status !== "finished" && c.status !== "cancelled";

  return (
    <Card pad="p-[18px]">
      {dialog}
      <div className="text-[18px] font-bold">{c.title}</div>
      <div className="text-[13px] text-ink-muted">{[c.community.name, t(`mode_${c.judging_mode}` as "mode_jury"), c.anonymous && t("anon")].filter(Boolean).join(" · ")}</div>
      <div className="mt-3.5 flex gap-1.5" aria-label={t("col_stage")}>
        {[t("stage_submit"), t("stage_vote"), t("stage_result")].map((l, i) => (
          <div key={l} className="flex-1 text-center">
            <div className={clsx("h-1.5 rounded-full", i <= stage ? "bg-accent" : "bg-line")} />
            <div className="mt-1.5 text-[11.5px] text-ink-muted">{l}</div>
          </div>
        ))}
      </div>
      <div className="mt-3.5">
        <Row label={t("k_entries")}>{t("k_entries_val", { entries: c.entry_count, people: c.entrant_count })}</Row>
        {c.judging_mode === "jury" && <Row label={t("k_jury")}>{t("k_jury_val", { done: c.judges_done, total: c.judge_count })}</Row>}
        <Row label={t("k_reported")}>{c.reported_entries}</Row>
        <Row label={t("date_deadline")}>{fmtDate(c.submission_deadline, locale, true)}</Row>
        <Row label={t("date_voting")}>{fmtDate(c.voting_end, locale, true)}</Row>
        <Row label={t("date_results")}>{fmtDate(c.results_at, locale, true)}</Row>
      </div>
      {editing && (
        <form className="mt-3 flex flex-col gap-2 rounded-2xl bg-bg p-3" onSubmit={(e) => {
          e.preventDefault();
          const f = new FormData(e.currentTarget);
          const iso = (k: string) => new Date(String(f.get(k))).toISOString();
          dates.mutate({ submission_deadline: iso("d"), voting_end: iso("v"), results_at: iso("r") });
        }}>
          {([["d", "date_deadline", c.submission_deadline], ["v", "date_voting", c.voting_end], ["r", "date_results", c.results_at]] as const).map(([n, l, v]) => (
            <label key={n} className="flex flex-col gap-1 text-[12.5px] font-semibold text-ink-muted">
              {t(l)}
              <input type="datetime-local" name={n} defaultValue={toLocal(v)} required className="h-10 rounded-xl border border-line bg-surface px-2.5 text-sm font-normal text-ink" />
            </label>
          ))}
          <p className="text-xs text-ink-muted">{t("dates_invalid")}</p>
          <div className="flex gap-2">
            <ActionButton type="submit" tone="dark" disabled={dates.isPending}>{t("save")}</ActionButton>
            <ActionButton onClick={() => setEditing(false)}>{t("cancel")}</ActionButton>
          </div>
        </form>
      )}
      <div className="mt-4 flex flex-col gap-2">
        {!c.hidden && (
          <Link href={`/contests/${c.id}`} className="inline-flex h-10 items-center justify-center gap-2 rounded-full border border-line text-sm font-bold hover:bg-surface-2">
            <ExternalLink className="h-4 w-4" />{t("act_view_contest")}
          </Link>
        )}
        {editable && !editing && <ActionButton icon={CalendarClock} onClick={() => setEditing(true)}>{t("act_dates")}</ActionButton>}
        {c.status !== "cancelled" && (c.hidden ? (
          <ActionButton tone="primary" icon={Check} disabled={hidden.isPending} onClick={() => hidden.mutate({ hidden: false, note: "" })}>{t("act_unhide_contest")}</ActionButton>
        ) : (
          <ActionButton tone="dark" icon={EyeOff} disabled={hidden.isPending} onClick={async () => {
            const r = await confirm({ title: t("act_hide_contest"), confirm: t("act_hide_contest") });
            if (r) hidden.mutate({ hidden: true, note: r.note });
          }}>{t("act_hide_contest")}</ActionButton>
        ))}
        {editable && (
          <ActionButton tone="danger" icon={X} disabled={cancel.isPending} onClick={async () => {
            const r = await confirm({ title: t("act_cancel_contest"), body: t("confirm_cancel_contest", { title: c.title }), confirm: t("act_cancel_contest"), danger: true });
            if (r) cancel.mutate(r.note);
          }}>{t("act_cancel_contest")}</ActionButton>
        )}
      </div>
      {err && <div className="mt-3"><Notice tone="error">{errorText(err, t("error"))}</Notice></div>}
    </Card>
  );
}
