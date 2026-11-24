"use client";

import { useQuery } from "@tanstack/react-query";
import { Pencil, Plus, Trash2 } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useState } from "react";
import { ActionButton, Card, Chip, Empty, Failed, Loading, PageHeader, Td, Th, errorText, fmtDate, useAdminAction, useConfirm } from "@/components/admin";
import { Notice } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { api } from "@/lib/api";
import { fromLocalInput, toLocalInput } from "@/lib/dates";
import type { ThemeAdmin } from "@/lib/types";

const field = "w-full rounded-[14px] border border-line bg-surface px-3.5 py-2.5 text-[14.5px] outline-none focus:border-accent";
const TONE = { scheduled: "muted", active: "ok", ended: "warn", finished: "acc" } as const;

type Form = { title_tr: string; title_en: string; description_tr: string; description_en: string; starts: string; ends: string };

/** Varsayılan: bir sonraki pazartesi 00:00 → ertesi pazartesi 00:00 (yerel). */
function nextWeek(): Pick<Form, "starts" | "ends"> {
  const d = new Date();
  const add = ((8 - d.getDay()) % 7) || 7;
  const s = new Date(d.getFullYear(), d.getMonth(), d.getDate() + add);
  const e = new Date(s.getFullYear(), s.getMonth(), s.getDate() + 7);
  return { starts: toLocalInput(s.toISOString()), ends: toLocalInput(e.toISOString()) };
}

const empty = (): Form => ({ title_tr: "", title_en: "", description_tr: "", description_en: "", ...nextWeek() });

