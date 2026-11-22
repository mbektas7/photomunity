"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import clsx from "clsx";
import {
  Bell, CreditCard, Flag, Globe, Home, Image as ImageIcon, LogOut, Search, Shield, Trophy, Users,
} from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useEffect, useRef, useState } from "react";
import { Avatar } from "@/components/Avatar";
import { BrandMark } from "@/components/Logo";
import { Button, Notice } from "@/components/ui";
import { Link, usePathname } from "@/i18n/navigation";
import type { AdminPhoto, AdminStats, AdminUserRow, CommunityMini } from "@/lib/admin-types";
import { ApiError, api } from "@/lib/api";
import { useMe } from "@/lib/hooks";

export const NAV = [
  { href: "/admin", key: "nav_overview", icon: Home },
  { href: "/admin/reports", key: "nav_reports", icon: Flag },
  { href: "/admin/users", key: "nav_users", icon: Users },
  { href: "/admin/photos", key: "nav_photos", icon: ImageIcon },
  { href: "/admin/communities", key: "nav_communities", icon: Globe },
  { href: "/admin/contests", key: "nav_contests", icon: Trophy },
  { href: "/admin/subscriptions", key: "nav_subscriptions", icon: CreditCard },
  { href: "/admin/announcements", key: "nav_announcements", icon: Bell },
  { href: "/admin/team", key: "nav_team", icon: Shield },
] as const;

export function useAdminStats(days = 30) {
  return useQuery({ queryKey: ["admin", "stats", days], queryFn: () => api<AdminStats>(`admin/stats?days=${days}`) });
}

/** Panelde bir işlem: başarılı olunca bütün yönetim sorguları tazelenir. */
export function useAdminAction<V, R = unknown>(fn: (v: V) => Promise<R>, onDone?: () => void) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: fn,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["admin"] });
      onDone?.();
    },
  });
}

export function errorText(e: unknown, fallback: string) {
  return e instanceof ApiError && e.message ? e.message : fallback;
}

export function fmtDate(iso: string | null | undefined, locale: string, withTime = false) {
  if (!iso) return "—";
  return new Intl.DateTimeFormat(locale, withTime ? { dateStyle: "medium", timeStyle: "short" } : { dateStyle: "medium" }).format(new Date(iso));
}

// ---------------------------------------------------------------- kabuk
export function AdminShell({ children }: { children: React.ReactNode }) {
  const t = useTranslations("admin");
  const { data: me, isLoading } = useMe();
  const pathname = usePathname();
  const stats = useQuery({
    queryKey: ["admin", "stats", 30],
    queryFn: () => api<AdminStats>("admin/stats?days=30"),
    enabled: !!me?.is_admin,
  });

  if (isLoading) return <div className="h-dvh" aria-busy />;
  if (!me?.is_admin) {
    return (
      <div className="mx-auto flex min-h-dvh max-w-md flex-col items-center justify-center gap-4 px-6 text-center">
        <BrandMark className="h-12 w-12" />
        <h1 className="text-[24px] font-semibold">{t("no_access_title")}</h1>
        <p className="text-ink-muted">{t("no_access_body")}</p>
        <Link href="/" className="font-semibold text-accent-text hover:underline">{t("back_home")}</Link>
      </div>
    );
  }
  const open = stats.data?.reports.open ?? 0;
  const isActive = (href: string) => (href === "/admin" ? pathname === "/admin" : pathname.startsWith(href));

  return (
    <div className="flex min-h-dvh flex-col bg-bg lg:flex-row">
      <aside className="flex shrink-0 flex-col bg-[#14161b] text-white lg:sticky lg:top-0 lg:h-dvh lg:w-[248px] lg:px-3.5 lg:py-5">
        <div className="flex items-center gap-2.5 px-4 py-3 lg:px-2.5 lg:pb-5 lg:pt-0">
          <BrandMark className="h-[30px] w-[30px] text-white" />
          <div className="leading-tight">
            <div className="text-[16px] font-bold">Photomunity</div>
            <div className="text-xs text-white/55">{t("brand_sub")}</div>
          </div>
        </div>
        <nav className="flex gap-1 overflow-x-auto px-3 pb-3 lg:flex-col lg:gap-0.5 lg:overflow-visible lg:px-0 lg:pb-0" aria-label={t("title")}>
          {NAV.map(({ href, key, icon: Icon }) => (
            <Link
              key={href}
              href={href}
              aria-current={isActive(href) ? "page" : undefined}
              className={clsx(
                "flex shrink-0 items-center gap-3 rounded-xl px-3 py-2.5 text-[14.5px] transition-colors",
                isActive(href) ? "bg-white/12 font-bold text-white" : "font-medium text-white/72 hover:bg-white/8 hover:text-white",
              )}
            >
              <Icon className="h-[19px] w-[19px]" aria-hidden />
              {t(key)}
              {key === "nav_reports" && open > 0 && (
                <span className="ml-auto rounded-full bg-[#d92d20] px-2 py-0.5 text-xs font-bold text-white">{open}</span>
              )}
            </Link>
          ))}
        </nav>
        <div className="mt-auto hidden items-center gap-2.5 border-t border-white/12 px-2.5 pt-3 lg:flex">
          <Avatar name={me.display_name} url={me.avatar_url} size={34} />
          <div className="min-w-0 flex-1 text-[13px]">
            <div className="truncate font-semibold">{me.username}</div>
            <div className="text-white/55">{t("role_admin")}</div>
          </div>
          <Link href="/feed" aria-label={t("open_app")} title={t("open_app")} className="grid h-9 w-9 place-items-center rounded-full text-white/70 hover:bg-white/10 hover:text-white">
            <LogOut className="h-4 w-4" />
          </Link>
        </div>
      </aside>
      <main className="min-w-0 flex-1 px-4 py-6 sm:px-6 lg:px-9 lg:py-8">{children}</main>
    </div>
  );
}

