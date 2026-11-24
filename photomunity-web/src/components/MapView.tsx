"use client";

import "maplibre-gl/dist/maplibre-gl.css";
import { Map as MlMap, Marker, NavigationControl, getVersion, setWorkerUrl } from "maplibre-gl";
import { useEffect, useRef } from "react";

const LIGHT = process.env.NEXT_PUBLIC_MAP_STYLE_LIGHT || "https://tiles.openfreemap.org/styles/positron";
const DARK = process.env.NEXT_PUBLIC_MAP_STYLE_DARK || "https://tiles.openfreemap.org/styles/dark";

/** user: hareket kullanıcıdan mı geldi (sürükleme, kaydırma), yoksa koddan mı (ilk yükleme, flyTo). */
export type View = { bbox: string; zoom: number; lat: number; lng: number; user?: boolean };

/** Taban haritanın üstüne çizilen yarı saydam raster katman (ör. gece ışıkları). */
export type RasterOverlay = { id: string; tiles: string[]; maxzoom: number; attribution: string; opacity: number };

export type MarkerSpec = { key: string; lat: number; lng: number; element: () => HTMLElement; onClick?: () => void };

/**
 * İnce bir MapLibre sarmalayıcısı. İşaretçiler HTML öğesidir (avatar, küme rozeti, küçük resim);
 * kümeleme sunucuda yapıldığı için harita yalnızca gelenleri çizer.
 */
export function MapView({ initial, markers, onView, flyTo, noRotate, overlay, onMapClick }: {
  initial: { lat: number; lng: number; zoom: number };
  markers: MarkerSpec[];
  onView: (v: View) => void;
  flyTo?: { lat: number; lng: number; zoom: number; seq: number } | null;
  /** Kuzey hep yukarıda kalsın (yön çizgileri harita üstüne çizildiğinde). */
  noRotate?: boolean;
  overlay?: RasterOverlay | null;
  /** Haritada boş bir yere dokunulunca */
  onMapClick?: (lat: number, lng: number) => void;
}) {
  const box = useRef<HTMLDivElement>(null);
  const map = useRef<MlMap | null>(null);
  const live = useRef(new Map<string, Marker>());
  const onViewRef = useRef(onView);
  onViewRef.current = onView;
  const onClickRef = useRef(onMapClick);
  onClickRef.current = onMapClick;
  const overlayRef = useRef(overlay);
  overlayRef.current = overlay;

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
    if (noRotate) {
      m.dragRotate.disable();
      m.touchZoomRotate.disableRotation();
      m.keyboard.disableRotation();
      m.touchPitch.disable();
      // Yakınlaştırma merkez etrafında: merkezdeki konum yerinde kalsın
      m.scrollZoom.enable({ around: "center" });
      m.touchZoomRotate.enable({ around: "center" });
      m.touchZoomRotate.disableRotation();
      m.doubleClickZoom.disable();
    }
    map.current = m;
    const emit = (e?: { originalEvent?: unknown }) => {
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
        user: !!e?.originalEvent,
      });
    };
    m.on("moveend", emit);
    m.on("click", (e) => onClickRef.current?.(e.lngLat.lat, ((((e.lngLat.lng + 180) % 360) + 360) % 360) - 180));
    // Stil yüklenince (ve yeniden yüklenirse) katmanı ekle
    m.on("style.load", () => applyOverlay(m, overlayRef.current));
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
    const m = map.current;
    if (m && m.isStyleLoaded()) applyOverlay(m, overlay);
  }, [overlay]);

  useEffect(() => {
    if (flyTo && map.current) map.current.easeTo({ center: [flyTo.lng, flyTo.lat], zoom: flyTo.zoom, duration: 600 });
  }, [flyTo]);

  return <div ref={box} className="h-full w-full" />;
}

/** Raster katmanı ekler ya da yalnızca saydamlığını günceller; null gelirse kaldırır. */
function applyOverlay(m: MlMap, o: RasterOverlay | null | undefined) {
  const existing = m.getStyle()?.layers?.find((l) => l.id.startsWith("overlay:"));
  if (existing && (!o || existing.id !== `overlay:${o.id}`)) {
    m.removeLayer(existing.id);
    if (m.getSource(existing.id)) m.removeSource(existing.id);
  }
  if (!o) return;
  const id = `overlay:${o.id}`;
  if (!m.getSource(id)) {
    m.addSource(id, { type: "raster", tiles: o.tiles, tileSize: 256, maxzoom: o.maxzoom, attribution: o.attribution });
  }
  if (!m.getLayer(id)) {
    // Yer adlarının altına çiz: ilk sembol katmanından önce
    const firstSymbol = m.getStyle().layers?.find((l) => l.type === "symbol")?.id;
    m.addLayer({ id, type: "raster", source: id, paint: { "raster-opacity": o.opacity, "raster-fade-duration": 0 } }, firstSymbol);
  } else {
    m.setPaintProperty(id, "raster-opacity", o.opacity);
  }
}
