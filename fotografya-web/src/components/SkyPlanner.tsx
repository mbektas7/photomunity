"use client";

import clsx from "clsx";
import { LocateFixed } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useMemo, useState } from "react";
import { type NightPlan, compassPoint, corePosition, moonPosition, planNight, sunPosition } from "@/lib/astro";
import { useMe } from "@/lib/hooks";
import { Button } from "./ui";

const fmtTime = (t: number | null, locale: string) =>
  t === null ? "—" : new Intl.DateTimeFormat(locale, { hour: "2-digit", minute: "2-digit" }).format(new Date(t));

export function MoonGlyph({ phase, fraction, size = 56 }: { phase: number; fraction: number; size?: number }) {
  // Aydınlık kısım: evre < 0.5 büyüyen (sağ), > 0.5 küçülen (sol)
  const r = size / 2;
  const waxing = phase < 0.5;
  const k = 1 - 2 * fraction; // terminatör elips yarıçap oranı
  const d = `M ${r} 0 A ${r} ${r} 0 0 ${waxing ? 1 : 0} ${r} ${size} A ${Math.abs(k) * r} ${r} 0 0 ${(k > 0) === waxing ? 0 : 1} ${r} 0 Z`;
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden>
      <circle cx={r} cy={r} r={r} fill="var(--line)" />
      <path d={d} fill="var(--ink-subtle)" />
    </svg>
  );
}

function darkRanges(s: NightPlan["samples"]) {
  const out: { start: number; end: number }[] = [];
  let open: number | null = null;
  for (const p of s) {
    if (p.sun.alt < -18 && open === null) open = p.t;
    if (p.sun.alt >= -18 && open !== null) { out.push({ start: open, end: p.t }); open = null; }
  }
  if (open !== null) out.push({ start: open, end: s.at(-1)!.t });
  return out;
}

/** Öğleden öğleye yükseklik grafiği: karanlık dönem gölgeli, en iyi pencere vurgulu. */
function AltitudeChart({ plan, selected, onSelect }: { plan: NightPlan; selected: number; onSelect: (t: number) => void }) {
  const t = useTranslations("planner");
  const locale = useLocale();
  const W = 720, H = 260, top = 16, bottom = 28;
  const s = plan.samples;
  const t0 = s[0]!.t, t1 = s.at(-1)!.t;
  const x = (tt: number) => ((tt - t0) / (t1 - t0)) * W;
  const y = (alt: number) => top + ((90 - Math.max(-20, Math.min(90, alt))) / 110) * (H - top - bottom);
  const path = (get: (i: number) => number) => s.map((p, i) => `${i ? "L" : "M"}${x(p.t).toFixed(1)},${y(get(i)).toFixed(1)}`).join("");
  const hours = Array.from({ length: 25 }, (_, i) => t0 + i * 3_600_000).filter((_, i) => i % 3 === 0);
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="block w-full touch-none select-none" role="img" aria-label={t("chart_label")}
      onPointerDown={(e) => {
        const move = (ev: PointerEvent | React.PointerEvent) => {
          const rect = (e.currentTarget as SVGElement).getBoundingClientRect();
          onSelect(t0 + Math.max(0, Math.min(1, (ev.clientX - rect.left) / rect.width)) * (t1 - t0));
        };
        move(e);
        const up = () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up); };
        window.addEventListener("pointermove", move);
        window.addEventListener("pointerup", up);
      }}>
      {/* Güneş −18°'nin altında: astronomik karanlık (kesintisiz aralıklar olarak) */}
      {darkRanges(s).map((r) => (
        <rect key={r.start} x={x(r.start)} y={top} width={x(r.end) - x(r.start)} height={H - top - bottom} fill="color-mix(in srgb, var(--ink) 9%, transparent)" />
      ))}
      {plan.bestWindows.map((w) => <rect key={w.start} x={x(w.start)} y={top} width={x(w.end) - x(w.start)} height={H - top - bottom} fill="color-mix(in srgb, var(--accent) 16%, transparent)" />)}
      <line x1={0} x2={W} y1={y(0)} y2={y(0)} stroke="var(--ink-muted)" strokeDasharray="3 4" />
      {[30, 60].map((a) => <line key={a} x1={0} x2={W} y1={y(a)} y2={y(a)} stroke="var(--line)" />)}
      <path d={path((i) => s[i]!.sun.alt)} fill="none" stroke="#e8a33d" strokeWidth={2} />
      <path d={path((i) => s[i]!.moon.alt)} fill="none" stroke="var(--ink-muted)" strokeWidth={2} />
      <path d={path((i) => s[i]!.core.alt)} fill="none" stroke="var(--accent)" strokeWidth={3} />
      <line x1={x(selected)} x2={x(selected)} y1={top} y2={H - bottom} stroke="var(--ink)" strokeWidth={1.5} />
      {hours.map((h) => (
        <text key={h} x={x(h)} y={H - 8} textAnchor="middle" fontSize={11} fill="var(--ink-muted)">{fmtTime(h, locale)}</text>
      ))}
      <text x={4} y={y(0) - 4} fontSize={10} fill="var(--ink-muted)">{t("horizon")}</text>
    </svg>
  );
}

