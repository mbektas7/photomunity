"use client";

import { useQuery } from "@tanstack/react-query";
import clsx from "clsx";
import { Check, ExternalLink, EyeOff, Trash2, Users } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useSearchParams } from "next/navigation";
import { Suspense, useState } from "react";
import {
  ActionButton, Card, Chip, CommunityBadge, Empty, Failed, Loading, PageHeader, Pager, Pills, Row, SearchInput, Td, Th, errorText, fmtDate,
  useAdminAction, useConfirm, useDebounced,
} from "@/components/admin";
import { Notice } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import type { AdminCommunity, AdminCommunityDetail, Paged } from "@/lib/admin-types";
import { api } from "@/lib/api";
import { countryName } from "@/lib/format";

const FILTERS = ["all", "open", "approval", "hidden", "month"] as const;
const LIMIT = 50;

export default function Page() {
  return <Suspense><AdminCommunities /></Suspense>;
}

function AdminCommunities() {
  const t = useTranslations("admin");
  const locale = useLocale();
  const [q, setQ] = useState("");
  const dq = useDebounced(q.trim());
  const [filter, setFilter] = useState<(typeof FILTERS)[number]>("all");
  const [offset, setOffset] = useState(0);
  const [picked, setPicked] = useState<string | null>(useSearchParams().get("community"));
  const params = new URLSearchParams({ filter, offset: String(offset), limit: String(LIMIT) });
  if (dq) params.set("q", dq);
  const list = useQuery({ queryKey: ["admin", "communities", dq, filter, offset], queryFn: () => api<Paged<AdminCommunity>>(`admin/communities?${params}`) });
  const sel = picked && list.data?.items.some((c) => c.id === picked) ? picked : picked ?? list.data?.items[0]?.id ?? null;

  return (
    <>
      <PageHeader title={t("nav_communities")} sub={list.data && t("communities_sub", { n: list.data.total })}
        right={<SearchInput value={q} onChange={(v) => { setQ(v); setOffset(0); }} placeholder={t("search_communities_ph")} className="w-full sm:w-[320px]" />} />
      <div className="mb-3.5">
        <Pills value={filter} onChange={(f) => { setFilter(f); setOffset(0); }} items={FILTERS.map((f) => ({ key: f, label: f === "all" ? t("f_all") : t(`cf_${f}` as "cf_open") }))} />
      </div>
      {list.error && <Failed error={list.error} />}
      <div className="flex flex-col items-start gap-3.5 xl:flex-row">
        <Card pad="p-2" className="w-full min-w-0 flex-1 overflow-x-auto">
          {list.isLoading ? <Loading /> : !list.data?.items.length ? <Empty /> : (
            <>
              <table className="w-full min-w-[720px] border-collapse">
                <thead><tr><Th>{t("col_community")}</Th><Th>{t("col_owner")}</Th><Th>{t("col_join")}</Th><Th>{t("col_members")}</Th><Th>{t("col_posts")}</Th><Th>{t("col_contests")}</Th><Th>{t("col_status")}</Th></tr></thead>
                <tbody>
                  {list.data.items.map((c) => (
                    <tr key={c.id} onClick={() => setPicked(c.id)} className={clsx("cursor-pointer", c.id === sel ? "bg-accent-tint" : "hover:bg-surface-2/60")}>
                      <Td className="max-w-[260px]">
                        <button type="button" onClick={() => setPicked(c.id)} className="flex w-full min-w-0 items-center gap-2.5 text-left">
                          <CommunityBadge c={c} />
                          <span className="min-w-0"><span className="block truncate font-semibold">{c.name}</span><span className="block truncate text-[12.5px] text-ink-muted">/c/{c.slug}</span></span>
                        </button>
                      </Td>
                      <Td>{c.owner ? `@${c.owner.username}` : "—"}</Td>
                      <Td>{c.join_approval ? t("join_approval") : t("join_open")}</Td>
                      <Td className="tabular-nums">{c.member_count}</Td>
                      <Td className="tabular-nums">{c.post_count}</Td>
                      <Td className="tabular-nums">{c.contest_count}</Td>
                      <Td>{c.hidden ? <Chip tone="warn">{t("st_hidden")}</Chip> : <Chip tone="ok">{t("status_active")}</Chip>}</Td>
                    </tr>
                  ))}
                </tbody>
              </table>
              <Pager offset={offset} limit={LIMIT} total={list.data.total} onChange={setOffset} />
            </>
          )}
        </Card>
        <div className="w-full xl:sticky xl:top-6 xl:w-[330px] xl:shrink-0">
          {sel ? <CommunityDetail id={sel} locale={locale} onGone={() => setPicked(null)} /> : <Card><Empty>{t("select_community")}</Empty></Card>}
        </div>
      </div>
    </>
  );
}

