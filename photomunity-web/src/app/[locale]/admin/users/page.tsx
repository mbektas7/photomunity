"use client";

import { useQuery } from "@tanstack/react-query";
import clsx from "clsx";
import { Ban, Check, Image as ImageIcon, LogOut, Shield, ShieldOff } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useSearchParams } from "next/navigation";
import { Suspense, useState } from "react";
import { Avatar } from "@/components/Avatar";
import {
  ActionButton, Card, Chip, Empty, Failed, Loading, PageHeader, Pager, Pills, Row, SearchInput, Td, Th, Who, errorText, fmtDate,
  useAdminAction, useConfirm, useDebounced,
} from "@/components/admin";
import { Notice } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import type { AdminUserDetail, AdminUserRow, Paged } from "@/lib/admin-types";
import { api } from "@/lib/api";
import { countryName } from "@/lib/format";
import { relativeTime } from "@/lib/relative-time";

const FILTERS = ["all", "pro", "admin", "disabled", "unverified", "new"] as const;
const LIMIT = 50;

export default function Page() {
  return <Suspense><AdminUsers /></Suspense>;
}

function StatusChip({ u }: { u: AdminUserRow }) {
  const t = useTranslations("admin");
  if (!u.is_active) return <Chip tone="danger">{t("status_disabled")}</Chip>;
  if (!u.email_verified) return <Chip tone="warn">{t("status_unverified")}</Chip>;
  return <Chip tone="ok">{t("status_active")}</Chip>;
}

function AdminUsers() {
  const t = useTranslations("admin");
  const locale = useLocale();
  const [q, setQ] = useState("");
  const dq = useDebounced(q.trim());
  const [filter, setFilter] = useState<(typeof FILTERS)[number]>("all");
  const [offset, setOffset] = useState(0);
  const [picked, setPicked] = useState<string | null>(useSearchParams().get("user"));

  const params = new URLSearchParams({ filter, offset: String(offset), limit: String(LIMIT) });
  if (dq) params.set("q", dq);
  const list = useQuery({ queryKey: ["admin", "users", dq, filter, offset], queryFn: () => api<Paged<AdminUserRow>>(`admin/users?${params}`) });
  const sel = picked ?? list.data?.items[0]?.id ?? null;

  return (
    <>
      <PageHeader title={t("nav_users")} sub={list.data && t("users_sub", { n: list.data.total })}
        right={<SearchInput value={q} onChange={(v) => { setQ(v); setOffset(0); }} placeholder={t("search_users")} className="w-full sm:w-[360px]" />} />
      <div className="mb-3.5">
        <Pills value={filter} onChange={(f) => { setFilter(f); setOffset(0); }} items={FILTERS.map((f) => ({ key: f, label: t(`f_${f}` as "f_all") }))} />
      </div>
      {list.error && <Failed error={list.error} />}
      <div className="flex flex-col items-start gap-3.5 xl:flex-row">
        <Card pad="p-2" className="w-full min-w-0 flex-1 overflow-x-auto">
          {list.isLoading ? <Loading /> : !list.data?.items.length ? <Empty /> : (
            <>
              <table className="w-full min-w-[720px] border-collapse">
                <thead><tr><Th>{t("col_user")}</Th><Th>{t("col_role")}</Th><Th>{t("col_login")}</Th><Th>{t("col_photos")}</Th><Th>{t("col_followers")}</Th><Th>{t("col_joined")}</Th><Th>{t("col_status")}</Th></tr></thead>
                <tbody>
                  {list.data.items.map((u) => (
                    <tr key={u.id} onClick={() => setPicked(u.id)} className={clsx("cursor-pointer", u.id === sel ? "bg-accent-tint" : "hover:bg-surface-2/60")}>
                      <Td className="max-w-[260px]"><button type="button" className="w-full text-left" onClick={() => setPicked(u.id)}><Who user={u} sub={`@${u.username} · ${u.email}`} /></button></Td>
                      <Td><span className="flex gap-1">{u.is_admin && <Chip>{t("f_admin")}</Chip>}{u.is_pro && <Chip tone="acc">Pro</Chip>}{!u.is_admin && !u.is_pro && "—"}</span></Td>
                      <Td>{u.providers.map((p) => t(`provider_${p}` as "provider_email")).join(", ") || "—"}</Td>
                      <Td className="tabular-nums">{u.photo_count}</Td>
                      <Td className="tabular-nums">{u.follower_count}</Td>
                      <Td className="whitespace-nowrap">{fmtDate(u.created_at, locale)}</Td>
                      <Td><StatusChip u={u} /></Td>
                    </tr>
                  ))}
                </tbody>
              </table>
              <Pager offset={offset} limit={LIMIT} total={list.data.total} onChange={setOffset} />
            </>
          )}
        </Card>
        <div className="w-full xl:sticky xl:top-6 xl:w-[330px] xl:shrink-0">
          {sel ? <UserDetail id={sel} locale={locale} /> : <Card><Empty>{t("select_user")}</Empty></Card>}
        </div>
      </div>
    </>
  );
}

