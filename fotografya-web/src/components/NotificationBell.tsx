"use client";

import { useQuery } from "@tanstack/react-query";
import { Bell } from "lucide-react";
import { useTranslations } from "next-intl";
import { Link, usePathname } from "@/i18n/navigation";
import { api } from "@/lib/api";

export function NotificationBell() {
  const t = useTranslations("nav");
  const pathname = usePathname();
  const { data } = useQuery({
    queryKey: ["notifications", "unread"],
    queryFn: () => api<{ count: number }>("notifications/unread-count"),
    refetchInterval: 60_000,
    refetchOnWindowFocus: true,
  });
  const count = data?.count ?? 0;
  return (
    <Link
      href="/notifications"
      aria-current={pathname.startsWith("/notifications") ? "page" : undefined}
      aria-label={count ? t("notifications_unread", { count }) : t("notifications")}
      className="relative inline-flex h-10 w-10 items-center justify-center rounded-full text-ink hover:bg-ink/5"
    >
      <Bell className="h-[21px] w-[21px]" strokeWidth={1.9} />
      {count > 0 && (
        <span className="tnum absolute right-1 top-1 inline-flex min-w-[18px] items-center justify-center rounded-full bg-accent px-1 text-[11px] font-semibold leading-[18px] text-accent-ink">
          {count > 99 ? "99+" : count}
        </span>
      )}
    </Link>
  );
}
