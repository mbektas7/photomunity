"use client";

import { MapPin } from "lucide-react";
import { useTranslations } from "next-intl";
import { useCallback, useEffect, useState, useSyncExternalStore } from "react";
import { Link } from "@/i18n/navigation";
import { useMe } from "@/lib/hooks";

// Gökyüzü sayfalarında ortak parçalar: konum, saat biçimi, Ay şekli.

export type SkyLoc = { lat: number; lng: number; label: string | null; source: "profile" | "default" | "custom" };

const DEFAULT = { lat: 41.01, lng: 28.98 }; // İstanbul
const KEY = "sky.location";

/** Hesaplar tarayıcının saat diliminde yapılır; sunucu çiziminde boş kalır (hidrasyon uyuşmazlığı olmasın). */
export function useMounted() {
  return useSyncExternalStore(
    () => () => {},
    () => true,
    () => false,
  );
}

/**
 * Konum: kullanıcının seçtiği (bu tarayıcıda saklanır) → profildeki enlem/boylam → İstanbul.
 */
export function useSkyLocation() {
  const t = useTranslations("sky");
  const { data: me } = useMe();
  const [custom, setCustomState] = useState<{ lat: number; lng: number } | null>(null);

  useEffect(() => {
    try {
      const raw = window.localStorage.getItem(KEY);
      if (raw) {
        const v = JSON.parse(raw) as { lat: number; lng: number };
        if (Math.abs(v.lat) <= 90 && Math.abs(v.lng) <= 180) setCustomState(v);
      }
    } catch { /* saklama kapalı olabilir */ }
  }, []);

  const setCustom = useCallback((v: { lat: number; lng: number } | null) => {
    setCustomState(v);
    try {
      if (v) window.localStorage.setItem(KEY, JSON.stringify(v));
      else window.localStorage.removeItem(KEY);
    } catch { /* yok say */ }
  }, []);

  const profile = me?.latitude != null && me.longitude != null ? { lat: me.latitude, lng: me.longitude } : null;
  const loc: SkyLoc = custom
    ? { ...custom, label: null, source: "custom" }
    : profile
      ? { ...profile, label: me?.city ?? null, source: "profile" }
      : { ...DEFAULT, label: t("default_place"), source: "default" };
  return { loc, setCustom, hasProfile: !!profile };
}

export const coords = (lat: number, lng: number) =>
  `${Math.abs(lat).toFixed(2)}° ${lat >= 0 ? "N" : "S"}, ${Math.abs(lng).toFixed(2)}° ${lng >= 0 ? "E" : "W"}`;

/** Konum satırı: yer adı ve koordinat, nereden geldiği ve değiştirme bağlantısı. */
export function LocationLine({ loc, change = true }: { loc: SkyLoc; change?: boolean }) {
  const t = useTranslations("sky");
  return (
    <p className="flex flex-wrap items-center gap-x-2 gap-y-1 text-sm text-ink-muted">
      <MapPin className="h-4 w-4" strokeWidth={1.8} aria-hidden />
      <span className="font-medium text-ink">{loc.label || t("custom_place")}</span>
      <span className="tnum">{coords(loc.lat, loc.lng)}</span>
      <span>· {t(`source.${loc.source}`)}</span>
      {change && <Link href="/sky/planner" className="font-medium text-accent-text hover:underline">{t("change_location")}</Link>}
    </p>
  );
}

export const fmtTime = (t: number | null | undefined, locale: string) =>
  t == null ? "—" : new Intl.DateTimeFormat(locale, { hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(new Date(t));

export const isoDate = (d: Date) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;

export function parseIsoDate(s: string | null | undefined): Date | null {
  const m = s?.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!m) return null;
  const d = new Date(+m[1]!, +m[2]! - 1, +m[3]!);
  return Number.isNaN(d.getTime()) ? null : d;
}

/**
 * Ay'ın görünen şekli (kuzey yarımküreden): aydınlık yarım disk + terminatör elipsi.
 * Büyürken (evre < 0.5) sağ taraf, küçülürken sol taraf aydınlık.
 */
export function MoonShape({ phase, fraction, size = 56, className }: { phase: number; fraction: number; size?: number; className?: string }) {
  const r = size / 2;
  const p = ((phase % 1) + 1) % 1;
  const waxing = p < 0.5;
  const k = 1 - 2 * Math.max(0, Math.min(1, fraction)); // terminatör elipsinin yatay yarıçap oranı
  // Üstten alta aydınlık tarafın kenarından, alttan üste terminatörden geç
  const d = `M ${r} 0 A ${r} ${r} 0 0 ${waxing ? 1 : 0} ${r} ${size} A ${(Math.abs(k) * r).toFixed(2)} ${r} 0 0 ${(k > 0) === waxing ? 0 : 1} ${r} 0 Z`;
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className={className} aria-hidden>
      <circle cx={r} cy={r} r={r - 0.25} fill="#2a2e38" />
      {fraction > 0.005 && <path d={d} fill="#efe8d2" />}
      <circle cx={r} cy={r} r={r - 0.5} fill="none" stroke="rgba(255,255,255,0.08)" strokeWidth={1} />
    </svg>
  );
}
