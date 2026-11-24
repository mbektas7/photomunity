"use client";

import { useQuery } from "@tanstack/react-query";
import clsx from "clsx";
import { Aperture, Camera } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useSearchParams } from "next/navigation";
import { Suspense, useCallback, useState } from "react";
import { useDebounced } from "@/components/admin";
import { Avatar } from "@/components/Avatar";
import { formatAperture, formatFocal, formatShutter } from "@/components/ExifChip";
import { JustifiedWall } from "@/components/JustifiedWall";
import { Notice } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import { useLoadMore, usePhotoPages } from "@/lib/hooks";
import type { GearName, GearStats } from "@/lib/types";

export default function GearPage() {
  return (
    <Suspense>
      <Gear />
    </Suspense>
  );
}

/** Ekipmana göre keşif: EXIF'teki kamera modeli ya da lens adı (birebir, büyük/küçük harf duyarsız). */
function Gear() {
  const t = useTranslations("gear");
  const locale = useLocale();
  const params = useSearchParams();
  const camera = params.get("camera")?.trim() || "";
  const lens = params.get("lens")?.trim() || "";
  const [sort, setSort] = useState<"recent" | "popular">("recent");
  const filter = new URLSearchParams({ ...(camera ? { camera } : {}), ...(lens ? { lens } : {}) }).toString();
  const has = !!(camera || lens);

  const stats = useQuery({ queryKey: ["gear", "stats", filter], enabled: has, queryFn: () => api<GearStats>(`gear/stats?${filter}`) });
  const photos = usePhotoPages(["gear", "photos", filter, sort], `gear/photos?${filter}&sort=${sort}`, has, "cursor");
  const { fetchNextPage, hasNextPage, isFetchingNextPage } = photos;
  const loadMore = useCallback(() => !isFetchingNextPage && fetchNextPage(), [fetchNextPage, isFetchingNextPage]);
  const sentinel = useLoadMore(loadMore, !!hasNextPage);
  const items = photos.data?.pages.flatMap((p) => p.items) ?? [];
  const s = stats.data;
  const cs = s?.common_settings;
  const name = lens || camera;
  const Icon = lens ? Aperture : Camera;

  const tiles = s
    ? [
        { k: "photos", v: s.photo_count.toLocaleString(locale), label: t("photos") },
        { k: "people", v: s.photographer_count.toLocaleString(locale), label: t("photographers") },
        { k: "shutter", v: cs?.median_shutter_display ? formatShutter(cs.median_shutter_display, locale) : null, label: t("median_shutter") },
        { k: "aperture", v: formatAperture(cs?.median_aperture), label: t("median_aperture") },
        { k: "iso", v: cs?.median_iso ? `ISO ${cs.median_iso}` : null, label: t("median_iso") },
        { k: "focal", v: formatFocal(cs?.median_focal_length_mm), label: t("median_focal") },
      ].filter((x) => x.v)
    : [];

  return (
    <div className="mx-auto max-w-[1440px] px-3 pb-16 sm:px-6 lg:px-10">
      <div className="flex flex-wrap items-end justify-between gap-4 pb-6 pt-2 sm:pt-4">
        <div className="min-w-0">
          <p className="flex items-center gap-2 text-sm font-semibold text-ink-muted">
            <Icon className="h-4 w-4" aria-hidden /> {lens ? t("lens") : camera ? t("camera") : t("title")}
          </p>
          <h1 className="mt-1 break-words text-[30px] font-bold leading-tight tracking-[-0.04em] sm:text-[44px]">{name || t("title")}</h1>
          {has && <p className="mt-2 text-ink-muted">{lens ? t("shot_with_lens") : t("shot_with_camera")}</p>}
        </div>
        <GearSearch />
      </div>

      {!has && <p className="rounded-card bg-surface px-6 py-12 text-ink-muted">{t("pick")}</p>}
      {stats.error && <Notice tone="error">{stats.error instanceof ApiError && stats.error.message ? stats.error.message : t("error")}</Notice>}

      {s && (
        <section className="mb-6 grid gap-4 lg:grid-cols-[minmax(0,1fr)_360px]">
          <dl className="grid grid-cols-2 content-start gap-2 self-start sm:grid-cols-3">
            {tiles.map((x) => (
              <div key={x.k} className="flex flex-col-reverse rounded-box bg-surface px-4 py-3">
                <dt className="text-caption text-ink-muted">{x.label}</dt>
                <dd className="tnum text-[24px] font-bold tracking-[-0.03em]">{x.v}</dd>
              </div>
            ))}
          </dl>
          {s.top_photographers.length > 0 && (
            <div className="rounded-card bg-surface p-4">
              <h2 className="mb-2 text-[15px] font-bold">{t("top_photographers")}</h2>
              <ul className="flex flex-col">
                {s.top_photographers.slice(0, 5).map((u) => (
                  <li key={u.id}>
                    <Link href={`/u/${u.username}`} className="flex items-center gap-2.5 rounded-[12px] px-1.5 py-1.5 hover:bg-surface-2">
                      <Avatar name={u.display_name} url={u.avatar_url} size={32} />
                      <span className="min-w-0">
                        <span className="block truncate text-[14.5px] font-semibold">{u.display_name}</span>
                        <span className="block truncate text-xs text-ink-muted">@{u.username}</span>
                      </span>
                    </Link>
                  </li>
                ))}
              </ul>
            </div>
          )}
        </section>
      )}

      {has && (
        <section aria-label={t("photos")}>
          <div className="mb-4 flex gap-2" role="tablist" aria-label={t("sort_label")}>
            {(["recent", "popular"] as const).map((k) => (
              <button
                key={k}
                type="button"
                role="tab"
                aria-selected={sort === k}
                onClick={() => setSort(k)}
                className={clsx("h-10 rounded-pill px-4 text-[15px] font-semibold", sort === k ? "bg-ink text-bg" : "bg-surface hover:bg-surface-2")}
              >
                {t(`sort.${k}`)}
              </button>
            ))}
          </div>
          {photos.isSuccess && items.length === 0 ? <p className="py-12 text-ink-muted">{t("empty")}</p> : <JustifiedWall photos={items} target={320} />}
          <div ref={sentinel} className="h-px" />
        </section>
      )}
    </div>
  );
}

