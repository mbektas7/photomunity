"use client";

import clsx from "clsx";
import { ChevronLeft, ChevronRight, LocateFixed, RotateCcw } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import dynamic from "next/dynamic";
import { useSearchParams } from "next/navigation";
import { Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { View } from "@/components/MapView";
import { LocationLine, MoonShape, type SkyLoc, fmtTime, isoDate, parseIsoDate, useMounted, useSkyLocation } from "@/components/sky";
import { Button } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { compassPoint, moonIllumination, sunPosition } from "@/lib/astro";
import { type DayPlan, type SkyEvent, moonPhaseKey, planDay } from "@/lib/sky";

const MapView = dynamic(() => import("@/components/MapView").then((m) => m.MapView), { ssr: false });

const SUN = "#f59e0b";
const SUN_SET = "#ef6c2f";
const MOON = "#3d63ff";
const MOON_SET = "#8b5cf6";

/** Harita: konum hep ortada; kaydırınca konum değişir. Yön çizgileri merkezden çizilir (kuzey yukarı). */
function DirectionMap({ loc, plan, onPick }: { loc: SkyLoc; plan: DayPlan; onPick: (lat: number, lng: number) => void }) {
  const [initial] = useState({ lat: loc.lat, lng: loc.lng, zoom: 10 });
  // Konum dışarıdan değişirse (profil yüklendi, konumum, sıfırla) oraya git; haritayı kaydırarak
  // seçilen konum için harita zaten orada, yeniden gitme (yakınlaştırma korunur)
  const zoom = useRef(10);
  const picked = useRef<string | null>(null);
  const lastFly = useRef<{ lat: number; lng: number; zoom: number; seq: number } | null>(null);
  const fly = useMemo(() => {
    if (picked.current !== `${loc.lat},${loc.lng}`) lastFly.current = { lat: loc.lat, lng: loc.lng, zoom: zoom.current, seq: Date.now() };
    return lastFly.current;
  }, [loc.lat, loc.lng]);
  const onView = useCallback((v: View) => {
    zoom.current = v.zoom;
    if (v.user && (Math.abs(v.lat - loc.lat) > 1e-4 || Math.abs(v.lng - loc.lng) > 1e-4)) {
      const lat = +v.lat.toFixed(4), lng = +v.lng.toFixed(4);
      picked.current = `${lat},${lng}`;
      onPick(lat, lng);
    }
  }, [loc.lat, loc.lng, onPick]);
  const lines = [
    { e: plan.sunrise, color: SUN, dash: undefined },
    { e: plan.sunset, color: SUN_SET, dash: "6 4" },
    { e: plan.moonrise, color: MOON, dash: undefined },
    { e: plan.moonset, color: MOON_SET, dash: "6 4" },
  ].filter((l): l is { e: SkyEvent; color: string; dash: string | undefined } => !!l.e);
  return (
    <div className="relative h-[340px] overflow-hidden rounded-card bg-surface-2 sm:h-[420px]">
      <MapView initial={initial} markers={[]} onView={onView} flyTo={fly} noRotate />
      <svg viewBox="-100 -100 200 200" preserveAspectRatio="xMidYMid meet" className="pointer-events-none absolute inset-0 h-full w-full overflow-visible" aria-hidden>
        {lines.map(({ e, color, dash }) => {
          const a = (e.az * Math.PI) / 180;
          return (
            <line key={color} x1={0} y1={0} x2={(400 * Math.sin(a)).toFixed(2)} y2={(-400 * Math.cos(a)).toFixed(2)}
              stroke={color} strokeWidth={2.2} strokeDasharray={dash} strokeLinecap="round" vectorEffect="non-scaling-stroke"
              style={{ filter: "drop-shadow(0 0 1.5px rgba(0,0,0,.6))" }} />
          );
        })}
        <circle r={3.2} fill="var(--accent)" stroke="#fff" strokeWidth={1.4} vectorEffect="non-scaling-stroke" />
      </svg>
      <span className="pointer-events-none absolute left-3 top-3 rounded-pill bg-scrim px-2.5 py-1 text-xs font-semibold backdrop-blur">N ↑</span>
    </div>
  );
}

/** Günün çizelgesi: gece / mavi saat / altın saat / gündüz (Güneş yüksekliğine göre, 5 dk adım). */
function Timeline({ date, lat, lng }: { date: Date; lat: number; lng: number }) {
  const t = useTranslations("sky");
  const locale = useLocale();
  const segs = useMemo(() => {
    const start = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
    const end = new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1).getTime();
    const kind = (alt: number) => (alt < -6 ? "night" : alt < -4 ? "blue" : alt < 6 ? "golden" : "day");
    const out: { kind: string; start: number; end: number }[] = [];
    for (let x = start; x < end; x += 5 * 60_000) {
      const k = kind(sunPosition(x + 150_000, lat, lng).alt);
      const last = out.at(-1);
      if (last && last.kind === k) last.end = Math.min(end, x + 5 * 60_000);
      else out.push({ kind: k, start: x, end: Math.min(end, x + 5 * 60_000) });
    }
    return { start, end, out };
  }, [date, lat, lng]);
  const total = segs.end - segs.start;
  const now = Date.now();
  const color: Record<string, string> = { night: "bg-[#161a26]", blue: "bg-[#3d63ff]", golden: "bg-[#f5a524]", day: "bg-[#cfe0ff]" };
  return (
    <div>
      <div className="relative flex h-10 overflow-hidden rounded-box">
        {segs.out.map((s) => (
          <div key={s.start} className={color[s.kind]} style={{ width: `${((s.end - s.start) / total) * 100}%` }}
            title={`${t(`timeline.${s.kind}`)} ${fmtTime(s.start, locale)}–${fmtTime(s.end, locale)}`} />
        ))}
        {now >= segs.start && now < segs.end && (
          <div className="absolute inset-y-0 w-0.5 bg-danger" style={{ left: `${((now - segs.start) / total) * 100}%` }} aria-label={t("timeline.now")} />
        )}
      </div>
      <div className="tnum mt-1.5 flex justify-between text-xs text-ink-muted">
        {[0, 6, 12, 18, 24].map((h) => <span key={h}>{String(h).padStart(2, "0")}:00</span>)}
      </div>
      <div className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-sm">
        {["night", "blue", "golden", "day"].map((k) => (
          <span key={k} className="flex items-center gap-2"><span className={clsx("h-3 w-5 rounded-[4px]", color[k])} /> {t(`timeline.${k}`)}</span>
        ))}
      </div>
    </div>
  );
}

