"use client";

import clsx from "clsx";
import { useLocale, useTranslations } from "next-intl";
import { useState } from "react";
import {
  ND_FILTERS, SENSORS, SHUTTER_SPEEDS, type SensorId, cropFactor, depthOfField, formatDistance, formatShutter, ndSeconds,
  npfSeconds, pixelPitch, rule500Seconds,
} from "@/lib/calculators";

const SENSOR_IDS = Object.keys(SENSORS) as SensorId[];
const APERTURES = [1.2, 1.4, 1.8, 2, 2.8, 4, 5.6, 8, 11, 16, 22];

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="flex flex-col gap-1.5">
      <span className="text-sm font-medium">{label}</span>
      {children}
    </label>
  );
}

const inputClass = "h-11 rounded-[10px] border border-line bg-mat px-3 text-[15px] outline-none focus:border-ink";

function SensorSelect({ value, onChange }: { value: SensorId; onChange: (s: SensorId) => void }) {
  const t = useTranslations("tools");
  return (
    <select value={value} onChange={(e) => onChange(e.target.value as SensorId)} className={inputClass}>
      {SENSOR_IDS.map((s) => <option key={s} value={s}>{t(`sensor.${s}`)} (×{cropFactor(s).toFixed(2)})</option>)}
    </select>
  );
}

function ApertureSelect({ value, onChange, from = 0 }: { value: number; onChange: (n: number) => void; from?: number }) {
  return (
    <select value={value} onChange={(e) => onChange(Number(e.target.value))} className={inputClass}>
      {APERTURES.slice(from).map((a) => <option key={a} value={a}>f/{a}</option>)}
    </select>
  );
}

/** Sonuç kutuları: vizör şeridiyle aynı görsel dil (siyah bant, büyük rakam). */
function Readout({ items }: { items: { value: string; label: string; strong?: boolean }[] }) {
  return (
    <dl className="mt-6 grid grid-cols-2 gap-px bg-black sm:grid-cols-3">
      {items.map((r) => (
        <div key={r.label} className="flex flex-col-reverse bg-black px-4 py-4 text-[#f2f2ee]">
          <dt className="mt-1 text-[12.5px] text-[#8d8d88]">{r.label}</dt>
          <dd className={clsx("tnum font-semibold leading-none tracking-tight", r.strong ? "text-[30px]" : "text-[22px]")}>{r.value}</dd>
        </div>
      ))}
    </dl>
  );
}

export function NpfCalculator() {
  const t = useTranslations("tools");
  const locale = useLocale();
  const [sensor, setSensor] = useState<SensorId>("ff");
  const [mp, setMp] = useState(24);
  const [focal, setFocal] = useState(14);
  const [aperture, setAperture] = useState(1.8);
  const npf = npfSeconds(sensor, mp, focal, aperture);
  const core = npfSeconds(sensor, mp, focal, aperture, -29.0078);
  const r500 = rule500Seconds(sensor, focal);
  return (
    <section id="npf" className="scroll-mt-24 bg-mat px-5 py-6 sm:px-6">
      <h2 className="text-xl font-semibold tracking-[-0.02em]">{t("npf_title")}</h2>
      <p className="mt-1 max-w-[62ch] text-[15px] text-muted">{t("npf_lead")}</p>
      <div className="mt-5 grid gap-4 sm:grid-cols-4">
        <Field label={t("sensor_label")}><SensorSelect value={sensor} onChange={setSensor} /></Field>
        <Field label={t("megapixels")}><input type="number" min={6} max={150} value={mp} onChange={(e) => setMp(Number(e.target.value) || 24)} className={inputClass} /></Field>
        <Field label={t("focal")}><input type="number" min={8} max={200} value={focal} onChange={(e) => setFocal(Number(e.target.value) || 14)} className={inputClass} /></Field>
        <Field label={t("aperture")}><ApertureSelect value={aperture} onChange={setAperture} /></Field>
      </div>
      <Readout items={[
        { value: formatShutter(npf, locale), label: t("npf_result"), strong: true },
        { value: formatShutter(core, locale), label: t("npf_core") },
        { value: formatShutter(r500, locale), label: t("rule500") },
      ]} />
      <p className="mt-3 text-sm text-muted">{t("npf_note", { pitch: pixelPitch(sensor, mp).toFixed(1) })}</p>
    </section>
  );
}

