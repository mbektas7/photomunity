"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import clsx from "clsx";
import { LocateFixed, MapPin, Moon, Telescope } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useMemo, useState } from "react";
import { PickMap } from "@/components/PickMap";
import { MoonShape, coords, fmtTime, isoDate, parseIsoDate, useMounted, useSkyLocation } from "@/components/sky";
import { Button, Notice, TextArea, TextField, Toggle, buttonClass } from "@/components/ui";
import { CloudLine, useForecast } from "@/components/weather";
import { Link, useRouter } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import { compassPoint, moonIllumination, planNight } from "@/lib/astro";
import { pct } from "@/lib/format";
import { isNightKind, suggestTime } from "@/lib/shoot";
import { moonPhaseKey, planDay } from "@/lib/sky";
import { PLAN_KINDS, type Plan, type PlanKind } from "@/lib/types";
import { cloudAt } from "@/lib/weather";

const DAY = 86_400_000;
const hhmm = (d: Date) => `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;

/** Gece türlerinde "o gecenin" tarihi: öğleden önceki hedef bir önceki günün gecesidir. */
function nightDate(kind: PlanKind, t: Date) {
  return isNightKind(kind) && t.getHours() < 12 ? new Date(t.getFullYear(), t.getMonth(), t.getDate() - 1) : new Date(t.getFullYear(), t.getMonth(), t.getDate());
}

function combine(kind: PlanKind, date: Date, time: string): Date | null {
  const m = time.match(/^(\d{2}):(\d{2})$/);
  if (!m) return null;
  const h = +m[1]!;
  const add = isNightKind(kind) && h < 12 ? 1 : 0;
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() + add, h, +m[2]!);
}

export type PlanPrefill = { kind?: PlanKind; lat?: number; lng?: number; place?: string; at?: number; title?: string };

export function PlanForm({ plan, prefill }: { plan?: Plan; prefill?: PlanPrefill }) {
  const t = useTranslations("plans");
  const ts = useTranslations("sky");
  const locale = useLocale();
  const router = useRouter();
  const qc = useQueryClient();
  const mounted = useMounted();
  const { loc: skyLoc } = useSkyLocation();

  const initAt = plan ? new Date(plan.target_at) : prefill?.at ? new Date(prefill.at) : null;
  const initKind: PlanKind = (plan?.kind as PlanKind) ?? prefill?.kind ?? "milkyway";
  const [kind, setKind] = useState<PlanKind>(initKind);
  const [title, setTitle] = useState(plan?.title ?? prefill?.title ?? "");
  const [pos, setPos] = useState<{ lat: number; lng: number } | null>(
    plan ? { lat: plan.latitude, lng: plan.longitude } : prefill?.lat != null && prefill.lng != null ? { lat: prefill.lat, lng: prefill.lng } : null,
  );
  const [place, setPlace] = useState(plan?.place_name ?? prefill?.place ?? "");
  const [date, setDate] = useState<Date>(() => (initAt ? nightDate(initKind, initAt) : new Date()));
  const [manualTime, setManualTime] = useState<string | null>(initAt ? hhmm(initAt) : null);
  const [remind, setRemind] = useState(plan?.remind ?? true);
  const [weatherAlert, setWeatherAlert] = useState(plan?.weather_alert ?? false);
  const [notes, setNotes] = useState(plan?.notes ?? "");

  const lat = pos?.lat ?? skyLoc.lat, lng = pos?.lng ?? skyLoc.lng;
  const day = useMemo(() => new Date(date.getFullYear(), date.getMonth(), date.getDate()), [date]);
  const suggestion = useMemo(() => (mounted ? suggestTime(kind, day, lat, lng) : null), [mounted, kind, day, lat, lng]);
  const time = manualTime ?? (suggestion ? hhmm(new Date(suggestion.t)) : "22:00");
  const target = combine(kind, day, time);
  const forecast = useForecast(lat, lng, !!target && target.getTime() - Date.now() < 7 * DAY && target.getTime() > Date.now());
  const cloud = forecast.data && target ? cloudAt(forecast.data, target.getTime()) : null;

  // Ay: hedef anındaki evre ve o günün/gecenin doğuş-batışı
  const moon = useMemo(() => {
    if (!mounted || !target) return null;
    const ill = moonIllumination(target.getTime());
    if (isNightKind(kind)) {
      const n = planNight(day, lat, lng);
      const sets = n.moonset && (!n.moonrise || n.moonset < n.moonrise);
      return { ...ill, note: sets ? ts("tonight.moon_sets", { time: fmtTime(n.moonset, locale) }) : n.moonrise ? ts("tonight.moon_rises", { time: fmtTime(n.moonrise, locale) }) : null };
    }
    const p = planDay(day, lat, lng);
    return { ...ill, note: p.moonrise ? ts("tonight.moon_rises", { time: fmtTime(p.moonrise.t, locale) }) : null };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mounted, target?.getTime(), kind, day, lat, lng, locale]);

  const save = useMutation({
    mutationFn: () => {
      const body = {
        kind, title: title.trim() || null, latitude: lat, longitude: lng, place_name: place.trim() || null,
        target_at: target!.toISOString(), remind, weather_alert: weatherAlert, notes: notes.trim() || null,
      };
      return plan ? api<Plan>(`me/plans/${plan.id}`, { method: "PATCH", body }) : api<Plan>("me/plans", { method: "POST", body });
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["plans"] });
      router.push("/plans");
    },
  });
  const remove = useMutation({
    mutationFn: () => api(`me/plans/${plan!.id}`, { method: "DELETE" }),
    onSuccess: () => {
      qc.removeQueries({ queryKey: ["plans", "one", plan!.id] });
      qc.invalidateQueries({ queryKey: ["plans"] });
      router.push("/plans");
    },
  });

  function locate() {
    navigator.geolocation?.getCurrentPosition((p) => setPos({ lat: +p.coords.latitude.toFixed(4), lng: +p.coords.longitude.toFixed(4) }));
  }

  const past = target ? target.getTime() <= Date.now() : true;
  const noteText = suggestion?.note
    ? suggestion.note === "core_peak" && suggestion.alt != null && suggestion.az != null
      ? t("suggest.core_peak", { alt: Math.round(suggestion.alt), dir: compassPoint(suggestion.az, locale) })
      : t(`suggest.${suggestion.note}`)
    : null;

  return (
    <form
      className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_380px]"
      onSubmit={(e) => {
        e.preventDefault();
        if (target && !past) save.mutate();
      }}
    >
      <div className="flex flex-col gap-5">
        <fieldset>
          <legend className="mb-2 text-sm font-medium">{t("kind_label")}</legend>
          <div className="flex flex-wrap gap-2" role="radiogroup">
            {PLAN_KINDS.map((k) => (
              <button
                key={k}
                type="button"
                role="radio"
                aria-checked={kind === k}
                onClick={() => setKind(k)}
                className={clsx(
                  "h-10 rounded-full border px-4 text-[14px] transition-colors",
                  kind === k ? "border-ink bg-ink font-bold text-bg" : "border-line bg-surface font-medium hover:bg-surface-2",
                )}
              >
                {t(`kind.${k}`)}
              </button>
            ))}
          </div>
        </fieldset>

        <TextField label={t("title_label")} name="plan-title" placeholder={t(`kind.${kind}`)} value={title} maxLength={120} onChange={(e) => setTitle(e.target.value)} />

        <fieldset className="flex flex-col gap-3">
          <legend className="mb-2 text-sm font-medium">{t("place_label")}</legend>
          <div className="flex flex-wrap items-center gap-2 text-sm">
            <span className="tnum inline-flex items-center gap-1.5 text-ink-muted"><MapPin className="h-4 w-4" aria-hidden /> {coords(lat, lng)}</span>
            <span className="ml-auto flex flex-wrap gap-1">
              <Button type="button" variant="ghost" className="!h-9 !min-h-9 px-3 text-[14px]" onClick={() => setPos({ lat: skyLoc.lat, lng: skyLoc.lng })}>
                <Telescope className="h-4 w-4" aria-hidden /> {t("use_sky_place")}
              </Button>
              <Button type="button" variant="ghost" className="!h-9 !min-h-9 px-3 text-[14px]" onClick={locate}>
                <LocateFixed className="h-4 w-4" aria-hidden /> {ts("planner.use_location")}
              </Button>
            </span>
          </div>
          {mounted && <PickMap lat={lat} lng={lng} onPick={(a, b) => setPos({ lat: a, lng: b })} label={t("map_label")} />}
          <p className="-mt-1 text-xs text-ink-muted">{t("map_hint")}</p>
          <TextField label={t("place_name")} name="place" placeholder={t("place_placeholder")} value={place} maxLength={200} onChange={(e) => setPlace(e.target.value)} />
        </fieldset>
      </div>

      <div className="flex flex-col gap-5">
        <div className="grid grid-cols-2 gap-3">
          <div className="flex flex-col gap-1.5">
            <label htmlFor="plan-date" className="text-sm font-medium">{isNightKind(kind) ? t("night_of") : t("date")}</label>
            <input
              id="plan-date"
              type="date"
              value={isoDate(day)}
              min={isoDate(new Date(Date.now() - DAY))}
              onChange={(e) => {
                const d = parseIsoDate(e.target.value);
                if (d) setDate(d);
              }}
              className="h-11 rounded-box border border-ring-idle bg-surface px-3 text-[15px] outline-none focus:border-accent"
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <label htmlFor="plan-time" className="text-sm font-medium">{t("time")}</label>
            <input
              id="plan-time"
              type="time"
              value={time}
              onChange={(e) => setManualTime(e.target.value || null)}
              className="tnum h-11 rounded-box border border-ring-idle bg-surface px-3 text-[15px] outline-none focus:border-accent"
            />
          </div>
        </div>
        {target && (
          <p className="-mt-2 text-sm text-ink-muted">
            {new Intl.DateTimeFormat(locale, { weekday: "long", day: "numeric", month: "long", hour: "2-digit", minute: "2-digit" }).format(target)}
          </p>
        )}

        <div className="flex flex-col gap-2 rounded-box bg-surface-2 p-4 text-[14.5px]">
          {noteText && suggestion && (
            <p className="flex flex-wrap items-center justify-between gap-2">
              <span>{t("suggested", { time: fmtTime(suggestion.t, locale) })} · <span className="text-ink-muted">{noteText}</span></span>
              {manualTime && manualTime !== hhmm(new Date(suggestion.t)) && (
                <button type="button" className="font-semibold text-accent-text hover:underline" onClick={() => setManualTime(null)}>
                  {t("use_suggestion")}
                </button>
              )}
            </p>
          )}
          {!suggestion && mounted && kind !== "other" && <p className="text-ink-muted">{t("suggest.none")}</p>}
          {moon && (
            <p className="flex items-center gap-2">
              <MoonShape phase={moon.phase} fraction={moon.fraction} size={20} />
              <span className="tnum">
                {ts(`phase.${moonPhaseKey(moon.phase)}`)} {pct(moon.fraction * 100, locale)}
                {moon.note ? ` · ${moon.note}` : ""}
              </span>
            </p>
          )}
          {cloud != null && <p className="text-ink-muted"><CloudLine value={cloud} /></p>}
          {kind === "milkyway" && moon && moon.fraction >= 0.35 && (
            <p className="flex items-center gap-2 text-ink-muted"><Moon className="h-4 w-4" aria-hidden /> {t("bright_moon")}</p>
          )}
        </div>

        <div className="flex flex-col gap-4 rounded-box bg-surface p-4">
          <Toggle checked={remind} onChange={setRemind} label={t("remind")} hint={t("remind_hint")} />
          <Toggle checked={weatherAlert} onChange={setWeatherAlert} label={t("weather_alert")} hint={t("weather_alert_hint", { pct: 40 })} />
        </div>

        <TextArea label={t("notes")} name="notes" rows={3} value={notes} maxLength={1000} onChange={(e) => setNotes(e.target.value)} />

        {past && target && <Notice tone="error">{t("past_error")}</Notice>}
        {save.error && <Notice tone="error">{save.error instanceof ApiError && save.error.message ? save.error.message : t("save_error")}</Notice>}
        <Button type="submit" variant="large" busy={save.isPending} disabled={!target || past}>
          {plan ? t("save_changes") : t("save")}
        </Button>
        {plan && (
          <Button type="button" variant="danger" className="self-start" busy={remove.isPending} onClick={() => window.confirm(t("delete_confirm")) && remove.mutate()}>
            {t("delete")}
          </Button>
        )}
      </div>
    </form>
  );
}

/** Plan listesinde tek satır. */
export function PlanRow({ plan, onDelete, busy }: { plan: Plan; onDelete?: () => void; busy?: boolean }) {
  const t = useTranslations("plans");
  const locale = useLocale();
  const at = new Date(plan.target_at);
  return (
    <li className="flex flex-wrap items-center gap-x-4 gap-y-2 rounded-card bg-surface px-5 py-4">
      <div className="min-w-0 flex-1">
        {(plan.title || plan.place_name) && <p className="text-xs font-semibold uppercase tracking-[0.06em] text-ink-muted">{t(`kind.${plan.kind}`)}</p>}
        <p className="truncate text-[17px] font-semibold">{plan.title || plan.place_name || t(`kind.${plan.kind}`)}</p>
        <p className="tnum text-sm text-ink-muted">
          {new Intl.DateTimeFormat(locale, { weekday: "short", day: "numeric", month: "short", year: at.getFullYear() !== new Date().getFullYear() ? "numeric" : undefined, hour: "2-digit", minute: "2-digit" }).format(at)}
          {plan.place_name && plan.title ? ` · ${plan.place_name}` : ""}
        </p>
        <p className="mt-1 flex flex-wrap gap-x-3 text-[13px] text-ink-muted">
          {plan.last_cloud_cover != null && <CloudLine value={plan.last_cloud_cover} />}
          {plan.remind && <span>{t("reminder_on")}</span>}
          {plan.weather_alert && <span>{t("weather_on")}</span>}
        </p>
      </div>
      <div className="flex gap-1">
        {plan.status === "upcoming" && (
          <Link href={`/plans/${plan.id}`} className={buttonClass("secondary")}>{t("edit")}</Link>
        )}
        {onDelete && (
          <Button variant="danger" busy={busy} onClick={onDelete} aria-label={t("delete_named", { name: plan.title || t(`kind.${plan.kind}`) })}>
            {t("delete")}
          </Button>
        )}
      </div>
    </li>
  );
}