// ---------------------------------------------------------------- yapı taşları
export function PageHeader({ title, sub, right }: { title: string; sub?: React.ReactNode; right?: React.ReactNode }) {
  return (
    <div className="mb-5 flex flex-wrap items-end gap-4">
      <div className="min-w-0 flex-1">
        <h1 className="text-[28px] font-bold tracking-[-0.02em]">{title}</h1>
        {sub && <p className="mt-1 text-sm text-ink-muted">{sub}</p>}
      </div>
      {right}
    </div>
  );
}

export function Pills<K extends string>({ items, value, onChange, label }: {
  items: { key: K; label: React.ReactNode }[];
  value: K;
  onChange: (k: K) => void;
  label?: string;
}) {
  return (
    <div className="flex flex-wrap gap-2" role="tablist" aria-label={label}>
      {items.map((i) => (
        <button
          key={i.key}
          type="button"
          role="tab"
          aria-selected={i.key === value}
          onClick={() => onChange(i.key)}
          className={clsx(
            "h-9 rounded-full border px-3.5 text-[13.5px] transition-colors",
            i.key === value ? "border-ink bg-ink font-bold text-bg" : "border-line bg-surface font-medium hover:bg-surface-2",
          )}
        >
          {i.label}
        </button>
      ))}
    </div>
  );
}

export function SearchInput({ value, onChange, placeholder, className }: { value: string; onChange: (v: string) => void; placeholder: string; className?: string }) {
  return (
    <label className={clsx("flex h-10 items-center gap-2 rounded-full border border-line bg-surface px-3.5 text-ink-muted", className)}>
      <Search className="h-4 w-4 shrink-0" aria-hidden />
      <input
        type="search"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        aria-label={placeholder}
        className="min-w-0 flex-1 bg-transparent text-sm text-ink outline-none placeholder:text-ink-muted"
      />
    </label>
  );
}

/** Yazarken her tuşta istek atmamak için kısa gecikmeli değer. */
export function useDebounced<T>(value: T, ms = 300) {
  const [v, setV] = useState(value);
  useEffect(() => {
    const id = setTimeout(() => setV(value), ms);
    return () => clearTimeout(id);
  }, [value, ms]);
  return v;
}

const TONES = {
  muted: "bg-surface-2 text-ink-muted",
  ok: "bg-[#e3f4ec] text-[#0f6e56]",
  warn: "bg-[#fdebd9] text-[#b45309]",
  danger: "bg-[#fdecea] text-[#d92d20]",
  acc: "bg-accent-tint text-accent-text",
} as const;

export function Chip({ tone = "muted", children }: { tone?: keyof typeof TONES; children: React.ReactNode }) {
  return <span className={clsx("inline-block whitespace-nowrap rounded-full px-2.5 py-1 text-xs font-bold", TONES[tone])}>{children}</span>;
}

export function Card({ className, children, pad = "p-5" }: { className?: string; children: React.ReactNode; pad?: string }) {
  return <div className={clsx("rounded-[20px] bg-surface", pad, className)}>{children}</div>;
}