function CommunityDetail({ id, locale, onGone }: { id: string; locale: string; onGone: () => void }) {
  const t = useTranslations("admin");
  const [dialog, confirm] = useConfirm();
  const q = useQuery({ queryKey: ["admin", "community", id], queryFn: () => api<AdminCommunityDetail>(`admin/communities/${id}`), retry: false });
  const hidden = useAdminAction((v: { hidden: boolean; note: string }) => api(`admin/communities/${id}/hidden`, { method: "POST", body: { hidden: v.hidden, note: v.note || null } }));
  const transfer = useAdminAction((v: { username: string; note: string }) => api(`admin/communities/${id}/transfer`, { method: "POST", body: { username: v.username, note: v.note || null } }));
  const del = useAdminAction((note: string) => api(`admin/communities/${id}/delete`, { method: "POST", body: { note: note || null } }), onGone);
  const c = q.data;
  if (q.error) return <Failed error={q.error} />;
  if (!c) return <Card><Loading /></Card>;
  const err = hidden.error ?? transfer.error ?? del.error;
  const place = [c.city, c.country && countryName(c.country, locale)].filter(Boolean).join(", ");

  return (
    <Card pad="p-[18px]">
      {dialog}
      <div className="flex items-center gap-3">
        <CommunityBadge c={c} size={48} />
        <div className="min-w-0 flex-1">
          <div className="truncate text-[18px] font-bold">{c.name}</div>
          <div className="truncate text-[13px] text-ink-muted">{[place, t("c_founded", { date: fmtDate(c.created_at, locale) })].filter(Boolean).join(" · ")}</div>
        </div>
      </div>
      <div className="mt-3.5">
        <Row label={t("col_owner")}>{c.owner ? `@${c.owner.username}` : "—"}</Row>
        <Row label={t("col_members")}>{c.member_count}</Row>
        <Row label={t("c_admins")}>{c.admin_count}</Row>
        <Row label={t("c_pending")}>{c.pending_requests}</Row>
        <Row label={t("c_posts")}>{c.news_count} / {c.photo_post_count}</Row>
      </div>
      <div className="mt-4 flex flex-col gap-2">
        {!c.hidden && (
          <Link href={`/c/${c.slug}`} className="inline-flex h-10 items-center justify-center gap-2 rounded-full border border-line text-sm font-bold hover:bg-surface-2">
            <ExternalLink className="h-4 w-4" />{t("act_open_community")}
          </Link>
        )}
        <ActionButton icon={Users} disabled={transfer.isPending} onClick={async () => {
          const r = await confirm({ title: t("act_transfer"), confirm: t("act_transfer"), input: { label: t("transfer_label"), placeholder: "@" } });
          if (r) transfer.mutate({ username: r.value, note: r.note });
        }}>{t("act_transfer")}</ActionButton>
        {c.hidden ? (
          <ActionButton tone="primary" icon={Check} disabled={hidden.isPending} onClick={() => hidden.mutate({ hidden: false, note: "" })}>{t("act_unhide_community")}</ActionButton>
        ) : (
          <ActionButton tone="dark" icon={EyeOff} disabled={hidden.isPending} onClick={async () => {
            const r = await confirm({ title: t("act_hide_community"), confirm: t("act_hide_community") });
            if (r) hidden.mutate({ hidden: true, note: r.note });
          }}>{t("act_hide_community")}</ActionButton>
        )}
        <ActionButton tone="danger" icon={Trash2} disabled={del.isPending} onClick={async () => {
          const r = await confirm({ title: t("act_delete"), body: t("confirm_delete_community", { name: c.name }), confirm: t("act_delete"), danger: true });
          if (r) del.mutate(r.note);
        }}>{t("act_delete")}</ActionButton>
      </div>
      {err && <div className="mt-3"><Notice tone="error">{errorText(err, t("error"))}</Notice></div>}
    </Card>
  );
}
