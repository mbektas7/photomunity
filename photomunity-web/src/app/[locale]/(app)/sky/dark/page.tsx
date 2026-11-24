"use client";

import { CalendarPlus, X } from "lucide-react";
import { useTranslations } from "next-intl";
import dynamic from "next/dynamic";
import { useCallback, useMemo, useState } from "react";
import { HowItWorks } from "@/components/intro";
import type { MarkerSpec, RasterOverlay } from "@/components/MapView";
import { coords, useMounted, useSkyLocation } from "@/components/sky";
import { buttonClass } from "@/components/ui";
import { Link } from "@/i18n/navigation";

const MapView = dynamic(() => import("@/components/MapView").then((m) => m.MapView), { ssr: false });

/**
 * NASA GIBS — VIIRS Black Marble (2016 yıllık gece ışıkları bileşimi), Web Mercator,
 * GoogleMapsCompatible_Level8: en fazla 8. seviye karo; üstünde MapLibre büyüterek gösterir.
 */
const GIBS_TILES = "https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/VIIRS_Black_Marble/default/2016-01-01/GoogleMapsCompatible_Level8/{z}/{y}/{x}.png";

/** Işık kirliliği için yaklaşık gösterge: gece ışıkları katmanı. Bortle değeri yok (veri kaynağı yok). */
export default function DarkSpotsPage() {
  const t = useTranslations("sky.dark");
  const ts = useTranslations("sky");
  const mounted = useMounted();
  const { loc } = useSkyLocation();
  const [opacity, setOpacity] = useState(0.75);
  const [pick, setPick] = useState<{ lat: number; lng: number } | null>(null);

  const overlay = useMemo<RasterOverlay>(
    () => ({ id: "viirs", tiles: [GIBS_TILES], maxzoom: 8, attribution: "NASA GIBS / VIIRS", opacity }),
    [opacity],
  );
  const markers = useMemo<MarkerSpec[]>(
    () => pick ? [{
      key: `${pick.lat},${pick.lng}`,
      lat: pick.lat,
      lng: pick.lng,
      element: () => {
        const el = document.createElement("span");
        el.style.cssText = "display:block;width:20px;height:20px;border-radius:999px;background:var(--accent);border:3px solid #fff;box-shadow:0 1px 6px rgba(0,0,0,.5)";
        return el;
      },
    }] : [],
    [pick],
  );
  const noop = useCallback(() => {}, []);
  const onMapClick = useCallback((lat: number, lng: number) => setPick({ lat: +lat.toFixed(4), lng: +lng.toFixed(4) }), []);

  return (
    <div className="mx-auto max-w-[1100px] px-4 pt-8 sm:px-6 sm:pt-12">
      <Link href="/sky" className="text-sm text-ink-muted hover:text-ink">← {ts("title")}</Link>
      <h1 className="mt-3 flex items-center gap-3 text-[clamp(2rem,4.5vw,3rem)] font-bold leading-none tracking-[-0.04em]">
        {t("title")} <HowItWorks module="dark" />
      </h1>
      <p className="mt-3 max-w-[62ch] text-ink-muted">{t("lead")}</p>

      <div className="relative mt-6 h-[62vh] min-h-[360px] overflow-hidden rounded-card bg-surface-2">
        {mounted && (
          <MapView
            key={`${loc.lat},${loc.lng}`}
            initial={{ lat: loc.lat, lng: loc.lng, zoom: 7 }}
            markers={markers}
            onView={noop}
            overlay={overlay}
            onMapClick={onMapClick}
          />
        )}
        {pick && (
          <div className="absolute left-3 right-14 top-3 flex flex-wrap items-center gap-x-3 gap-y-2 rounded-box bg-surface p-3 shadow-float sm:right-auto sm:w-[430px]">
            <span className="tnum mr-auto whitespace-nowrap text-sm text-ink-muted">{coords(pick.lat, pick.lng)}</span>
            <Link href={`/plans/new?kind=milkyway&lat=${pick.lat}&lng=${pick.lng}`} className={buttonClass("primary", "!h-10 !min-h-10 px-4 text-[14px]")}>
              <CalendarPlus className="h-4 w-4" aria-hidden /> {t("plan_here")}
            </Link>
            <button type="button" onClick={() => setPick(null)} aria-label={t("clear")} className="grid h-10 w-10 place-items-center rounded-full hover:bg-surface-2">
              <X className="h-4 w-4" aria-hidden />
            </button>
          </div>
        )}
      </div>

      <div className="mt-4 grid gap-4 sm:grid-cols-2">
        <div className="rounded-card bg-surface p-4">
          <label htmlFor="dark-opacity" className="flex items-baseline justify-between text-sm font-medium">
            {t("opacity")} <span className="tnum text-ink-muted">{Math.round(opacity * 100)}%</span>
          </label>
          <input
            id="dark-opacity"
            type="range"
            min={0}
            max={1}
            step={0.05}
            value={opacity}
            onChange={(e) => setOpacity(+e.target.value)}
            className="mt-3 w-full accent-[var(--accent)]"
          />
        </div>
        <div className="rounded-card bg-surface p-4">
          <p className="text-sm font-medium">{t("legend_title")}</p>
          <div className="mt-3 h-3 rounded-full bg-[linear-gradient(90deg,#05070f,#1b2340_35%,#d9a441_75%,#fff6d8)]" aria-hidden />
          <div className="mt-1.5 flex justify-between gap-4 text-[13px] text-ink-muted">
            <span>{t("legend_dark")}</span>
            <span className="text-right">{t("legend_bright")}</span>
          </div>
        </div>
      </div>
      <p className="mt-4 text-sm text-ink-muted">{t("tap_hint")}</p>
      <p className="mt-2 text-xs text-ink-muted">{t("note")}</p>
    </div>
  );
}
