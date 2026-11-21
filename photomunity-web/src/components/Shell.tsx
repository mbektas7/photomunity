"use client";

import clsx from "clsx";
import {
  Bell,
  BookOpen,
  Compass,
  House,
  Map as MapIcon,
  MessageCircle,
  Plus,
  Trophy,
  UserRound,
  UsersRound,
  type LucideIcon,
} from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useQueryClient } from "@tanstack/react-query";
import { Link, usePathname, useRouter } from "@/i18n/navigation";
import { authAction } from "@/lib/api";
import { useMe } from "@/lib/hooks";
import { Avatar } from "./Avatar";
import { BrandLogo } from "./Logo";
import { MessagesLink, useMessageUnread } from "./messages";
import { NotificationBell, useNotificationUnread } from "./NotificationBell";
import { buttonClass } from "./ui";

export function Wordmark({ className }: { className?: string }) {
  return <BrandLogo className={clsx("w-auto", className ?? "h-[30px]")} />;
}

/** Sol menülü akış düzeninde üst çubuk yalnızca dar ekranda görünür. */
const SIDEBAR_ROUTES = ["/feed"];
export const usesSidebar = (pathname: string) => SIDEBAR_ROUTES.some((r) => pathname === r || pathname.startsWith(`${r}/`));

function LocaleSwitch({ className }: { className?: string }) {
  const locale = useLocale();
  const pathname = usePathname();
  const router = useRouter();
  const next = locale === "tr" ? "en" : "tr";
  return (
    <button
      type="button"
      onClick={() => router.replace(pathname, { locale: next })}
      className={clsx("h-11 min-w-11 rounded-full px-2 text-sm font-semibold text-ink-muted hover:bg-surface hover:text-ink", className)}
      aria-label={next === "en" ? "Switch to English" : "Türkçeye geç"}
    >
      {next.toUpperCase()}
    </button>
  );
}

function UserMenu({ size = 40, withName = false }: { size?: number; withName?: boolean }) {
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

  const item = "flex min-h-11 items-center rounded-box px-3 text-[15px] font-medium hover:bg-surface-2";
  return (
    <details className="relative">
      <summary
        className={clsx(
          "flex cursor-pointer list-none items-center gap-3 rounded-full [&::-webkit-details-marker]:hidden",
          withName && "rounded-box px-2 py-1.5 hover:bg-surface",
        )}
        aria-label={t("account")}
      >
        <Avatar name={me.display_name} url={me.avatar_url} size={size} />
        {withName && (
          <span className="min-w-0">
            <span className="block truncate text-[14.5px] font-semibold">{me.display_name}</span>
            <span className="block truncate text-caption text-ink-muted">@{me.username}</span>
          </span>
        )}
      </summary>
      <div
        className={clsx(
          "absolute z-30 w-60 rounded-box bg-surface p-1.5 shadow-float",
          withName ? "bottom-14 left-0" : "right-0 top-12",
        )}
      >
        <p className="truncate px-3 pb-2 pt-1.5 text-caption text-ink-muted">@{me.username}</p>
        <Link href={`/u/${me.username}`} className={item}>
          {t("profile")}
        </Link>
        <Link href="/settings" className={item}>
          {t("settings")}
        </Link>
        <Link href="/pro" className={clsx(item, "justify-between")}>
          Photomunity Pro {me.is_pro && <span className="text-xs font-bold text-accent-text">✓</span>}
        </Link>
        <button type="button" onClick={logout} className={clsx(item, "w-full text-left")}>
          {t("logout")}
        </button>
      </div>
    </details>
  );
}

/** Üst çubuk: tanıtım ve giriş yapılmış detay sayfaları (web-02…05). Dar ekranda mobil akış başlığı. */
export function Header() {
  const t = useTranslations("nav");
  const pathname = usePathname();
  const { data: me, isLoading } = useMe();
  const sidebar = !!me && usesSidebar(pathname);

  const links = [
    { href: "/explore", label: t("explore") },
    { href: "/communities", label: t("communities") },
    { href: "/contests", label: t("contests") },
    { href: "/map", label: t("map") },
    { href: "/guide", label: t("guide") },
  ];

  return (
    <header className={clsx("sticky top-0 z-20 bg-bg/90 backdrop-blur-md", sidebar && "md:hidden")}>
      <div className="mx-auto flex h-[72px] max-w-[1440px] items-center gap-4 px-5 sm:px-6 lg:h-20 lg:px-10">
        <Link href={me ? "/feed" : "/"} aria-label="Photomunity" className="rounded-box">
          <Wordmark />
        </Link>
        <nav aria-label={t("main")} className="ml-2 hidden items-center gap-0.5 md:flex">
          {links.map((l) => (
            <Link
              key={l.href}
              href={l.href}
              aria-current={pathname.startsWith(l.href) ? "page" : undefined}
              className="inline-flex h-11 items-center rounded-full px-2.5 text-[15px] font-medium text-ink-muted hover:text-ink aria-[current=page]:font-bold aria-[current=page]:text-ink lg:px-3"
            >
              {l.label}
            </Link>
          ))}
        </nav>
        <div className="ml-auto flex items-center gap-1.5 sm:gap-3">
          <LocaleSwitch className={me ? "max-md:hidden" : undefined} />
          {!isLoading && !me && (
            <>
              <Link href="/login" className={buttonClass("ghost", "px-3 sm:px-4")}>
                {t("login")}
              </Link>
              <Link href="/register" className={buttonClass("primary", "px-4")}>
                {t("register")}
              </Link>
            </>
          )}
          {me && (
            <>
              <MessagesLink />
              <NotificationBell />
              <Link href="/upload" className={buttonClass("primary", "px-[18px] max-md:hidden")}>
                <Plus className="h-[18px] w-[18px]" strokeWidth={2.4} aria-hidden />
                {t("upload")}
              </Link>
              <span className="max-md:hidden">
                <UserMenu />
              </span>
            </>
          )}
        </div>
      </div>
    </header>
  );
}

