"use client";

import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import clsx from "clsx";
import { ChevronRight, Sparkles, Trophy } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useCallback, useState } from "react";
import { Avatar } from "@/components/Avatar";
import { MyPhotoPicker } from "@/components/community";
import { Countdown, useShortRemaining } from "@/components/Countdown";
import { JustifiedWall } from "@/components/JustifiedWall";
import { Button, Notice, buttonClass } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import { useLoadMore, useMe } from "@/lib/hooks";
import type { Page, Theme, ThemeEntry, ThemeWin } from "@/lib/types";

export function useCurrentTheme() {
  return useQuery({
    queryKey: ["theme", "current"],
    queryFn: async () => {
      try {
        return await api<Theme>("themes/current");
      } catch (e) {
        if (e instanceof ApiError && e.status === 404) return null;
        throw e;
      }
    },
    staleTime: 60_000,
  });
}

/** "#48 · 23–30 Kasım" */
export function themeRange(th: Theme, locale: string) {
  const f = new Intl.DateTimeFormat(locale, { day: "numeric", month: "long" });
  return `#${th.number} · ${f.formatRange(new Date(th.starts_at), new Date(th.ends_at))}`;
}

/** Ana sayfa / keşfet girişi: etkin tema kısa kartı. */
export function ThemeBanner({ className }: { className?: string }) {
  const t = useTranslations("theme");
  const q = useCurrentTheme();
  const left = useShortRemaining(q.data?.ends_at);
  const th = q.data;
  if (!th) return null;
  return (
    <Link href="/themes" className={clsx("group flex items-center gap-4 rounded-card bg-[linear-gradient(135deg,#1b2a4a,#3d2a5a)] px-5 py-4 text-white", className)}>
      <span className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-white/15">
        <Sparkles className="h-5 w-5" strokeWidth={1.8} aria-hidden />
      </span>
      <span className="min-w-0 flex-1">
        <span className="block text-xs font-semibold uppercase tracking-[0.08em] text-white/65">{t("weekly")}</span>
        <span className="block truncate text-[17px] font-bold">{th.title}</span>
        <span className="tnum block text-[13px] text-white/70">
          {t("entries", { count: th.entry_count })}{left ? ` · ${left.left}` : ""}
        </span>
      </span>
      <span className="hidden text-sm font-semibold sm:inline">{th.my_entry ? t("entered") : t("join")}</span>
      <ChevronRight className="h-5 w-5 shrink-0 transition-transform group-hover:translate-x-0.5" aria-hidden />
    </Link>
  );
}

/** Profil rozeti: kazanılan haftalık temalar; açılınca liste. */
export function ThemeWinsBadge({ username, count }: { username: string; count: number }) {
  const t = useTranslations("theme");
  const [open, setOpen] = useState(false);
  const q = useQuery({ queryKey: ["theme-wins", username], enabled: open, queryFn: () => api<ThemeWin[]>(`users/${username}/theme-wins`) });
  return (
    <details className="relative self-start" onToggle={(e) => setOpen((e.target as HTMLDetailsElement).open)}>
      <summary className="inline-flex h-9 cursor-pointer list-none items-center gap-1.5 rounded-full bg-[#fdf2d6] px-3 text-[13.5px] font-bold text-[#8a5a00] dark:bg-[#8a5a00]/30 dark:text-[#f5d27a] [&::-webkit-details-marker]:hidden">
        <Trophy className="h-4 w-4" strokeWidth={2} aria-hidden /> {t("wins_badge", { count })}
      </summary>
      <div className="absolute left-0 top-11 z-20 w-72 rounded-box bg-surface p-2 shadow-float">
        {q.data?.length === 0 && <p className="px-2 py-2 text-sm text-ink-muted">—</p>}
        <ul>
          {q.data?.map((w) => (
            <li key={w.theme_id}>
              <Link href={`/themes/${w.theme_id}`} className="flex items-center gap-3 rounded-[12px] px-2 py-2 hover:bg-surface-2">
                {w.photo.images.thumb && (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={w.photo.images.thumb.url} alt="" className="h-10 w-10 shrink-0 rounded-[8px] bg-surface-2 object-contain" />
                )}
                <span className="min-w-0">
                  <span className="block truncate text-[14px] font-semibold">#{w.number} · {w.title}</span>
                  <span className="block text-xs text-ink-muted">{t("likes", { count: w.like_count })}</span>
                </span>
              </Link>
            </li>
          ))}
        </ul>
      </div>
    </details>
  );
}

type Sort = "top" | "new" | "following";

