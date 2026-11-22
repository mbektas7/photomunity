"use client";

import { useQuery } from "@tanstack/react-query";
import { ExternalLink } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useState } from "react";
import { Card, Chip, Empty, Failed, Loading, PageHeader, Pills, Td, Th, Who, fmtDate } from "@/components/admin";
import { Link } from "@/i18n/navigation";
import type { AdminSubscription } from "@/lib/admin-types";
import { api } from "@/lib/api";

const STORES = ["all", "app_store", "play_store", "stripe"] as const;
const STATUSES = ["all", "active", "grace", "cancelled", "expired"] as const;
const TONE = { active: "ok", grace: "warn", cancelled: "muted", expired: "danger" } as const;

type Res = { summary: { active: number; not_renewing: number; grace: number; ending_this_month: number }; items: AdminSubscription[] };

export default function AdminSubscriptions() {
  const t = useTranslations("admin");
  const locale = useLocale();
  const [store, setStore] = useState<(typeof STORES)[number]>("all");
  const [status, setStatus] = useState<(typeof STATUSES)[number]>("all");
  const params = new URLSearchParams();
  if (store !== "all") params.set("store", store);
  if (status !== "all") params.set("status", status);
  const q = useQuery({ queryKey: ["admin", "subs", store, status], queryFn: () => api<Res>(`admin/subscriptions?${params}`) });
  const s = q.data?.summary;

  return (
    <>
      <PageHeader title={t("nav_subscriptions")} sub={t("subs_sub")} right={
        <a href="https://app.revenuecat.com" target="_blank" rel="noreferrer" className="inline-flex h-10 items-center gap-2 rounded-full border border-line bg-surface px-4 text-sm font-bold hover:bg-surface-2">
          <ExternalLink className="h-4 w-4" />{t("open_revenuecat")}
        </a>
      } />
      {s && (
        <div className="mb-3.5 grid grid-cols-2 gap-3.5 lg:grid-cols-4">
          {([["s_active", s.active], ["s_not_renewing", s.not_renewing], ["s_grace", s.grace], ["s_ending", s.ending_this_month]] as const).map(([k, v]) => (
            <Card key={k} pad="p-[18px]"><div className="text-[13px] font-semibold text-ink-muted">{t(k)}</div><div className="mt-1.5 text-[28px] font-bold tabular-nums">{v}</div></Card>
          ))}
        </div>
      )}
      <div className="mb-3.5 flex flex-wrap gap-2.5">
        <Pills value={store} onChange={setStore} items={STORES.map((k) => ({ key: k, label: t(`store_${k}` as "store_all") }))} />
        <div className="flex-1" />
        <Pills value={status} onChange={setStatus} items={STATUSES.map((k) => ({ key: k, label: t(`ss_${k}` as "ss_all") }))} />
      </div>
      {q.error && <Failed error={q.error} />}
      <Card pad="p-2" className="overflow-x-auto">
        {q.isLoading ? <Loading /> : !q.data?.items.length ? <Empty /> : (
          <table className="w-full min-w-[720px] border-collapse">
            <thead><tr><Th>{t("col_user")}</Th><Th>{t("col_store")}</Th><Th>{t("col_product")}</Th><Th>{t("col_status")}</Th><Th>{t("col_renews")}</Th><Th>{t("col_period_end")}</Th></tr></thead>
            <tbody>
              {q.data.items.map((x) => (
                <tr key={x.id} className="hover:bg-surface-2/60">
                  <Td>{x.user ? <Link href={`/admin/users?user=${x.user.id}`}><Who user={x.user} /></Link> : "—"}</Td>
                  <Td>{t(`store_${x.store}` as "store_app_store")}</Td>
                  <Td className="font-mono text-[13px]">{x.product_id ?? "—"}</Td>
                  <Td><Chip tone={TONE[x.status]}>{t(`ss_${x.status}` as "ss_active")}</Chip></Td>
                  <Td>{x.will_renew ? t("yes") : t("no")}</Td>
                  <Td>{fmtDate(x.period_end, locale)}</Td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Card>
    </>
  );
}
