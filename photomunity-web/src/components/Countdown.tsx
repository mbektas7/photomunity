"use client";

import clsx from "clsx";
import { useTranslations } from "next-intl";
import { useEffect, useState } from "react";

/** Yalnızca zamanla ilgili canlı durumlar için turuncu rozet ("Oylama açık", "3 gün"). */
export function LiveBadge({ children, size = "md", className }: { children: React.ReactNode; size?: "sm" | "md"; className?: string }) {
  return (
    <span
      className={clsx(
        "inline-flex shrink-0 items-center whitespace-nowrap rounded-pill bg-live font-bold text-live-ink",
        size === "sm" ? "h-5 px-[7px] text-[11px]" : "h-7 px-2.5 text-[13px]",
        className,
      )}
    >
      {children}
    </span>
  );
}

type Parts = { days: number; hours: number; minutes: number; seconds: number; ms: number };

function split(target: number, now: number): Parts {
  const ms = Math.max(0, target - now);
  return {
    ms,
    days: Math.floor(ms / 86_400_000),
    hours: Math.floor((ms % 86_400_000) / 3_600_000),
    minutes: Math.floor((ms % 3_600_000) / 60_000),
    seconds: Math.floor((ms % 60_000) / 1000),
  };
}

/** Sunucu ve istemci aynı ilk çıktıyı versin diye saat yalnızca istemcide işler. */
function useNow(intervalMs: number) {
  const [now, setNow] = useState<number | null>(null);
  useEffect(() => {
    setNow(Date.now());
    const id = setInterval(() => setNow(Date.now()), intervalMs);
    return () => clearInterval(id);
  }, [intervalMs]);
  return now;
}

/**
 * Yarışmanın bir sonraki aşamasına kalan süre: gün / saat / dakika; bir günün altında saat / dakika / saniye.
 * Ekran okuyucuya tek cümle okunur.
 */
export function Countdown({
  until,
  label,
  srLabel,
  badge,
  className,
}: {
  until: string;
  /** Kutuların üstündeki kısa açıklama ("Oylamanın kapanmasına"). */
  label?: string;
  /** Ekran okuyucu cümlesinin başı ("Oylamanın kapanmasına"); verilmezse label kullanılır. */
  srLabel?: string;
  /** Aşamayı söyleyen live rozeti ("Oylama açık"). */
  badge?: string;
  className?: string;
}) {
  const t = useTranslations("ui");
  const target = new Date(until).getTime();
  const now = useNow(1000);
  const p = split(target, now ?? target);
  const underDay = now !== null && p.days === 0;
  const boxes = underDay
    ? [
        { v: p.hours, u: t("hours") },
        { v: p.minutes, u: t("minutes") },
        { v: p.seconds, u: t("seconds") },
      ]
    : [
        { v: p.days, u: t("days") },
        { v: p.hours, u: t("hours") },
        { v: p.minutes, u: t("minutes") },
      ];
  const sentence = t("countdown_sr", {
    label: srLabel ?? label ?? "",
    days: p.days,
    hours: p.hours,
    minutes: p.minutes,
  });

  return (
    <div className={clsx("flex flex-col gap-3", className)}>
      {badge && (
        <span>
          <LiveBadge>{badge}</LiveBadge>
        </span>
      )}
      {label && <p className="text-[13.5px] font-semibold text-ink-muted">{label}</p>}
      <p className="sr-only" aria-live="off">
        {now === null ? "" : sentence}
      </p>
      <div className="grid grid-cols-3 gap-2" aria-hidden>
        {boxes.map((b) => (
          <span key={b.u} className="flex flex-col items-center justify-center rounded-box bg-surface-2 px-2 py-3">
            <span className="tnum text-numeral">{now === null ? "--" : String(b.v).padStart(2, "0")}</span>
            <span className="mt-1 text-caption text-ink-muted">{b.u}</span>
          </span>
        ))}
      </div>
    </div>
  );
}

/** "2 gün kaldı" gibi kısa kalan süre; rozetlerin yanında ve hikâye halkasında. */
export function useShortRemaining(until: string | null | undefined) {
  const t = useTranslations("ui");
  const now = useNow(60_000);
  if (!until || now === null) return null;
  const p = split(new Date(until).getTime(), now);
  if (p.ms <= 0) return null;
  if (p.days > 0) return { short: t("days_short", { count: p.days }), left: t("days_left", { count: p.days }) };
  if (p.hours > 0) return { short: t("hours_short", { count: p.hours }), left: t("hours_left", { count: p.hours }) };
  return { short: t("minutes_short", { count: Math.max(1, p.minutes) }), left: t("minutes_left", { count: Math.max(1, p.minutes) }) };
}
