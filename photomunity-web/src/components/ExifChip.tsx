import clsx from "clsx";
import type { Exif, ExifSummary } from "@/lib/types";

/** Fotoğrafın çekim bilgisini gösteren küçük hap; uygulamanın imzası. Değer yoksa hiç çizilmez. */
export function ExifChip({ children, className }: { children?: React.ReactNode; className?: string }) {
  if (children == null || children === "") return null;
  return (
    <span
      className={clsx(
        "tnum inline-flex h-7 shrink-0 items-center rounded-pill bg-surface-2 px-2.5 text-caption font-semibold text-ink-muted",
        className,
      )}
    >
      {children}
    </span>
  );
}

export const formatAperture = (a: number | null | undefined) => (a ? `f/${Number(a.toFixed(1))}` : null);
/** API uzun pozları `15"` biçiminde verir; ekranda "15 sn" / "15 s" gösterilir. */
export const formatShutter = (v: string | null | undefined, locale = "tr") =>
  v ? v.replace(/^([\d.,]+)"$/, (_m, n: string) => `${locale === "tr" ? n.replace(".", ",") : n} ${locale === "tr" ? "sn" : "s"}`) : null;
export const formatFocal = (mm: number | null | undefined) => (mm ? `${Math.round(mm)}mm` : null);

/**
 * Kartın altındaki çipler: diyafram, enstantane, ISO; yer kalırsa odak.
 * Boş değerler atlanır, tire yazılmaz.
 */
export function exifChips(exif: ExifSummary | Exif | null | undefined, max = 3, locale = "tr"): string[] {
  if (!exif) return [];
  return [
    formatAperture(exif.aperture),
    formatShutter(exif.shutter_display, locale),
    exif.iso ? `ISO ${exif.iso}` : null,
    formatFocal(exif.focal_length_mm),
  ]
    .filter((v): v is string => !!v)
    .slice(0, max);
}

export function ExifChips({ exif, max = 3, locale, className }: { exif: ExifSummary | Exif | null | undefined; max?: number; locale?: string; className?: string }) {
  const chips = exifChips(exif, max, locale);
  if (!chips.length) return null;
  return (
    <span className={clsx("flex flex-wrap items-center gap-1.5", className)}>
      {chips.map((c) => (
        <ExifChip key={c}>{c}</ExifChip>
      ))}
    </span>
  );
}

/**
 * Fotoğraf detayındaki 4 EXIF kutusu (vizör şeridinin yerine): enstantane, diyafram, ISO, odak.
 * Değeri olmayan kutu çizilmez.
 */
export function ExifGrid({
  exif,
  labels,
  locale,
  className,
}: {
  exif: Exif;
  locale?: string;
  labels: { shutter: string; aperture: string; iso: string; focal: string };
  className?: string;
}) {
  const boxes = [
    exif.shutter_display && { v: formatShutter(exif.shutter_display, locale)!, l: labels.shutter },
    formatAperture(exif.aperture) && { v: formatAperture(exif.aperture)!, l: labels.aperture },
    exif.iso && { v: String(exif.iso), l: labels.iso },
    formatFocal(exif.focal_length_mm) && { v: formatFocal(exif.focal_length_mm)!, l: labels.focal },
  ].filter(Boolean) as { v: string; l: string }[];
  if (!boxes.length) return null;
  return (
    <dl className={clsx("grid grid-cols-2 gap-2", className)}>
      {boxes.map((b) => (
        <div key={b.l} className="flex flex-col-reverse rounded-box bg-surface-2 px-3.5 py-3">
          <dt className="mt-1 text-caption text-ink-muted">{b.l}</dt>
          <dd className="tnum text-[26px] font-bold leading-[28px] tracking-[-0.03em]">{b.v}</dd>
        </div>
      ))}
    </dl>
  );
}
