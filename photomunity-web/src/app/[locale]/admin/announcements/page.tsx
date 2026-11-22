"use client";

import { useQuery } from "@tanstack/react-query";
import clsx from "clsx";
import { Bell, Send } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useState } from "react";
import { ActionButton, Card, Chip, Empty, Failed, PageHeader, errorText, useAdminAction, useConfirm, useDebounced } from "@/components/admin";
import { BrandMark } from "@/components/Logo";
import { Notice } from "@/components/ui";
import type { Announcement } from "@/lib/admin-types";
import { api } from "@/lib/api";
import { relativeTime } from "@/lib/relative-time";

type Channel = "push" | "inbox" | "banner";
type Kind = "all" | "pro" | "community" | "locale" | "country";

const field = "w-full rounded-[14px] border border-line bg-surface px-3.5 py-2.5 text-[14.5px] outline-none focus:border-accent";

function Choice({ on, onClick, children, multi }: { on: boolean; onClick: () => void; children: React.ReactNode; multi?: boolean }) {
  return (
    <button type="button" role={multi ? "checkbox" : "radio"} aria-checked={on} onClick={onClick}
      className={clsx("inline-flex h-10 items-center gap-2 rounded-full border px-3.5 text-[13.5px]", on ? "border-accent bg-accent-tint font-bold" : "border-line bg-surface font-medium hover:bg-surface-2")}>
      <span className={clsx("h-3.5 w-3.5 border-[4px] bg-white", multi ? "rounded-[4px]" : "rounded-full", on ? "border-accent" : "border-line")} />
      {children}
    </button>
  );
}

