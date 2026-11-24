"use client";

import { useQuery } from "@tanstack/react-query";
import clsx from "clsx";
import { useTranslations } from "next-intl";
import { useSearchParams } from "next/navigation";
import { Suspense, useCallback } from "react";
import { Map as MapIcon } from "lucide-react";
import { AdSlot } from "@/components/AdSlot";
import { ContestMini } from "@/components/community";
import { JustifiedWall } from "@/components/JustifiedWall";
import { ThemeBanner } from "@/components/themes";
import { buttonClass } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { api } from "@/lib/api";
import { useLoadMore, usePhotoPages } from "@/lib/hooks";
import type { ContestCard } from "@/lib/types";
import { HowItWorks } from "@/components/intro";

export default function ExplorePage() {
  return (
    <Suspense>
      <Explore />
    </Suspense>
  );
}

function Explore() {
  const t = useTranslations("explore");
  const tf = useTranslations("feed");
  // ?tab=critique: "Eleştiri bekleyenler" akışı (Revizyon 7)
  const tab = useSearchParams().get("tab") === "critique" ? "critique" : "for_you";
  const q = usePhotoPages(tab === "critique" ? ["critique-requests"] : ["explore"], tab === "critique" ? "critiques/requests" : "explore", true, tab === "critique" ? "cursor" : "before");
  const live = useQuery({
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
  const { fetchNextPage, hasNextPage, isFetchingNextPage } = q;
  const loadMore = useCallback(() => !isFetchingNextPage && fetchNextPage(), [fetchNextPage, isFetchingNextPage]);
  const sentinel = useLoadMore(loadMore, !!hasNextPage);
  const items = q.data?.pages.flatMap((p) => p.items) ?? [];
  const contests = live.data ?? [];

  return (
    <div className="mx-auto max-w-[1440px] px-3 sm:px-6 lg:px-10">
      <div className="flex flex-wrap items-end justify-between gap-4 pb-6 pt-2 sm:pt-4">
        <div>
          <h1 className="flex items-center gap-3 text-[34px] font-bold leading-none tracking-[-0.04em] sm:text-[44px]">{t("title")} <HowItWorks module="explore" auto={tab !== "critique"} /></h1>
          <p className="mt-3 max-w-[56ch] text-ink-muted">{t("lead")}</p>
        </div>
        <Link href="/map" className={buttonClass("secondary", "bg-surface hover:bg-surface-2")}>
          <MapIcon className="h-[18px] w-[18px]" strokeWidth={1.8} aria-hidden /> {t("open_map")}
        </Link>
      </div>

      <ThemeBanner className="mb-8" />

      {contests.length > 0 && (
        <section aria-labelledby="live" className="pb-8">
          <div className="mb-3 flex items-center justify-between">
            <h2 id="live" className="text-heading">{tf("live_contests")}</h2>
            <Link href="/contests" className="inline-flex min-h-11 items-center text-[14.5px] font-semibold text-accent-text hover:underline">
              {tf("all_contests")}
            </Link>
          </div>
          <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
            {contests.slice(0, 3).map((c) => (
              <div key={c.id} className="rounded-card bg-surface p-2.5">
                <ContestMini c={c} />
              </div>
            ))}
          </div>
        </section>
      )}

      <section aria-label={tab === "critique" ? t("critique_tab") : t("for_you")}>
        <nav className="mb-4 flex gap-2" aria-label={t("tabs")}>
          {(["for_you", "critique"] as const).map((k) => (
            <Link
              key={k}
              href={k === "for_you" ? "/explore" : "/explore?tab=critique"}
              scroll={false}
              aria-current={tab === k ? "page" : undefined}
              className={clsx("inline-flex h-10 items-center rounded-pill px-4 text-[15px] font-semibold", tab === k ? "bg-ink text-bg" : "bg-surface hover:bg-surface-2")}
            >
              {k === "for_you" ? t("for_you") : t("critique_tab")}
            </Link>
          ))}
        </nav>
        {tab === "critique" && (
          <p className="mb-4 flex max-w-[60ch] items-start gap-2 text-sm text-ink-muted">{t("critique_lead")} <HowItWorks module="critique" /></p>
        )}
        {q.isSuccess && items.length === 0 ? <p className="py-16 text-ink-muted">{tab === "critique" ? t("critique_empty") : t("empty")}</p> : <JustifiedWall photos={items} />}
      </section>
      <div className="mt-6"><AdSlot kind="banner" /></div>
      <div ref={sentinel} className="h-px" />
      {isFetchingNextPage && <p className="py-8 text-center text-sm text-ink-muted">{t("loading")}</p>}
    </div>
  );
}
