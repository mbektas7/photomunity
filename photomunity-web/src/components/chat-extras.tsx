"use client";

import { useInfiniteQuery } from "@tanstack/react-query";
import clsx from "clsx";
import { Search, X } from "lucide-react";
import { useTranslations } from "next-intl";
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { ApiError, api } from "@/lib/api";
import type { Gif, Reaction } from "@/lib/types";

export const EMOJIS = ["❤️", "😂", "😮", "😢", "👍", "🔥"] as const;
const PAGE = 24;

/** Mesajın altındaki tepki hapları: emojiye göre gruplu, sayılı; benimki vurgulu. */
export function ReactionPills({ reactions, meId, mine, onToggle }: { reactions: Reaction[]; meId: string; mine: boolean; onToggle?: (emoji: string) => void }) {
  const t = useTranslations("messages");
  if (!reactions.length) return null;
  const groups = new Map<string, { count: number; me: boolean }>();
  for (const r of reactions) {
    const g = groups.get(r.emoji) ?? { count: 0, me: false };
    g.count += 1;
    g.me ||= r.user_id === meId;
    groups.set(r.emoji, g);
  }
  return (
    <div className={clsx("-mt-2.5 flex flex-wrap gap-1 px-2", mine ? "justify-end" : "justify-start")}>
      {[...groups].map(([emoji, g]) => (
        <button
          key={emoji}
          type="button"
          disabled={!onToggle}
          onClick={() => onToggle?.(emoji)}
          aria-pressed={g.me}
          aria-label={t("reaction_label", { emoji, count: g.count })}
          className={clsx(
            "tnum inline-flex h-7 items-center gap-1 rounded-pill border-2 border-bg px-2 text-[13px] font-semibold",
            g.me ? "bg-accent-tint text-accent-text" : "bg-surface-2 text-ink",
          )}
        >
          <span aria-hidden>{emoji}</span>
          {g.count > 1 && <span>{g.count}</span>}
        </button>
      ))}
    </div>
  );
}

type MenuItem = { label: string; onClick: () => void; danger?: boolean };

/** Mesaja tıklayınca (ya da uzun basınca) açılan menü: tepki çubuğu ve işlemler. Konumu sabit, ekrandan taşmaz. */
export function MessageMenu({ anchor, mine, myEmoji, onReact, items, onClose }: {
  anchor: DOMRect;
  mine: boolean;
  myEmoji: string | null;
  onReact?: (emoji: string) => void;
  items: MenuItem[];
  onClose: () => void;
}) {
  const t = useTranslations("messages");
  const ref = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState<{ top: number; left: number } | null>(null);

  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const w = el.offsetWidth, h = el.offsetHeight, pad = 8;
    const above = anchor.top - h - 6;
    const top = above > pad ? above : Math.min(anchor.bottom + 6, window.innerHeight - h - pad);
    const rawLeft = mine ? anchor.right - w : anchor.left;
    setPos({ top, left: Math.max(pad, Math.min(rawLeft, window.innerWidth - w - pad)) });
  }, [anchor, mine]);

  useEffect(() => {
    const down = (e: Event) => !ref.current?.contains(e.target as Node) && onClose();
    const key = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    document.addEventListener("mousedown", down);
    document.addEventListener("touchstart", down);
    document.addEventListener("keydown", key);
    window.addEventListener("resize", onClose);
    return () => {
      document.removeEventListener("mousedown", down);
      document.removeEventListener("touchstart", down);
      document.removeEventListener("keydown", key);
      window.removeEventListener("resize", onClose);
    };
  }, [onClose]);

  return (
    <div
      ref={ref}
      role="menu"
      style={pos ? { top: pos.top, left: pos.left } : { top: -9999, left: -9999 }}
      className="fixed z-50 w-[248px] rounded-box bg-surface p-1.5 shadow-float"
      onScroll={(e) => e.stopPropagation()}
    >
      {onReact && (
        <div className="flex justify-between gap-0.5 border-b border-line px-0.5 pb-1.5" role="group" aria-label={t("react")}>
          {EMOJIS.map((e) => (
            <button
              key={e}
              type="button"
              onClick={() => onReact(e)}
              aria-pressed={myEmoji === e}
              aria-label={t("react_with", { emoji: e })}
              className={clsx("inline-flex h-9 w-9 items-center justify-center rounded-full text-[20px] transition-transform hover:scale-110 hover:bg-surface-2", myEmoji === e && "bg-accent-tint")}
            >
              {e}
            </button>
          ))}
        </div>
      )}
      <div className={clsx(onReact && "pt-1")}>
        {items.map((it) => (
          <button
            key={it.label}
            type="button"
            role="menuitem"
            onClick={() => {
              it.onClick();
              onClose();
            }}
            className={clsx("block min-h-10 w-full rounded-box px-3 py-2 text-left text-[14.5px] hover:bg-surface-2", it.danger && "text-danger")}
          >
            {it.label}
          </button>
        ))}
      </div>
    </div>
  );
}

