"use client";

import { useQuery } from "@tanstack/react-query";
import clsx from "clsx";
import { MapPin, MessageCircle, X } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import dynamic from "next/dynamic";
import { useSearchParams } from "next/navigation";
import { Suspense, useCallback, useMemo, useState } from "react";
import { Avatar } from "@/components/Avatar";
import type { MarkerSpec, View } from "@/components/MapView";
import { buttonClass } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { api } from "@/lib/api";
import { countryName, initials } from "@/lib/format";
import { useMe } from "@/lib/hooks";
import type { MapCluster, MapPhotographer, MapPhotoPoint, PhotoMapData, PhotographerMapData } from "@/lib/types";

const MapView = dynamic(() => import("@/components/MapView").then((m) => m.MapView), { ssr: false });
const SPECIALTIES = ["astro", "landscape", "street", "portrait", "wildlife", "sports", "architecture", "documentary", "wedding", "macro", "aerial", "travel"];

function clusterEl(c: MapCluster) {
  const el = document.createElement("div");
  const size = Math.min(64, 30 + Math.log2(c.count) * 7);
  if (c.thumb_url) {
    el.className = "relative overflow-hidden border-[3px] border-white shadow-[0_6px_20px_-6px_rgba(0,0,0,.45)]";
    el.style.cssText = `width:${size + 14}px;height:${size + 14}px;background:#ddd url("${c.thumb_url}") center/cover`;
    const badge = document.createElement("span");
    badge.className = "absolute bottom-0 right-0 bg-black/75 px-1.5 text-[11px] font-semibold text-white";
    badge.textContent = String(c.count);
    el.appendChild(badge);
  } else {
    el.className = "flex items-center justify-center rounded-full bg-[var(--ink)] text-[13px] font-semibold text-[var(--surface)] ring-4 ring-[color-mix(in_srgb,var(--ink)_18%,transparent)]";
    el.style.cssText = `width:${size}px;height:${size}px`;
    el.textContent = String(c.count);
  }
  return el;
}

function avatarEl(p: MapPhotographer, selected: boolean) {
  const el = document.createElement("div");
  el.className = clsx("flex h-11 w-11 items-center justify-center overflow-hidden rounded-full border-[3px] bg-[var(--ink)] text-[14px] font-semibold text-[var(--surface)] shadow-[0_6px_18px_-6px_rgba(0,0,0,.5)]",
    selected ? "border-[var(--accent)]" : "border-white");
  if (p.user.avatar_url) {
    const img = document.createElement("img");
    img.src = p.user.avatar_url;
    img.alt = "";
    img.className = "h-full w-full object-cover";
    el.appendChild(img);
  } else el.textContent = initials(p.user.display_name);
  el.setAttribute("aria-label", p.user.display_name);
  return el;
}

function photoEl(p: MapPhotoPoint, selected: boolean) {
  const el = document.createElement("div");
  el.className = clsx("h-14 w-14 border-[3px] shadow-[0_6px_18px_-6px_rgba(0,0,0,.5)]", selected ? "border-[var(--accent)]" : "border-white");
  el.style.background = `#ddd url("${p.thumb_url ?? ""}") center/cover`;
  el.setAttribute("aria-label", p.title ?? p.user.display_name);
  return el;
}

export default function MapPage() {
  return (
    <Suspense>
      <MapScreen />
    </Suspense>
  );
}

