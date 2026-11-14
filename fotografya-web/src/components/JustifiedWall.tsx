"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { Link } from "@/i18n/navigation";
import type { PhotoCard } from "@/lib/types";

const GAP = 10;

type Row = { height: number; items: { photo: PhotoCard; width: number }[] };

function ratio(p: PhotoCard) {
  const v = p.images.feed ?? p.images.thumb ?? p.images.full;
  return v && v.height ? v.width / v.height : 1.5;
}

/** Kareleri asla kırpmadan, her birini kendi en-boy oranında satırlara dizer. */
export function buildRows(photos: PhotoCard[], width: number, target: number): Row[] {
  const rows: Row[] = [];
  let current: PhotoCard[] = [];
  let sum = 0;
  for (const photo of photos) {
    current.push(photo);
    sum += ratio(photo);
    const height = (width - GAP * (current.length - 1)) / sum;
    if (height <= target) {
      rows.push({ height, items: current.map((p) => ({ photo: p, width: ratio(p) * height })) });
      current = [];
      sum = 0;
    }
  }
  if (current.length) {
    const height = Math.min(target, (width - GAP * (current.length - 1)) / sum);
    rows.push({ height, items: current.map((p) => ({ photo: p, width: ratio(p) * height })) });
  }
  return rows;
}

export function JustifiedWall({
  photos,
  target = 300,
  completeRowsOnly = false,
  maxRows,
}: {
  photos: PhotoCard[];
  target?: number;
  /** Vitrin duvarlarında yarım kalan son satırı göstermez */
  completeRowsOnly?: boolean;
  /** Vitrinlerde satır sayısını sınırlar (ör. tanıtım sayfası) */
  maxRows?: number;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const ro = new ResizeObserver(([entry]) => setWidth(Math.floor(entry!.contentRect.width)));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const rowTarget = width && width < 640 ? Math.round(target * 0.62) : target;
  const rows = useMemo(() => {
    if (!width) return [];
    const all = buildRows(photos, width, rowTarget);
    const last = all.at(-1);
    const incomplete = last && last.items.reduce((s, i) => s + i.width, 0) < width * 0.9;
    const rows = completeRowsOnly && incomplete && all.length > 1 ? all.slice(0, -1) : all;
    return maxRows ? rows.slice(0, maxRows) : rows;
  }, [photos, width, rowTarget, completeRowsOnly, maxRows]);

  return (
    <div ref={ref} className="flex flex-col" style={{ gap: GAP }}>
      {rows.map((row, i) => (
        <div key={i} className="flex" style={{ gap: GAP, height: row.height }}>
          {row.items.map(({ photo, width: w }) => {
            const src = (row.height > 360 ? photo.images.feed : photo.images.thumb) ?? photo.images.feed;
            return (
              <Link
                key={photo.id}
                href={`/p/${photo.id}`}
                className="print-placeholder group relative block shrink-0 overflow-hidden rounded-photo"
                style={{ width: w, height: row.height }}
              >
                {src && (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    src={src.url}
                    alt={photo.title ?? ""}
                    loading="lazy"
                    decoding="async"
                    className="fade-in h-full w-full object-cover"
                  />
                )}
                <span className="pointer-events-none absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/60 to-transparent px-3 pb-2.5 pt-8 text-sm font-medium text-white opacity-0 transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100">
                  {photo.user.display_name}
                </span>
              </Link>
            );
          })}
        </div>
      ))}
    </div>
  );
}
