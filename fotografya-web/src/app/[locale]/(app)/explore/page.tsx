"use client";

import { useTranslations } from "next-intl";
import { useCallback } from "react";
import { Map as MapIcon } from "lucide-react";
import { AdSlot } from "@/components/AdSlot";
import { JustifiedWall } from "@/components/JustifiedWall";
import { buttonClass } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { useLoadMore, usePhotoPages } from "@/lib/hooks";

export default function ExplorePage() {
  const t = useTranslations("explore");
  const q = usePhotoPages(["explore"], "explore");
  const { fetchNextPage, hasNextPage, isFetchingNextPage } = q;
  const loadMore = useCallback(() => !isFetchingNextPage && fetchNextPage(), [fetchNextPage, isFetchingNextPage]);
  const sentinel = useLoadMore(loadMore, !!hasNextPage);
  const items = q.data?.pages.flatMap((p) => p.items) ?? [];

  return (
    <div>
      <div className="mx-auto max-w-[1400px] px-4 pb-6 pt-8 sm:px-6 sm:pt-12">
        <h1 className="text-[clamp(2rem,4.5vw,3.2rem)] font-bold leading-none tracking-[-0.04em]">{t("title")}</h1>
        <div className="mt-3 flex flex-wrap items-center justify-between gap-4">
          <p className="max-w-[56ch] text-muted">{t("lead")}</p>
          <Link href="/map" className={buttonClass("secondary")}><MapIcon className="h-4 w-4" /> {t("open_map")}</Link>
        </div>
      </div>
      <div className="px-1.5">
        {q.isSuccess && items.length === 0 ? (
          <p className="mx-auto max-w-[1400px] px-3 py-16 text-muted sm:px-5">{t("empty")}</p>
        ) : (
          <JustifiedWall photos={items} />
        )}
      </div>
      <div className="mx-auto mt-6 max-w-[1400px] px-1.5"><AdSlot kind="banner" /></div>
      <div ref={sentinel} className="h-px" />
      {isFetchingNextPage && <p className="py-8 text-center text-sm text-muted">{t("loading")}</p>}
    </div>
  );
}
