"use client";

import { MessageCircle } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { Link } from "@/i18n/navigation";
import { relativeTime } from "@/lib/relative-time";
import type { PhotoCard as PhotoCardData } from "@/lib/types";
import { Avatar } from "./Avatar";
import { ExifChips } from "./ExifChip";
import { FollowButton } from "./FollowButton";
import { LikeButton } from "./LikeButton";
import { ShareButton } from "./ShareButton";

/** Yazarın takip durumu akış yanıtında yok; gelirse Takip et yalnızca takip edilmeyende görünür. */
type CardPhoto = PhotoCardData & { user: PhotoCardData["user"] & { is_following?: boolean } };

/**
 * Akıştaki tek fotoğraf: yazar, kırpılmamış kare, beğeni, yorum ve çekim bilgisi; varsa son yorum tek satır.
 * Kart surface, radius-card, iç boşluk space-3; gölge yok. Fotoğraf kendi oranında, radius-photo.
 */
export function PhotoCard({ photo, meId }: { photo: CardPhoto; meId?: string }) {
  const locale = useLocale();
  const t = useTranslations("photo");
  const img = photo.images.feed ?? photo.images.full;
  const when = photo.published_at ? relativeTime(photo.published_at, locale) : null;
  const meta = [photo.place, when].filter(Boolean).join(", ");
  const showFollow = photo.user.is_following === false && photo.user.id !== meId;

  return (
    <article className="rounded-card bg-surface p-3 sm:p-3.5">
      <header className="flex items-center gap-3 px-1 pb-3 pt-0.5">
        <Link href={`/u/${photo.user.username}`} className="flex min-w-0 flex-1 items-center gap-3 rounded-box">
          <Avatar name={photo.user.display_name} url={photo.user.avatar_url} size={40} />
          <span className="flex min-w-0 flex-col">
            <span className="truncate text-[16px] font-semibold leading-[21px]">{photo.user.display_name}</span>
            {meta && <span className="truncate text-[13px] leading-[17px] text-ink-muted">{meta}</span>}
          </span>
        </Link>
        {showFollow && <FollowButton username={photo.user.username} following={false} size="sm" />}
      </header>
      <Link href={`/p/${photo.id}`} className="block rounded-photo" aria-label={photo.title ?? t("open_photo")}>
        {img && (
          <span
            className="print-placeholder block overflow-hidden rounded-photo"
            style={{ aspectRatio: `${img.width} / ${img.height}` }}
          >
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={img.url} alt={photo.title ?? ""} loading="lazy" decoding="async" className="fade-in block h-full w-full" />
          </span>
        )}
      </Link>
      <footer className="flex flex-wrap items-center gap-2 px-1 pb-0.5 pt-3">
        <LikeButton id={photo.id} liked={photo.liked_by_me} count={photo.like_count} />
        {!photo.comments_off && (
          <Link
            href={`/p/${photo.id}#comments`}
            aria-label={t("comments_count", { count: photo.comment_count ?? 0 })}
            className="inline-flex h-[38px] items-center justify-center gap-1.5 rounded-pill bg-surface-2 px-3.5 text-[14.5px] font-semibold text-ink transition-colors hover:bg-line"
          >
            <MessageCircle className="h-[19px] w-[19px]" strokeWidth={1.9} aria-hidden />
            <span className="tnum">{photo.comment_count ?? 0}</span>
          </Link>
        )}
        <ShareButton url={`/${locale}/p/${photo.id}`} title={photo.title ?? undefined} />
        <span className="flex-1" />
        <ExifChips exif={photo.exif} locale={locale} />
      </footer>
      {!photo.comments_off && photo.last_comment && (
        <div className="px-1 pb-0.5 pt-2.5 text-[14.5px] leading-[20px]">
          <Link href={`/p/${photo.id}#comments`} className="block truncate">
            <span className="font-semibold">{photo.last_comment.username}</span>{" "}
            <span>{photo.last_comment.body}</span>
          </Link>
          {photo.comment_count > 1 && (
            <Link href={`/p/${photo.id}#comments`} className="mt-0.5 inline-block text-ink-muted hover:text-ink">
              {t("view_all_comments", { count: photo.comment_count })}
            </Link>
          )}
        </div>
      )}
    </article>
  );
}
