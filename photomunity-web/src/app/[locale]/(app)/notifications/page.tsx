"use client";

import { useInfiniteQuery, useQueryClient } from "@tanstack/react-query";
import { Image as ImageIcon } from "lucide-react";
import clsx from "clsx";
import { useLocale, useTranslations } from "next-intl";
import { useCallback, useEffect, useRef } from "react";
import { Avatar } from "@/components/Avatar";
import { Link, useRouter } from "@/i18n/navigation";
import { api } from "@/lib/api";
import { buttonClass } from "@/lib/button-class";
import { useLoadMore, useMe } from "@/lib/hooks";
import { relativeTime } from "@/lib/relative-time";
import type { AppNotification, NotificationPage } from "@/lib/types";

function target(n: AppNotification) {
  // Mesaj isteği: istekler klasöründeki sohbete gider
  if (n.type === "message_request" && n.data.conversation_id) return `/messages/${n.data.conversation_id}?folder=requests`;
  // Yönetim duyurusu kendi uygulama içi yolunu taşır
  if (typeof n.data.link === "string" && n.data.link.startsWith("/")) return n.data.link;
  if (n.data.contest_id) return `/contests/${n.data.contest_id}`;
  if (n.data.community_slug) return `/c/${n.data.community_slug}`;
  if (n.photo) return `/p/${n.photo.id}`;
  if (n.actor) return `/u/${n.actor.username}`;
  return "/feed";
}

export default function NotificationsPage() {
  const t = useTranslations("notifications");
  const locale = useLocale();
  const router = useRouter();
  const qc = useQueryClient();
  const { data: me, isLoading } = useMe();
  const marked = useRef(false);

  const q = useInfiniteQuery({
    queryKey: ["notifications", "list"],
    enabled: !!me,
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) => api<NotificationPage>(pageParam ? `notifications?before=${encodeURIComponent(pageParam)}` : "notifications"),
    getNextPageParam: (last) => last.next_cursor,
  });
  const { fetchNextPage, hasNextPage, isFetchingNextPage } = q;
  const loadMore = useCallback(() => !isFetchingNextPage && fetchNextPage(), [fetchNextPage, isFetchingNextPage]);
  const sentinel = useLoadMore(loadMore, !!hasNextPage);

  useEffect(() => {
    if (!isLoading && !me) router.replace("/login");
  }, [me, isLoading, router]);

  // Sayfa açıldığında okunmamışlar okundu sayılır; listede vurgu bu ziyaret boyunca kalır
  useEffect(() => {
    if (q.isSuccess && !marked.current && (q.data.pages[0]?.unread_count ?? 0) > 0) {
      marked.current = true;
      api("notifications/read", { method: "POST", body: {} }).then(() =>
        qc.setQueryData(["notifications", "unread"], { count: 0 }),
      );
    }
  }, [q.isSuccess, q.data, qc]);

  const items = q.data?.pages.flatMap((p) => p.items) ?? [];

  return (
    <div className="mx-auto max-w-[680px] px-4 pt-8 sm:pt-12">
      <h1 className="text-[clamp(2rem,4.5vw,3rem)] font-bold leading-none tracking-[-0.04em]">{t("title")}</h1>
      {q.isSuccess && items.length === 0 && <p className="mt-8 text-ink-muted">{t("empty")}</p>}
      <ul className="mt-8 divide-y divide-line overflow-hidden rounded-card bg-surface">
        {items.map((n) => (
          <li key={n.id}>
            <Link href={target(n)} className={clsx("flex items-center gap-3.5 py-3.5 pr-1", !n.read && "bg-accent/[0.06]")}>
              <span className="relative pl-4">
                {!n.read && <span aria-hidden className="absolute left-1.5 top-1/2 h-1.5 w-1.5 -translate-y-1/2 rounded-full bg-accent" />}
                {n.actor ? (
                  <Avatar name={n.actor.display_name} url={n.actor.avatar_url} size={40} />
                ) : (
                  <span className="inline-flex h-10 w-10 items-center justify-center rounded-full bg-ink text-surface" aria-hidden>
                    <ImageIcon className="h-[18px] w-[18px]" />
                  </span>
                )}
              </span>
              <span className="min-w-0 flex-1">
                <span className="block text-[15px] leading-snug">{n.text}</span>
                {n.type === "message_request" && n.data.preview && (
                  <span className="mt-0.5 block truncate text-[14px] text-ink-muted">“{n.data.preview}”</span>
                )}
                <span className="mt-0.5 block text-[13px] text-ink-muted">{relativeTime(n.created_at, locale)}</span>
              </span>
              {n.type === "message_request" && n.data.conversation_id && (
                // Satırın tamamı bağlantı; bu yalnızca görsel düğme
                <span className={buttonClass("primary", "mr-3 h-9 min-h-9 shrink-0 px-4 text-[14px]")}>{t("view")}</span>
              )}
              {n.photo?.thumb_url && (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={n.photo.thumb_url} alt="" className="h-12 w-12 shrink-0 object-cover" />
              )}
            </Link>
          </li>
        ))}
      </ul>
      <div ref={sentinel} className="h-px" />
    </div>
  );
}
