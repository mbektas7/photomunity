"use client";

import { Flag } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useState } from "react";
import { ActionButton, Card, Chip, Failed, GlobalSearch, Loading, PageHeader, Pills, Td, Th, Who, fmtDate, useAdminStats } from "@/components/admin";
import { Link, useRouter } from "@/i18n/navigation";
import { countryName } from "@/lib/format";
import { relativeTime } from "@/lib/relative-time";

export default function AdminOverview() {
  const t = useTranslations("admin");
  const locale = useLocale();
  const router = useRouter();
  const [days, setDays] = useState<"7" | "30" | "90">("30");
  const q = useAdminStats(Number(days));
  const s = q.data;
  const today = new Intl.DateTimeFormat(locale, { dateStyle: "full" }).format(new Date());
  const num = (n: number) => new Intl.NumberFormat(locale).format(n);

  return (
    <>
      <PageHeader title={t("nav_overview")} sub={today} right={<GlobalSearch />} />
      {q.error && <Failed error={q.error} />}
      {!s ? (
        !q.error && <Loading />
      ) : (
        <>
          <div className="grid grid-cols-2 gap-3.5 md:grid-cols-3 xl:grid-cols-6">
            {[
              [t("kpi_users"), s.users.total, <Chip key="u" tone="ok">{t("this_week", { n: s.users.week })}</Chip>],
              [t("kpi_photos"), s.photos.total, <Chip key="p" tone="ok">{t("this_week", { n: s.photos.week })}</Chip>],
              [t("kpi_pro"), s.pro.total, null],
              [t("kpi_reports"), s.reports.open, s.reports.overdue > 0 ? <Chip key="r" tone="danger">{t("overdue", { n: s.reports.overdue })}</Chip> : null],
              [t("kpi_communities"), s.communities.total, <Chip key="c">{t("this_month", { n: s.communities.month })}</Chip>],
              [t("kpi_contests"), s.contests.running, <Chip key="k">{t("judging_n", { n: s.contests.judging })}</Chip>],
            ].map(([label, value, chip]) => (
              <Card key={String(label)} pad="p-[18px]">
                <div className="text-[13px] font-semibold text-ink-muted">{label}</div>
                <div className="mt-1.5 text-[30px] font-bold tracking-[-0.02em] tabular-nums">{num(value as number)}</div>
                {chip && <div className="mt-2">{chip}</div>}
              </Card>
            ))}
          </div>

          <div className="mt-3.5 flex flex-col gap-3.5 xl:flex-row">
            <Card className="xl:flex-[1.6]">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <h2 className="text-[16px] font-bold">{t("uploads_title")}</h2>
                <Pills value={days} onChange={setDays} items={(["7", "30", "90"] as const).map((d) => ({ key: d, label: t("days", { n: d }) }))} />
              </div>
              <UploadsChart data={s.uploads} label={t("uploads_aria", { n: days })} locale={locale} />
              <div className="flex justify-between text-xs text-ink-muted">
                <span>{fmtDate(s.uploads[0]?.date, locale)}</span>
                <span>{t("today_n", { n: s.uploads.at(-1)?.count ?? 0 })}</span>
              </div>
            </Card>
            <Card className="xl:flex-1">
              <h2 className="mb-1 text-[16px] font-bold">{t("pending_title")}</h2>
              <ul>
                {s.reports.open > 0 && (
                  <li className="flex items-center gap-3 border-b border-line py-3 text-sm"><Chip tone="danger">{t("nav_reports")}</Chip>{t("pending_reports", { n: s.reports.open })}</li>
                )}
                {s.pending.grace > 0 && (
                  <li className="flex items-center gap-3 border-b border-line py-3 text-sm"><Chip tone="warn">{t("nav_subscriptions")}</Chip>{t("pending_grace", { n: s.pending.grace })}</li>
                )}
                {s.pending.awaiting_results.map((c) => (
                  <li key={c.id} className="flex items-center gap-3 border-b border-line py-3 text-sm">
                    <Chip tone="acc">{t("nav_contests")}</Chip>
                    <span className="min-w-0 flex-1 truncate">{t("pending_results", { title: c.title })}</span>
                    <span className="text-xs text-ink-muted">{relativeTime(c.results_at, locale)}</span>
                  </li>
                ))}
                {s.reports.open === 0 && s.pending.grace === 0 && s.pending.awaiting_results.length === 0 && (
                  <li className="py-3 text-sm text-ink-muted">{t("pending_none")}</li>
                )}
              </ul>
              <ActionButton tone="dark" icon={Flag} className="mt-4" onClick={() => router.push("/admin/reports")}>{t("go_reports")}</ActionButton>
            </Card>
          </div>

          <Card className="mt-3.5 overflow-x-auto" pad="p-2">
            <table className="w-full min-w-[640px] border-collapse">
              <thead><tr><Th>{t("recent_signups")}</Th><Th>{t("col_login")}</Th><Th>{t("col_country")}</Th><Th>{t("col_photos")}</Th><Th>{t("col_joined")}</Th></tr></thead>
              <tbody>
                {s.recent_users.map((u) => (
                  <tr key={u.id} className="hover:bg-surface-2/60">
                    <Td><Link href={`/admin/users?user=${u.id}`}><Who user={u} /></Link></Td>
                    <Td>{u.providers.map((p) => t(`provider_${p}` as "provider_email")).join(", ") || "—"}</Td>
                    <Td>{u.country ? countryName(u.country, locale) : "—"}</Td>
                    <Td className="tabular-nums">{u.photo_count}</Td>
                    <Td>{relativeTime(u.created_at, locale)}</Td>
                  </tr>
                ))}
              </tbody>
            </table>
          </Card>
        </>
      )}
    </>
  );
}

function UploadsChart({ data, label, locale }: { data: { date: string; count: number }[]; label: string; locale: string }) {
  const max = Math.max(1, ...data.map((d) => d.count));
  const w = 21;
  return (
    <svg viewBox={`0 0 ${data.length * w} 190`} preserveAspectRatio="none" className="mt-3.5 h-[220px] w-full" role="img" aria-label={label}>
      {data.map((d, i) => {
        const h = Math.max(2, (d.count / max) * 170);
        return (
          <rect key={d.date} x={i * w + 3} y={180 - h} width={w - 7} height={h} rx={4} className={i === data.length - 1 ? "fill-accent" : "fill-accent/35"}>
            <title>{`${fmtDate(d.date, locale)}: ${d.count}`}</title>
          </rect>
        );
      })}
    </svg>
  );
}
