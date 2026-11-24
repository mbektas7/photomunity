"use client";

import dynamic from "next/dynamic";
import { useCallback, useMemo, useRef, useState } from "react";
import type { MarkerSpec, View } from "./MapView";

const MapView = dynamic(() => import("./MapView").then((m) => m.MapView), { ssr: false });

/**
 * Konum seçme haritası: işaret hep ortada, harita kaydırılınca konum değişir.
 * Dışarıdan gelen konum değişince (ör. "konumum") haritayı oraya götürür.
 */
export function PickMap({ lat, lng, onPick, label, className = "h-[260px]" }: {
  lat: number;
  lng: number;
  onPick: (lat: number, lng: number) => void;
  label: string;
  className?: string;
}) {
  const [initial] = useState({ lat, lng, zoom: 9 });
  const zoom = useRef(9);
  const picked = useRef<string | null>(null);
  const lastFly = useRef<{ lat: number; lng: number; zoom: number; seq: number } | null>(null);
  const fly = useMemo(() => {
    if (picked.current !== `${lat},${lng}`) lastFly.current = { lat, lng, zoom: zoom.current, seq: Date.now() };
    return lastFly.current;
  }, [lat, lng]);
  const onView = useCallback((v: View) => {
    zoom.current = v.zoom;
    if (v.user && (Math.abs(v.lat - lat) > 1e-4 || Math.abs(v.lng - lng) > 1e-4)) {
      const a = +v.lat.toFixed(4), b = +v.lng.toFixed(4);
      picked.current = `${a},${b}`;
      onPick(a, b);
    }
  }, [lat, lng, onPick]);
  const markers = useMemo<MarkerSpec[]>(() => [], []);
  return (
    <div className={`relative overflow-hidden rounded-card bg-surface-2 ${className}`} role="group" aria-label={label}>
      <MapView initial={initial} markers={markers} onView={onView} flyTo={fly} noRotate />
      <svg viewBox="-12 -12 24 24" className="pointer-events-none absolute left-1/2 top-1/2 h-7 w-7 -translate-x-1/2 -translate-y-1/2" aria-hidden>
        <circle r={5} fill="var(--accent)" stroke="#fff" strokeWidth={2} />
      </svg>
    </div>
  );
}

/** Salt okunur küçük harita (etkinlik yeri). */
export function StaticMap({ lat, lng, className = "h-[200px]" }: { lat: number; lng: number; className?: string }) {
  const [initial] = useState({ lat, lng, zoom: 11 });
  const markers = useMemo<MarkerSpec[]>(() => [{
    key: "p",
    lat,
    lng,
    element: () => {
      const el = document.createElement("span");
      el.style.cssText = "display:block;width:18px;height:18px;border-radius:999px;background:var(--accent);border:3px solid #fff;box-shadow:0 1px 4px rgba(0,0,0,.4)";
      return el;
    },
  }], [lat, lng]);
  const noop = useCallback(() => {}, []);
  return (
    <div className={`relative overflow-hidden rounded-card bg-surface-2 ${className}`}>
      <MapView initial={initial} markers={markers} onView={noop} />
    </div>
  );
}