function GearSearch() {
  const t = useTranslations("gear");
  const [q, setQ] = useState("");
  const dq = useDebounced(q.trim());
  const res = useQuery({ queryKey: ["gear", "search", dq], enabled: dq.length >= 2, queryFn: () => api<GearName[]>(`gear/search?q=${encodeURIComponent(dq)}&limit=10`) });
  return (
    <div className="relative w-full sm:w-[340px]">
      <label className="flex h-11 items-center gap-2 rounded-full border border-line bg-surface px-4">
        <Camera className="h-4 w-4 shrink-0 text-ink-muted" aria-hidden />
        <input
          type="search"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder={t("search")}
          aria-label={t("search")}
          className="min-w-0 flex-1 bg-transparent text-[15px] outline-none placeholder:text-ink-muted"
        />
      </label>
      {dq.length >= 2 && res.data && (
        <ul className="absolute right-0 top-12 z-30 w-full overflow-hidden rounded-box bg-surface p-1.5 shadow-float">
          {res.data.length === 0 && <li className="px-3 py-2 text-sm text-ink-muted">{t("search_empty")}</li>}
          {res.data.map((g) => (
            <li key={`${g.kind}:${g.name}`}>
              <Link href={`/gear?${g.kind}=${encodeURIComponent(g.name)}`} onClick={() => setQ("")} className="flex items-center gap-2.5 rounded-[12px] px-3 py-2 hover:bg-surface-2">
                {g.kind === "lens" ? <Aperture className="h-4 w-4 shrink-0 text-ink-muted" aria-hidden /> : <Camera className="h-4 w-4 shrink-0 text-ink-muted" aria-hidden />}
                <span className="min-w-0 flex-1 truncate text-[14.5px]">{g.name}</span>
                <span className="tnum text-xs text-ink-muted">{g.photo_count}</span>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