export function DofCalculator() {
  const t = useTranslations("tools");
  const locale = useLocale();
  const [sensor, setSensor] = useState<SensorId>("ff");
  const [focal, setFocal] = useState(24);
  const [aperture, setAperture] = useState(8);
  const [distance, setDistance] = useState(3);
  const r = depthOfField(sensor, focal, aperture, distance);
  const total = r.far === null ? null : r.far - r.near;
  return (
    <section id="dof" className="scroll-mt-24 bg-mat px-5 py-6 sm:px-6">
      <h2 className="text-xl font-semibold tracking-[-0.02em]">{t("dof_title")}</h2>
      <p className="mt-1 max-w-[62ch] text-[15px] text-muted">{t("dof_lead")}</p>
      <div className="mt-5 grid gap-4 sm:grid-cols-4">
        <Field label={t("sensor_label")}><SensorSelect value={sensor} onChange={setSensor} /></Field>
        <Field label={t("focal")}><input type="number" min={8} max={800} value={focal} onChange={(e) => setFocal(Number(e.target.value) || 24)} className={inputClass} /></Field>
        <Field label={t("aperture")}><ApertureSelect value={aperture} onChange={setAperture} /></Field>
        <Field label={t("distance")}><input type="number" min={0.2} max={1000} step={0.1} value={distance} onChange={(e) => setDistance(Number(e.target.value) || 1)} className={inputClass} /></Field>
      </div>
      <Readout items={[
        { value: formatDistance(r.hyperfocal, locale), label: t("hyperfocal"), strong: true },
        { value: formatDistance(r.near, locale), label: t("near") },
        { value: formatDistance(r.far, locale), label: t("far") },
      ]} />
      <p className="mt-3 text-sm text-muted">
        {total === null ? t("dof_infinite", { near: formatDistance(r.near, locale) }) : t("dof_total", { total: formatDistance(total, locale) })}{" "}
        {t("dof_hyperfocal_tip", { h: formatDistance(r.hyperfocal, locale), half: formatDistance(r.hyperfocal / 2, locale) })}
      </p>
    </section>
  );
}

export function NdCalculator() {
  const t = useTranslations("tools");
  const locale = useLocale();
  const [base, setBase] = useState(1 / 125);
  const [stops, setStops] = useState(10);
  const out = ndSeconds(base, stops);
  return (
    <section id="nd" className="scroll-mt-24 bg-mat px-5 py-6 sm:px-6">
      <h2 className="text-xl font-semibold tracking-[-0.02em]">{t("nd_title")}</h2>
      <p className="mt-1 max-w-[62ch] text-[15px] text-muted">{t("nd_lead")}</p>
      <div className="mt-5 grid gap-4 sm:grid-cols-2">
        <Field label={t("nd_base")}>
          <select value={base} onChange={(e) => setBase(Number(e.target.value))} className={inputClass}>
            {SHUTTER_SPEEDS.map((s) => <option key={s} value={s}>{formatShutter(s, locale)}</option>)}
          </select>
        </Field>
        <Field label={t("nd_filter")}>
          <div className="flex flex-wrap gap-2">
            {ND_FILTERS.map((f) => (
              <button key={f.label} type="button" onClick={() => setStops(f.stops)} aria-pressed={stops === f.stops}
                className={clsx("h-11 rounded-full border px-4 text-sm font-medium", stops === f.stops ? "border-ink bg-ink text-mat" : "border-line hover:border-ink")}>
                {f.label} · {t("stops", { n: f.stops })}
              </button>
            ))}
          </div>
        </Field>
      </div>
      <Readout items={[{ value: formatShutter(out, locale), label: t("nd_result"), strong: true }]} />
      {out > 30 && <p className="mt-3 text-sm text-muted">{t("nd_bulb")}</p>}
    </section>
  );
}

export function CalculatorFor({ id }: { id: string | null }) {
  if (id === "npf") return <NpfCalculator />;
  if (id === "dof") return <DofCalculator />;
  if (id === "nd") return <NdCalculator />;
  return null;
}
