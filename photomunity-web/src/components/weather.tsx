"use client";

import { useQuery } from "@tanstack/react-query";
import clsx from "clsx";
import { Cloud } from "lucide-react";
import { useTranslations } from "next-intl";
import { fetchForecast, type ScoreLabel } from "@/lib/weather";

/** Open-Meteo saatlik tahmini; konum ~1 km'ye yuvarlanır, 30 dk taze sayılır. */
export function useForecast(lat: number | null | undefined, lng: number | null | undefined, enabled = true) {
  const ok = lat != null && lng != null && enabled;
  return useQuery({
    queryKey: ["weather", ok ? lat.toFixed(2) : null, ok ? lng.toFixed(2) : null],
    enabled: ok,
    queryFn: ({ signal }) => fetchForecast(lat!, lng!, signal),
    staleTime: 30 * 60_000,
    gcTime: 60 * 60_000,
    retry: 1,
  });
}

const LABEL_TONE: Record<ScoreLabel, string> = {
  good: "bg-[#e3f4ec] text-[#0f6e56] dark:bg-[#0f6e56]/30 dark:text-[#7fe0c0]",
  fair: "bg-[#fdebd9] text-[#b45309] dark:bg-[#b45309]/25 dark:text-[#f5c27a]",
  poor: "bg-[#fdecea] text-[#d92d20] dark:bg-[#d92d20]/25 dark:text-[#ff9b92]",
};

export function ScoreChip({ label, className }: { label: ScoreLabel; className?: string }) {
  const t = useTranslations("weather");
  return <span className={clsx("inline-block rounded-full px-2.5 py-0.5 text-xs font-bold", LABEL_TONE[label], className)}>{t(`label.${label}`)}</span>;
}

/** Bulut oranı çubuğu (0–100). */
export function CloudBar({ value, className }: { value: number; className?: string }) {
  const v = Math.max(0, Math.min(100, value));
  return (
    <span className={clsx("relative block h-1.5 overflow-hidden rounded-full bg-current/15", className)} aria-hidden>
      <span className="absolute inset-y-0 left-0 rounded-full bg-current/70" style={{ width: `${v}%` }} />
    </span>
  );
}

/** Tek satırlık bulut tahmini (plan, etkinlik): "Bulut tahmini %12". */
export function CloudLine({ value }: { value: number | null }) {
  const t = useTranslations("weather");
  if (value == null) return null;
  return (
    <span className="inline-flex items-center gap-1.5">
      <Cloud className="h-4 w-4" strokeWidth={1.8} aria-hidden />
      {t("cloud_forecast", { pct: Math.round(value) })}
    </span>
  );
}