function UserDetail({ id, locale }: { id: string; locale: string }) {
  const t = useTranslations("admin");
  const [dialog, confirm] = useConfirm();
  const [done, setDone] = useState<string | null>(null);
  const q = useQuery({ queryKey: ["admin", "user", id], queryFn: () => api<AdminUserDetail>(`admin/users/${id}`) });
  const status = useAdminAction((v: { active: boolean; note: string }) => api(`admin/users/${id}/status`, { method: "POST", body: { active: v.active, note: v.note || null } }));
  const logout = useAdminAction(() => api(`admin/users/${id}/logout`, { method: "POST" }), () => setDone(t("logged_out")));
  const admin = useAdminAction((make: boolean) => make
    ? api("admin/admins", { method: "POST", body: { username: q.data!.username } })
    : api(`admin/admins/${id}`, { method: "DELETE" }));
  const u = q.data;
  if (q.error) return <Failed error={q.error} />;
  if (!u) return <Card><Loading /></Card>;
  const err = status.error ?? logout.error ?? admin.error;
  const sub = u.subscription ? `${t(`store_${u.subscription.store}` as "store_app_store")} · ${t(`ss_${u.subscription.status}` as "ss_active")}` : t("d_none");

  return (
    <Card pad="p-[18px]">
      {dialog}
      <div className="flex items-center gap-3">
        <Avatar name={u.display_name} url={u.avatar_url} size={56} />
        <div className="min-w-0 flex-1">
          <div className="truncate text-[18px] font-bold">{u.display_name}</div>
          <div className="truncate text-[13px] text-ink-muted">@{u.username}{(u.city || u.country) && ` · ${[u.city, u.country && countryName(u.country, locale)].filter(Boolean).join(", ")}`}</div>
        </div>
      </div>
      <div className="mt-3.5 grid grid-cols-3 gap-2">
        {[[u.photo_count, t("stat_photos")], [u.follower_count, t("stat_followers")], [u.report_count, t("stat_reports")]].map(([v, l]) => (
          <div key={String(l)} className="rounded-xl bg-bg p-2.5"><div className="text-[18px] font-bold tabular-nums">{v}</div><div className="text-xs text-ink-muted">{l}</div></div>
        ))}
      </div>
      <div className="mt-3.5">
        <Row label={t("d_email")}>{u.email} {u.email_verified && "✓"}</Row>
        <Row label={t("d_login")}>{u.providers.map((p) => t(`provider_${p}` as "provider_email")).join(", ") || "—"}</Row>
        <Row label={t("d_subscription")}>{sub}</Row>
        <Row label={t("d_last_login")}>{u.last_login ? `${relativeTime(u.last_login, locale)}${u.platforms.length ? ` · ${u.platforms.join(", ")}` : ""}` : t("d_never")}</Row>
        <Row label={t("d_communities")}>{t("d_communities_val", { n: u.communities, admin: u.communities_admin })}</Row>
        <Row label={t("col_joined")}>{fmtDate(u.created_at, locale)}</Row>
      </div>
      <div className="mt-4 flex flex-col gap-2">
        <Link href={`/u/${u.username}`} className="inline-flex h-10 items-center justify-center gap-2 rounded-full border border-line text-sm font-bold hover:bg-surface-2">
          <ImageIcon className="h-4 w-4" />{t("act_view_photos")}
        </Link>
        <ActionButton icon={LogOut} disabled={logout.isPending} onClick={() => logout.mutate(undefined)}>{t("act_logout")}</ActionButton>
        {!u.is_owner && (u.is_admin
          ? <ActionButton icon={ShieldOff} disabled={admin.isPending} onClick={() => admin.mutate(false)}>{t("act_remove_admin")}</ActionButton>
          : <ActionButton icon={Shield} disabled={admin.isPending || !u.is_active} onClick={() => admin.mutate(true)}>{t("act_make_admin")}</ActionButton>)}
        {u.is_owner ? <p className="text-xs text-ink-muted">{t("owner_locked")}</p> : u.is_active ? (
          <ActionButton tone="danger" icon={Ban} disabled={status.isPending} onClick={async () => {
            const r = await confirm({ title: t("act_disable"), body: t("disable_hint"), confirm: t("act_disable"), danger: true });
            if (r) status.mutate({ active: false, note: r.note });
          }}>{t("act_disable")}</ActionButton>
        ) : (
          <ActionButton tone="primary" icon={Check} disabled={status.isPending} onClick={() => status.mutate({ active: true, note: "" })}>{t("act_enable")}</ActionButton>
        )}
      </div>
      <p className="mt-2.5 text-xs text-ink-muted">{t("disable_hint")}</p>
      {done && <div className="mt-3"><Notice tone="success">{done}</Notice></div>}
      {err && <div className="mt-3"><Notice tone="error">{errorText(err, t("error"))}</Notice></div>}
    </Card>
  );
}