export function Who({ user, sub, size = 34 }: { user: { display_name: string; avatar_url: string | null; username: string }; sub?: React.ReactNode; size?: number }) {
  return (
    <span className="flex min-w-0 items-center gap-2.5">
      <Avatar name={user.display_name} url={user.avatar_url} size={size} />
      <span className="min-w-0">
        <span className="block truncate font-semibold">{user.display_name}</span>
        <span className="block truncate text-[12.5px] text-ink-muted">{sub ?? `@${user.username}`}</span>
      </span>
    </span>
  );
}

export function CommunityBadge({ c, size = 34 }: { c: CommunityMini; size?: number }) {
  const style = { width: size, height: size, fontSize: Math.round(size * 0.38) };
  if (c.logo_url) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={c.logo_url} alt="" style={style} className="shrink-0 rounded-[10px] object-cover" />;
  }
  const letters = c.name.split(/\s+/).map((w) => w[0]).join("").slice(0, 2).toUpperCase();
  return <span aria-hidden style={style} className="grid shrink-0 place-items-center rounded-[10px] bg-accent-tint font-bold text-accent-text">{letters}</span>;
}

export function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex justify-between gap-3 py-1 text-[13.5px]">
      <span className="text-ink-muted">{label}</span>
      <span className="min-w-0 truncate text-right">{children}</span>
    </div>
  );
}

export function Th({ children, className }: { children?: React.ReactNode; className?: string }) {
  return <th className={clsx("border-b border-line px-3.5 py-3 text-left text-xs font-bold text-ink-muted", className)}>{children}</th>;
}

export function Td({ children, className }: { children?: React.ReactNode; className?: string }) {
  return <td className={clsx("border-b border-line px-3.5 py-3 align-middle text-sm ", className)}>{children}</td>;
}

export function Loading() {
  const t = useTranslations("admin");
  return <p className="py-10 text-center text-sm text-ink-muted" aria-busy>{t("loading")}</p>;
}

export function Empty({ children }: { children?: React.ReactNode }) {
  const t = useTranslations("admin");
  return <p className="py-10 text-center text-sm text-ink-muted">{children ?? t("empty")}</p>;
}

export function Failed({ error }: { error: unknown }) {
  const t = useTranslations("admin");
  return <Notice tone="error">{errorText(error, t("error"))}</Notice>;
}

export function Pager({ offset, limit, total, onChange }: { offset: number; limit: number; total: number; onChange: (o: number) => void }) {
  const t = useTranslations("admin");
  if (total <= limit) return null;
  return (
    <div className="flex items-center justify-end gap-3 px-3.5 py-3 text-sm text-ink-muted">
      <span>{t("page_n", { from: offset + 1, to: Math.min(offset + limit, total), total })}</span>
      <Button variant="secondary" className="!h-9" disabled={offset === 0} onClick={() => onChange(Math.max(0, offset - limit))}>{t("prev")}</Button>
      <Button variant="secondary" className="!h-9" disabled={offset + limit >= total} onClick={() => onChange(offset + limit)}>{t("next")}</Button>
    </div>
  );
}

/** Dolgulu küçük eylem düğmesi (panelin sağ ayrıntı kartlarında). */
export function ActionButton({ tone = "ghost", icon: Icon, children, ...rest }: React.ButtonHTMLAttributes<HTMLButtonElement> & {
  tone?: "ghost" | "dark" | "danger" | "primary";
  icon?: React.ComponentType<{ className?: string }>;
}) {
  return (
    <button
      type="button"
      {...rest}
      className={clsx(
        "inline-flex h-10 items-center justify-center gap-2 whitespace-nowrap rounded-full px-4 text-sm font-bold transition-colors disabled:cursor-not-allowed disabled:opacity-50",
        tone === "ghost" && "border border-line bg-surface text-ink hover:bg-surface-2",
        tone === "dark" && "bg-ink text-bg hover:opacity-90",
        tone === "danger" && "bg-[#fdecea] text-[#d92d20] hover:bg-[#fbd9d5]",
        tone === "primary" && "bg-accent text-accent-ink hover:brightness-110",
        rest.className,
      )}
    >
      {Icon && <Icon className="h-4 w-4" />}
      {children}
    </button>
  );
}

// ---------------------------------------------------------------- onay penceresi
type ConfirmOpts = { title: string; body?: string; confirm: string; danger?: boolean; note?: boolean; input?: { label: string; placeholder?: string } };
type ConfirmResult = { note: string; value: string };

