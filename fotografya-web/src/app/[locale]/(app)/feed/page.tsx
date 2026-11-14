"use client";

import { useTranslations } from "next-intl";
import { useCallback, useEffect } from "react";
import { Fragment } from "react";
import { AdSlot } from "@/components/AdSlot";
import { PhotoPrint } from "@/components/PhotoPrint";
import { buttonClass } from "@/components/ui";
import { Link, useRouter } from "@/i18n/navigation";
import { useLoadMore, useMe, usePhotoPages } from "@/lib/hooks";

export default function FeedPage() {
  const t = useTranslations("feed");
  const router = useRouter();
  const { data: me, isLoading: meLoading } = useMe();
  const feed = usePhotoPages(["feed"], "feed", !!me);
  const { fetchNextPage, hasNextPage, isFetchingNextPage } = feed;
  const loadMore = useCallback(() => !isFetchingNextPage && fetchNextPage(), [fetchNextPage, isFetchingNextPage]);
  const sentinel = useLoadMore(loadMore, !!hasNextPage);

  useEffect(() => {
    if (!meLoading && !me) router.replace("/login");
  }, [me, meLoading, router]);

  const items = feed.data?.pages.flatMap((p) => p.items) ?? [];

  return (
    <div className="mx-auto max-w-[680px] px-0 pt-6 sm:px-4 sm:pt-10">
      <h1 className="sr-only">{t("title")}</h1>
      {feed.isSuccess && items.length === 0 && (
        <div className="mx-4 bg-mat px-6 py-12 sm:mx-0">
          <h2 className="text-2xl font-semibold tracking-[-0.02em]">{t("empty_title")}</h2>
          <p className="mt-2 max-w-[44ch] leading-relaxed text-muted">{t("empty_body")}</p>
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
      <div className="flex flex-col gap-6 sm:gap-10">
        {items.map((photo, i) => (
          <Fragment key={photo.id}>
            <PhotoPrint photo={photo} />
            {(i + 1) % 8 === 0 && <AdSlot kind="feed" />}
          </Fragment>
        ))}
      </div>
      <div ref={sentinel} className="h-px" />
      {isFetchingNextPage && <p className="py-8 text-center text-sm text-muted">{t("loading")}</p>}
    </div>
  );
}
