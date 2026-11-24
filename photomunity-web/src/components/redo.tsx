"use client";

import { useQuery } from "@tanstack/react-query";
import clsx from "clsx";
import { CalendarPlus, Repeat, Telescope } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useMemo, useState } from "react";
import { isoDate, useMounted } from "@/components/sky";
import { buttonClass } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { compassPoint } from "@/lib/astro";
import { captureSky, findRedoDates, naiveToEpoch, offsetFromLongitude } from "@/lib/shoot";
import type { PhotoDetail, PlanKind } from "@/lib/types";
import { fetchUtcOffset } from "@/lib/weather";

/**
 * "Bu kareyi tekrar çek": konumu ve çekim zamanı olan karede, çekim anındaki Güneş / galaktik çekirdek
 * konumunu hesaplar ve önümüzdeki 12 ayda aynı görünümün yakalanabileceği günleri önerir.
 * Konum yoksa (sahibi eklemediyse) kart hiç çıkmaz.
 */
export function RedoCard({ photo }: { photo: PhotoDetail }) {
  const loc = photo.location;
  const taken = photo.exif?.taken_at;
  if (!loc || !taken) return null;
  return <Redo lat={loc.latitude} lng={loc.longitude} place={loc.name ?? null} taken={taken} title={photo.title} />;
}

function Redo({ lat, lng, place, taken, title }: { lat: number; lng: number; place: string | null; taken: string; title: string | null }) {
  const t = useTranslations("redo");
  const locale = useLocale();
  const mounted = useMounted();
  // EXIF saati konumun yerel saatidir; UTC farkı Open-Meteo'dan (timezone=auto), olmazsa boylamdan tahmin
  const offset = useQuery({
    queryKey: ["utc-offset", lat.toFixed(2), lng.toFixed(2)],
    queryFn: () => fetchUtcOffset(lat, lng),
    staleTime: Infinity,
    retry: 1,
  });
  const off = offset.data ?? (offset.isError ? offsetFromLongitude(lng) : null);

  const result = useMemo(() => {
    if (!mounted || off == null) return null;
    const t0 = naiveToEpoch(taken, off);
    if (t0 == null) return null;
    const cap = captureSky(t0, lat, lng);
    return { cap, matches: cap.mode === "none" ? [] : findRedoDates(cap, lat, lng) };
  }, [mounted, off, taken, lat, lng]);
  const [pick, setPick] = useState(0);

  if (!result) {
    return (
      <section aria-busy className="rounded-box bg-surface-2 p-4">
        <p className="text-xs font-bold uppercase tracking-[0.06em] text-ink-muted">{t("title")}</p>
        <p className="mt-2 text-sm text-ink-muted">{t("computing")}</p>
      </section>
    );
  }
  const { cap, matches } = result;
  const target = cap.mode === "core" ? cap.core : cap.sun;
  const kind: PlanKind = cap.mode === "core" ? "milkyway" : cap.sun.alt < -4 ? "blue" : cap.sun.alt < 6 ? "golden" : "other";
  const chosen = matches[Math.min(pick, matches.length - 1)];
  const df = new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", year: "numeric" });
  const tf = new Intl.DateTimeFormat(locale, { hour: "2-digit", minute: "2-digit", hourCycle: "h23" });

  const planHref = chosen
    ? `/plans/new?${new URLSearchParams({ kind, lat: String(lat), lng: String(lng), at: String(chosen.t), ...(place ? { place } : {}), ...(title ? { title } : {}) })}`
    : null;
  const skyHref = `/sky/planner?${new URLSearchParams({ date: isoDate(new Date(chosen?.t ?? Date.now())), lat: String(lat), lng: String(lng) })}`;

  return (
    <section aria-labelledby="redo-title" className="rounded-box bg-surface-2 p-4">
      <h2 id="redo-title" className="flex items-center gap-2 text-xs font-bold uppercase tracking-[0.06em] text-ink-muted">
        <Repeat className="h-4 w-4" aria-hidden /> {t("title")}
      </h2>
      {cap.mode === "none" ? (
        <p className="mt-2 text-[14.5px]">{t("none")}</p>
      ) : (
        <>
          <p className="mt-2 text-[14.5px] leading-snug">
            {t(cap.mode === "core" ? "core_was" : "sun_was", {
              az: Math.round(target.az),
              dir: compassPoint(target.az, locale) ?? "",
              alt: Math.round(target.alt),
            })}{" "}
            {matches.length > 0 ? t(cap.mode === "core" ? "core_dates" : "sun_dates") : t("no_dates")}
          </p>
          {matches.length > 0 && (
            <div role="radiogroup" aria-label={t("dates_label")} className="mt-3 grid grid-cols-3 gap-1.5">
              {matches.map((m, i) => (
                <button
                  key={m.t}
                  type="button"
                  role="radio"
                  aria-checked={i === pick}
                  onClick={() => setPick(i)}
                  className={clsx(
                    "tnum rounded-[12px] border px-2 py-2 text-left text-[13px] transition-colors",
                    i === pick ? "border-accent bg-accent-tint" : "border-line bg-surface hover:bg-bg",
                  )}
                >
                  <span className="block font-bold">{df.format(new Date(m.t))}</span>
                  <span className="block">{tf.format(new Date(m.t))}</span>
                  <span className="block text-ink-muted">{t("moon", { pct: Math.round(m.moon * 100) })}</span>
                </button>
              ))}
            </div>
          )}
        </>
      )}
      <div className="mt-3 flex flex-wrap gap-2">
        {planHref && (
          <Link href={planHref} className={buttonClass("primary", "!h-10 !min-h-10 px-4 text-[14px]")}>
            <CalendarPlus className="h-4 w-4" aria-hidden /> {t("create_plan")}
          </Link>
        )}
        <Link href={skyHref} className={buttonClass("secondary", "!h-10 !min-h-10 bg-surface px-4 text-[14px]")}>
          <Telescope className="h-4 w-4" aria-hidden /> {t("open_planner")}
        </Link>
      </div>
      <p className="mt-2 text-xs text-ink-muted">{t("tz_note")}</p>
    </section>
  );
}