/** Geri alınamayan ya da kayda geçen işlemler için onay; isteğe bağlı not ve tek alan. */
export function useConfirm() {
  const t = useTranslations("admin");
  const [opts, setOpts] = useState<ConfirmOpts | null>(null);
  const [note, setNote] = useState("");
  const [value, setValue] = useState("");
  const resolver = useRef<((r: ConfirmResult | null) => void) | null>(null);
  const ref = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    if (opts) ref.current?.showModal();
  }, [opts]);

  const ask = (o: ConfirmOpts) =>
    new Promise<ConfirmResult | null>((resolve) => {
      setNote("");
      setValue("");
      resolver.current = resolve;
      setOpts(o);
    });
  const close = (r: ConfirmResult | null) => {
    ref.current?.close();
    resolver.current?.(r);
    resolver.current = null;
    setOpts(null);
  };

  const dialog = opts ? (
    <dialog
      ref={ref}
      onCancel={(e) => { e.preventDefault(); close(null); }}
      className="m-auto w-[min(92vw,460px)] rounded-[22px] bg-surface p-0 text-ink backdrop:bg-black/50"
    >
      <form method="dialog" className="flex flex-col gap-4 p-6" onSubmit={(e) => { e.preventDefault(); close({ note, value }); }}>
        <h2 className="text-[19px] font-bold">{opts.title}</h2>
        {opts.body && <p className="text-sm leading-relaxed text-ink-muted">{opts.body}</p>}
        {opts.input && (
          <label className="flex flex-col gap-1.5 text-sm font-semibold">
            {opts.input.label}
            <input autoFocus required value={value} onChange={(e) => setValue(e.target.value)} placeholder={opts.input.placeholder}
              className="h-11 rounded-xl border border-line bg-bg px-3 font-normal outline-none focus:border-accent" />
          </label>
        )}
        {opts.note !== false && (
          <label className="flex flex-col gap-1.5 text-sm font-semibold">
            {t("note_label")}
            <textarea value={note} onChange={(e) => setNote(e.target.value)} rows={2} maxLength={1000}
              className="rounded-xl border border-line bg-bg px-3 py-2 font-normal outline-none focus:border-accent" />
          </label>
        )}
        <div className="flex justify-end gap-2">
          <ActionButton onClick={() => close(null)}>{t("cancel")}</ActionButton>
          <ActionButton type="submit" tone={opts.danger ? "danger" : "dark"}>{opts.confirm}</ActionButton>
        </div>
      </form>
    </dialog>
  ) : null;

  return [dialog, ask] as const;
}

// ---------------------------------------------------------------- genel arama
export function GlobalSearch() {
  const t = useTranslations("admin");
  const [q, setQ] = useState("");
  const dq = useDebounced(q.trim());
  const res = useQuery({
    queryKey: ["admin", "search", dq],
    queryFn: () => api<{ users: AdminUserRow[]; photos: AdminPhoto[]; communities: CommunityMini[] }>(`admin/search?q=${encodeURIComponent(dq)}`),
    enabled: dq.length >= 2,
  });
  const d = res.data;
  const none = d && !d.users.length && !d.photos.length && !d.communities.length;
  return (
    <div className="relative w-full sm:w-[340px]">
      <SearchInput value={q} onChange={setQ} placeholder={t("search_all")} />
      {dq.length >= 2 && d && (
        <div className="absolute right-0 top-12 z-30 w-full overflow-hidden rounded-2xl bg-surface p-2 shadow-float">
          {none && <p className="px-3 py-2 text-sm text-ink-muted">{t("search_empty")}</p>}
          {d.users.length > 0 && <p className="px-3 pt-1 text-xs font-bold text-ink-muted">{t("search_people")}</p>}
          {d.users.map((u) => (
            <Link key={u.id} href={`/admin/users?user=${u.id}`} className="block rounded-xl px-3 py-2 hover:bg-surface-2" onClick={() => setQ("")}>
              <Who user={u} size={28} />
            </Link>
          ))}
          {d.photos.length > 0 && <p className="px-3 pt-2 text-xs font-bold text-ink-muted">{t("search_photos")}</p>}
          {d.photos.map((p) => (
            <Link key={p.id} href={`/p/${p.id}`} className="block truncate rounded-xl px-3 py-2 text-sm hover:bg-surface-2">
              {p.title ?? p.id} · <span className="text-ink-muted">@{p.user.username}</span>
            </Link>
          ))}
          {d.communities.length > 0 && <p className="px-3 pt-2 text-xs font-bold text-ink-muted">{t("search_communities")}</p>}
          {d.communities.map((c) => (
            <Link key={c.id} href={`/admin/communities?community=${c.id}`} className="flex items-center gap-2.5 rounded-xl px-3 py-2 text-sm hover:bg-surface-2" onClick={() => setQ("")}>
              <CommunityBadge c={c} size={28} /> {c.name}
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}

export function useLocaleStr() {
  return useLocale();
}
