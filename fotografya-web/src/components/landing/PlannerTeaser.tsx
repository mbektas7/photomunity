"use client";

import { LocateFixed } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useMemo, useState } from "react";
import { MoonGlyph } from "@/components/SkyPlanner";
import { compassPoint, planNight } from "@/lib/astro";

const fmt = (t: number, locale: string) => new Intl.DateTimeFormat(locale, { hour: "2-digit", minute: "2-digit" }).format(new Date(t));

/** Bu gece (yoksa önümüzdeki 30 gün içindeki ilk uygun gece) için gerçek hesap: tarayıcıda yapılır. */
export function PlannerTeaser() {
  const t = useTranslations("landing");
  const tp = useTranslations("planner");
  const locale = useLocale();
  const [loc, setLoc] = useState({ lat: 40.83, lng: 41.16, name: t("planner_default_place") });

  const result = useMemo(() => {
    const today = new Date();
    // Kış aylarında çekirdek karanlıkta görünmez; ilk uygun geceyi 150 güne kadar ara
    for (let i = 0; i < 150; i++) {
      const d = new Date(today);
      d.setDate(today.getDate() + i);
      const plan = planNight(d, loc.lat, loc.lng);
      if (plan.bestWindows.length) return { date: d, plan, isTonight: i === 0 };
    }
    return { date: today, plan: planNight(today, loc.lat, loc.lng), isTonight: true, none: true };
  }, [loc]);

  const { plan, date, isTonight } = result;
  const none = "none" in result;
  const best = plan.bestWindows[0];
  const keys = ["new", "waxing_crescent", "first_quarter", "waxing_gibbous", "full", "waning_gibbous", "last_quarter", "waning_crescent"];
  const phaseName = tp(`phase.${keys[Math.round(plan.phase * 8) % 8]}`);
  const when = isTonight
    ? t("planner_tonight", { place: loc.name })
    : t("planner_next", { place: loc.name, date: new Intl.DateTimeFormat(locale, { day: "numeric", month: "long" }).format(date) });

  return (
    <div className="flex flex-col gap-2.5">
      <div className="flex flex-col gap-2.5 sm:flex-row">
        <div className="flex flex-1 flex-col gap-2 rounded-card bg-accent p-5 text-accent-ink">
          <p className="text-[13.5px] font-semibold opacity-90">{when}</p>
          <p className="tnum text-[clamp(2rem,4vw,2.6rem)] font-bold leading-none tracking-[-0.04em]">
            {best ? `${fmt(best.start, locale)} – ${fmt(best.end, locale)}` : t("planner_none")}
          </p>
          {plan.coreTransit && (
            <p className="tnum text-[14px] opacity-90">{t("planner_core", { alt: Math.round(plan.coreTransit.alt), dir: compassPoint(plan.coreTransit.az, locale) })}</p>
          )}
          {!isTonight && <p className="text-[13px] opacity-85">{t("planner_season")}</p>}
          {none && <p className="text-[13px] opacity-85">{t("planner_never")}</p>}
        </div>
        <div className="flex flex-row items-center gap-3 rounded-card bg-surface-2 p-5 sm:w-[210px] sm:flex-col sm:items-start sm:justify-end">
          <MoonGlyph phase={plan.phase} fraction={plan.illumination} size={44} />
          <span>
            <span className="block text-[16px] font-bold">{phaseName}</span>
            <span className="tnum block text-caption text-ink-muted">{t("planner_moon_lit", { pct: Math.round(plan.illumination * 100) })}</span>
          </span>
        </div>
      </div>
      <button
        type="button"
        onClick={() => navigator.geolocation?.getCurrentPosition((p) => setLoc({ lat: p.coords.latitude, lng: p.coords.longitude, name: t("planner_here") }))}
        className="inline-flex min-h-11 items-center gap-1.5 self-start rounded-pill px-2 text-[14px] font-semibold text-accent-text hover:bg-surface-2"
      >
        <LocateFixed className="h-4 w-4" strokeWidth={1.8} aria-hidden /> {t("planner_use_location")}
      </button>
    </div>
  );
}
