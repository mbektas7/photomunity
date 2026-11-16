"use client";

import { useQuery } from "@tanstack/react-query";
import { Bell } from "lucide-react";
import { useTranslations } from "next-intl";
import { Link, usePathname } from "@/i18n/navigation";
import { api } from "@/lib/api";

export function useNotificationUnread(enabled = true) {
  return useQuery({
    queryKey: ["notifications", "unread"],
    enabled,
    queryFn: () => api<{ count: number }>("notifications/unread-count"),
    refetchInterval: 60_000,
    refetchOnWindowFocus: true,
  });
}

export function NotificationBell() {
  const t = useTranslations("nav");
  const pathname = usePathname();
  const { data } = useNotificationUnread();
  const count = data?.count ?? 0;
  return (
    <Link
      href="/notifications"
      aria-current={pathname.startsWith("/notifications") ? "page" : undefined}
      aria-label={count ? t("notifications_unread", { count }) : t("notifications")}
      className="relative inline-flex h-11 w-11 items-center justify-center rounded-full text-ink hover:bg-surface md:bg-surface md:hover:bg-surface-2"
    >
      <Bell className="h-[21px] w-[21px]" strokeWidth={1.8} aria-hidden />
      {count > 0 && (
        <span className="tnum absolute -right-0.5 -top-0.5 inline-flex min-w-[20px] items-center justify-center rounded-full border-2 border-bg bg-accent px-1 text-[11px] font-bold leading-4 text-accent-ink">
          {count > 99 ? "99+" : count}
        </span>
      )}
    </Link>
  );
}
