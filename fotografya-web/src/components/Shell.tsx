"use client";

import clsx from "clsx";
import { Compass, Images, Plus, UserRound, UsersRound } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useQueryClient } from "@tanstack/react-query";
import { Link, usePathname, useRouter } from "@/i18n/navigation";
import { authAction } from "@/lib/api";
import { useMe } from "@/lib/hooks";
import { Avatar } from "./Avatar";
import { MessagesLink } from "./messages";
import { NotificationBell } from "./NotificationBell";
import { buttonClass } from "./ui";

export function Wordmark({ className }: { className?: string }) {
  return (
    <span className={clsx("text-[21px] font-bold tracking-[-0.035em]", className)}>
      Fotografya
    </span>
  );
}

function LocaleSwitch() {
  const locale = useLocale();
  const pathname = usePathname();
  const router = useRouter();
  const next = locale === "tr" ? "en" : "tr";
  return (
    <button
      type="button"
      onClick={() => router.replace(pathname, { locale: next })}
      className="h-9 rounded-full px-2 text-sm font-medium text-muted hover:text-ink sm:px-3"
      aria-label={next === "en" ? "Switch to English" : "Türkçeye geç"}
    >
      {next.toUpperCase()}
    </button>
  );
}

function UserMenu() {
  const t = useTranslations("nav");
  const { data: me } = useMe();
  const qc = useQueryClient();
  const router = useRouter();
  if (!me) return null;

  async function logout() {
    await authAction("logout");
    qc.clear();
    router.push("/");
  }

  return (
    <details className="relative">
      <summary className="flex cursor-pointer list-none items-center rounded-full [&::-webkit-details-marker]:hidden" aria-label={t("account")}>
        <Avatar name={me.display_name} url={me.avatar_url} size={36} />
      </summary>
      <div className="absolute right-0 top-12 z-30 w-56 border border-line bg-mat p-1.5 shadow-[0_12px_40px_-12px_rgba(0,0,0,0.25)]">
        <p className="truncate px-3 pb-2 pt-1.5 text-sm text-muted">@{me.username}</p>
        <Link href={`/u/${me.username}`} className="block rounded-md px-3 py-2 text-[15px] hover:bg-ink/5">
          {t("profile")}
        </Link>
        <Link href="/settings" className="block rounded-md px-3 py-2 text-[15px] hover:bg-ink/5">
          {t("settings")}
        </Link>
        <Link href="/pro" className="flex items-center justify-between rounded-md px-3 py-2 text-[15px] hover:bg-ink/5">
          Fotografya Pro {me.is_pro && <span className="text-xs text-accent">✓</span>}
        </Link>
        <button type="button" onClick={logout} className="block w-full rounded-md px-3 py-2 text-left text-[15px] hover:bg-ink/5">
          {t("logout")}
        </button>
      </div>
    </details>
  );
}

export function Header() {
  const t = useTranslations("nav");
  const pathname = usePathname();
  const { data: me, isLoading } = useMe();

  const links = [
    { href: "/feed", label: t("feed"), show: !!me },
    { href: "/explore", label: t("explore"), show: true },
    { href: "/map", label: t("map"), show: true },
    { href: "/communities", label: t("communities"), show: true },
    { href: "/contests", label: t("contests"), show: true },
    { href: "/guide", label: t("guide"), show: true },
  ].filter((l) => l.show);

  return (
    <header className="sticky top-0 z-20 border-b border-line bg-wall/85 backdrop-blur-md">
      <div className="mx-auto flex h-16 max-w-[1400px] items-center gap-4 px-4 sm:gap-6 sm:px-6">
        <Link href={me ? "/feed" : "/"} aria-label="Fotografya">
          <Wordmark />
        </Link>
        <nav className="hidden items-center gap-1 md:flex">
          {links.map((l) => (
            <Link
              key={l.href}
              href={l.href}
              aria-current={pathname.startsWith(l.href) ? "page" : undefined}
              className="rounded-full px-3.5 py-2 text-[15px] font-medium text-muted hover:text-ink aria-[current=page]:text-ink"
            >
              {l.label}
            </Link>
          ))}
        </nav>
        <div className="ml-auto flex items-center gap-1 sm:gap-2">
          <LocaleSwitch />
          {!isLoading && !me && (
            <>
              <Link href="/login" className={buttonClass("ghost", "h-10 px-3 sm:px-4")}>
                {t("login")}
              </Link>
              <Link href="/register" className={buttonClass("primary", "h-10 px-3.5 sm:px-4")}>
                {t("register")}
              </Link>
            </>
          )}
          {me && (
            <>
              <MessagesLink />
              <NotificationBell />
              <Link href="/upload" className={buttonClass("primary", "h-10 px-4 max-md:hidden")}>
                <Plus className="h-4 w-4" strokeWidth={2.5} />
                {t("upload")}
              </Link>
              <UserMenu />
            </>
          )}
        </div>
      </div>
    </header>
  );
}

export function MobileTabBar() {
  const t = useTranslations("nav");
  const pathname = usePathname();
  const { data: me } = useMe();
  if (!me) return null;

  const tabs = [
    { href: "/feed", label: t("feed"), icon: Images },
    { href: "/explore", label: t("explore"), icon: Compass },
    { href: "/communities", label: t("communities"), icon: UsersRound },
    { href: "/upload", label: t("upload"), icon: Plus },
    { href: `/u/${me.username}`, label: t("profile"), icon: UserRound },
  ];

  return (
    <nav
      aria-label={t("main")}
      className="fixed inset-x-0 bottom-0 z-20 border-t border-line bg-wall/95 pb-[env(safe-area-inset-bottom)] backdrop-blur-md md:hidden"
    >
      <ul className="grid grid-cols-5">
        {tabs.map(({ href, label, icon: Icon }) => {
          const active = pathname.startsWith(href) || (href === "/communities" && (pathname.startsWith("/c/") || pathname.startsWith("/contests")));
          return (
            <li key={href}>
              <Link
                href={href}
                aria-current={active ? "page" : undefined}
                className={clsx("flex flex-col items-center gap-1 py-2.5 text-[11px] font-medium", active ? "text-ink" : "text-muted")}
              >
                <Icon className="h-[22px] w-[22px]" strokeWidth={active ? 2.4 : 1.8} />
                {label}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