function MapScreen() {
  const t = useTranslations("map");
  const ts = useTranslations("specialties");
  const params = useSearchParams();
  const { data: me } = useMe();
  const [layer, setLayer] = useState<"photographers" | "photos">(params.get("layer") === "photos" ? "photos" : "photographers");
  const [specialty, setSpecialty] = useState("");
  const [view, setView] = useState<View | null>(null);
  const [selected, setSelected] = useState<{ kind: "user"; p: MapPhotographer } | { kind: "photo"; p: MapPhotoPoint } | null>(null);
  const [flyTo, setFlyTo] = useState<{ lat: number; lng: number; zoom: number; seq: number } | null>(null);

  const initial = useMemo(() => {
    const lat = Number(params.get("lat")), lng = Number(params.get("lng")), z = Number(params.get("z"));
    if (lat && lng) return { lat, lng, zoom: z || 12 };
    if (me?.latitude != null && me.longitude != null) return { lat: me.latitude, lng: me.longitude, zoom: 7 };
    return { lat: 39.2, lng: 35.2, zoom: 5 };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const users = useQuery({
    queryKey: ["map", "photographers", view?.bbox, view?.zoom, specialty],
    enabled: !!view && layer === "photographers",
    placeholderData: (prev) => prev,
    queryFn: () => api<PhotographerMapData>(`map/photographers?bbox=${view!.bbox}&zoom=${view!.zoom}${specialty ? `&specialty=${specialty}` : ""}`),
  });
  const photos = useQuery({
    queryKey: ["map", "photos", view?.bbox, view?.zoom],
    enabled: !!view && layer === "photos",
    placeholderData: (prev) => prev,
    queryFn: () => api<PhotoMapData>(`map/photos?bbox=${view!.bbox}&zoom=${view!.zoom}`),
  });

  const zoomInto = useCallback((c: MapCluster) => setFlyTo({ lat: c.lat, lng: c.lng, zoom: Math.min((view?.zoom ?? 5) + 2, 16), seq: Date.now() }), [view?.zoom]);

  const markers: MarkerSpec[] = useMemo(() => {
    const sel = selected ? (selected.kind === "user" ? selected.p.user.id : selected.p.photo_id) : null;
    if (layer === "photographers") {
      const d = users.data;
      if (!d) return [];
      return [
        ...d.clusters.map((c) => ({ key: `c:${c.lat.toFixed(3)}:${c.lng.toFixed(3)}:${c.count}`, lat: c.lat, lng: c.lng, element: () => clusterEl(c), onClick: () => zoomInto(c) })),
        ...d.photographers.map((p) => ({ key: `u:${p.user.id}:${sel === p.user.id}`, lat: p.lat, lng: p.lng, element: () => avatarEl(p, sel === p.user.id), onClick: () => setSelected({ kind: "user", p }) })),
      ];
    }
    const d = photos.data;
    if (!d) return [];
    return [
      ...d.clusters.map((c) => ({ key: `pc:${c.lat.toFixed(3)}:${c.lng.toFixed(3)}:${c.count}`, lat: c.lat, lng: c.lng, element: () => clusterEl(c), onClick: () => zoomInto(c) })),
      ...d.photos.map((p) => ({ key: `p:${p.photo_id}:${sel === p.photo_id}`, lat: p.lat, lng: p.lng, element: () => photoEl(p, sel === p.photo_id), onClick: () => setSelected({ kind: "photo", p }) })),
    ];
  }, [layer, users.data, photos.data, selected, zoomInto]);

  const total = layer === "photographers" ? users.data?.total : photos.data?.total;

  return (
    <div data-fullbleed className="relative h-[calc(100dvh-4rem-4.5rem)] md:h-[calc(100dvh-4rem)]">
      <MapView initial={initial} markers={markers} onView={setView} flyTo={flyTo} />

      <div className="pointer-events-none absolute inset-x-3 top-3 flex flex-col items-start gap-2 sm:left-4 sm:top-4">
        <div className="pointer-events-auto flex rounded-full border border-line bg-surface p-1 shadow-[0_8px_30px_-12px_rgba(0,0,0,.35)]">
          {(["photographers", "photos"] as const).map((k) => (
            <button key={k} type="button" onClick={() => { setLayer(k); setSelected(null); }} aria-pressed={layer === k}
              className={clsx("h-9 rounded-full px-4 text-sm font-medium", layer === k ? "bg-ink text-surface" : "text-ink-muted hover:text-ink")}>
              {t(`layer_${k}`)}
            </button>
          ))}
        </div>
        {layer === "photographers" && (
          <select value={specialty} onChange={(e) => setSpecialty(e.target.value)} aria-label={t("specialty")}
            className="pointer-events-auto h-10 rounded-full border border-line bg-surface px-4 text-sm shadow-[0_8px_30px_-12px_rgba(0,0,0,.35)]">
            <option value="">{t("all_specialties")}</option>
            {SPECIALTIES.map((s) => <option key={s} value={s}>{ts(s)}</option>)}
          </select>
        )}
        {total !== undefined && (
          <span className="pointer-events-auto rounded-full bg-surface/90 px-3 py-1.5 text-xs text-ink-muted backdrop-blur">
            {t(layer === "photographers" ? "count_photographers" : "count_photos", { count: total })}
          </span>
        )}
      </div>

      {selected && <SelectedCard s={selected} meId={me?.id} onClose={() => setSelected(null)} />}
    </div>
  );
}

function SelectedCard({ s, meId, onClose }: { s: { kind: "user"; p: MapPhotographer } | { kind: "photo"; p: MapPhotoPoint }; meId?: string; onClose: () => void }) {
  const t = useTranslations("map");
  const ts = useTranslations("specialties");
  const locale = useLocale();
  return (
    <div className="absolute inset-x-3 bottom-3 z-10 bg-surface p-4 shadow-[0_18px_50px_-15px_rgba(0,0,0,.5)] sm:inset-x-auto sm:bottom-auto sm:right-4 sm:top-20 sm:w-[340px]">
      <button type="button" onClick={onClose} aria-label={t("close")} className="absolute right-2 top-2 rounded-full p-1.5 text-ink-muted hover:bg-ink/5"><X className="h-4 w-4" /></button>
      {s.kind === "user" ? (
        <>
          <div className="flex items-center gap-3 pr-8">
            <Avatar name={s.p.user.display_name} url={s.p.user.avatar_url} size={52} />
            <div className="min-w-0">
              <p className="truncate font-semibold">{s.p.user.display_name}</p>
              <p className="flex items-center gap-1 truncate text-sm text-ink-muted">
                <MapPin className="h-3.5 w-3.5 shrink-0" /> {[s.p.city, countryName(s.p.country, locale)].filter(Boolean).join(", ") || t("approximate")}
              </p>
            </div>
          </div>
          {s.p.specialties.length > 0 && (
            <ul className="mt-3 flex flex-wrap gap-1.5">
              {s.p.specialties.slice(0, 5).map((x) => <li key={x} className="rounded-full bg-ink/[0.06] px-2.5 py-1 text-xs">{ts.has(x) ? ts(x) : x}</li>)}
            </ul>
          )}
          <div className="mt-4 flex gap-2">
            <Link href={`/u/${s.p.user.username}`} className={buttonClass("secondary", "h-10 flex-1 px-3")}>{t("profile")}</Link>
            {meId !== s.p.user.id && (
              <Link href={`/messages/new?to=${s.p.user.username}`} className={buttonClass("primary", "h-10 flex-1 px-3")}>
                <MessageCircle className="h-4 w-4" /> {t("message")}
              </Link>
            )}
          </div>
          <p className="mt-3 text-xs text-ink-muted">{t("privacy_note")}</p>
        </>
      ) : (
        <>
          <Link href={`/p/${s.p.photo_id}`} className="block pr-6">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            {s.p.thumb_url && <img src={s.p.thumb_url} alt={s.p.title ?? ""} className="max-h-[220px] w-full bg-ink/5 object-contain" />}
          </Link>
          <p className="mt-3 font-semibold">{s.p.title}</p>
          <Link href={`/u/${s.p.user.username}`} className="text-sm text-ink-muted hover:text-ink">{s.p.user.display_name}</Link>
          <Link href={`/p/${s.p.photo_id}`} className={buttonClass("primary", "mt-4 h-10 w-full")}>{t("open_photo")}</Link>
        </>
      )}
    </div>
  );
}