function WinnerCard({ entry, label }: { entry: ThemeEntry; label: string }) {
  const t = useTranslations("theme");
  const v = entry.photo.images.feed ?? entry.photo.images.thumb;
  return (
    <Link href={`/p/${entry.photo.id}`} className="flex items-center gap-4 rounded-card bg-surface p-3 pr-5 hover:bg-surface/80">
      {v && (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={v.url} alt={entry.photo.title ?? ""} className="h-20 w-28 shrink-0 rounded-photo bg-surface-2 object-contain" />
      )}
      <span className="min-w-0 flex-1">
        <span className="flex items-center gap-1.5 text-xs font-bold uppercase tracking-[0.06em] text-[#8a5a00] dark:text-[#f5d27a]">
          <Trophy className="h-4 w-4" aria-hidden /> {label}
        </span>
        <span className="mt-1 flex items-center gap-2">
          <Avatar name={entry.photo.user.display_name} url={entry.photo.user.avatar_url} size={24} />
          <span className="truncate font-semibold">{entry.photo.user.display_name}</span>
        </span>
        <span className="tnum block text-sm text-ink-muted">{t("likes", { count: entry.photo.like_count })}</span>
      </span>
    </Link>
  );
}

/** Tema sayfası: başlık, geri sayım, katılım, sıralama sekmeleri ve kareler. */
export function ThemeView({ theme, previous }: { theme: Theme; previous?: Theme | null }) {
  const t = useTranslations("theme");
  const locale = useLocale();
  const qc = useQueryClient();
  const { data: me } = useMe();
  const [sort, setSort] = useState<Sort>("top");
  const [picking, setPicking] = useState(false);
  const active = theme.status === "active";

  const entries = useInfiniteQuery({
    queryKey: ["theme", theme.id, "entries", sort],
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) => api<Page<ThemeEntry>>(`themes/${theme.id}/entries?sort=${sort}${pageParam ? `&cursor=${encodeURIComponent(pageParam)}` : ""}`),
    getNextPageParam: (last) => last.next_cursor,
  });
  const { fetchNextPage, hasNextPage, isFetchingNextPage } = entries;
  const loadMore = useCallback(() => !isFetchingNextPage && fetchNextPage(), [fetchNextPage, isFetchingNextPage]);
  const sentinel = useLoadMore(loadMore, !!hasNextPage);
  const refresh = () => {
    qc.invalidateQueries({ queryKey: ["theme"] });
  };
  const enter = useMutation({
    mutationFn: (photoId: string) => api<ThemeEntry>(`themes/${theme.id}/entries`, { method: "POST", body: { photo_id: photoId } }),
    onSuccess: () => {
      setPicking(false);
      refresh();
    },
  });
  const withdraw = useMutation({ mutationFn: () => api(`themes/${theme.id}/entries/me`, { method: "DELETE" }), onSuccess: refresh });

  const items = entries.data?.pages.flatMap((p) => p.items) ?? [];
  const sorts: Sort[] = me ? ["top", "new", "following"] : ["top", "new"];
  const err = enter.error ?? withdraw.error;

  return (
    <div className="flex flex-col gap-6">
      <section className="grid gap-6 rounded-card bg-surface p-5 sm:rounded-[28px] sm:p-8 lg:grid-cols-[minmax(0,1fr)_340px]">
        <div className="flex flex-col gap-3">
          <p className="text-xs font-bold uppercase tracking-[0.08em] text-ink-muted">{t("weekly")} · {t("no_jury")}</p>
          <p className="tnum text-sm text-ink-muted">{themeRange(theme, locale)}</p>
          <h1 className="text-[34px] font-bold leading-none tracking-[-0.04em] sm:text-[48px]">{theme.title}</h1>
          {theme.description && <p className="max-w-[62ch] whitespace-pre-line text-[16px] leading-[1.55]">{theme.description}</p>}
          <details className="text-sm text-ink-muted">
            <summary className="cursor-pointer font-semibold text-ink">{t("rules_title")}</summary>
            <ul className="mt-2 list-disc space-y-1 pl-5">
              <li>{t("rule_one")}</li>
              <li>{t("rule_own")}</li>
              <li>{t("rule_likes")}</li>
            </ul>
          </details>
        </div>
        <div className="flex flex-col gap-3">
          <div className="flex items-baseline gap-2">
            <span className="tnum text-[32px] font-bold tracking-[-0.03em]">{theme.entry_count.toLocaleString(locale)}</span>
            <span className="text-ink-muted">{t("entry_word", { count: theme.entry_count })}</span>
          </div>
          {active ? <Countdown until={theme.ends_at} label={t("ends_in")} /> : <p className="font-semibold">{theme.status === "finished" ? t("finished") : t("ended")}</p>}
          {active && me && !theme.my_entry && (
            <Button variant="large" onClick={() => setPicking(true)}>{t("submit")}</Button>
          )}
          {active && !me && <Link href="/login" className={buttonClass("large")}>{t("login_to_join")}</Link>}
          {theme.my_entry && (
            <div className="flex items-center gap-3 rounded-box bg-surface-2 p-2.5">
              {theme.my_entry.photo.images.thumb && (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={theme.my_entry.photo.images.thumb.url} alt="" className="h-12 w-12 shrink-0 rounded-[10px] bg-bg object-contain" />
              )}
              <span className="min-w-0 flex-1 text-sm">
                <span className="block font-semibold">{t("your_entry")}</span>
                <span className="tnum text-ink-muted">{t("likes", { count: theme.my_entry.photo.like_count })}</span>
              </span>
              {active && (
                <Button variant="danger" className="!h-9 !min-h-9 text-[14px]" busy={withdraw.isPending} onClick={() => window.confirm(t("withdraw_confirm")) && withdraw.mutate()}>
                  {t("withdraw")}
                </Button>
              )}
            </div>
          )}
          {err && <Notice tone="error">{err instanceof ApiError && err.message ? err.message : t("error")}</Notice>}
        </div>
      </section>

      {theme.winner && <WinnerCard entry={theme.winner} label={t("winner")} />}
      {previous?.winner && previous.id !== theme.id && (
        <Link href={`/themes/${previous.id}`} className="flex items-center gap-3 rounded-card bg-surface px-5 py-4 hover:bg-surface/80">
          <Trophy className="h-5 w-5 shrink-0 text-[#b7791f]" aria-hidden />
          <span className="min-w-0 flex-1 text-[15px]">
            <span className="font-semibold">{t("last_week", { title: previous.title })}</span>{" "}
            <span className="text-ink-muted">{t("last_winner", { name: previous.winner.photo.user.username })}</span>
          </span>
          <ChevronRight className="h-5 w-5 text-ink-muted" aria-hidden />
        </Link>
      )}

      <section aria-label={t("entries_title")}>
        <div className="mb-4 flex flex-wrap gap-2" role="tablist" aria-label={t("sort_label")}>
          {sorts.map((s) => (
            <button
              key={s}
              type="button"
              role="tab"
              aria-selected={sort === s}
              onClick={() => setSort(s)}
              className={clsx("h-10 rounded-pill px-4 text-[15px] font-semibold", sort === s ? "bg-ink text-bg" : "bg-surface hover:bg-surface-2")}
            >
              {t(`sort.${s}`)}
            </button>
          ))}
        </div>
        {entries.isSuccess && items.length === 0 && <p className="rounded-card bg-surface px-6 py-12 text-ink-muted">{sort === "following" ? t("empty_following") : t("empty")}</p>}
        <JustifiedWall photos={items.map((e) => e.photo)} target={320} />
        <div ref={sentinel} className="h-px" />
      </section>

      {active && me && (
        <MyPhotoPicker open={picking} onClose={() => setPicking(false)} onPick={(p) => enter.mutate(p.id)} busy={enter.isPending} title={t("pick_title")} />
      )}
    </div>
  );
}

