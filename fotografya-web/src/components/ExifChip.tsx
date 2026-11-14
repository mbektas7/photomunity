import clsx from "clsx";
import type { Exif } from "@/lib/types";

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
export const formatFocal = (mm: number | null | undefined) => (mm ? `${Math.round(mm)}mm` : null);

/**
 * Kartın altındaki çipler: diyafram, enstantane, ISO; yer kalırsa odak.
 * Boş değerler atlanır, tire yazılmaz.
 */
export function exifChips(exif: Exif | null | undefined, max = 3): string[] {
  if (!exif) return [];
  return [
    formatAperture(exif.aperture),
    exif.shutter_display,
    exif.iso ? `ISO ${exif.iso}` : null,
    formatFocal(exif.focal_length_mm),
  ]
    .filter((v): v is string => !!v)
    .slice(0, max);
}

export function ExifChips({ exif, max = 3, className }: { exif: Exif | null | undefined; max?: number; className?: string }) {
  const chips = exifChips(exif, max);
  if (!chips.length) return null;
  return (
    <span className={clsx("flex flex-wrap items-center gap-1.5", className)}>
      {chips.map((c) => (
        <ExifChip key={c}>{c}</ExifChip>
      ))}
    </span>
  );
}
