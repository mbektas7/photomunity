"use client";

import "maplibre-gl/dist/maplibre-gl.css";
import { Map as MlMap, Marker, NavigationControl, getVersion, setWorkerUrl } from "maplibre-gl";
import { useEffect, useRef } from "react";

const LIGHT = process.env.NEXT_PUBLIC_MAP_STYLE_LIGHT || "https://tiles.openfreemap.org/styles/positron";
const DARK = process.env.NEXT_PUBLIC_MAP_STYLE_DARK || "https://tiles.openfreemap.org/styles/dark";

export type View = { bbox: string; zoom: number; lat: number; lng: number };

export type MarkerSpec = { key: string; lat: number; lng: number; element: () => HTMLElement; onClick?: () => void };

/**
 * İnce bir MapLibre sarmalayıcısı. İşaretçiler HTML öğesidir (avatar, küme rozeti, küçük resim);
 * kümeleme sunucuda yapıldığı için harita yalnızca gelenleri çizer.
 */
export function MapView({ initial, markers, onView, flyTo }: {
  initial: { lat: number; lng: number; zoom: number };
  markers: MarkerSpec[];
  onView: (v: View) => void;
  flyTo?: { lat: number; lng: number; zoom: number; seq: number } | null;
}) {
  const box = useRef<HTMLDivElement>(null);
  const map = useRef<MlMap | null>(null);
  const live = useRef(new Map<string, Marker>());
  const onViewRef = useRef(onView);
  onViewRef.current = onView;

  useEffect(() => {
    if (!box.current) return;
    setWorkerUrl(new URL(`/vendor/maplibre-gl-worker-${getVersion()}.mjs`, window.location.origin).href);
    const dark = window.matchMedia("(prefers-color-scheme: dark)").matches;
    const m = new MlMap({
      container: box.current,
      style: dark ? DARK : LIGHT,
      center: [initial.lng, initial.lat],
      zoom: initial.zoom,
      attributionControl: { compact: true },
      renderWorldCopies: true,
    });
    m.addControl(new NavigationControl({ showCompass: false }), "top-right");
    map.current = m;
    const emit = () => {
      const b = m.getBounds();
      const c = m.getCenter();
      // Dünya kopyalarında boylamı -180..180 aralığına sar
      const wrap = (x: number) => ((((x + 180) % 360) + 360) % 360) - 180;
      const west = b.getWest(), east = b.getEast();
      const full = east - west >= 360;
      onViewRef.current({
        bbox: [full ? -180 : wrap(west), Math.max(-90, b.getSouth()), full ? 180 : wrap(east), Math.min(90, b.getNorth())].map((n) => n.toFixed(4)).join(","),
        zoom: Math.round(m.getZoom()),
        lat: c.lat,
        lng: wrap(c.lng),
      });
    };
    m.on("moveend", emit);
    emit();
    return () => {
      live.current.forEach((mk) => mk.remove());
      live.current.clear();
      m.remove();
      map.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // İşaretçileri anahtar bazında güncelle: değişmeyenler yerinde kalır, titreme olmaz
  useEffect(() => {
    const m = map.current;
    if (!m) return;
    const next = new Set(markers.map((s) => s.key));
    live.current.forEach((mk, key) => {
      if (!next.has(key)) {
        mk.remove();
        live.current.delete(key);
      }
    });
    for (const spec of markers) {
      if (live.current.has(spec.key)) continue;
      const el = spec.element();
      if (spec.onClick) {
        el.style.cursor = "pointer";
        el.addEventListener("click", (e) => {
          e.stopPropagation();
          spec.onClick?.();
        });
      }
      live.current.set(spec.key, new Marker({ element: el }).setLngLat([spec.lng, spec.lat]).addTo(m));
    }
  }, [markers]);

  useEffect(() => {
    if (flyTo && map.current) map.current.easeTo({ center: [flyTo.lng, flyTo.lat], zoom: flyTo.zoom, duration: 600 });
  }, [flyTo]);

  return <div ref={box} className="h-full w-full" />;
}
