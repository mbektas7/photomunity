"use client";

import clsx from "clsx";
import { Check, Maximize2, Minimize2, X } from "lucide-react";
import { useTranslations } from "next-intl";
import { useEffect, useRef, useState } from "react";
import { formatAperture, formatFocal, formatShutter } from "@/components/ExifChip";
import { cameraName } from "@/lib/format";
import type { ContestStatus, Entry, Exif, ImageVariant } from "@/lib/types";

/** Derece renkleri: altın, gümüş, bronz (tasarım onaylı; temaya göre değişmez). */
export const MEDAL: Record<number, string> = { 1: "#e2b33c", 2: "#b9c0cc", 3: "#c98b5a" };

/** Klavye kısayolları yazı yazarken (not alanı, arama kutusu) çalışmamalı. */
export function isTypingTarget(t: EventTarget | null) {
  if (!(t instanceof HTMLElement)) return false;
  return t instanceof HTMLInputElement || t instanceof HTMLTextAreaElement || t instanceof HTMLSelectElement || t.isContentEditable;
}

export const largestImage = (e: Entry): ImageVariant | undefined => e.images.full ?? e.images.feed ?? e.images.thumb;
export const smallImage = (e: Entry): ImageVariant | undefined => e.images.thumb ?? e.images.feed ?? e.images.full;

/** Sıra rozeti: ilk üç derece rengiyle, sonrakiler sakin zeminde. */
export function RankBadge({ rank, size = 30, tone = "light" }: { rank: number | null; size?: number; tone?: "light" | "dark" }) {
  const medal = rank ? MEDAL[rank] : undefined;
  return (
    <span
      style={{ width: size, height: size, fontSize: Math.round(size * 0.44), ...(medal ? { background: medal, color: "#14161b" } : {}) }}
      className={clsx(
        "tnum inline-flex shrink-0 items-center justify-center rounded-full font-bold",
        !medal && (tone === "dark" ? "bg-white/10 text-white" : "bg-surface-2 text-ink"),
      )}
    >
      {rank ?? "–"}
    </span>
  );
}

/** Taslak → Başvuru → Değerlendirme → Sonuç adımları (organizatör ve jüri üst çubuğu). */
export function StageStepper({ status, tone = "light", className }: { status: ContestStatus; tone?: "light" | "dark"; className?: string }) {
  const t = useTranslations("contests");
  const current = status === "draft" ? 0 : status === "open" ? 1 : status === "finished" ? 3 : 2;
  const steps = [t("stage.draft"), t("stage.entries"), t("stage.judging"), t("stage.results")];
  const dark = tone === "dark";
  return (
    <ol className={clsx("flex items-center gap-2.5", className)} aria-label={t("stage.label")}>
      {steps.map((label, i) => {
        const done = i < current || (i === 3 && current === 3);
        const active = i === current && !done;
        return (
          <li key={label} className="flex items-center gap-2.5" aria-current={active ? "step" : undefined}>
            {i > 0 && <span aria-hidden className={clsx("h-0.5 w-6 xl:w-8", i <= current ? "bg-accent" : dark ? "bg-white/20" : "bg-line")} />}
            <span className={clsx("flex items-center gap-2 whitespace-nowrap text-[13.5px]", active ? "font-bold" : "font-medium", !done && !active && "opacity-60")}>
              <span
                aria-hidden
                className={clsx(
                  "flex h-[22px] w-[22px] items-center justify-center rounded-full border-2",
                  done ? "border-accent bg-accent text-accent-ink" : active ? "border-accent" : dark ? "border-white/25" : "border-ring-idle",
                )}
              >
                {done && <Check className="h-3 w-3" strokeWidth={3.2} />}
              </span>
              <span className={clsx(!active && "max-sm:sr-only")}>{label}</span>
            </span>
          </li>
        );
      })}
    </ol>
  );
}

/**
 * Fotoğraf kendi oranında, kırpılmadan (object-contain); boş kalan alanı aynı karenin bulanık kopyası doldurur.
 */
export function BlurredPhoto({
  img,
  alt = "",
  className,
  imgClassName,
  blur = 40,
  dim = 0.45,
  children,
  eager,
}: {
  img: ImageVariant | undefined;
  alt?: string;
  className?: string;
  imgClassName?: string;
  blur?: number;
  dim?: number;
  children?: React.ReactNode;
  eager?: boolean;
}) {
  return (
    <div className={clsx("relative overflow-hidden bg-black", className)}>
      {img && (
        <>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={img.url}
            alt=""
            aria-hidden
            className="absolute inset-0 h-full w-full scale-125 object-cover"
            style={{ filter: `blur(${blur}px) brightness(${dim})` }}
          />
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={img.url}
            alt={alt}
            width={img.width}
            height={img.height}
            loading={eager ? "eager" : "lazy"}
            className={clsx("fade-in relative block h-full w-full object-contain", imgClassName)}
          />
        </>
      )}
      {children}
    </div>
  );
}

/** Jüri ve odak görünümündeki EXIF kutuları: kamera, lens, pozlama, ISO. Boş değerler atlanır. */
export function exifTiles(exif: Exif | null | undefined, locale: string, labels: { camera: string; lens: string; exposure: string; iso: string }) {
  if (!exif) return [];
  const exposure = [formatShutter(exif.shutter_display, locale), formatAperture(exif.aperture)].filter(Boolean).join(" · ");
  return [
    { label: labels.camera, value: cameraName(exif.camera_make, exif.camera_model) },
    { label: labels.lens, value: exif.lens ?? formatFocal(exif.focal_length_mm) },
    { label: labels.exposure, value: exposure || null },
    { label: labels.iso, value: exif.iso ? String(exif.iso) : null },
  ].filter((x): x is { label: string; value: string } => !!x.value);
}