type NavItem = { href: string; label: string; icon: LucideIcon; badge?: number };

/** Giriş yapılmış akış düzeninin sol menüsü (web-01). */
export function Sidebar() {
  const t = useTranslations("nav");
  const pathname = usePathname();
  const msg = useMessageUnread();
  const notif = useNotificationUnread();

  const items: NavItem[] = [
    { href: "/feed", label: t("feed"), icon: House },
    { href: "/explore", label: t("explore"), icon: Compass },
    { href: "/communities", label: t("communities"), icon: UsersRound },
    { href: "/contests", label: t("contests"), icon: Trophy },
    { href: "/map", label: t("map"), icon: MapIcon },
    { href: "/messages", label: t("messages"), icon: MessageCircle, badge: (msg.data?.inbox ?? 0) + (msg.data?.requests ?? 0) },
    { href: "/notifications", label: t("notifications"), icon: Bell, badge: notif.data?.count ?? 0 },
    { href: "/guide", label: t("guide"), icon: BookOpen },
  ];

  return (
    <aside className="sticky top-6 hidden w-[230px] shrink-0 flex-col gap-1.5 self-start md:flex">
      <Link href="/feed" aria-label="Photomunity" className="rounded-box px-3.5 pb-5 pt-1.5">
        <Wordmark className="h-8" />
      </Link>
      <nav aria-label={t("main")} className="flex flex-col gap-1">
        {items.map(({ href, label, icon: Icon, badge }) => {
          const active = pathname === href || pathname.startsWith(`${href}/`);
          return (
            <Link
              key={href}
              href={href}
              aria-current={active ? "page" : undefined}
              aria-label={badge ? `${label}, ${badge}` : undefined}
              className={clsx(
                "flex h-[46px] items-center gap-3 rounded-photo px-3.5 text-[15.5px] transition-colors",
                active ? "bg-accent-tint font-bold text-accent-text" : "font-medium text-ink hover:bg-surface",
              )}
            >
              <Icon className="h-[21px] w-[21px]" strokeWidth={active ? 2.1 : 1.8} aria-hidden />
              <span className="flex-1">{label}</span>
              {!!badge && (
                <span className="tnum min-w-5 rounded-full bg-accent px-1.5 text-center text-[11px] font-bold leading-5 text-accent-ink">
                  {badge > 99 ? "99+" : badge}
                </span>
              )}
            </Link>
          );
        })}
      </nav>
      <Link href="/upload" className="mt-[18px] flex h-[50px] items-center justify-center gap-2 rounded-box bg-accent text-[15.5px] font-bold text-accent-ink hover:brightness-110">
        <Plus className="h-5 w-5" strokeWidth={2.4} aria-hidden />
        {t("upload_photo")}
      </Link>
      <div className="mt-6 flex items-center justify-between gap-2">
        <UserMenu withName size={38} />
        <LocaleSwitch />
      </div>
    </aside>
  );
}

/**
 * Dar ekranda yüzen alt menü (BottomNav): Akış, Keşfet, (Yükle), Yarışmalar, Profil.
 * Etiket yok; her düğmenin aria-label'ı var. Mesajlar ve bildirimler üst çubukta.
 */
export function MobileTabBar() {
  const t = useTranslations("nav");
  const pathname = usePathname();
  const { data: me } = useMe();
  if (!me) return null;

  const tabs: NavItem[] = [
    { href: "/feed", label: t("feed"), icon: House },
    { href: "/explore", label: t("explore"), icon: Compass },
    { href: "/contests", label: t("contests"), icon: Trophy },
    { href: `/u/${me.username}`, label: t("profile"), icon: UserRound },
  ];
  const tab = ({ href, label, icon: Icon }: NavItem) => {
    const active = pathname === href || pathname.startsWith(`${href}/`);
    return (
      <li key={href} className="flex justify-center">
        <Link
          href={href}
          aria-label={label}
          aria-current={active ? "page" : undefined}
          className={clsx("flex h-12 w-12 items-center justify-center rounded-full", active ? "text-ink" : "text-ink-subtle")}
        >
          <Icon className="h-[25px] w-[25px]" strokeWidth={active ? 2.1 : 1.8} aria-hidden />
        </Link>
      </li>
    );
  };

  return (
    <nav
      aria-label={t("main")}
      className="fixed inset-x-3 bottom-[max(12px,env(safe-area-inset-bottom))] z-20 rounded-card bg-surface shadow-float md:hidden"
    >
      <ul className="grid h-[66px] grid-cols-5 items-center">
        {tabs.slice(0, 2).map(tab)}
        <li className="flex justify-center">
          <Link
            href="/upload"
            aria-label={t("upload")}
            aria-current={pathname.startsWith("/upload") ? "page" : undefined}
            className="-mt-[44px] flex h-[54px] w-[54px] items-center justify-center rounded-full bg-accent text-accent-ink shadow-accent"
          >
            <Plus className="h-[26px] w-[26px]" strokeWidth={2.4} aria-hidden />
          </Link>
        </li>
        {tabs.slice(2).map(tab)}
      </ul>
    </nav>
  );
}
