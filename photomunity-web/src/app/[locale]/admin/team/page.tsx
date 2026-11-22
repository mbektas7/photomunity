"use client";

import { useQuery } from "@tanstack/react-query";
import { Shield } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useState } from "react";
import { ActionButton, Card, Chip, Empty, Failed, Loading, PageHeader, Pager, Pills, Td, Th, Who, errorText, fmtDate, useAdminAction } from "@/components/admin";
import { Notice } from "@/components/ui";
import type { AdminMember, LogEntry, Paged } from "@/lib/admin-types";
import { api } from "@/lib/api";

const KINDS = ["all", "moderation", "user", "content", "announcement", "team"] as const;
const LIMIT = 50;

export default function AdminTeam() {
  const t = useTranslations("admin");
  const locale = useLocale();
  const [username, setUsername] = useState("");
  const [kind, setKind] = useState<(typeof KINDS)[number]>("all");
  const [offset, setOffset] = useState(0);
  const admins = useQuery({ queryKey: ["admin", "admins"], queryFn: () => api<AdminMember[]>("admin/admins") });
  const params = new URLSearchParams({ offset: String(offset), limit: String(LIMIT) });
  if (kind !== "all") params.set("kind", kind);
  const log = useQuery({ queryKey: ["admin", "log", kind, offset], queryFn: () => api<Paged<LogEntry>>(`admin/log?${params}`) });
  const add = useAdminAction((u: string) => api("admin/admins", { method: "POST", body: { username: u } }), () => setUsername(""));
  const remove = useAdminAction((id: string) => api(`admin/admins/${id}`, { method: "DELETE" }));
  const err = add.error ?? remove.error;

  return (
    <>
      <PageHeader title={t("nav_team")} sub={t("team_sub")} />
      <div className="flex flex-col items-start gap-3.5 xl:flex-row">
        <Card className="w-full xl:w-[400px] xl:shrink-0">
          <h2 className="mb-1.5 text-[16px] font-bold">{t("admins")}</h2>
          {admins.error && <Failed error={admins.error} />}
          {admins.isLoading && <Loading />}
          <ul>
            {admins.data?.map((a) => (
              <li key={a.id} className="flex items-center gap-2.5 border-b border-line py-2.5">
                <span className="min-w-0 flex-1"><Who user={a} sub={a.since ? `@${a.username} · ${t("since", { date: fmtDate(a.since, locale) })}` : `@${a.username}`} /></span>
                {a.is_owner ? <Chip tone="acc">{t("role_owner")}</Chip> : (
                  <ActionButton className="!h-[34px]" disabled={remove.isPending} onClick={() => remove.mutate(a.id)}>{t("act_remove")}</ActionButton>
                )}
              </li>
            ))}
          </ul>
          <form className="mt-3.5 flex gap-2" onSubmit={(e) => { e.preventDefault(); if (username.trim()) add.mutate(username.trim()); }}>
            <input value={username} onChange={(e) => setUsername(e.target.value)} placeholder={t("username_ph")} aria-label={t("username_ph")}
              className="h-10 min-w-0 flex-1 rounded-full border border-line bg-surface px-3.5 text-sm outline-none focus:border-accent" />
            <ActionButton type="submit" tone="primary" icon={Shield} disabled={add.isPending}>{t("act_add_admin")}</ActionButton>
          </form>
          <p className="mt-2.5 text-[12.5px] text-ink-muted">{t("admins_hint")}</p>
          {err && <div className="mt-3"><Notice tone="error">{errorText(err, t("error"))}</Notice></div>}
        </Card>

        <Card pad="p-2" className="w-full min-w-0 flex-1 overflow-x-auto">
          <div className="flex flex-wrap items-center justify-between gap-3 px-3.5 pb-1 pt-2.5">
            <h2 className="text-[16px] font-bold">{t("log")}</h2>
            <Pills value={kind} onChange={(k) => { setKind(k); setOffset(0); }} items={KINDS.map((k) => ({ key: k, label: t(`lk_${k}` as "lk_all") }))} />
          </div>
          {log.error && <Failed error={log.error} />}
          {log.isLoading ? <Loading /> : !log.data?.items.length ? <Empty /> : (
            <>
              <table className="w-full min-w-[720px] border-collapse">
                <thead><tr><Th>{t("col_time")}</Th><Th>{t("col_admin")}</Th><Th>{t("col_action")}</Th><Th>{t("col_target")}</Th><Th>{t("col_note")}</Th></tr></thead>
                <tbody>
                  {log.data.items.map((l) => (
                    <tr key={l.id}>
                      <Td className="whitespace-nowrap">{fmtDate(l.created_at, locale, true)}</Td>
                      <Td>{l.admin ? <Who user={l.admin} /> : "—"}</Td>
                      <Td>{t.has(`a_${l.action}`) ? t(`a_${l.action}` as "a_photo_hide") : l.action}</Td>
                      <Td className="max-w-[240px] truncate">{l.target_label ?? "—"}</Td>
                      <Td className="max-w-[220px] truncate text-ink-muted">{l.note ?? "—"}</Td>
                    </tr>
                  ))}
                </tbody>
              </table>
              <Pager offset={offset} limit={LIMIT} total={log.data.total} onChange={setOffset} />
            </>
          )}
        </Card>
      </div>
    </>
  );
}
