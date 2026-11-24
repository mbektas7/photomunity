"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { Fragment, useCallback, useEffect } from "react";
import { AdSlot } from "@/components/AdSlot";
import { useShortRemaining } from "@/components/Countdown";
import { ContestMini } from "@/components/community";
import { HomeBanner } from "@/components/HomeBanner";
import { ProfileCompleteCard } from "@/components/Onboarding";
import { PhotoCard } from "@/components/PhotoCard";
import { Sidebar } from "@/components/Shell";
import { StoryRing } from "@/components/StoryRing";
import { ThemeBanner } from "@/components/themes";
import { buttonClass } from "@/components/ui";
import { Link, useRouter } from "@/i18n/navigation";
import { api } from "@/lib/api";
import { useLoadMore, useMe, usePhotoPages } from "@/lib/hooks";
import type { CommunityCard, ContestCard } from "@/lib/types";

/** Açık (katılım) ve oylamadaki yarışmalar; en yakın bitişe göre. */
function useLiveContests() {
  return useQuery({
    queryKey: ["contests", "live"],
    queryFn: async () => {
      const [open, judging] = await Promise.all([
        api<ContestCard[]>("contests?status=open&limit=10"),
        api<ContestCard[]>("contests?status=judging&limit=10"),
      ]);
      const end = (c: ContestCard) => new Date(c.status === "open" ? c.submission_deadline : c.voting_end).getTime();
      return [...judging, ...open].sort((a, b) => end(a) - end(b));
    },
    staleTime: 60_000,
  });
}

function ContestStory({ c }: { c: ContestCard }) {
  const t = useTranslations("feed");
  const left = useShortRemaining(c.status === "open" ? c.submission_deadline : c.voting_end);
  return (
    <StoryRing
      href={`/contests/${c.id}`}
      label={c.title}
      image={c.community.logo_url}
      state="live"
      badge={left?.short}
      ariaLabel={left ? t("contest_left", { title: c.title, time: left.left }) : c.title}
    />
  );
}

/**
 * Hikâye halkaları. "Görülmemiş içerik" bilgisi API'de yok (README → Veri gereksinimleri):
 * açık yarışmalar live, üye olunan topluluklar accent halkayla gösterilir.
 */
function Stories({ contests }: { contests: ContestCard[] }) {
  const t = useTranslations("feed");
  const mine = useQuery({
    queryKey: ["communities", "mine"],
    queryFn: () => api<CommunityCard[]>("communities?mine=true&limit=30"),
    staleTime: 60_000,
  });
  const communities = mine.data ?? [];
  if (!contests.length && !communities.length) return null;
  return (
    <nav aria-label={t("stories")} className="no-scrollbar -mx-4 flex gap-2 overflow-x-auto px-4 pb-1.5 pt-1 sm:mx-0 sm:px-0">
      {contests.slice(0, 6).map((c) => (
        <ContestStory key={c.id} c={c} />
      ))}
      {communities.map((c) => (
        <StoryRing key={c.id} href={`/c/${c.slug}`} label={c.name} image={c.logo_url} state="accent" />
      ))}
    </nav>
  );
}

export default function FeedPage() {
  const t = useTranslations("feed");
  const router = useRouter();
  const { data: me, isLoading: meLoading } = useMe();
  const feed = usePhotoPages(["feed"], "feed", !!me);
  const live = useLiveContests();
  const { fetchNextPage, hasNextPage, isFetchingNextPage } = feed;
  const loadMore = useCallback(() => !isFetchingNextPage && fetchNextPage(), [fetchNextPage, isFetchingNextPage]);
  const sentinel = useLoadMore(loadMore, !!hasNextPage);

  useEffect(() => {
    if (!meLoading && !me) router.replace("/login");
  }, [me, meLoading, router]);

  const items = feed.data?.pages.flatMap((p) => p.items) ?? [];
  const contests = live.data ?? [];

  return (
    <div className="mx-auto flex max-w-[1440px] items-start gap-8 px-3 pt-2 sm:px-6 md:pt-6">
      <Sidebar />
      <div className="flex min-w-0 max-w-[660px] flex-[999_1_560px] flex-col gap-[18px]">
        <h1 className="sr-only">{t("title")}</h1>
        <Stories contests={contests} />
        {me && !me.onboarding_done && <ProfileCompleteCard me={me} />}
        <HomeBanner />
        <ThemeBanner />
        {feed.isSuccess && items.length === 0 && (
          <div className="rounded-card bg-surface px-6 py-12">
            <h2 className="text-title">{t("empty_title")}</h2>
            <p className="mt-2 max-w-[44ch] text-ink-muted">{t("empty_body")}</p>
            <div className="mt-6 flex flex-wrap gap-3">
              <Link href="/explore" className={buttonClass("primary")}>
                {t("go_explore")}
              </Link>
              <Link href="/upload" className={buttonClass("secondary")}>
                {t("upload_first")}
              </Link>
            </div>
          </div>
        )}
        {items.map((photo, i) => (
          <Fragment key={photo.id}>
            <PhotoCard photo={photo} meId={me?.id} />
            {(i + 1) % 8 === 0 && <AdSlot kind="feed" />}
          </Fragment>
        ))}
        <div ref={sentinel} className="h-px" />
        {isFetchingNextPage && <p className="py-8 text-center text-sm text-ink-muted">{t("loading")}</p>}
      </div>
      {contests.length > 0 && (
        <aside className="sticky top-6 hidden max-w-[360px] flex-[1_1_300px] flex-col gap-5 xl:flex">
          <section aria-labelledby="live-contests" className="flex flex-col gap-3 rounded-card bg-surface p-5">
            <h2 id="live-contests" className="mb-1 text-heading">
              {t("live_contests")}
            </h2>
            {contests.slice(0, 3).map((c) => (
              <ContestMini key={c.id} c={c} />
            ))}
            <Link href="/contests" className="self-start rounded-box px-0.5 pt-1 text-[14px] font-semibold text-accent-text hover:underline">
              {t("all_contests")}
            </Link>
          </section>
        </aside>
      )}
    </div>
  );
}
