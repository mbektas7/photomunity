"use client";

import { useLocale, useTranslations } from "next-intl";
import { cameraName, formatDate } from "@/lib/format";
import type { Exif } from "@/lib/types";

/**
 * EXIF, makinenin vizöründeki alt bilgi şeridi gibi okunur: enstantane, diyafram, ISO, odak uzaklığı.
 * Temadan bağımsız olarak her zaman siyahtır — tıpkı vizörün kendisi gibi.
 */
export function Viewfinder({ exif }: { exif: Exif }) {
  const t = useTranslations("photo");
  const locale = useLocale();
  const readings = [
    exif.shutter_display && { value: exif.shutter_display, label: t("shutter") },
    exif.aperture && { value: `f/${Number(exif.aperture.toFixed(1))}`, label: t("aperture") },
    exif.iso && { value: String(exif.iso), label: "ISO" },
    exif.focal_length_mm && {
      value: `${Math.round(exif.focal_length_mm)}mm`,
      label: exif.focal_length_35mm && exif.focal_length_35mm !== Math.round(exif.focal_length_mm)
        ? t("equivalent", { mm: exif.focal_length_35mm })
        : t("focal"),
    },
  ].filter(Boolean) as { value: string; label: string }[];

  const camera = cameraName(exif.camera_make, exif.camera_model);
  if (!readings.length && !camera) return null;

  return (
    <section aria-label={t("settings")} className="bg-black px-5 py-5 text-[#f2f2ee] sm:px-7">
      {readings.length > 0 && (
        <dl className="grid grid-cols-4 gap-x-3 sm:flex sm:flex-wrap sm:gap-x-9 sm:gap-y-4">
          {readings.map((r) => (
            <div key={r.label} className="flex flex-col-reverse">
              <dt className="mt-1 text-[12px] leading-tight text-[#8d8d88] sm:text-[13px]">{r.label}</dt>
              <dd className="tnum text-[22px] font-semibold leading-none tracking-tight sm:text-[34px]">{r.value}</dd>
            </div>
          ))}
        </dl>
      )}
      {(camera || exif.lens || exif.taken_at) && (
        <p className="mt-5 flex flex-wrap gap-x-4 gap-y-1 border-t border-white/15 pt-4 text-[14px] text-[#c9c9c4]">
          {camera && <span className="text-[#f2f2ee]">{camera}</span>}
          {exif.lens && <span>{exif.lens}</span>}
          {exif.taken_at && <span>{formatDate(exif.taken_at, locale)}</span>}
        </p>
      )}
    </section>
  );
}

export function exifSummary(exif: Exif | null) {
  if (!exif) return null;
  return [
    exif.focal_length_mm && `${Math.round(exif.focal_length_mm)}mm`,
    exif.aperture && `f/${Number(exif.aperture.toFixed(1))}`,
    exif.shutter_display,
    exif.iso && `ISO ${exif.iso}`,
  ]
    .filter(Boolean)
    .join("   ");
}