/** Tek satırlık çekim özeti: "Sony A7 IV · 14mm · 20 sn f/2 ISO 3200". */
export function exifLine(exif: Exif | null | undefined, locale: string) {
  if (!exif) return "";
  const settings = [formatShutter(exif.shutter_display, locale), formatAperture(exif.aperture), exif.iso ? `ISO ${exif.iso}` : null].filter(Boolean).join(" ");
  return [cameraName(exif.camera_make, exif.camera_model), formatFocal(exif.focal_length_mm), settings].filter(Boolean).join(" · ");
}

/**
 * "1:1 incele": en büyük varyantı gerçek boyutunda açar; tıklayınca sığdır / 1:1 arasında geçer, kaydırarak gezilir.
 */
export function ZoomOverlay({ img, alt, onClose }: { img: ImageVariant; alt: string; onClose: () => void }) {
  const t = useTranslations("contests");
  const dialog = useRef<HTMLDialogElement>(null);
  const [actual, setActual] = useState(true);
  useEffect(() => {
    if (!dialog.current?.open) dialog.current?.showModal();
  }, []);
  return (
    <dialog
      ref={dialog}
      onClose={onClose}
      aria-label={t("zoom_title")}
      className="fixed inset-0 m-0 h-dvh max-h-none w-screen max-w-none bg-black p-0 text-white backdrop:bg-black"
    >
      <div className={clsx("h-full w-full overflow-auto", !actual && "flex items-center justify-center")}>
        <button
          type="button"
          onClick={() => setActual((v) => !v)}
          aria-label={actual ? t("zoom_fit") : t("zoom_actual")}
          className={clsx("block", actual ? "cursor-zoom-out" : "h-full w-full cursor-zoom-in")}
        >
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={img.url}
            alt={alt}
            width={img.width}
            height={img.height}
            className={clsx("block max-w-none", !actual && "h-full w-full object-contain")}
            style={actual ? { width: img.width, height: img.height } : undefined}
          />
        </button>
      </div>
      <div className="pointer-events-none fixed inset-x-0 top-0 flex items-center justify-end gap-2 p-4">
        <button
          type="button"
          onClick={() => setActual((v) => !v)}
          className="pointer-events-auto inline-flex h-11 items-center gap-2 rounded-pill bg-black/60 px-4 text-[14px] font-semibold backdrop-blur hover:bg-black/80"
        >
          {actual ? <Minimize2 className="h-4 w-4" aria-hidden /> : <Maximize2 className="h-4 w-4" aria-hidden />}
          {actual ? t("zoom_fit") : t("zoom_actual")}
        </button>
        <button
          type="button"
          onClick={() => dialog.current?.close()}
          aria-label={t("close")}
          className="pointer-events-auto inline-flex h-11 w-11 items-center justify-center rounded-full bg-black/60 backdrop-blur hover:bg-black/80"
        >
          <X className="h-5 w-5" aria-hidden />
        </button>
      </div>
      <p className="pointer-events-none fixed inset-x-0 bottom-0 p-3 text-center text-caption text-white/70">
        <span className="tnum">{img.width} × {img.height}</span>
      </p>
    </dialog>
  );
}

/** Filtre sekmeleri (Tümü 84 / Puanlanmamış 19 ...). */
export function FilterTabs<K extends string>({
  value,
  onChange,
  items,
  label,
}: {
  value: K;
  onChange: (k: K) => void;
  items: { key: K; label: string; count?: number }[];
  label: string;
}) {
  return (
    <div role="tablist" aria-label={label} className="flex flex-wrap gap-2">
      {items.map((it) => (
        <button
          key={it.key}
          type="button"
          role="tab"
          aria-selected={value === it.key}
          onClick={() => onChange(it.key)}
          className={clsx(
            "inline-flex h-9 items-center gap-1.5 rounded-pill border px-3.5 text-[13.5px] transition-colors",
            value === it.key ? "border-ink bg-ink font-bold text-bg" : "border-line bg-surface font-medium text-ink hover:bg-surface-2",
          )}
        >
          {it.label}
          {it.count !== undefined && <span className="tnum">{it.count}</span>}
        </button>
      ))}
    </div>
  );
}

/** "Başvuru #N": API'nin verdiği kalıcı numara (katılım sırası); jüri, seçmen ve organizatör aynı numarayı görür. */
export function entryNumbers(adminList: Entry[] | undefined) {
  return new Map((adminList ?? []).map((e, i) => [e.id, e.number ?? i + 1] as const));
}

/** "2 gün önce" / "3 gün sonra" gibi göreli zaman. */
export function relTime(iso: string, locale: string, now = Date.now()) {
  const diff = new Date(iso).getTime() - now;
  const abs = Math.abs(diff);
  const rtf = new Intl.RelativeTimeFormat(locale, { numeric: "always" });
  if (abs >= 86_400_000) return rtf.format(Math.round(diff / 86_400_000), "day");
  if (abs >= 3_600_000) return rtf.format(Math.round(diff / 3_600_000), "hour");
  return rtf.format(Math.round(diff / 60_000), "minute");
}