/** Seçilen andaki pusula: çekirdek ve Ay'ın yönü ile yüksekliği. */
function Compass({ at, lat, lng }: { at: number; lat: number; lng: number }) {
  const t = useTranslations("planner");
  const locale = useLocale();
  const core = corePosition(at, lat, lng), moon = moonPosition(at, lat, lng), sun = sunPosition(at, lat, lng);
  const R = 110, C = 130;
  const pt = (az: number, alt: number) => {
    const r = R * (1 - Math.max(0, alt) / 90);
    return { x: C + r * Math.sin((az * Math.PI) / 180), y: C - r * Math.cos((az * Math.PI) / 180) };
  };
  const bodies = [
    { key: "core", p: core, color: "var(--accent)", size: 9, label: t("core") },
    { key: "moon", p: moon, color: "var(--ink-muted)", size: 8, label: t("moon") },
    { key: "sun", p: sun, color: "#e8a33d", size: 8, label: t("sun") },
  ].filter((b) => b.p.alt > -1);
  return (
    <div className="flex flex-wrap items-center gap-6">
      <svg viewBox="0 0 260 260" className="w-[220px] shrink-0" role="img" aria-label={t("compass_label")}>
        <circle cx={C} cy={C} r={R} fill="var(--surface)" stroke="var(--line)" />
        {[30, 60].map((a) => <circle key={a} cx={C} cy={C} r={R * (1 - a / 90)} fill="none" stroke="var(--line)" strokeDasharray="2 4" />)}
        {[0, 90, 180, 270].map((az) => {
          const p = pt(az, -12);
          return <text key={az} x={p.x} y={p.y + 4} textAnchor="middle" fontSize={12} fontWeight={600} fill="var(--ink)">{compassPoint(az, locale)}</text>;
        })}
        {bodies.map((b) => {
          const p = pt(b.p.az, b.p.alt);
          return <circle key={b.key} cx={p.x} cy={p.y} r={b.size} fill={b.color} stroke="var(--surface)" strokeWidth={2} />;
        })}
      </svg>
      <dl className="grid min-w-[220px] flex-1 gap-3">
        {[{ k: "core", p: core }, { k: "moon", p: moon }].map(({ k, p }) => (
          <div key={k} className="flex items-baseline justify-between gap-4 border-b border-line pb-2">
            <dt className="flex items-center gap-2 text-[15px] font-medium">
              <span className={clsx("inline-block h-2.5 w-2.5 rounded-full", k === "core" ? "bg-accent" : "bg-ink-muted")} /> {t(k)}
            </dt>
            <dd className="tnum text-[15px]">
              {p.alt < 0 ? <span className="text-ink-muted">{t("below_horizon")}</span> : `${compassPoint(p.az, locale)} ${Math.round(p.az)}° · ${t("altitude")} ${Math.round(p.alt)}°`}
            </dd>
          </div>
        ))}
      </dl>
    </div>
  );
}