export default function AdminThemes() {
  const t = useTranslations("admin");
  const locale = useLocale();
  const [dialog, confirm] = useConfirm();
  const [editing, setEditing] = useState<ThemeAdmin | "new" | null>(null);
  const [f, setF] = useState<Form>(empty);
  // Düzenlemede yalnızca değişen tarihler gönderilir (dakika hassasiyetli giriş, saniyeleri bozmasın;
  // başlamış temanın başlangıcı değiştirilemez)
  const [initial, setInitial] = useState<Form | null>(null);
  const q = useQuery({ queryKey: ["admin", "themes"], queryFn: () => api<ThemeAdmin[]>("admin/themes") });

  const save = useAdminAction(
    (body: Record<string, unknown>) =>
      editing && editing !== "new"
        ? api<ThemeAdmin>(`admin/themes/${editing.id}`, { method: "PATCH", body })
        : api<ThemeAdmin>("admin/themes", { method: "POST", body }),
    () => setEditing(null),
  );
  const remove = useAdminAction((id: string) => api(`admin/themes/${id}`, { method: "DELETE" }));

  function open(th: ThemeAdmin | "new") {
    save.reset();
    setEditing(th);
    const next = th === "new" ? empty() : {
      title_tr: th.title_tr, title_en: th.title_en, description_tr: th.description_tr ?? "", description_en: th.description_en ?? "",
      starts: toLocalInput(th.starts_at), ends: toLocalInput(th.ends_at),
    };
    setF(next);
    setInitial(th === "new" ? null : next);
  }
  async function del(th: ThemeAdmin) {
    const r = await confirm({ title: t("theme_delete_title", { n: th.number }), body: t("theme_delete_body"), confirm: t("theme_delete"), danger: true, note: false });
    if (r) remove.mutate(th.id);
  }
  const set = (k: keyof Form) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => setF({ ...f, [k]: e.target.value });
  const valid = f.title_tr.trim() && f.title_en.trim() && f.starts && f.ends && f.ends > f.starts;
  const items = q.data ?? [];

  return (
    <>
      {dialog}
      <PageHeader
        title={t("nav_themes")}
        sub={t("themes_sub")}
        right={<ActionButton tone="dark" icon={Plus} onClick={() => open("new")}>{t("theme_new")}</ActionButton>}
      />
      <div className="flex flex-col items-start gap-3.5 xl:flex-row">
        <Card pad="p-0" className="w-full min-w-0 flex-1 overflow-x-auto">
          {q.isLoading ? <Loading /> : q.error ? <div className="p-5"><Failed error={q.error} /></div> : items.length === 0 ? <Empty /> : (
            <table className="w-full min-w-[640px] border-collapse">
              <thead>
                <tr>
                  <Th>#</Th><Th>{t("theme_title")}</Th><Th>{t("theme_dates")}</Th><Th>{t("theme_status")}</Th><Th>{t("theme_entries")}</Th><Th />
                </tr>
              </thead>
              <tbody>
                {items.map((th) => (
                  <tr key={th.id}>
                    <Td className="tnum font-bold">{th.number}</Td>
                    <Td>
                      <span className="block font-semibold">{locale === "tr" ? th.title_tr : th.title_en}</span>
                      <span className="block text-[12.5px] text-ink-muted">{locale === "tr" ? th.title_en : th.title_tr}</span>
                    </Td>
                    <Td className="tnum whitespace-nowrap">{fmtDate(th.starts_at, locale, true)} – {fmtDate(th.ends_at, locale, true)}</Td>
                    <Td><Chip tone={TONE[th.status]}>{t(`theme_s_${th.status}`)}</Chip></Td>
                    <Td className="tnum">
                      {th.status === "scheduled" ? th.entry_count : <Link href={`/themes/${th.id}`} className="font-semibold text-accent-text hover:underline">{th.entry_count}</Link>}
                    </Td>
                    <Td className="whitespace-nowrap text-right">
                      {(th.status === "scheduled" || th.status === "active") && <button type="button" onClick={() => open(th)} aria-label={t("theme_edit_n", { n: th.number })} className="inline-grid h-9 w-9 place-items-center rounded-full hover:bg-surface-2"><Pencil className="h-4 w-4" aria-hidden /></button>}
                      <button type="button" onClick={() => del(th)} aria-label={t("theme_delete_title", { n: th.number })} className="inline-grid h-9 w-9 place-items-center rounded-full text-[#d92d20] hover:bg-[#fdecea]"><Trash2 className="h-4 w-4" aria-hidden /></button>
                    </Td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
          {remove.error && <div className="p-4"><Notice tone="error">{errorText(remove.error, t("error"))}</Notice></div>}
        </Card>

        {editing && (
          <Card className="w-full xl:w-[420px]">
            <form
              className="flex flex-col gap-3.5"
              onSubmit={(e) => {
                e.preventDefault();
                if (!valid) return;
                save.mutate({
                  title_tr: f.title_tr.trim(), title_en: f.title_en.trim(),
                  description_tr: f.description_tr.trim() || null, description_en: f.description_en.trim() || null,
                  ...(!initial || f.starts !== initial.starts ? { starts_at: fromLocalInput(f.starts) } : {}),
                  ...(!initial || f.ends !== initial.ends ? { ends_at: fromLocalInput(f.ends) } : {}),
                });
              }}
            >
              <h2 className="text-[17px] font-bold">{editing === "new" ? t("theme_new") : t("theme_edit_n", { n: editing.number })}</h2>
              <label className="flex flex-col gap-1.5 text-sm font-semibold">{t("theme_title_tr")}<input required maxLength={100} value={f.title_tr} onChange={set("title_tr")} className={field} /></label>
              <label className="flex flex-col gap-1.5 text-sm font-semibold">{t("theme_title_en")}<input required maxLength={100} value={f.title_en} onChange={set("title_en")} className={field} /></label>
              <label className="flex flex-col gap-1.5 text-sm font-semibold">{t("theme_desc_tr")}<textarea rows={3} maxLength={1000} value={f.description_tr} onChange={set("description_tr")} className={field} /></label>
              <label className="flex flex-col gap-1.5 text-sm font-semibold">{t("theme_desc_en")}<textarea rows={3} maxLength={1000} value={f.description_en} onChange={set("description_en")} className={field} /></label>
              <div className="grid gap-3 sm:grid-cols-2">
                <label className="flex flex-col gap-1.5 text-sm font-semibold">{t("theme_starts")}<input type="datetime-local" required value={f.starts} onChange={set("starts")} disabled={editing !== "new" && editing.status === "active"} className={`${field} disabled:opacity-60`} /></label>
                <label className="flex flex-col gap-1.5 text-sm font-semibold">{t("theme_ends")}<input type="datetime-local" required min={f.starts} value={f.ends} onChange={set("ends")} className={field} /></label>
              </div>
              <p className="text-xs text-ink-muted">{t("theme_overlap_hint")}</p>
              {save.error && <Notice tone="error">{errorText(save.error, t("error"))}</Notice>}
              <div className="flex justify-end gap-2">
                <ActionButton onClick={() => setEditing(null)}>{t("cancel")}</ActionButton>
                <ActionButton type="submit" tone="primary" disabled={!valid || save.isPending}>{t("save")}</ActionButton>
              </div>
            </form>
          </Card>
        )}
      </div>
    </>
  );
}
