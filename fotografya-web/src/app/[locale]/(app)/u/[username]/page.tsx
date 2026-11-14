"use client";

import { useQuery } from "@tanstack/react-query";
import { Lock, MapPin, MessageCircle } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useParams } from "next/navigation";
import { useCallback } from "react";
import { Avatar } from "@/components/Avatar";
import { FollowButton } from "@/components/FollowButton";
import { JustifiedWall } from "@/components/JustifiedWall";
import { ReportButton } from "@/components/ReportDialog";
import { ProBadge } from "@/components/AdSlot";
import { BlockButton } from "@/components/BlockButton";
import { Notice, buttonClass } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import { countryName } from "@/lib/format";
import { useLoadMore, usePhotoPages } from "@/lib/hooks";
import type { Equipment, Profile } from "@/lib/types";

const KIT_ORDER: Equipment["type"][] = ["body", "lens", "drone", "flash", "tripod", "filter", "other"];

export default function ProfilePage() {
  const { username } = useParams<{ username: string }>();
  const t = useTranslations("profile");
  const te = useTranslations("equipment");
  const ts = useTranslations("specialties");
  const locale = useLocale();

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
    <div>
      {p.cover_url && (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={p.cover_url} alt="" className="block aspect-[3/1] max-h-[360px] w-full object-cover" />
      )}
      <section className="mx-auto max-w-[1400px] px-4 pb-10 pt-10 sm:px-6 sm:pt-14">
        <div className="grid gap-10 lg:grid-cols-[minmax(0,1fr)_380px]">
          <div className="min-w-0">
            <div className="flex items-start gap-5">
              <Avatar name={p.display_name} url={p.avatar_url} size={88} className="text-[32px]" />
              <div className="min-w-0 pt-1">
                <h1 className="flex flex-wrap items-center gap-3 text-[clamp(1.8rem,4vw,2.8rem)] font-bold leading-none tracking-[-0.04em]">
                  {p.display_name}
                  {p.is_pro && <ProBadge />}
                </h1>
                <p className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-[15px] text-ink-muted">
                  <span>@{p.username}</span>
                  {!p.is_public && (
                    <span className="inline-flex items-center gap-1">
                      <Lock className="h-3.5 w-3.5" /> {t("private")}
                    </span>
                  )}
                  {place && (
                    <span className="inline-flex items-center gap-1">
                      <MapPin className="h-3.5 w-3.5" /> {place}
                    </span>
                  )}
                </p>
              </div>
            </div>

            {p.bio && <p className="mt-6 max-w-[60ch] whitespace-pre-line text-[16px] leading-relaxed">{p.bio}</p>}
            {p.website && (
              <a href={p.website} target="_blank" rel="noreferrer nofollow" className="mt-3 inline-block text-[15px] font-medium underline underline-offset-4">
                {p.website.replace(/^https?:\/\//, "")}
              </a>
            )}
            {p.specialties.length > 0 && (
              <ul className="mt-5 flex flex-wrap gap-2">
                {p.specialties.map((s) => (
                  <li key={s} className="rounded-full bg-ink/[0.06] px-3 py-1 text-sm">
                    {ts.has(s) ? ts(s) : s}
                  </li>
                ))}
              </ul>
            )}

            <div className="mt-7 flex flex-wrap items-center gap-x-8 gap-y-4">
              <dl className="flex gap-7">
                {stats.map((s) => (
                  <div key={s.label} className="flex flex-col-reverse">
                    <dt className="text-sm text-ink-muted">{s.label}</dt>
                    <dd className="tnum text-xl font-semibold">{s.n}</dd>
                  </div>
                ))}
              </dl>
              {p.is_me ? (
                <Link href="/settings" className={buttonClass("secondary")}>
                  {t("edit_profile")}
                </Link>
              ) : (
                <>
                  <FollowButton profile={p} />
                  {p.is_public && (
                    <Link href={`/messages/new?to=${p.username}`} className={buttonClass("secondary")}>
                      <MessageCircle className="h-4 w-4" /> {t("message")}
                    </Link>
                  )}
                  <ReportButton targetType="user" targetId={p.id} />
                  <BlockButton username={p.username} name={p.display_name} />
                </>
              )}
            </div>
          </div>

          {kit.length > 0 && (
            <aside aria-labelledby="kit" className="self-start bg-surface px-5 py-5">
              <h2 id="kit" className="text-[15px] font-semibold">
                {t("kit")}
              </h2>
              <ul className="mt-3 divide-y divide-line">
                {kit.map((e) => (
                  <li key={e.id} className="flex items-baseline justify-between gap-4 py-2.5">
                    <span className="min-w-0 truncate text-[15px]">
                      {e.brand} {e.model}
                    </span>
                    <span className="shrink-0 text-[13px] text-ink-muted">{te(e.type)}</span>
                  </li>
                ))}
              </ul>
            </aside>
          )}
        </div>
      </section>

      <section aria-label={t("photos")} className="px-1.5">
        {!canView ? (
          <div className="mx-auto max-w-[1400px] px-3 sm:px-5">
            <div className="bg-surface px-6 py-14">
              <Lock className="h-6 w-6" />
              <h2 className="mt-4 text-xl font-semibold tracking-[-0.02em]">{t("private_title")}</h2>
              <p className="mt-1.5 text-ink-muted">{t("private_body")}</p>
            </div>
          </div>
        ) : photos.isSuccess && items.length === 0 ? (
          <div className="mx-auto max-w-[1400px] px-3 sm:px-5">
            <div className="bg-surface px-6 py-14">
              <p className="text-ink-muted">{p.is_me ? t("empty_me") : t("empty")}</p>
              {p.is_me && (
                <Link href="/upload" className={buttonClass("primary", "mt-5")}>
                  {t("upload_first")}
                </Link>
              )}
            </div>
          </div>
        ) : (
          <JustifiedWall photos={items} target={280} />
        )}
        <div ref={sentinel} className="h-px" />
      </section>
    </div>
  );
}
