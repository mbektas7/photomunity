"use client";

import clsx from "clsx";
import { ChevronLeft, ChevronRight, X } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useMemo, useState } from "react";
import { LocationLine, MoonShape, fmtTime, isoDate, useMounted, useSkyLocation } from "@/components/sky";
import { buttonClass } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { compassPoint, planNight } from "@/lib/astro";
import { type MoonDay, moonAgeDays, moonMonth, moonPhaseKey, nextPhase, planDay } from "@/lib/sky";

function DayDetail({ day, lat, lng, onClose }: { day: MoonDay; lat: number; lng: number; onClose: () => void }) {
  const t = useTranslations("sky");
  const locale = useLocale();
  const { d, night, newMoon } = useMemo(() => {
    const at22 = new Date(day.date.getFullYear(), day.date.getMonth(), day.date.getDate(), 22);
    return { d: planDay(day.date, lat, lng), night: planNight(day.date, lat, lng), newMoon: nextPhase(at22) };
  }, [day, lat, lng]);
  const ev = (e: { t: number; az: number } | null) =>
    e ? `${fmtTime(e.t, locale)} · ${Math.round(e.az)}° ${compassPoint(e.az, locale)}` : t("moon.none");
  const rows: [string, string][] = [
    [t("moon.moonrise"), ev(d.moonrise)],
    [t("moon.moonset"), ev(d.moonset)],
    [t("moon.highest"), d.moonTransit ? `${fmtTime(d.moonTransit.t, locale)} · ${Math.round(d.moonTransit.alt)}° ${compassPoint(d.moonTransit.az, locale)}` : t("moon.none")],
    [t("moon.sun_set_rise"), `${fmtTime(d.sunset?.t, locale)} / ${fmtTime(d.sunrise?.t, locale)}`],
    [t("moon.astro_dark"), night.duskAstro ? `${fmtTime(night.duskAstro, locale)} – ${fmtTime(night.dawnAstro, locale)}` : t("moon.no_dark")],
    [t("moon.next_new"), new Intl.DateTimeFormat(locale, { day: "numeric", month: "long" }).format(newMoon)],
  ];
  return (
    <section className="rounded-card bg-surface px-5 py-5" aria-live="polite">
      <div className="flex items-start gap-4">
        <MoonShape phase={day.phase} fraction={day.fraction} size={64} />
        <div className="min-w-0 flex-1">
          <p className="text-xs font-semibold uppercase tracking-[0.08em] text-ink-muted">
            {new Intl.DateTimeFormat(locale, { weekday: "long", day: "numeric", month: "long" }).format(day.date)}
          </p>
          <p className="mt-1 text-[22px] font-bold leading-tight tracking-[-0.02em]">{t(`phase.${moonPhaseKey(day.phase)}`)}</p>
          <p className="tnum text-sm text-ink-muted">
            {t("moon.lit", { pct: Math.round(day.fraction * 100) })} · {t("moon.age", { days: moonAgeDays(day.phase).toLocaleString(locale, { maximumFractionDigits: 1, minimumFractionDigits: 1 }) })}
          </p>
        </div>
        <button onClick={onClose} aria-label={t("close")} className="-mr-2 -mt-1 grid h-10 w-10 place-items-center rounded-full text-ink-muted hover:bg-surface-2"><X className="h-5 w-5" /></button>
      </div>
      <dl className="mt-5 divide-y divide-line">
        {rows.map(([k, v]) => (
          <div key={k} className="flex items-baseline justify-between gap-4 py-2.5">
            <dt className="text-[15px] text-ink-muted">{k}</dt>
            <dd className="tnum text-right text-[15px] font-medium">{v}</dd>
          </div>
        ))}
      </dl>
      <div className="mt-4 flex flex-wrap gap-2">
        <Link href={`/sky/planner?date=${isoDate(day.date)}`} className={buttonClass("primary")}>{t("moon.open_planner")}</Link>
        <Link href="/planner" className={buttonClass("secondary")}>{t("moon.open_night")}</Link>
      </div>
      <p className="mt-3 text-xs text-ink-muted">{t("moon.ar_hint")}</p>
    </section>
  );
}

