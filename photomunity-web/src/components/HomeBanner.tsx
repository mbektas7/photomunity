"use client";

import { useQuery } from "@tanstack/react-query";
import { Megaphone, X } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useEffect, useState } from "react";
import { Link } from "@/i18n/navigation";
import { api } from "@/lib/api";

type Banner = { id: string; title: string; body: string; link: string | null } | null;
const KEY = "pm-banner-closed";

/** Yönetimin ana sayfa duyurusu; kapatılan duyuru bu tarayıcıda bir daha gösterilmez. */
export function HomeBanner() {
  const t = useTranslations("feed");
  const locale = useLocale();
  const q = useQuery({ queryKey: ["banner", locale], queryFn: () => api<Banner>(`announcements/banner?locale=${locale}`), staleTime: 300_000 });
  const [closed, setClosed] = useState<string | null>(null);
  useEffect(() => {
    try {
      setClosed(localStorage.getItem(KEY));
    } catch {
      /* depolama kapalı olabilir */
    }
  }, []);
  const b = q.data;
  if (!b || closed === b.id) return null;
  const close = () => {
    setClosed(b.id);
    try {
      localStorage.setItem(KEY, b.id);
    } catch {
      /* depolama kapalı olabilir */
    }
  };
  return (
    <aside className="flex items-start gap-3 rounded-card bg-accent-tint px-4 py-3.5 text-ink">
      <Megaphone className="mt-0.5 h-5 w-5 shrink-0 text-accent-text" aria-hidden />
      <div className="min-w-0 flex-1">
        <p className="font-semibold">{b.title}</p>
        <p className="mt-0.5 text-[14.5px] text-ink-muted">{b.body}</p>
        {b.link && <Link href={b.link} className="mt-1.5 inline-block text-sm font-semibold text-accent-text hover:underline">{t("banner_open")}</Link>}
      </div>
      <button type="button" onClick={close} aria-label={t("banner_close")} className="grid h-8 w-8 shrink-0 place-items-center rounded-full hover:bg-surface/60">
        <X className="h-4 w-4" />
      </button>
    </aside>
  );
}
