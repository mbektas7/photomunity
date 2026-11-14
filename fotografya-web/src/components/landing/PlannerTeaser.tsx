"use client";

import { LocateFixed } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useMemo, useState } from "react";
import { MoonGlyph } from "@/components/SkyPlanner";
import { Link } from "@/i18n/navigation";
import { compassPoint, planNight } from "@/lib/astro";

const fmt = (t: number, locale: string) => new Intl.DateTimeFormat(locale, { hour: "2-digit", minute: "2-digit" }).format(new Date(t));

/** Bu gece (yoksa önümüzdeki 30 gün içindeki ilk uygun gece) için gerçek hesap: tarayıcıda yapılır. */
export function PlannerTeaser() {
  const t = useTranslations("landing");
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
  const s = plan.samples, t0 = s[0]!.t, t1 = s.at(-1)!.t;
  const W = 520, H = 120;
  const x = (tt: number) => ((tt - t0) / (t1 - t0)) * W;
  const y = (alt: number) => 6 + ((90 - Math.max(-10, Math.min(90, alt))) / 100) * (H - 12);
  const path = (get: (i: number) => number) => s.map((p, i) => `${i ? "L" : "M"}${x(p.t).toFixed(1)},${y(get(i)).toFixed(1)}`).join("");

  return (
    <div className="bg-black p-5 text-[#f2f2ee] sm:p-6">
      <div className="flex items-start justify-between gap-4">
        <div>
          <p className="text-[13px] text-[#8d8d88]">{isTonight ? t("planner_tonight", { place: loc.name }) : t("planner_next", { place: loc.name, date: new Intl.DateTimeFormat(locale, { day: "numeric", month: "long" }).format(date) })}</p>
          <p className="tnum mt-1 text-[32px] font-semibold leading-none tracking-tight">{best ? `${fmt(best.start, locale)} – ${fmt(best.end, locale)}` : t("planner_none")}</p>
          {!isTonight && <p className="mt-2 max-w-[38ch] text-[13px] text-[#8d8d88]">{t("planner_season")}</p>}
          {none && <p className="mt-2 max-w-[38ch] text-[13px] text-[#8d8d88]">{t("planner_never")}</p>}
          {plan.coreTransit && (
            <p className="tnum mt-2 text-[14px] text-[#c9c9c4]">
              {t("planner_core", { alt: Math.round(plan.coreTransit.alt), dir: compassPoint(plan.coreTransit.az, locale) })}
            </p>
          )}
        </div>
        <div className="flex shrink-0 flex-col items-center gap-1 text-[12px] text-[#8d8d88] [--ink:#f2f2ee]">
          <MoonGlyph phase={plan.phase} fraction={plan.illumination} size={44} />
          <span className="tnum">{t("planner_moon", { pct: Math.round(plan.illumination * 100) })}</span>
        </div>
      </div>
      <svg viewBox={`0 0 ${W} ${H}`} className="mt-5 block w-full" aria-hidden>
        {plan.bestWindows.map((w) => <rect key={w.start} x={x(w.start)} y={0} width={x(w.end) - x(w.start)} height={H} fill="rgba(156,147,255,0.22)" />)}
        <line x1={0} x2={W} y1={y(0)} y2={y(0)} stroke="#555" strokeDasharray="3 4" />
        <path d={path((i) => s[i]!.moon.alt)} fill="none" stroke="#8d8d88" strokeWidth={1.5} />
        <path d={path((i) => s[i]!.core.alt)} fill="none" stroke="#9c93ff" strokeWidth={2.5} />
      </svg>
      <div className="mt-4 flex flex-wrap items-center gap-3">
        <Link href="/planner" className="inline-flex h-10 items-center rounded-full border border-white/30 px-4 text-[15px] font-semibold text-[#f2f2ee] hover:border-white">{t("planner_open")}</Link>
        <button
          type="button"
          onClick={() => navigator.geolocation?.getCurrentPosition((p) => setLoc({ lat: p.coords.latitude, lng: p.coords.longitude, name: t("planner_here") }))}
          className="inline-flex items-center gap-1.5 text-sm text-[#c9c9c4] hover:text-white"
        >
          <LocateFixed className="h-4 w-4" /> {t("planner_use_location")}
        </button>
      </div>
    </div>
  );
}