/** GIPHY'den GIF ve çıkartma seçici. Kırpılmaz: sütunlarda kendi oranında. */
export function GifPicker({ onPick, onClose, busy }: { onPick: (g: Gif) => void; onClose: () => void; busy?: boolean }) {
  const t = useTranslations("messages");
  const [kind, setKind] = useState<"gif" | "sticker">("gif");
  const [text, setText] = useState("");
  const [query, setQuery] = useState("");
  const input = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const id = setTimeout(() => setQuery(text.trim()), 350);
    return () => clearTimeout(id);
  }, [text]);
  useEffect(() => input.current?.focus(), []);

  const q = useInfiniteQuery({
    queryKey: ["gifs", kind, query],
    initialPageParam: 0,
    queryFn: ({ pageParam }) =>
      api<Gif[]>(`gifs?${new URLSearchParams({ kind, offset: String(pageParam), limit: String(PAGE), ...(query ? { q: query } : {}) })}`),
    getNextPageParam: (last, all) => (last.length === PAGE && all.length * PAGE < 500 ? all.length * PAGE : undefined),
    retry: (n, e) => !(e instanceof ApiError && e.code === "gifs_unavailable") && n < 2,
    staleTime: 5 * 60_000,
  });
  const gifs = q.data?.pages.flat() ?? [];
  const unavailable = q.error instanceof ApiError && q.error.code === "gifs_unavailable";

  return (
    <div className="absolute bottom-full left-3 right-3 z-30 mb-2 flex max-h-[min(460px,60dvh)] flex-col rounded-card bg-surface shadow-float sm:left-4 sm:right-auto sm:w-[380px]">
      <div className="flex items-center gap-2 px-3 pt-3">
        <div className="flex flex-1 gap-1 rounded-pill bg-surface-2 p-1" role="tablist">
          {(["gif", "sticker"] as const).map((k) => (
            <button
              key={k}
              type="button"
              role="tab"
              aria-selected={kind === k}
              onClick={() => setKind(k)}
              className={clsx("h-8 flex-1 rounded-pill text-[14px] font-semibold", kind === k ? "bg-surface text-ink shadow-sm" : "text-ink-muted")}
            >
              {k === "gif" ? t("tab_gif") : t("tab_sticker")}
            </button>
          ))}
        </div>
        <button type="button" onClick={onClose} aria-label={t("close")} className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full hover:bg-surface-2">
          <X className="h-4 w-4" />
        </button>
      </div>
      <label className="mx-3 mt-2 flex h-10 items-center gap-2 rounded-pill border border-transparent bg-surface-2 px-3 focus-within:border-accent">
        <Search className="h-4 w-4 shrink-0 text-ink-muted" aria-hidden />
        <input
          ref={input}
          value={text}
          onChange={(e) => setText(e.target.value)}
          maxLength={50}
          placeholder={t("gif_search")}
          aria-label={t("gif_search")}
          className="min-w-0 flex-1 bg-transparent text-[15px] outline-none placeholder:text-ink-muted focus-visible:outline-none"
        />
      </label>
      <div
        className="mt-2 min-h-[160px] flex-1 overflow-y-auto px-3"
        onScroll={(e) => {
          const el = e.currentTarget;
          if (el.scrollHeight - el.scrollTop - el.clientHeight < 200 && q.hasNextPage && !q.isFetchingNextPage) q.fetchNextPage();
        }}
      >
        {unavailable ? (
          <p className="px-2 py-10 text-center text-[14.5px] text-ink-muted">{t("gif_unavailable")}</p>
        ) : q.error ? (
          <p className="px-2 py-10 text-center text-[14.5px] text-ink-muted">{q.error instanceof ApiError && q.error.message ? q.error.message : t("gif_error")}</p>
        ) : q.isSuccess && gifs.length === 0 ? (
          <p className="px-2 py-10 text-center text-[14.5px] text-ink-muted">{t("gif_empty")}</p>
        ) : (
          <div className="columns-2 gap-2 sm:columns-3" aria-busy={q.isFetching}>
            {gifs.map((g) => (
              <button
                key={g.id}
                type="button"
                disabled={busy}
                onClick={() => onPick(g)}
                className={clsx("mb-2 block w-full overflow-hidden rounded-[10px] disabled:opacity-50", g.kind === "gif" && "bg-surface-2")}
              >
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={g.url} alt="" width={g.width} height={g.height} loading="lazy" className="block h-auto w-full" />
              </button>
            ))}
          </div>
        )}
      </div>
      <p className="px-3 py-2 text-right text-[11px] font-semibold uppercase tracking-wide text-ink-muted">{t("powered_by_giphy")}</p>
    </div>
  );
}