/** Geçmiş temalar listesi. */
export function PastThemes() {
  const t = useTranslations("theme");
  const locale = useLocale();
  const q = useInfiniteQuery({
    queryKey: ["theme", "past"],
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) => api<Page<Theme>>(`themes?status=past${pageParam ? `&cursor=${encodeURIComponent(pageParam)}` : ""}`),
    getNextPageParam: (last) => last.next_cursor,
  });
  const items = q.data?.pages.flatMap((p) => p.items) ?? [];
  if (!items.length) return null;
  return (
    <section aria-labelledby="past-themes">
      <h2 id="past-themes" className="mb-3 text-heading">{t("past")}</h2>
      <ul className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
        {items.map((th) => {
          const v = th.winner?.photo.images.thumb ?? th.winner?.photo.images.feed;
          return (
            <li key={th.id}>
              <Link href={`/themes/${th.id}`} className="flex items-center gap-3 rounded-card bg-surface p-3 hover:bg-surface/80">
                {v ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={v.url} alt="" className="h-16 w-16 shrink-0 rounded-[12px] bg-surface-2 object-contain" />
                ) : (
                  <span className="grid h-16 w-16 shrink-0 place-items-center rounded-[12px] bg-surface-2 text-ink-muted"><Sparkles className="h-5 w-5" aria-hidden /></span>
                )}
                <span className="min-w-0">
                  <span className="tnum block text-xs text-ink-muted">{themeRange(th, locale)}</span>
                  <span className="block truncate font-semibold">{th.title}</span>
                  <span className="block truncate text-sm text-ink-muted">
                    {th.winner ? t("winner_name", { name: th.winner.photo.user.display_name }) : t("entries", { count: th.entry_count })}
                  </span>
                </span>
              </Link>
            </li>
          );
        })}
      </ul>
      {q.hasNextPage && (
        <Button variant="secondary" className="mt-4" busy={q.isFetchingNextPage} onClick={() => q.fetchNextPage()}>{t("more")}</Button>
      )}
    </section>
  );
}

export function usePreviousTheme() {
  return useQuery({ queryKey: ["theme", "past", "first"], queryFn: () => api<Page<Theme>>("themes?status=past&limit=1"), staleTime: 60_000 });
}