function Planner() {
  const t = useTranslations("sky");
  const locale = useLocale();
  const params = useSearchParams();
  const { loc, setCustom, hasProfile } = useSkyLocation();
  const [date, setDate] = useState<Date>(() => parseIsoDate(params.get("date")) ?? new Date());
  const day = useMemo(() => new Date(date.getFullYear(), date.getMonth(), date.getDate()), [date]);
  const plan = useMemo(() => planDay(day, loc.lat, loc.lng), [day, loc.lat, loc.lng]);
  const moon = useMemo(() => moonIllumination(new Date(day.getFullYear(), day.getMonth(), day.getDate(), 22).getTime()), [day]);
  const shift = (n: number) => setDate(new Date(day.getFullYear(), day.getMonth(), day.getDate() + n));
  const onPick = useCallback((lat: number, lng: number) => setCustom({ lat, lng }), [setCustom]);
  // ?lat=&lng= ile gelindiyse (ör. fotoğraftaki "Bu kareyi tekrar çek") o konumu bir kez uygula
  const applied = useRef(false);
  useEffect(() => {
    if (applied.current) return;
    applied.current = true;
    const a = Number(params.get("lat")), b = Number(params.get("lng"));
    if (params.get("lat") && params.get("lng") && Number.isFinite(a) && Number.isFinite(b) && Math.abs(a) <= 90 && Math.abs(b) <= 180) {
      setCustom({ lat: +a.toFixed(4), lng: +b.toFixed(4) });
    }
  }, [params, setCustom]);

  function locate() {
    navigator.geolocation?.getCurrentPosition((p) => setCustom({ lat: +p.coords.latitude.toFixed(4), lng: +p.coords.longitude.toFixed(4) }));
  }

  const span = (s: { start: number; end: number } | null) => (s ? `${fmtTime(s.start, locale)} – ${fmtTime(s.end, locale)}` : "—");
  const ev = (e: SkyEvent | null) => (e ? `${Math.round(e.az)}° ${compassPoint(e.az, locale)}` : "");

  return (
    <div className="mt-6 flex flex-col gap-4">
      <div className="flex flex-wrap items-center gap-2">
        <button onClick={() => shift(-1)} aria-label={t("planner.prev_day")} className="grid h-11 w-11 place-items-center rounded-full bg-surface hover:bg-surface-2"><ChevronLeft className="h-5 w-5" /></button>
        <input type="date" value={isoDate(day)} aria-label={t("planner.date")}
          onChange={(e) => { const d = parseIsoDate(e.target.value); if (d) setDate(d); }}
          className="h-11 rounded-box border border-ring-idle bg-surface px-3 text-[15px]" />
        <button onClick={() => shift(1)} aria-label={t("planner.next_day")} className="grid h-11 w-11 place-items-center rounded-full bg-surface hover:bg-surface-2"><ChevronRight className="h-5 w-5" /></button>
        <Button variant="secondary" onClick={() => setDate(new Date())}>{t("planner.today")}</Button>
        <p className="ml-auto text-[15px] font-semibold capitalize">
          {new Intl.DateTimeFormat(locale, { weekday: "long", day: "numeric", month: "long", year: "numeric" }).format(day)}
        </p>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <LocationLine loc={loc} change={false} />
        <div className="ml-auto flex flex-wrap gap-1">
          <Button variant="ghost" onClick={locate}><LocateFixed className="h-4 w-4" /> {t("planner.use_location")}</Button>
          {loc.source === "custom" && (
            <Button variant="ghost" onClick={() => setCustom(null)}><RotateCcw className="h-4 w-4" /> {hasProfile ? t("planner.reset_profile") : t("planner.reset_default")}</Button>
          )}
        </div>
      </div>

      <DirectionMap loc={loc} plan={plan} onPick={onPick} />
      <p className="-mt-2 text-xs text-ink-muted">{t("planner.map_hint")}</p>

      <dl className="grid grid-cols-2 gap-px overflow-hidden rounded-card bg-line sm:grid-cols-4">
        {([["sunrise", plan.sunrise, SUN], ["sunset", plan.sunset, SUN_SET], ["moonrise", plan.moonrise, MOON], ["moonset", plan.moonset, MOON_SET]] as const).map(([k, e, c]) => (
          <div key={k} className="bg-surface px-4 py-3">
            <dt className="flex items-center gap-2 text-sm text-ink-muted"><span className="h-[3px] w-4 rounded-full" style={{ background: c }} /> {t(`planner.${k}`)}</dt>
            <dd className="tnum mt-0.5 text-lg font-semibold">{fmtTime(e?.t, locale)}</dd>
            <dd className="tnum text-sm text-ink-muted">{ev(e) || t("planner.none_today")}</dd>
          </div>
        ))}
      </dl>

      <section className="rounded-card bg-surface px-5 py-5">
        <h2 className="mb-4 font-semibold">{t("planner.timeline")}</h2>
        <Timeline date={day} lat={loc.lat} lng={loc.lng} />
      </section>

      <div className="grid gap-4 md:grid-cols-2">
        <section className="rounded-card bg-surface px-5 py-5">
          <h2 className="font-semibold">{t("planner.light")}</h2>
          <dl className="mt-3 divide-y divide-line">
            {([["blue_morning", plan.blueMorning, "#3d63ff"], ["golden_morning", plan.goldenMorning, "#f5a524"], ["golden_evening", plan.goldenEvening, "#f5a524"], ["blue_evening", plan.blueEvening, "#3d63ff"]] as const).map(([k, s, c]) => (
              <div key={k} className="flex items-baseline justify-between gap-4 py-2.5">
                <dt className="flex items-center gap-2 text-[15px]"><span className="h-2.5 w-2.5 rounded-full" style={{ background: c }} /> {t(`planner.${k}`)}</dt>
                <dd className="tnum text-[15px] font-medium">{span(s)}</dd>
              </div>
            ))}
          </dl>
          {plan.sunNoonAlt < -0.833 && <p className="mt-2 text-sm text-ink-muted">{t("planner.polar_night")}</p>}
        </section>
        <section className="rounded-card bg-surface px-5 py-5">
          <div className="flex items-center gap-3">
            <MoonShape phase={moon.phase} fraction={moon.fraction} size={40} />
            <div>
              <h2 className="font-semibold">{t(`phase.${moonPhaseKey(moon.phase)}`)}</h2>
              <p className="tnum text-sm text-ink-muted">{t("moon.lit", { pct: Math.round(moon.fraction * 100) })}</p>
            </div>
          </div>
          <dl className="mt-3 divide-y divide-line">
            {([
              ["civil", plan.civilDawn, plan.civilDusk],
              ["astro", plan.astroDawn, plan.astroDusk],
            ] as const).map(([k, a, b]) => (
              <div key={k} className="flex items-baseline justify-between gap-4 py-2.5">
                <dt className="text-[15px]">{t(`planner.${k}`)}</dt>
                <dd className="tnum text-[15px] font-medium">{fmtTime(a, locale)} / {fmtTime(b, locale)}</dd>
              </div>
            ))}
            <div className="flex items-baseline justify-between gap-4 py-2.5">
              <dt className="text-[15px]">{t("moon.highest")}</dt>
              <dd className="tnum text-[15px] font-medium">
                {plan.moonTransit ? `${fmtTime(plan.moonTransit.t, locale)} · ${Math.round(plan.moonTransit.alt)}° ${compassPoint(plan.moonTransit.az, locale)}` : t("moon.none")}
              </dd>
            </div>
          </dl>
        </section>
      </div>
      <p className="text-xs text-ink-muted">
        {t("planner.definitions")} <Link href="/planner" className="font-medium text-accent-text hover:underline">{t("planner.night_link")}</Link>
      </p>
    </div>
  );
}

export default function SunMoonPlannerPage() {
  const t = useTranslations("sky");
  const mounted = useMounted();
  return (
    <div className="mx-auto max-w-[1000px] px-4 pt-8 sm:px-6 sm:pt-12">
      <Link href="/sky" className="text-sm text-ink-muted hover:text-ink">← {t("title")}</Link>
      <h1 className="mt-3 text-[clamp(2rem,4.5vw,3rem)] font-bold leading-none tracking-[-0.04em]">{t("planner.title")}</h1>
      <p className="mt-3 max-w-[62ch] text-ink-muted">{t("planner.lead")}</p>
      {mounted ? <Suspense><Planner /></Suspense> : <div className="mt-10 h-[600px] rounded-card bg-surface" />}
      <p className="mt-6 text-xs text-ink-muted">{t("accuracy")}</p>
    </div>
  );
}