export default function AdminAnnouncements() {
  const t = useTranslations("admin");
  const locale = useLocale();
  const [channels, setChannels] = useState<Channel[]>(["push", "inbox"]);
  const [f, setF] = useState({ title_tr: "", title_en: "", body_tr: "", body_en: "", link: "" });
  const [kind, setKind] = useState<Kind>("all");
  const [value, setValue] = useState("");
  const [days, setDays] = useState(7);
  const [ok, setOk] = useState<string | null>(null);
  const [dialog, confirm] = useConfirm();
  const dv = useDebounced(value.trim());
  const needsValue = kind === "community" || kind === "locale" || kind === "country";
  const audience = { kind, value: needsValue ? (kind === "locale" ? value || "tr" : dv) || null : null };

  const size = useQuery({
    queryKey: ["admin", "audience", audience.kind, audience.value],
    queryFn: () => api<{ count: number }>(`admin/announcements/audience?kind=${audience.kind}${audience.value ? `&value=${encodeURIComponent(audience.value)}` : ""}`),
  });
  const history = useQuery({ queryKey: ["admin", "announcements"], queryFn: () => api<Announcement[]>("admin/announcements") });
  const send = useAdminAction((test: boolean) => api<{ recipient_count: number; test: boolean }>("admin/announcements", {
    method: "POST",
    body: { channels, ...f, link: f.link.trim() || null, audience, banner_days: days, test },
  }));
  const endBanner = useAdminAction((id: string) => api(`admin/announcements/${id}/end-banner`, { method: "POST" }));

  const n = size.data?.count ?? 0;
  const valid = channels.length > 0 && f.title_tr && f.title_en && f.body_tr && f.body_en && (!f.link || f.link.startsWith("/")) && (!needsValue || audience.value);
  const toggle = (c: Channel) => setChannels((cs) => (cs.includes(c) ? cs.filter((x) => x !== c) : [...cs, c]));
  const set = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => setF({ ...f, [k]: e.target.value });
  const title = locale === "tr" ? f.title_tr : f.title_en;
  const body = locale === "tr" ? f.body_tr : f.body_en;

  async function submit(test: boolean) {
    setOk(null);
    if (!test) {
      const r = await confirm({ title: t("send_n", { n }), body: t("confirm_send", { n }), confirm: t("send_n", { n }), note: false });
      if (!r) return;
    }
    send.mutate(test, {
      onSuccess: (res) => {
        setOk(res.test ? t("test_ok") : t("sent_ok", { n: res.recipient_count }));
        if (!res.test) setF({ title_tr: "", title_en: "", body_tr: "", body_en: "", link: "" });
      },
    });
  }

  return (
    <>
      {dialog}
      <PageHeader title={t("nav_announcements")} sub={t("ann_sub")} />
      <div className="flex flex-col items-start gap-3.5 xl:flex-row">
        <Card className="w-full xl:flex-[1.5]" pad="p-[22px]">
          <h2 className="mb-3.5 text-[16px] font-bold">{t("ann_new")}</h2>
          <p className="mb-1.5 text-[12.5px] font-bold text-ink-muted">{t("ch_where")}</p>
          <div className="mb-3.5 flex flex-wrap gap-2">
            {(["push", "inbox", "banner"] as const).map((c) => <Choice key={c} multi on={channels.includes(c)} onClick={() => toggle(c)}>{t(`ch_${c}`)}</Choice>)}
          </div>
          {channels.includes("banner") && (
            <label className="mb-3.5 flex items-center gap-3 text-[13px] font-semibold text-ink-muted">
              {t("banner_days")}
              <input type="number" min={1} max={60} value={days} onChange={(e) => setDays(Math.max(1, Math.min(60, Number(e.target.value) || 1)))} className="h-9 w-20 rounded-xl border border-line bg-surface px-2.5 text-ink" />
            </label>
          )}
          <div className="grid gap-3 md:grid-cols-2">
            {(["title_tr", "title_en"] as const).map((k) => (
              <label key={k} className="flex flex-col gap-1.5 text-[12.5px] font-bold text-ink-muted">{t(`f_${k}`)}
                <input value={f[k]} onChange={set(k)} maxLength={120} className={field} />
              </label>
            ))}
            {(["body_tr", "body_en"] as const).map((k) => (
              <label key={k} className="flex flex-col gap-1.5 text-[12.5px] font-bold text-ink-muted">{t(`f_${k}`)}
                <textarea value={f[k]} onChange={set(k)} maxLength={400} rows={3} className={field} />
              </label>
            ))}
          </div>
          <label className="mt-3 flex flex-col gap-1.5 text-[12.5px] font-bold text-ink-muted">{t("f_link")}
            <input value={f.link} onChange={set("link")} maxLength={300} placeholder="/contests/…" className={field} />
            <span className="font-normal">{t("f_link_hint")}</span>
          </label>
          <p className="mb-1.5 mt-4 text-[12.5px] font-bold text-ink-muted">{t("aud_title")}</p>
          <div className="flex flex-wrap gap-2">
            {(["all", "pro", "community", "locale", "country"] as const).map((k) => (
              <Choice key={k} on={kind === k} onClick={() => { setKind(k); setValue(""); }}>{t(`aud_${k}`)}</Choice>
            ))}
          </div>
          {kind === "community" && <input value={value} onChange={(e) => setValue(e.target.value)} placeholder={t("aud_community_ph")} className={clsx(field, "mt-2.5 max-w-sm")} />}
          {kind === "country" && <input value={value} onChange={(e) => setValue(e.target.value.toUpperCase().slice(0, 2))} placeholder={t("aud_country_ph")} className={clsx(field, "mt-2.5 max-w-[200px]")} />}
          {kind === "locale" && (
            <div className="mt-2.5 flex gap-2">
              {(["tr", "en"] as const).map((l) => <Choice key={l} on={(value || "tr") === l} onClick={() => setValue(l)}>{l.toUpperCase()}</Choice>)}
            </div>
          )}
          <div className="mt-5 flex flex-wrap items-center gap-2.5">
            <ActionButton tone="primary" icon={Send} disabled={!valid || send.isPending || n === 0} onClick={() => submit(false)}>{t("send_n", { n })}</ActionButton>
            <ActionButton icon={Bell} disabled={!valid || send.isPending} onClick={() => submit(true)}>{t("send_test")}</ActionButton>
            <span className="text-[12.5px] text-ink-muted">{t("lang_hint")}</span>
          </div>
          {ok && <div className="mt-3"><Notice tone="success">{ok}</Notice></div>}
          {send.error && <div className="mt-3"><Notice tone="error">{errorText(send.error, t("error"))}</Notice></div>}
        </Card>

        <Card className="w-full xl:flex-1">
          <p className="mb-2.5 text-[13px] font-bold text-ink-muted">{t("preview")}</p>
          <div className="rounded-[26px] bg-[#0b0d12] px-3.5 py-4">
            <div className="mb-4 mt-1.5 text-center text-[44px] font-light text-white">21:04</div>
            <div className="flex gap-2.5 rounded-[18px] bg-white/90 p-3 text-[13px] text-[#14161b]">
              <span className="grid h-[34px] w-[34px] shrink-0 place-items-center rounded-[9px] bg-[#14161b]"><BrandMark className="h-[22px] w-[22px] text-white" /></span>
              <div className="min-w-0 flex-1">
                <div className="flex justify-between"><b>{title || "Photomunity"}</b><span className="text-[#5d6270]">{t("now")}</span></div>
                <div className="break-words">{body || "…"}</div>
              </div>
            </div>
          </div>
          <h2 className="mb-1.5 mt-5 text-[16px] font-bold">{t("history")}</h2>
          {history.error && <Failed error={history.error} />}
          {history.data?.length === 0 && <Empty />}
          <ul>
            {history.data?.map((a) => {
              const live = a.banner_until && new Date(a.banner_until) > new Date();
              const aud = a.audience.kind === "all" ? t("aud_short_all") : a.audience.kind === "pro" ? t("aud_short_pro") : `${t(`aud_${a.audience.kind}` as "aud_all")}: ${a.audience.value}`;
              return (
                <li key={a.id} className="border-b border-line py-2.5 text-[13.5px]">
                  <div className="flex items-center gap-2">
                    <span className="min-w-0 flex-1 truncate font-semibold">{locale === "tr" ? a.title_tr : a.title_en}</span>
                    {live && <Chip tone="acc">{t("banner_live")}</Chip>}
                  </div>
                  <div className="text-[12.5px] text-ink-muted">
                    {[aud, t("n_sent", { n: a.recipient_count }), a.channels.map((c) => t(`ch_short_${c}`)).join(" + "), relativeTime(a.created_at, locale)].join(" · ")}
                  </div>
                  {live && <button type="button" onClick={() => endBanner.mutate(a.id)} className="mt-1 text-[12.5px] font-semibold text-accent-text hover:underline">{t("end_banner")}</button>}
                </li>
              );
            })}
          </ul>
        </Card>
      </div>
    </>
  );
}
