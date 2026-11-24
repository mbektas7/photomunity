"use client";

import { Minus, Plus, X } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { formatAperture, formatShutter } from "@/components/ExifChip";
import { cameraName } from "@/lib/format";
import type { PhotoDetail } from "@/lib/types";

type View = { s: number; x: number; y: number };

/**
 * Tam ekran görüntüleyici: en büyük türev (images.full, uzun kenar 2560 px). Tekerlek / iki parmakla
 * yakınlaştırma, sürükleyerek kaydırma, çift tık 1:1 ↔ sığdır, küçük harita ve EXIF şeridi.
 * Ölçek s: ekran pikseli / görsel pikseli (1 = %100). Görsel hiçbir zaman kırpılmaz; sığdırılmış hâli
 * tamamını gösterir.
 */
export function ZoomViewer({ photo, open, onClose, protect }: { photo: PhotoDetail; open: boolean; onClose: () => void; protect: boolean }) {
  const t = useTranslations("zoom");
  const locale = useLocale();
  const dialog = useRef<HTMLDialogElement>(null);
  const stage = useRef<HTMLDivElement>(null);
  const img = photo.images.full ?? photo.images.feed;
  const thumb = photo.images.thumb ?? photo.images.feed;
  const [box, setBox] = useState({ w: 0, h: 0 });
  const [view, setView] = useState<View>({ s: 1, x: 0, y: 0 });
  const pointers = useRef(new Map<number, { x: number; y: number }>());
  const pinch = useRef<{ d: number; s: number } | null>(null);
  const moved = useRef(false);

  const nw = img?.width ?? 1, nh = img?.height ?? 1;
  const fit = box.w && box.h ? Math.min(box.w / nw, box.h / nh, 1) : 1;
  const minS = fit, maxS = Math.max(2, fit * 4);

  /** Görsel kutudan küçükse ortala, büyükse kenar boşluğu bırakmadan sınırla. */
  const clamp = useCallback((v: View): View => {
    const s = Math.max(minS, Math.min(maxS, v.s));
    const w = nw * s, h = nh * s;
    const x = w <= box.w ? (box.w - w) / 2 : Math.min(0, Math.max(box.w - w, v.x));
    const y = h <= box.h ? (box.h - h) / 2 : Math.min(0, Math.max(box.h - h, v.y));
    return { s, x, y };
  }, [minS, maxS, nw, nh, box.w, box.h]);

  const fitView = useCallback(() => setView(clamp({ s: fit, x: 0, y: 0 })), [clamp, fit]);

  useEffect(() => {
    if (open) dialog.current?.showModal();
    else dialog.current?.close();
  }, [open]);

  useLayoutEffect(() => {
    const el = stage.current;
    if (!open || !el) return;
    const ro = new ResizeObserver(([e]) => setBox({ w: e!.contentRect.width, h: e!.contentRect.height }));
    ro.observe(el);
    return () => ro.disconnect();
  }, [open]);

  // Açılınca ve boyut değişince sığdır
  useEffect(() => {
    if (open && box.w) fitView();
  }, [open, box.w, box.h, fitView]);

  /** (px, py) noktası yerinde kalacak şekilde yeni ölçek. */
  const zoomAt = useCallback((s: number, px: number, py: number) => {
    setView((v) => clamp({ s, x: px - ((px - v.x) * Math.max(minS, Math.min(maxS, s))) / v.s, y: py - ((py - v.y) * Math.max(minS, Math.min(maxS, s))) / v.s }));
  }, [clamp, minS, maxS]);

  // Tekerlek: pasif olmayan dinleyici (sayfa kaymasın)
  useEffect(() => {
    const el = stage.current;
    if (!open || !el) return;
    const onWheel = (e: WheelEvent) => {
      e.preventDefault();
      const r = el.getBoundingClientRect();
      setView((v) => {
        const s = Math.max(minS, Math.min(maxS, v.s * Math.exp(-e.deltaY * 0.0022)));
        const px = e.clientX - r.left, py = e.clientY - r.top;
        return clamp({ s, x: px - ((px - v.x) * s) / v.s, y: py - ((py - v.y) * s) / v.s });
      });
    };
    el.addEventListener("wheel", onWheel, { passive: false });
    return () => el.removeEventListener("wheel", onWheel);
  }, [open, clamp, minS, maxS]);

  function onPointerDown(e: React.PointerEvent) {
    (e.target as Element).setPointerCapture?.(e.pointerId);
    pointers.current.set(e.pointerId, { x: e.clientX, y: e.clientY });
    moved.current = false;
    if (pointers.current.size === 2) {
      const [a, b] = [...pointers.current.values()];
      pinch.current = { d: Math.hypot(a!.x - b!.x, a!.y - b!.y), s: view.s };
    }
  }
  function onPointerMove(e: React.PointerEvent) {
    const prev = pointers.current.get(e.pointerId);
    if (!prev) return;
    const cur = { x: e.clientX, y: e.clientY };
    pointers.current.set(e.pointerId, cur);
    if (pointers.current.size === 2 && pinch.current) {
      const [a, b] = [...pointers.current.values()];
      const d = Math.hypot(a!.x - b!.x, a!.y - b!.y);
      const r = stage.current!.getBoundingClientRect();
      zoomAt(pinch.current.s * (d / pinch.current.d), (a!.x + b!.x) / 2 - r.left, (a!.y + b!.y) / 2 - r.top);
      moved.current = true;
      return;
    }
    const dx = cur.x - prev.x, dy = cur.y - prev.y;
    if (Math.abs(dx) + Math.abs(dy) > 1) moved.current = true;
    setView((v) => clamp({ s: v.s, x: v.x + dx, y: v.y + dy }));
  }
  function onPointerUp(e: React.PointerEvent) {
    pointers.current.delete(e.pointerId);
    if (pointers.current.size < 2) pinch.current = null;
  }
  function onDoubleClick(e: React.MouseEvent) {
    const r = stage.current!.getBoundingClientRect();
    const px = e.clientX - r.left, py = e.clientY - r.top;
    if (Math.abs(view.s - 1) < 0.01 && fit < 1) fitView();
    else zoomAt(1, px, py);
  }
  function onKey(e: React.KeyboardEvent) {
    const cx = box.w / 2, cy = box.h / 2;
    const step = 80;
    if (e.key === "+" || e.key === "=") zoomAt(view.s * 1.25, cx, cy);
    else if (e.key === "-") zoomAt(view.s / 1.25, cx, cy);
    else if (e.key === "0") fitView();
    else if (e.key === "1") zoomAt(1, cx, cy);
    else if (e.key === "ArrowLeft") setView((v) => clamp({ ...v, x: v.x + step }));
    else if (e.key === "ArrowRight") setView((v) => clamp({ ...v, x: v.x - step }));
    else if (e.key === "ArrowUp") setView((v) => clamp({ ...v, y: v.y + step }));
    else if (e.key === "ArrowDown") setView((v) => clamp({ ...v, y: v.y - step }));
    else return;
    e.preventDefault();
  }

  const pct = Math.round(view.s * 100);
  const zoomed = view.s > fit + 0.001;
  // Küçük harita: görünen bölge (görsel koordinatlarında)
  const mini = 150;
  const mw = nw >= nh ? mini : (mini * nw) / nh, mh = nw >= nh ? (mini * nh) / nw : mini;
  const vx = Math.max(0, -view.x / view.s), vy = Math.max(0, -view.y / view.s);
  const vw = Math.min(nw - vx, box.w / view.s), vh = Math.min(nh - vy, box.h / view.s);

  const ex = photo.exif;
  const strip = ex
    ? [
        { k: t("camera"), v: cameraName(ex.camera_make, ex.camera_model) },
        { k: t("lens"), v: ex.lens },
        { k: t("exposure"), v: [formatShutter(ex.shutter_display, locale), formatAperture(ex.aperture), ex.iso ? `ISO ${ex.iso}` : null].filter(Boolean).join(" · ") || null },
      ].filter((x) => x.v)
    : [];

  return (
    <dialog
      ref={dialog}
      onClose={onClose}
      aria-label={t("label", { title: photo.title ?? "" })}
      className="m-0 h-dvh max-h-none w-screen max-w-none bg-[#0b0c0f] p-0 text-white backdrop:bg-black"
    >
      {open && img && (
        <div className="flex h-full flex-col">
          <div className="flex items-center gap-2 px-3 py-2.5 sm:px-5">
            <p className="tnum min-w-0 flex-1 truncate text-sm text-white/75" aria-live="polite">
              {t("zoom_level", { pct })}{Math.abs(view.s - 1) < 0.01 ? " · 1:1" : ""}
            </p>
            <button type="button" onClick={() => zoomAt(view.s / 1.25, box.w / 2, box.h / 2)} aria-label={t("zoom_out")} className="grid h-10 w-10 place-items-center rounded-full bg-white/10 hover:bg-white/20">
              <Minus className="h-5 w-5" aria-hidden />
            </button>
            <button type="button" onClick={() => zoomAt(view.s * 1.25, box.w / 2, box.h / 2)} aria-label={t("zoom_in")} className="grid h-10 w-10 place-items-center rounded-full bg-white/10 hover:bg-white/20">
              <Plus className="h-5 w-5" aria-hidden />
            </button>
            <button type="button" onClick={() => (zoomed ? fitView() : zoomAt(1, box.w / 2, box.h / 2))} className="h-10 rounded-full bg-white/10 px-3.5 text-sm font-semibold hover:bg-white/20">
              {zoomed ? t("fit") : "1:1"}
            </button>
            <button type="button" onClick={onClose} aria-label={t("close")} className="grid h-10 w-10 place-items-center rounded-full bg-white/10 hover:bg-white/20">
              <X className="h-5 w-5" aria-hidden />
            </button>
          </div>
          <div
            ref={stage}
            tabIndex={0}
            role="img"
            aria-label={t("stage_label")}
            onKeyDown={onKey}
            onPointerDown={onPointerDown}
            onPointerMove={onPointerMove}
            onPointerUp={onPointerUp}
            onPointerCancel={onPointerUp}
            onDoubleClick={onDoubleClick}
            onContextMenu={protect ? (e) => e.preventDefault() : undefined}
            className="relative min-h-0 flex-1 touch-none select-none overflow-hidden outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-accent"
            style={{ cursor: zoomed ? "grab" : "zoom-in" }}
          >
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={img.url}
              alt={photo.title ?? ""}
              draggable={false}
              className="absolute left-0 top-0 max-w-none"
              style={{ width: nw * view.s, height: nh * view.s, transform: `translate(${view.x}px, ${view.y}px)` }}
            />
            {zoomed && thumb && (
              <div className="pointer-events-none absolute bottom-3 right-3 overflow-hidden rounded-[10px] border border-white/25 bg-black/60" style={{ width: mw, height: mh }} aria-hidden>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={thumb.url} alt="" className="h-full w-full object-contain opacity-80" />
                <span
                  className="absolute border-2 border-white shadow-[0_0_0_999px_rgba(0,0,0,0.35)]"
                  style={{ left: (vx / nw) * mw, top: (vy / nh) * mh, width: (vw / nw) * mw, height: (vh / nh) * mh }}
                />
              </div>
            )}
          </div>
          <div className="flex flex-wrap items-center gap-x-6 gap-y-1 px-4 py-3 text-[13px] sm:px-6">
            {strip.map((x) => (
              <span key={x.k} className="min-w-0">
                <span className="text-white/55">{x.k} </span>
                <span className="font-semibold">{x.v}</span>
              </span>
            ))}
            <span className="ml-auto hidden text-white/50 sm:inline">{t("hint")}</span>
          </div>
        </div>
      )}
    </dialog>
  );
}