function Calendar() {
  const t = useTranslations("sky");
  const locale = useLocale();
  const { loc } = useSkyLocation();
  const now = new Date();
  const [ym, setYm] = useState({ y: now.getFullYear(), m: now.getMonth() + 1 });
  const [sel, setSel] = useState<string | null>(isoDate(now));
  const days = useMemo(() => moonMonth(ym.y, ym.m), [ym]);
  const lead = (days[0]!.date.getDay() + 6) % 7; // Pazartesi ilk gün
  const weekdays = Array.from({ length: 7 }, (_, i) =>
    new Intl.DateTimeFormat(locale, { weekday: "short" }).format(new Date(2024, 0, 1 + i)), // 1 Ocak 2024 Pazartesi
  );
  const selected = days.find((d) => isoDate(d.date) === sel) ?? null;
  const todayIso = isoDate(now);
  const shift = (n: number) => setYm(({ y, m }) => {
    const d = new Date(y, m - 1 + n, 1);
    return { y: d.getFullYear(), m: d.getMonth() + 1 };
  });

  return (
    <>
      <div className="mt-4"><LocationLine loc={loc} /></div>
      <div className="mt-6 grid items-start gap-4 lg:grid-cols-[1fr_360px]">
        <section className="rounded-card bg-surface px-3 py-4 sm:px-5 sm:py-5">
          <div className="mb-4 flex items-center justify-between gap-2">
            <button onClick={() => shift(-1)} aria-label={t("prev_month")} className="grid h-10 w-10 place-items-center rounded-full hover:bg-surface-2"><ChevronLeft className="h-5 w-5" /></button>
            <h2 className="text-lg font-semibold capitalize">
              {new Intl.DateTimeFormat(locale, { month: "long", year: "numeric" }).format(new Date(ym.y, ym.m - 1, 1))}
            </h2>
            <button onClick={() => shift(1)} aria-label={t("next_month")} className="grid h-10 w-10 place-items-center rounded-full hover:bg-surface-2"><ChevronRight className="h-5 w-5" /></button>
          </div>
          <div className="grid grid-cols-7 gap-1 text-center">
            {weekdays.map((w) => <div key={w} className="pb-1 text-xs font-medium text-ink-muted">{w}</div>)}
            {Array.from({ length: lead }, (_, i) => <div key={`e${i}`} />)}
            {days.map((d) => {
              const iso = isoDate(d.date);
              return (
                <button
                  key={iso}
                  onClick={() => setSel(iso)}
                  aria-pressed={sel === iso}
                  aria-label={`${new Intl.DateTimeFormat(locale, { day: "numeric", month: "long" }).format(d.date)}, ${t(`phase.${moonPhaseKey(d.phase)}`)}, %${Math.round(d.fraction * 100)}`}
                  className={clsx(
                    "flex flex-col items-center gap-1 rounded-box px-0.5 py-2 transition-colors",
                    d.dark ? "bg-[#11141c] text-white hover:bg-[#1b2030]" : "hover:bg-surface-2",
                    sel === iso && "ring-2 ring-accent",
                  )}
                >
                  <span className={clsx("tnum text-[13px] font-semibold", iso === todayIso && "rounded-full bg-accent px-1.5 text-accent-ink")}>{d.date.getDate()}</span>
                  <MoonShape phase={d.phase} fraction={d.fraction} size={26} />
                  <span className={clsx("tnum text-[11px]", d.dark ? "text-white/65" : "text-ink-muted")}>%{Math.round(d.fraction * 100)}</span>
                </button>
              );
            })}
          </div>
          <p className="mt-4 flex items-center gap-2 px-1 text-sm text-ink-muted">
            <span className="inline-block h-3.5 w-3.5 rounded-[5px] bg-[#11141c]" /> {t("moon.dark_legend")}
          </p>
        </section>
        {selected
          ? <DayDetail day={selected} lat={loc.lat} lng={loc.lng} onClose={() => setSel(null)} />
          : <p className="rounded-card bg-surface px-5 py-5 text-sm text-ink-muted">{t("moon.pick_day")}</p>}
      </div>
    </>
  );
}

export default function MoonCalendarPage() {
  const t = useTranslations("sky");
  const mounted = useMounted();
  return (
    <div className="mx-auto max-w-[1100px] px-4 pt-8 sm:px-6 sm:pt-12">
      <Link href="/sky" className="text-sm text-ink-muted hover:text-ink">← {t("title")}</Link>
      <h1 className="mt-3 text-[clamp(2rem,4.5vw,3rem)] font-bold leading-none tracking-[-0.04em]">{t("moon.title")}</h1>
      <p className="mt-3 max-w-[62ch] text-ink-muted">{t("moon.lead")}</p>
      {mounted ? <Calendar /> : <div className="mt-10 h-[520px] rounded-card bg-surface" />}
      <p className="mt-6 text-xs text-ink-muted">{t("accuracy")}</p>
    </div>
  );
}
