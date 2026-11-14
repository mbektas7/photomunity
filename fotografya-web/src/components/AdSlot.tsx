"use client";

import clsx from "clsx";
import { useTranslations } from "next-intl";
import { useEffect, useRef } from "react";
import { Link } from "@/i18n/navigation";
import { useMe } from "@/lib/hooks";

const CLIENT = process.env.NEXT_PUBLIC_ADSENSE_CLIENT;
const SLOTS = { feed: process.env.NEXT_PUBLIC_ADSENSE_SLOT_FEED, banner: process.env.NEXT_PUBLIC_ADSENSE_SLOT_BANNER };

declare global {
  interface Window {
    adsbygoogle?: unknown[];
  }
}

let scriptAdded = false;
function ensureScript() {
  if (scriptAdded || !CLIENT) return;
  scriptAdded = true;
  const s = document.createElement("script");
  s.async = true;
  s.crossOrigin = "anonymous";
  // Aynı betik AdSense'in "Gizlilik ve mesajlaşma" onay penceresini (GDPR/KVKK) de gösterir
  s.src = `https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${CLIENT}`;
  document.head.appendChild(s);
}

/**
 * Reklam alanı. Pro kullanıcıya, giriş yapılmamışken yüklenirken ya da AdSense yapılandırılmamışsa hiç çizilmez.
 * Bilinçli olarak yalnızca akış, keşfet ve rehberde kullanılır; fotoğraf detayı, mesajlar, yarışma oylaması reklamsızdır.
 */
export function AdSlot({ kind, className }: { kind: "feed" | "banner"; className?: string }) {
  const t = useTranslations("ads");
  const { data: me, isLoading } = useMe();
  const ref = useRef<HTMLModElement>(null);
  const slot = SLOTS[kind];
  const show = !!CLIENT && !!slot && !isLoading && !me?.is_pro;

  useEffect(() => {
    if (!show || !ref.current || ref.current.dataset.adsbygoogleStatus) return;
    ensureScript();
    try {
      (window.adsbygoogle = window.adsbygoogle || []).push({});
    } catch {
      /* reklam engelleyici */
    }
  }, [show]);

  if (!show) return null;
  return (
    <aside aria-label={t("label")} className={clsx("bg-mat px-3 pb-3 pt-2", className)}>
      <div className="mb-2 flex items-center justify-between text-[11px] text-muted">
        <span>{t("label")}</span>
        <Link href="/pro" className="font-medium hover:text-ink">{t("remove")}</Link>
      </div>
      <ins ref={ref} className="adsbygoogle block" style={{ display: "block", minHeight: kind === "feed" ? 250 : 90 }}
        data-ad-client={CLIENT} data-ad-slot={slot} data-ad-format={kind === "feed" ? "fluid" : "auto"}
        data-ad-layout-key={kind === "feed" ? "-fb+5w+4e-db+86" : undefined} data-full-width-responsive="true" />
    </aside>
  );
}

export function ProBadge({ className }: { className?: string }) {
  return (
    <span className={clsx("inline-flex items-center rounded-[5px] bg-accent px-1.5 py-[1px] text-[10px] font-bold tracking-[0.06em] text-accent-ink", className)}>
      PRO
    </span>
  );
}
