"use client";

import { type InfiniteData, useInfiniteQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import clsx from "clsx";
import { ArrowLeft, ImagePlus, LocateFixed, MapPin, MoreHorizontal, SendHorizontal } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { Link, useRouter } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import type { ChatMessage, Conversation, MessagePageData, UserCard } from "@/lib/types";
import { Avatar } from "./Avatar";
import { MyPhotoPicker } from "./community";
import { Button, Notice } from "./ui";

function dayLabel(iso: string, locale: string) {
  const d = new Date(iso);
  const today = new Date();
  const y = new Date(); y.setDate(today.getDate() - 1);
  const same = (a: Date, b: Date) => a.toDateString() === b.toDateString();
  if (same(d, today)) return locale === "tr" ? "Bugün" : "Today";
  if (same(d, y)) return locale === "tr" ? "Dün" : "Yesterday";
  return new Intl.DateTimeFormat(locale, { day: "numeric", month: "long", year: d.getFullYear() === today.getFullYear() ? undefined : "numeric" }).format(d);
}

function Bubble({ m, mine }: { m: ChatMessage; mine: boolean }) {
  const t = useTranslations("messages");
  const locale = useLocale();
  const time = new Intl.DateTimeFormat(locale, { hour: "2-digit", minute: "2-digit" }).format(new Date(m.created_at));
  const img = m.photo?.images.feed ?? m.photo?.images.thumb;
  return (
    <div className={clsx("flex", mine ? "justify-end" : "justify-start")}>
      <div className={clsx("max-w-[78%] sm:max-w-[62%]", mine ? "items-end" : "items-start", "flex flex-col gap-1")}>
        {m.photo && img && (
          <Link href={`/p/${m.photo.id}`} className="block overflow-hidden bg-surface p-1.5">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={img.url} alt={m.photo.title ?? ""} className="block max-h-[320px] w-auto max-w-full" />
            <span className="block px-1 pb-0.5 pt-1.5 text-xs text-ink-muted">{m.photo.title ?? m.photo.user.display_name}</span>
          </Link>
        )}
        {m.location && (
          <a href={`/map?lat=${m.location.latitude}&lng=${m.location.longitude}&z=12&layer=photos`}
            className={clsx("inline-flex items-center gap-1.5 rounded-[18px] px-3.5 py-2 text-[15px]", mine ? "bg-ink text-surface" : "bg-surface")}>
            <MapPin className="h-4 w-4" /> {m.location.name || t("shared_location")}
          </a>
        )}
        {m.body && (
          <p className={clsx("whitespace-pre-wrap break-words rounded-[18px] px-3.5 py-2 text-[15px] leading-snug", mine ? "rounded-br-[6px] bg-ink text-surface" : "rounded-bl-[6px] bg-surface")}>
            {m.body}
          </p>
        )}
        <span className="tnum px-1 text-[11px] text-ink-muted">{time}</span>
      </div>
    </div>
  );
}

/** Tek sohbet. `conversation` yoksa yeni sohbet: ilk mesaj gönderilince oluşturulur. */
export function Thread({ conversation, other, meId }: { conversation: Conversation | null; other: UserCard; meId: string }) {
  const t = useTranslations("messages");
  const locale = useLocale();
  const router = useRouter();
  const qc = useQueryClient();
  const cid = conversation?.id;
  const scroller = useRef<HTMLDivElement>(null);
  const content = useRef<HTMLDivElement>(null);
  const atBottom = useRef(true);
  const [text, setText] = useState("");
  const [picker, setPicker] = useState(false);
  const [menu, setMenu] = useState(false);

  const q = useInfiniteQuery({
    queryKey: ["messages", cid],
    enabled: !!cid,
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) => api<MessagePageData>(`conversations/${cid}/messages${pageParam ? `?before=${encodeURIComponent(pageParam)}` : ""}`),
    getNextPageParam: (last) => last.next_cursor,
    refetchInterval: 20_000, // WebSocket koparsa yedek
  });
  // Sayfalar yeniden eskiye; her sayfanın içi eskiden yeniye
  const messages = q.data ? [...q.data.pages].reverse().flatMap((p) => p.items) : [];
  const lastId = messages.at(-1)?.id;

  const read = useMutation({ mutationFn: () => api(`conversations/${cid}/read`, { method: "POST" }), onSuccess: () => qc.invalidateQueries({ queryKey: ["messages-unread"] }) });
  useEffect(() => {
    if (cid && lastId && messages.at(-1)?.sender_id !== meId) read.mutate();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cid, lastId]);

  useLayoutEffect(() => {
    const el = scroller.current;
    if (el && atBottom.current) el.scrollTop = el.scrollHeight;
  }, [lastId, q.data?.pages.length]);

  // Fotoğraflar sonradan yüklenip içeriği uzatır; kullanıcı en alttaysa en altta kalsın
  useEffect(() => {
    const el = scroller.current, inner = content.current;
    if (!el || !inner) return;
    const ro = new ResizeObserver(() => {
      if (atBottom.current) el.scrollTop = el.scrollHeight;
    });
    ro.observe(inner);
    return () => ro.disconnect();
  }, []);

  const send = useMutation({
    mutationFn: async (payload: Record<string, unknown>) => {
      if (!cid) {
        const c = await api<Conversation>("conversations", { method: "POST", body: { username: other.username, ...payload } });
        return { created: c };
      }
      const m = await api<ChatMessage>(`conversations/${cid}/messages`, { method: "POST", body: payload });
      return { message: m };
    },
    onSuccess: (r) => {
      setText("");
      setPicker(false);
      atBottom.current = true;
      if (r.created) {
        qc.invalidateQueries({ queryKey: ["conversations"] });
        router.replace(`/messages/${r.created.id}`);
        return;
      }
      const m = r.message!;
      qc.setQueryData<InfiniteData<MessagePageData>>(["messages", cid], (data) => {
        if (!data || data.pages[0]?.items.some((x) => x.id === m.id)) return data;
        const [first, ...rest] = data.pages;
        return { ...data, pages: [{ ...first!, items: [...first!.items, m] }, ...rest] };
      });
      qc.invalidateQueries({ queryKey: ["conversations"] });
      qc.invalidateQueries({ queryKey: ["conversation", cid] });
    },
  });
  const act = useMutation({
    mutationFn: (action: "accept" | "decline" | "block") =>
      action === "block" ? api(`users/${other.username}/block`, { method: "POST" }) : api(`conversations/${cid}/${action}`, { method: "POST" }),
    onSuccess: (_d, action) => {
      qc.invalidateQueries({ queryKey: ["conversations"] });
      qc.invalidateQueries({ queryKey: ["messages-unread"] });
      if (action === "accept") qc.invalidateQueries({ queryKey: ["conversation", cid] });
      else router.replace("/messages");
    },
  });

  function submit() {
    const body = text.trim();
    if (body) send.mutate({ body });
  }

  function shareLocation() {
    navigator.geolocation?.getCurrentPosition((p) =>
      send.mutate({ location: { latitude: +p.coords.latitude.toFixed(4), longitude: +p.coords.longitude.toFixed(4), name: null } }),
    );
  }

  const seenAt = conversation?.other_last_read_at ? new Date(conversation.other_last_read_at) : null;
  // "Görüldü" yalnızca en son mesaj bensem ve karşı taraf onu okuduysa
  const last = messages.at(-1);
  const seen = !!(last && last.sender_id === meId && seenAt && seenAt >= new Date(last.created_at));
  const pendingMine = conversation?.status === "request" && !conversation.is_request_to_me;

  return (
    <div className="flex h-full flex-col">
      <header className="flex items-center gap-3 border-b border-line px-3 py-2.5 sm:px-4">
        <Link href="/messages" className="rounded-full p-2 hover:bg-ink/5 lg:hidden" aria-label={t("back")}><ArrowLeft className="h-5 w-5" /></Link>
        <Link href={`/u/${other.username}`} className="flex min-w-0 flex-1 items-center gap-3">
          <Avatar name={other.display_name} url={other.avatar_url} size={38} />
          <span className="min-w-0">
            <span className="block truncate font-semibold">{other.display_name}</span>
            <span className="block truncate text-xs text-ink-muted">@{other.username}</span>
          </span>
        </Link>
        {cid && (
          <div className="relative">
            <button type="button" onClick={() => setMenu((x) => !x)} aria-label={t("more")} aria-expanded={menu} className="rounded-full p-2 hover:bg-ink/5"><MoreHorizontal className="h-5 w-5" /></button>
            {menu && (
              <div className="absolute right-0 top-11 z-20 w-48 border border-line bg-surface p-1.5 shadow-[0_12px_40px_-12px_rgba(0,0,0,0.25)]">
                <button type="button" className="block w-full rounded-md px-3 py-2 text-left text-[15px] text-danger hover:bg-ink/5"
                  onClick={() => window.confirm(t("block_confirm", { name: other.display_name })) && act.mutate("block")}>
                  {t("block")}
                </button>
              </div>
            )}
          </div>
        )}
      </header>

      <div ref={scroller} className="min-h-0 flex-1 overflow-y-auto px-3 py-4 sm:px-5"
        onScroll={(e) => {
          const el = e.currentTarget;
          atBottom.current = el.scrollHeight - el.scrollTop - el.clientHeight < 80;
          if (el.scrollTop < 120 && q.hasNextPage && !q.isFetchingNextPage) q.fetchNextPage();
        }}>
        <div ref={content}>
        {!cid && <p className="mx-auto mt-10 max-w-[44ch] text-center text-sm text-ink-muted">{t("new_hint", { name: other.display_name })}</p>}
        <div className="flex flex-col gap-2.5">
          {messages.map((m, i) => {
            const showDay = i === 0 || new Date(messages[i - 1]!.created_at).toDateString() !== new Date(m.created_at).toDateString();
            return (
              <div key={m.id} className="flex flex-col gap-2.5">
                {showDay && <p className="my-2 text-center text-xs font-medium text-ink-muted">{dayLabel(m.created_at, locale)}</p>}
                <Bubble m={m} mine={m.sender_id === meId} />
              </div>
            );
          })}
        </div>
        {seen && <p className="mt-1 px-1 text-right text-[11px] text-ink-muted">{t("seen")}</p>}
        </div>
      </div>

      {conversation?.is_request_to_me && conversation.status === "request" ? (
        <div className="border-t border-line bg-surface px-4 py-4">
          <p className="text-[15px]">{t("request_from", { name: other.display_name })}</p>
          <p className="mt-1 text-sm text-ink-muted">{t("request_hint")}</p>
          <div className="mt-3 flex flex-wrap gap-2">
            <Button busy={act.isPending && act.variables === "accept"} onClick={() => act.mutate("accept")}>{t("accept")}</Button>
            <Button variant="secondary" onClick={() => act.mutate("decline")}>{t("decline")}</Button>
            <Button variant="danger" onClick={() => window.confirm(t("block_confirm", { name: other.display_name })) && act.mutate("block")}>{t("block")}</Button>
          </div>
        </div>
      ) : (
        <div className="border-t border-line px-3 py-3 sm:px-4">
          {pendingMine && <p className="mb-2 text-xs text-ink-muted">{t("pending_hint")}</p>}
          {send.error && <div className="mb-2"><Notice tone="error">{send.error instanceof ApiError ? send.error.message : t("error")}</Notice></div>}
          <form className="flex items-end gap-2" onSubmit={(e) => { e.preventDefault(); submit(); }}>
            <button type="button" onClick={() => setPicker(true)} aria-label={t("attach_photo")} className="mb-0.5 rounded-full p-2.5 text-ink-muted hover:bg-ink/5 hover:text-ink"><ImagePlus className="h-5 w-5" /></button>
            <button type="button" onClick={shareLocation} aria-label={t("attach_location")} className="mb-0.5 rounded-full p-2.5 text-ink-muted hover:bg-ink/5 hover:text-ink"><LocateFixed className="h-5 w-5" /></button>
            <textarea
              value={text}
              onChange={(e) => setText(e.target.value)}
              onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) { e.preventDefault(); submit(); } }}
              rows={1}
              maxLength={4000}
              placeholder={t("placeholder")}
              aria-label={t("placeholder")}
              className="max-h-40 min-h-11 flex-1 resize-none rounded-[22px] border border-line bg-surface px-4 py-2.5 text-[15px] leading-snug outline-none [field-sizing:content] focus:border-ink"
            />
            <button type="submit" disabled={!text.trim() || send.isPending} aria-label={t("send")}
              className="mb-0.5 inline-flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-ink text-surface transition-opacity disabled:opacity-30">
              <SendHorizontal className="h-[18px] w-[18px]" />
            </button>
          </form>
        </div>
      )}
      <MyPhotoPicker open={picker} onClose={() => setPicker(false)} title={t("attach_photo")} busy={send.isPending} onPick={(p) => send.mutate({ photo_id: p.id })} />
    </div>
  );
}
