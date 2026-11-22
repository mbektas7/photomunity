"use client";

import { useQuery } from "@tanstack/react-query";
import clsx from "clsx";
import { Check, EyeOff, Trash2, X } from "lucide-react";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { ActionButton, Card, Chip, Empty, Failed, Loading, PageHeader, Pager, Pills, SearchInput, errorText, useAdminAction, useConfirm, useDebounced } from "@/components/admin";
import { Notice } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import type { AdminPhoto, Paged } from "@/lib/admin-types";
import { api } from "@/lib/api";

const TABS = ["recent", "hidden", "rejected", "processing", "top"] as const;
const LIMIT = 40;

export default function AdminPhotos() {
  const t = useTranslations("admin");
  const [tab, setTab] = useState<(typeof TABS)[number]>("recent");
  const [q, setQ] = useState("");
  const dq = useDebounced(q.trim());
  const [offset, setOffset] = useState(0);
  const [sel, setSel] = useState<Set<string>>(new Set());
  const [dialog, confirm] = useConfirm();

  const params = new URLSearchParams({ tab, offset: String(offset), limit: String(LIMIT) });
  if (dq) params.set("q", dq);
  const list = useQuery({ queryKey: ["admin", "photos", tab, dq, offset], queryFn: () => api<Paged<AdminPhoto>>(`admin/photos?${params}`) });
  const bulk = useAdminAction((v: { action: "hide" | "unhide" | "delete"; note: string }) =>
    api("admin/photos/bulk", { method: "POST", body: { ids: [...sel], action: v.action, note: v.note || null } }), () => setSel(new Set()));

  const toggle = (id: string) => setSel((s) => { const n = new Set(s); if (n.has(id)) n.delete(id); else n.add(id); return n; });
  const status = (p: AdminPhoto): [string, "ok" | "warn" | "danger" | "muted"] =>
    p.hidden ? [t("ps_hidden"), "warn"] : p.status === "published" ? [t("ps_published"), "ok"] : p.status === "rejected" ? [t("ps_rejected"), "danger"] : [t("ps_processing"), "muted"];

  async function run(action: "hide" | "unhide" | "delete") {
    const label = t(`act_${action}` as "act_hide");
    const r = await confirm({ title: label, body: action === "delete" ? t("confirm_delete_photos", { n: sel.size }) : undefined, confirm: label, danger: action === "delete" });
    if (r) bulk.mutate({ action, note: r.note });
  }

  return (
    <>
      {dialog}
      <PageHeader title={t("nav_photos")} sub={list.data && t("photos_sub", { n: list.data.total })}
        right={<SearchInput value={q} onChange={(v) => { setQ(v); setOffset(0); }} placeholder={t("search_photos_ph")} className="w-full sm:w-[340px]" />} />
      <div className="mb-3.5">
        <Pills value={tab} onChange={(v) => { setTab(v); setOffset(0); setSel(new Set()); }} items={TABS.map((k) => ({ key: k, label: t(`tab_${k}` as "tab_recent") }))} />
      </div>
      {sel.size > 0 && (
        <div className="sticky top-3 z-20 mb-3.5 flex flex-wrap items-center gap-2.5 rounded-full bg-ink py-2 pl-5 pr-2 text-bg">
          <span className="text-sm font-bold">{t("n_selected", { n: sel.size })}</span>
          <button type="button" onClick={() => setSel(new Set())} aria-label={t("clear_selection")} className="grid h-8 w-8 place-items-center rounded-full hover:bg-white/10"><X className="h-4 w-4" /></button>
          <div className="flex-1" />
          <ActionButton icon={EyeOff} disabled={bulk.isPending} onClick={() => run("hide")} className="!h-[34px]">{t("act_hide")}</ActionButton>
          <ActionButton icon={Check} disabled={bulk.isPending} onClick={() => run("unhide")} className="!h-[34px]">{t("act_unhide")}</ActionButton>
          <ActionButton tone="danger" icon={Trash2} disabled={bulk.isPending} onClick={() => run("delete")} className="!h-[34px]">{t("act_delete")}</ActionButton>
        </div>
      )}
      {bulk.error && <div className="mb-3"><Notice tone="error">{errorText(bulk.error, t("error"))}</Notice></div>}
      {list.error && <Failed error={list.error} />}
      {list.isLoading ? <Loading /> : !list.data?.items.length ? <Card><Empty /></Card> : (
        <>
          <div className="grid grid-cols-2 gap-3.5 md:grid-cols-3 xl:grid-cols-4">
            {list.data.items.map((p) => {
              const on = sel.has(p.id);
              const [label, tone] = status(p);
              const img = p.images.feed ?? p.images.thumb ?? p.images.full;
              return (
                <div key={p.id} className={clsx("overflow-hidden rounded-[18px] bg-surface", on && "outline outline-[3px] outline-accent")}>
                  <div className="relative flex h-[170px] items-center justify-center bg-[#0b0d12]">
                    {/* Önizleme kırpılmadan */}
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    {img && <img src={img.url} alt={p.title ?? ""} className="max-h-full max-w-full object-contain" />}
                    <label className="absolute left-2 top-2 grid h-7 w-7 cursor-pointer place-items-center rounded-lg bg-white/85 text-white has-[:checked]:bg-accent">
                      <input type="checkbox" checked={on} onChange={() => toggle(p.id)} className="sr-only" aria-label={t("select_photo", { title: p.title ?? p.id })} />
                      {on && <Check className="h-4 w-4" />}
                    </label>
                    <span className="absolute right-2 top-2"><Chip tone={tone}>{label}</Chip></span>
                  </div>
                  <Link href={`/p/${p.id}`} className="block px-3 py-2.5 hover:bg-surface-2">
                    <div className="truncate text-sm font-bold">{p.title ?? "—"}</div>
                    <div className="truncate text-[12.5px] text-ink-muted">@{p.user.username}{p.width && p.height ? ` · ${p.width}×${p.height}` : ""} · ♥ {p.like_count}</div>
                  </Link>
                </div>
              );
            })}
          </div>
          <Pager offset={offset} limit={LIMIT} total={list.data.total} onChange={(o) => { setOffset(o); setSel(new Set()); }} />
        </>
      )}
    </>
  );
}
