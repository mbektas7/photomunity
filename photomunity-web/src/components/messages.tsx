"use client";

import { useQuery } from "@tanstack/react-query";
import clsx from "clsx";
import { ChevronRight, MessageCircle } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { Link, usePathname } from "@/i18n/navigation";
import { api } from "@/lib/api";
import { relativeTime } from "@/lib/relative-time";
import type { Conversation } from "@/lib/types";
import { Avatar } from "./Avatar";

export function useMessageUnread(enabled = true) {
  return useQuery({
    queryKey: ["messages-unread"],
    enabled,
    queryFn: () => api<{ inbox: number; requests: number }>("messages/unread-count"),
    refetchInterval: 60_000,
  });
}

export function MessagesLink() {
  const t = useTranslations("nav");
  const pathname = usePathname();
  const { data } = useMessageUnread();
  const count = (data?.inbox ?? 0) + (data?.requests ?? 0);
  return (
    <Link
      href="/messages"
      aria-current={pathname.startsWith("/messages") ? "page" : undefined}
      aria-label={count ? t("messages_unread", { count }) : t("messages")}
      className="relative inline-flex h-11 w-11 items-center justify-center rounded-full text-ink hover:bg-surface md:bg-surface md:hover:bg-surface-2"
    >
      <MessageCircle className="h-[21px] w-[21px]" strokeWidth={1.8} aria-hidden />
      {count > 0 && (
        <span className="tnum absolute -right-0.5 -top-0.5 inline-flex min-w-[20px] items-center justify-center rounded-full border-2 border-bg bg-accent px-1 text-[11px] font-bold leading-4 text-accent-ink">
          {count > 99 ? "99+" : count}
        </span>
      )}
    </Link>
  );
}

export function preview(c: Conversation, meId: string | undefined, t: (k: string) => string) {
  const m = c.last_message;
  if (!m) return "";
  const prefix = m.sender_id === meId ? `${t("you")}: ` : "";
  return prefix + (m.body ?? (m.photo || m.image ? `📷 ${t("photo")}` : m.gif ? "GIF" : m.location ? `📍 ${t("location")}` : t("removed")));
}

export function ConversationList({ folder, meId, activeId }: { folder: "inbox" | "requests"; meId?: string; activeId?: string }) {
  const t = useTranslations("messages");
  const locale = useLocale();
  const q = useQuery({
    queryKey: ["conversations", folder],
    queryFn: () => api<Conversation[]>(`conversations?folder=${folder}`),
    refetchInterval: 30_000,
  });
  if (q.isSuccess && q.data.length === 0) {
    return <p className="px-4 py-10 text-[15px] text-ink-muted">{folder === "requests" ? t("no_requests") : t("empty")}</p>;
  }
  return (
    <ul>
      {q.data?.map((c) => (
        <li key={c.id}>
          <Link
            href={folder === "requests" ? `/messages/${c.id}?folder=requests` : `/messages/${c.id}`}
            aria-current={activeId === c.id ? "page" : undefined}
            className={clsx("flex items-center gap-3 px-4 py-3 transition-colors hover:bg-surface-2", activeId === c.id && "bg-accent-tint")}
          >
            <Avatar name={c.other.display_name} url={c.other.avatar_url} size={46} />
            <span className="min-w-0 flex-1">
              <span className="flex items-baseline justify-between gap-2">
                <span className={clsx("truncate text-[15px]", c.unread ? "font-semibold" : "font-medium")}>{c.other.display_name}</span>
                <span className="shrink-0 text-xs text-ink-muted">{relativeTime(c.last_message_at, locale)}</span>
              </span>
              <span className="flex items-center gap-2">
                <span className={clsx("min-w-0 flex-1 truncate text-sm", c.unread ? "text-ink" : "text-ink-muted")}>
                  {c.status === "request" && !c.is_request_to_me ? `${t("pending")} · ` : ""}
                  {preview(c, meId, t)}
                </span>
                {c.unread > 0 && <span className="tnum h-5 min-w-5 shrink-0 rounded-full bg-accent px-1.5 text-center text-[11px] font-semibold leading-5 text-accent-ink">{c.unread}</span>}
              </span>
            </span>
          </Link>
        </li>
      ))}
    </ul>
  );
}

/** Gelen kutusunun üstünde: okunmamış mesaj isteği varsa isteklere götüren bant. */
export function RequestsBanner({ unreadRequests }: { unreadRequests: number }) {
  const t = useTranslations("messages");
  const q = useQuery({
    queryKey: ["conversations", "requests"],
    enabled: unreadRequests > 0,
    queryFn: () => api<Conversation[]>("conversations?folder=requests"),
    refetchInterval: 30_000,
  });
  const list = q.data ?? [];
  if (unreadRequests <= 0 || list.length === 0) return null;
  const first = list[0]!.other.display_name;
  const others = list.length - 1;
  return (
    <Link
      href="/messages?folder=requests"
      className="mx-3 mb-2 flex items-center gap-3 rounded-card bg-surface px-3.5 py-3 transition-colors hover:bg-surface-2 lg:bg-surface-2 lg:hover:bg-line"
    >
      <span className="flex shrink-0">
        {list.slice(0, 2).map((c, i) => (
          <span key={c.id} className={clsx("rounded-full ring-2 ring-surface lg:ring-surface-2", i > 0 && "-ml-3")}>
            <Avatar name={c.other.display_name} url={c.other.avatar_url} size={38} />
          </span>
        ))}
      </span>
      <span className="min-w-0 flex-1">
        <span className="block text-[15px] font-bold">{t("requests_banner_title", { count: list.length })}</span>
        <span className="block truncate text-[13px] text-ink-muted">
          {others > 0 ? t("requests_banner_many", { name: first, count: others }) : t("requests_banner_one", { name: first })}
        </span>
      </span>
      <ChevronRight className="h-5 w-5 shrink-0 text-ink-muted" aria-hidden />
    </Link>
  );
}
