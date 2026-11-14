"use client";

import { useLocale } from "next-intl";
import { Link } from "@/i18n/navigation";
import { formatDate } from "@/lib/format";
import type { PhotoCard } from "@/lib/types";
import { Avatar } from "./Avatar";
import { LikeButton } from "./LikeButton";

/** Akıştaki tek kare: paspartulu bir baskı gibi, kırpılmadan. */
export function PhotoPrint({ photo }: { photo: PhotoCard }) {
  const locale = useLocale();
  const img = photo.images.feed ?? photo.images.full;
  return (
    <article className="bg-mat">
      <header className="flex items-center gap-3 px-4 py-3 sm:px-5">
        <Link href={`/u/${photo.user.username}`} className="flex min-w-0 items-center gap-3">
          <Avatar name={photo.user.display_name} url={photo.user.avatar_url} size={36} />
          <span className="min-w-0">
            <span className="block truncate text-[15px] font-semibold">{photo.user.display_name}</span>
            <span className="block truncate text-[13px] text-muted">@{photo.user.username}</span>
          </span>
        </Link>
      </header>
      <Link href={`/p/${photo.id}`} className="block px-3 sm:px-5">
        {img && (
          <span className="print-placeholder block" style={{ aspectRatio: `${img.width} / ${img.height}` }}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={img.url} alt={photo.title ?? ""} loading="lazy" decoding="async" className="fade-in block h-full w-full" />
          </span>
        )}
      </Link>
      <footer className="flex items-center justify-between gap-3 px-2 py-2 sm:px-3">
        <LikeButton id={photo.id} liked={photo.liked_by_me} count={photo.like_count} />
        <span className="flex min-w-0 items-baseline gap-2.5 px-2 text-[13px]">
          {photo.title && <span className="truncate font-medium">{photo.title}</span>}
          <span className="shrink-0 text-muted">{formatDate(photo.published_at, locale)}</span>
        </span>
      </footer>
    </article>
  );
}
