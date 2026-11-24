"use client";

import { useQuery } from "@tanstack/react-query";
import clsx from "clsx";
import { Lock, MapPin, MessageCircle, MoreVertical } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useParams, useSearchParams } from "next/navigation";
import { useCallback } from "react";
import { Avatar } from "@/components/Avatar";
import { ExifChip } from "@/components/ExifChip";
import { FollowButton } from "@/components/FollowButton";
import { ShareButton } from "@/components/ShareButton";
import { JustifiedWall } from "@/components/JustifiedWall";
import { ReportButton } from "@/components/ReportDialog";
import { ProBadge } from "@/components/AdSlot";
import { BlockButton } from "@/components/BlockButton";
import { ProfileCollections } from "@/components/collections";
import { ThemeWinsBadge } from "@/components/themes";
import { Notice, buttonClass } from "@/components/ui";
import { Link, usePathname } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import { countryName } from "@/lib/format";
import { useLoadMore, usePhotoPages } from "@/lib/hooks";
import type { Equipment, Profile } from "@/lib/types";
import { HowItWorks } from "@/components/intro";

const KIT_ORDER: Equipment["type"][] = ["body", "lens", "drone", "flash", "tripod", "filter", "other"];

export default function ProfilePage() {
  const { username } = useParams<{ username: string }>();
  const t = useTranslations("profile");
  const te = useTranslations("equipment");
  const ts = useTranslations("specialties");
  const tu = useTranslations("ui");
  const locale = useLocale();

  const tc = useTranslations("collections");
  const pathname = usePathname();
  const tab = useSearchParams().get("tab") === "collections" ? "collections" : "photos";
  const profile = useQuery({ queryKey: ["profile", username], queryFn: () => api<Profile>(`users/${username}`) });
  const canView = !!profile.data?.can_view_photos;
  const photos = usePhotoPages(["photos", "user", username], `users/${username}/photos`, canView);
  const { fetchNextPage, hasNextPage, isFetchingNextPage } = photos;
  const loadMore = useCallback(() => !isFetchingNextPage && fetchNextPage(), [fetchNextPage, isFetchingNextPage]);
  const sentinel = useLoadMore(loadMore, !!hasNextPage);

  if (profile.error) {
    return (
      <div className="mx-auto max-w-[680px] px-4 py-20">
        <Notice tone="error">{profile.error instanceof ApiError ? profile.error.message : t("not_found")}</Notice>
      </div>
    );
  }
  const p = profile.data;
  if (!p) return <div className="h-[60vh]" aria-busy />;

  const place = [p.city, countryName(p.country, locale)].filter(Boolean).join(", ");
  const kit = [...p.equipment].sort((a, b) => KIT_ORDER.indexOf(a.type) - KIT_ORDER.indexOf(b.type));
  const items = photos.data?.pages.flatMap((pg) => pg.items) ?? [];
  const stats = [
    { n: p.photos_count, label: t("photos") },
    { n: p.followers_count, label: t("followers") },
    { n: p.following_count, label: t("following") },
  ];

  return (
    <div className="mx-auto max-w-[1440px] px-3 pb-16 sm:px-6 lg:px-10">
      <section className="flex flex-col gap-6 rounded-card bg-surface p-5 sm:rounded-[28px] sm:p-8 lg:flex-row lg:flex-wrap lg:gap-8">
        {p.cover_url && (
          // Kapak bir afiş görseli; kartın üstünde şerit olarak durur.
          // eslint-disable-next-line @next/next/no-img-element
          <img src={p.cover_url} alt="" className="block aspect-[4/1] max-h-[260px] w-full rounded-photo object-cover lg:basis-full" />
        )}
        <div className="flex min-w-0 flex-[1_1_420px] flex-col gap-5 sm:flex-row sm:gap-8">
          <Avatar name={p.display_name} url={p.avatar_url} size={132} className="border-[3px] border-accent-tint text-[44px] max-sm:!h-[100px] max-sm:!w-[100px]" />
          <div className="flex min-w-0 flex-1 flex-col gap-3.5">
            <h1 className="flex flex-wrap items-center gap-3 text-[34px] font-bold leading-none tracking-[-0.04em] sm:text-[44px]">
              {p.display_name}
              {p.is_pro && <ProBadge />}
              {p.is_me && <HowItWorks module="profile" />}
            </h1>
            {!!p.theme_wins && <ThemeWinsBadge username={p.username} count={p.theme_wins} />}
            <p className="flex flex-wrap items-center gap-x-4 gap-y-1 text-[15px] text-ink-muted">
              <span>@{p.username}</span>
              {!p.is_public && (
                <span className="inline-flex items-center gap-1.5">
                  <Lock className="h-4 w-4" strokeWidth={1.8} aria-hidden /> {t("private")}
                </span>
              )}
              {place && (
                <span className="inline-flex items-center gap-1.5">
                  <MapPin className="h-4 w-4" strokeWidth={1.8} aria-hidden /> {place}
                </span>
              )}
            </p>
            {p.bio && <p className="max-w-[620px] whitespace-pre-line text-[16px] leading-[1.55]">{p.bio}</p>}
            {p.website && (
              <a href={p.website} target="_blank" rel="noreferrer nofollow" className="self-start text-[15px] font-semibold text-accent-text hover:underline">
                {p.website.replace(/^https?:\/\//, "")}
              </a>
            )}
            {p.specialties.length > 0 && (
              <ul className="flex flex-wrap gap-1.5">
                {p.specialties.map((s) => (
                  <li key={s}>
                    <ExifChip>{ts.has(s) ? ts(s) : s}</ExifChip>
                  </li>
                ))}
              </ul>
            )}
            <div className="flex flex-wrap items-center gap-2.5 pt-1">
              {p.is_me ? (
                <Link href="/settings" className={buttonClass("secondary")}>
                  {t("edit_profile")}
                </Link>
              ) : (
                <>
                  <FollowButton profile={p} />
                  {p.is_public && (
                    <Link href={`/messages/new?to=${p.username}`} className={buttonClass("secondary")}>
                      <MessageCircle className="h-[19px] w-[19px]" strokeWidth={1.8} aria-hidden /> {t("message")}
                    </Link>
                  )}
                </>
              )}
              <ShareButton title={p.display_name} size={46} />
              {!p.is_me && (
                <details className="relative">
                  <summary
                    aria-label={tu("more")}
                    className="flex h-[46px] w-[46px] cursor-pointer list-none items-center justify-center rounded-full bg-surface-2 hover:bg-line [&::-webkit-details-marker]:hidden"
                  >
                    <MoreVertical className="h-5 w-5" strokeWidth={1.8} aria-hidden />
                  </summary>
                  <div className="absolute left-0 top-14 z-20 flex w-56 flex-col rounded-box bg-surface p-1.5 shadow-float">
                    <ReportButton targetType="user" targetId={p.id} />
                    <BlockButton username={p.username} name={p.display_name} />
                  </div>
                </details>
              )}
            </div>
          </div>
        </div>

        <div className="flex flex-[0_1_300px] flex-col gap-3.5">
          <dl className="flex gap-2">
            {stats.map((s) => (
              <div key={s.label} className="flex flex-1 flex-col-reverse gap-0.5 rounded-box bg-surface-2 px-[18px] py-3 lg:flex-none">
                <dt className="text-caption text-ink-muted">{s.label.toLocaleLowerCase(locale)}</dt>
                <dd className="tnum text-[24px] font-bold tracking-[-0.03em]">{s.n.toLocaleString(locale)}</dd>
              </div>
            ))}
          </dl>
          {kit.length > 0 && (
            <div>
              <h2 className="mb-1 text-[14px] font-bold text-ink-muted">{t("kit")}</h2>
              <ul>
                {kit.map((e) => (
                  <li key={e.id} className="flex flex-col border-t border-line py-2.5">
                    <span className="text-[14.5px] font-semibold">
                      {e.brand} {e.model}
                    </span>
                    <span className="text-caption text-ink-muted">{te(e.type)}</span>
                  </li>
                ))}
              </ul>
            </div>
          )}
        </div>
      </section>

      <section aria-label={t("photos")} className="mt-6">
        <nav className="mb-4 flex gap-2" aria-label={t("sections")}>
          {([["photos", t("photos"), p.photos_count], ["collections", tc("title"), null]] as const).map(([key, label, n]) => (
            <Link
              key={key}
              href={key === "photos" ? pathname : `${pathname}?tab=collections`}
              scroll={false}
              aria-current={tab === key ? "page" : undefined}
              className={clsx(
                "inline-flex h-[42px] items-center gap-2 rounded-pill px-4 text-[15px] font-semibold",
                tab === key ? "bg-ink text-bg" : "bg-surface text-ink hover:bg-surface-2",
              )}
            >
              {label}
              {n != null && <span className="tnum text-[13px] opacity-70">{n}</span>}
            </Link>
          ))}
        </nav>
        {tab === "collections" ? (
          canView ? <ProfileCollections username={p.username} isMe={p.is_me} /> : (
            <div className="rounded-card bg-surface px-6 py-14">
              <Lock className="h-6 w-6" strokeWidth={1.8} aria-hidden />
              <h3 className="mt-4 text-heading">{t("private_title")}</h3>
              <p className="mt-1.5 text-ink-muted">{t("private_body")}</p>
            </div>
          )
        ) : !canView ? (
          <div className="rounded-card bg-surface px-6 py-14">
            <Lock className="h-6 w-6" strokeWidth={1.8} aria-hidden />
            <h3 className="mt-4 text-heading">{t("private_title")}</h3>
            <p className="mt-1.5 text-ink-muted">{t("private_body")}</p>
          </div>
        ) : photos.isSuccess && items.length === 0 ? (
          <div className="rounded-card bg-surface px-6 py-14">
            <p className="text-ink-muted">{p.is_me ? t("empty_me") : t("empty")}</p>
            {p.is_me && (
              <Link href="/upload" className={buttonClass("primary", "mt-5")}>
                {t("upload_first")}
              </Link>
            )}
          </div>
        ) : (
          <JustifiedWall photos={items} target={360} />
        )}
        {tab === "photos" && <div ref={sentinel} className="h-px" />}
      </section>
    </div>
  );
}