export function SkyPlanner() {
  const t = useTranslations("planner");
  const locale = useLocale();
  const { data: me } = useMe();
  const today = new Date();
  const [date, setDate] = useState(`${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}-${String(today.getDate()).padStart(2, "0")}`);
  const [loc, setLoc] = useState<{ lat: number; lng: number; label: string }>(
    me?.latitude != null && me.longitude != null ? { lat: me.latitude, lng: me.longitude, label: me.city ?? "" } : { lat: 40.83, lng: 41.16, label: "Kaçkar Dağları" },
  );
  const [latInput, setLatInput] = useState(String(loc.lat));
  const [lngInput, setLngInput] = useState(String(loc.lng));
  const plan = useMemo(() => planNight(new Date(`${date}T12:00:00`), loc.lat, loc.lng), [date, loc]);
  const [selected, setSelected] = useState<number | null>(null);
  const at = selected ?? plan.coreTransit?.t ?? plan.samples[Math.floor(plan.samples.length / 2)]!.t;

  function locate() {
    navigator.geolocation?.getCurrentPosition((p) => {
      const lat = +p.coords.latitude.toFixed(3), lng = +p.coords.longitude.toFixed(3);
      setLoc({ lat, lng, label: t("my_location") });
      setLatInput(String(lat));
      setLngInput(String(lng));
      setSelected(null);
    });
  }

  const best = plan.bestWindows[0];
  const phaseName = (() => {
    const p = plan.phase;
    const keys = ["new", "waxing_crescent", "first_quarter", "waxing_gibbous", "full", "waning_gibbous", "last_quarter", "waning_crescent"];
    return t(`phase.${keys[Math.round(p * 8) % 8]}`);
  })();

  return (
    <div className="flex flex-col gap-8">
      <div className="flex flex-wrap items-end gap-3">
        <label className="flex flex-col gap-1.5">
          <span className="text-sm font-medium">{t("date")}</span>
          <input type="date" value={date} onChange={(e) => { setDate(e.target.value); setSelected(null); }} className="h-11 rounded-[10px] border border-line bg-surface px-3 text-[15px]" />
        </label>
        <label className="flex w-28 flex-col gap-1.5">
          <span className="text-sm font-medium">{t("lat")}</span>
          <input inputMode="decimal" value={latInput} onChange={(e) => setLatInput(e.target.value)} className="h-11 rounded-[10px] border border-line bg-surface px-3 text-[15px]" />
        </label>
        <label className="flex w-28 flex-col gap-1.5">
          <span className="text-sm font-medium">{t("lng")}</span>
          <input inputMode="decimal" value={lngInput} onChange={(e) => setLngInput(e.target.value)} className="h-11 rounded-[10px] border border-line bg-surface px-3 text-[15px]" />
        </label>
        <Button variant="secondary" onClick={() => {
          const lat = Number(latInput.replace(",", ".")), lng = Number(lngInput.replace(",", "."));
          if (Math.abs(lat) <= 90 && Math.abs(lng) <= 180) { setLoc({ lat, lng, label: "" }); setSelected(null); }
        }}>{t("apply")}</Button>
        <Button variant="ghost" onClick={locate}><LocateFixed className="h-4 w-4" /> {t("use_location")}</Button>
      </div>

      <div className="grid gap-px bg-line sm:grid-cols-3">
        <div className="flex items-center gap-4 bg-surface px-5 py-5">
          <MoonGlyph phase={plan.phase} fraction={plan.illumination} />
          <div>
            <p className="font-semibold">{phaseName}</p>
            <p className="tnum text-sm text-ink-muted">{t("illuminated", { pct: Math.round(plan.illumination * 100) })}</p>
          </div>
        </div>
        <div className="bg-surface px-5 py-5">
          <p className="text-sm text-ink-muted">{t("dark_window")}</p>
          <p className="tnum mt-1 text-[22px] font-semibold">{plan.duskAstro ? `${fmtTime(plan.duskAstro, locale)} – ${fmtTime(plan.dawnAstro, locale)}` : t("no_darkness")}</p>
        </div>
        <div className={clsx("px-5 py-5", best ? "bg-ink text-surface" : "bg-surface")}>
          <p className={clsx("text-sm", best ? "text-surface/70" : "text-ink-muted")}>{t("best_window")}</p>
          <p className="tnum mt-1 text-[22px] font-semibold">{best ? `${fmtTime(best.start, locale)} – ${fmtTime(best.end, locale)}` : t("no_window")}</p>
          {plan.coreTransit && <p className={clsx("tnum mt-1 text-sm", best ? "text-surface/70" : "text-ink-muted")}>{t("core_peak", { time: fmtTime(plan.coreTransit.t, locale), alt: Math.round(plan.coreTransit.alt), dir: compassPoint(plan.coreTransit.az, locale) })}</p>}
        </div>
      </div>
      {!best && <p className="-mt-4 text-sm text-ink-muted">{plan.illumination >= 0.25 && plan.coreTransit ? t("why_moon") : !plan.coreTransit ? t("why_core") : t("why_dark")}</p>}

      <div className="bg-surface px-3 py-4 sm:px-5">
        <div className="mb-2 flex flex-wrap gap-x-5 gap-y-1 px-2 text-sm">
          <span className="flex items-center gap-2"><span className="h-[3px] w-5 bg-accent" /> {t("core")}</span>
          <span className="flex items-center gap-2"><span className="h-[2px] w-5 bg-ink-muted" /> {t("moon")}</span>
          <span className="flex items-center gap-2"><span className="h-[2px] w-5 bg-[#e8a33d]" /> {t("sun")}</span>
          <span className="flex items-center gap-2"><span className="h-3 w-5 bg-accent/20" /> {t("best_window")}</span>
        </div>
        <AltitudeChart plan={plan} selected={at} onSelect={setSelected} />
        <p className="px-2 text-xs text-ink-muted">{t("chart_hint")}</p>
      </div>

      <div className="bg-surface px-5 py-5">
        <p className="tnum mb-4 text-[15px] font-semibold">{t("at_time", { time: fmtTime(at, locale) })}</p>
        <Compass at={at} lat={loc.lat} lng={loc.lng} />
      </div>

      <dl className="grid grid-cols-2 gap-px bg-line sm:grid-cols-4">
        {[["sunset", plan.sunset], ["sunrise", plan.sunrise], ["moonrise", plan.moonrise], ["moonset", plan.moonset],
          ["core_rise", plan.coreRise], ["core_set", plan.coreSet], ["dusk", plan.duskAstro], ["dawn", plan.dawnAstro]].map(([k, v]) => (
          <div key={k as string} className="flex flex-col-reverse bg-surface px-4 py-3">
            <dt className="text-sm text-ink-muted">{t(`event.${k}`)}</dt>
            <dd className="tnum text-lg font-semibold">{fmtTime(v as number | null, locale)}</dd>
          </div>
        ))}
      </dl>
      <p className="text-xs text-ink-muted">{t("accuracy")}</p>
    </div>
  );
}
