"use client";

import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import clsx from "clsx";
import { AlertCircle, Aperture, ArrowLeft, Clock3, Images, LocateFixed, MapPin, MoreHorizontal, Plus, SendHorizontal, Smile, SmilePlus, X } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { Link, useRouter } from "@/i18n/navigation";
import { ApiError, api, uploadToStorage } from "@/lib/api";
import {
  type PendingMessage, appendMessage, discardPending, isRemoved, pendingKey, retryPending, sendOptimistic, setMessageReactions, visiblePending,
} from "@/lib/chat-cache";
import type { ChatMessage, Conversation, Gif, MessagePageData, MessageQuote, Reaction, UserCard } from "@/lib/types";
import { Avatar } from "./Avatar";
import { GifPicker, MessageMenu, ReactionPills } from "./chat-extras";
import { MyPhotoPicker } from "./community";
import { ReportDialog } from "./ReportDialog";
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

const IMAGE_TYPES = "image/jpeg,image/png,image/webp,image/heic,image/heif,.heic";

/** Galeriden seçilen görseli profil görseli akışıyla yükler; sohbete gönderilecek anahtarı döner. */
async function uploadChatImage(file: File) {
  const slot = await api<{ upload_url: string; fields: Record<string, string> }>("me/images/upload-url", {
    method: "POST",
    body: { kind: "message", content_type: file.type || "image/heic", size_bytes: file.size },
  });
  await uploadToStorage(slot.upload_url, slot.fields, file, () => undefined);
  return slot.fields.key!;
}

function useQuoteText() {
  const t = useTranslations("messages");
  return (q: Pick<MessageQuote, "kind" | "preview">) => q.preview || t(`kind_${q.kind}` as "kind_text");
}

function quoteOf(m: ChatMessage): Pick<MessageQuote, "kind" | "preview"> {
  const kind = m.image ? "image" : m.gif ? "gif" : m.photo ? "photo" : m.location ? "location" : "text";
  return { kind, preview: m.body };
}

function Bubble({ m, mine, meId, otherName, onMenu, onReact, onJump, status, error, onRetry, onDiscard }: {
  m: ChatMessage;
  mine: boolean;
  meId: string;
  otherName: string;
  onMenu?: (m: ChatMessage, rect: DOMRect) => void;
  onReact?: (m: ChatMessage, emoji: string) => void;
  onJump: (id: string) => void;
  /** Yalnızca anında gönderilen (henüz sunucuya ulaşmamış) mesajlarda */
  status?: PendingMessage["status"];
  error?: string | null;
  onRetry?: () => void;
  onDiscard?: () => void;
}) {
  const t = useTranslations("messages");
  const locale = useLocale();
  const quoteText = useQuoteText();
  const time = new Intl.DateTimeFormat(locale, { hour: "2-digit", minute: "2-digit" }).format(new Date(m.created_at));
  const img = m.photo?.images.feed ?? m.photo?.images.thumb;
  const removed = isRemoved(m);
  const body = useRef<HTMLDivElement>(null);
  const press = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const open = () => body.current && onMenu?.(m, body.current.getBoundingClientRect());
  const r = m.reply_to;
  const failed = status === "failed";

  return (
    <div id={`m-${m.id}`} className={clsx("group flex items-center gap-1.5", mine ? "flex-row-reverse" : "flex-row")}>
      <div
        ref={body}
        className={clsx("max-w-[78%] sm:max-w-[62%]", mine ? "items-end" : "items-start", "flex flex-col gap-1", status === "sending" && "opacity-60")}
        onContextMenu={(e) => {
          if (!onMenu || removed) return;
          e.preventDefault();
          open();
        }}
        onTouchStart={() => {
          if (!onMenu || removed) return;
          press.current = setTimeout(open, 450);
        }}
        onTouchEnd={() => clearTimeout(press.current)}
        onTouchMove={() => clearTimeout(press.current)}
      >
        {r && (
          <button type="button" onClick={() => onJump(r.id)}
            className={clsx("max-w-full rounded-[14px] border-l-[3px] px-3 py-1.5 text-left text-[13px]", mine ? "border-accent bg-accent-tint" : "border-line bg-surface-2")}>
            <span className="block font-semibold">{r.sender_id === meId ? t("you") : otherName}</span>
            <span className="line-clamp-2 break-words text-ink-muted">{quoteText(r)}</span>
          </button>
        )}
        {removed ? (
          <p className="rounded-[20px] border border-line px-4 py-2.5 text-[15px] italic text-ink-muted">{t("removed")}</p>
        ) : (
          <>
            {m.image && !m.image.url && (
              // Önizlemesi tarayıcıda gösterilemeyen (HEIC) görsel yüklenirken
              <span className="flex h-[140px] w-[180px] items-center justify-center rounded-[18px] bg-surface-2 text-ink-muted">
                <Images className="h-7 w-7" strokeWidth={1.6} aria-label={t("kind_image")} />
              </span>
            )}
            {m.image && m.image.url && (
              <a href={m.image.url} target="_blank" rel="noreferrer" className="block max-w-full">
                {/* Galeriden gelen görsel kırpılmadan, kendi oranında */}
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={m.image.url} alt={t("kind_image")} width={m.image.width} height={m.image.height}
                  className="block h-auto max-h-[300px] w-auto max-w-full rounded-[18px] bg-surface-2 object-contain" />
              </a>
            )}
            {m.gif && (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={m.gif.url} alt={m.gif.kind === "sticker" ? t("tab_sticker") : "GIF"} width={m.gif.width} height={m.gif.height}
                className={clsx("block h-auto max-h-[220px] w-auto max-w-full object-contain", m.gif.kind === "gif" && "rounded-[18px]")} />
            )}
            {m.photo && img && (
              <Link href={`/p/${m.photo.id}`} className="block overflow-hidden rounded-card bg-surface p-3">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={img.url} alt={m.photo.title ?? ""} className="block max-h-[320px] w-auto max-w-full rounded-photo" />
                <span className="block px-1 pb-0.5 pt-2.5 text-[14px] font-semibold">{m.photo.title ?? m.photo.user.display_name}</span>
              </Link>
            )}
            {m.location && (
              <a href={`/map?lat=${m.location.latitude}&lng=${m.location.longitude}&z=12&layer=photos`}
                className={clsx("inline-flex min-h-11 items-center gap-2 rounded-[20px] px-4 py-2.5 text-[15.5px] font-semibold", mine ? "bg-accent text-accent-ink" : "bg-surface")}>
                <MapPin className="h-[18px] w-[18px]" strokeWidth={1.9} aria-hidden /> {m.location.name || t("shared_location")}
              </a>
            )}
            {m.body && (
              <p className={clsx(
                "whitespace-pre-wrap break-words rounded-[20px] px-4 py-2.5 text-[15.5px] leading-[1.45]",
                failed ? "rounded-br-[6px] border-[1.5px] border-danger/50 bg-surface text-ink" : mine ? "rounded-br-[6px] bg-accent text-accent-ink" : "rounded-bl-[6px] bg-surface",
              )}>
                {m.body}
              </p>
            )}
          </>
        )}
        <ReactionPills reactions={m.reactions ?? []} meId={meId} mine={mine} onToggle={onReact && ((e) => onReact(m, e))} />
        {status === "sending" ? (
          <span className="flex items-center gap-1 px-1 text-[11.5px] text-ink-muted" aria-live="polite">
            <Clock3 className="h-3 w-3" strokeWidth={2} aria-hidden /> {t("sending")}
          </span>
        ) : failed ? (
          <span className="flex flex-col items-end gap-0.5 px-1" role="alert">
            <span className="flex items-center gap-1">
              <button type="button" onClick={onRetry} className="inline-flex min-h-8 items-center gap-1 rounded-pill text-[12px] font-bold text-danger hover:underline">
                <AlertCircle className="h-3.5 w-3.5" strokeWidth={2} aria-hidden /> {t("send_failed_retry")}
              </button>
              <span aria-hidden className="text-[12px] text-ink-muted">·</span>
              <button type="button" onClick={onDiscard} className="inline-flex min-h-8 items-center rounded-pill text-[12px] font-semibold text-ink-muted hover:text-ink hover:underline">
                {t("send_failed_delete")}
              </button>
            </span>
            {error && <span className="max-w-[36ch] text-right text-[11.5px] text-ink-muted">{error}</span>}
          </span>
        ) : (
          <span className="tnum px-1 text-[11px] text-ink-muted">{time}</span>
        )}
      </div>
      {onMenu && !removed && (
        <button type="button" onClick={open} aria-label={t("message_actions")}
          className="inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-ink-muted opacity-0 transition-opacity hover:bg-surface hover:text-ink focus-visible:opacity-100 group-hover:opacity-100 [@media(hover:none)]:hidden">
          <SmilePlus className="h-[18px] w-[18px]" />
        </button>
      )}
    </div>
  );
}

/** Tek sohbet. `conversation` yoksa yeni sohbet: ilk mesaj gönderilince oluşturulur. */
export function Thread({ conversation, other, meId, initialText = "" }: { conversation: Conversation | null; other: UserCard; meId: string; /** Yazma alanına önceden konan metin (ör. lisans isteği) */ initialText?: string }) {
  const t = useTranslations("messages");
  const locale = useLocale();
  const router = useRouter();
  const qc = useQueryClient();
  const cid = conversation?.id;
  const scroller = useRef<HTMLDivElement>(null);
  const content = useRef<HTMLDivElement>(null);
  const atBottom = useRef(true);
  const [text, setText] = useState(initialText);
  const [picker, setPicker] = useState(false);
  const [menu, setMenu] = useState(false);
  const [plus, setPlus] = useState(false);
  const [gifs, setGifs] = useState(false);
  const [replyTo, setReplyTo] = useState<ChatMessage | null>(null);
  const [msgMenu, setMsgMenu] = useState<{ m: ChatMessage; rect: DOMRect } | null>(null);
  const [reporting, setReporting] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);
  const fileInput = useRef<HTMLInputElement>(null);
  const textInput = useRef<HTMLTextAreaElement>(null);
  const plusRef = useRef<HTMLDivElement>(null);
  const quoteText = useQuoteText();

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

  // Anında gönderilen, sunucu yanıtı beklenen ya da gönderilemeyen mesajlar (bkz. chat-cache)
  const pendingQ = useQuery({
    queryKey: pendingKey(cid ?? ""),
    enabled: !!cid,
    queryFn: () => qc.getQueryData<PendingMessage[]>(pendingKey(cid!)) ?? [],
    initialData: [] as PendingMessage[],
    staleTime: Infinity,
    gcTime: Infinity,
  });
  const pending = cid ? visiblePending(messages, pendingQ.data) : [];
  const shown: (ChatMessage | PendingMessage)[] = [...messages, ...pending];
  const shownLastId = shown.at(-1)?.id;

  const read = useMutation({ mutationFn: () => api(`conversations/${cid}/read`, { method: "POST" }), onSuccess: () => qc.invalidateQueries({ queryKey: ["messages-unread"] }) });
  useEffect(() => {
    if (cid && lastId && messages.at(-1)?.sender_id !== meId) read.mutate();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cid, lastId]);

  useLayoutEffect(() => {
    const el = scroller.current;
    if (el && atBottom.current) el.scrollTop = el.scrollHeight;
  }, [shownLastId, q.data?.pages.length]);

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

  /** Yeni sohbet: ilk mesaj sohbeti oluşturur; yanıt beklenir ve sohbet sayfasına geçilir. */
  const send = useMutation({
    mutationFn: async (payload: Record<string, unknown>) => {
      if (!cid) {
        const c = await api<Conversation>("conversations", { method: "POST", body: { username: other.username, ...payload } });
        return { created: c };
      }
      const m = await api<ChatMessage>(`conversations/${cid}/messages`, { method: "POST", body: payload });
      return { message: m };
    },
    onSuccess: (r, payload) => {
      if (payload.body) setText("");
      setPicker(false);
      setGifs(false);
      setReplyTo(null);
      atBottom.current = true;
      if (r.created) {
        qc.invalidateQueries({ queryKey: ["conversations"] });
        router.replace(`/messages/${r.created.id}`);
        return;
      }
      appendMessage(qc, cid!, r.message!);
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

  const react = useMutation({
    mutationFn: ({ m, emoji }: { m: ChatMessage; emoji: string | null }) =>
      emoji
        ? api<Reaction[]>(`conversations/${cid}/messages/${m.id}/reaction`, { method: "PUT", body: { emoji } })
        : api<Reaction[]>(`conversations/${cid}/messages/${m.id}/reaction`, { method: "DELETE" }),
    onSuccess: (list, { m }) => setMessageReactions(qc, cid!, m.id, list),
  });

  function toggleReaction(m: ChatMessage, emoji: string) {
    const mineNow = m.reactions?.find((r) => r.user_id === meId)?.emoji ?? null;
    react.mutate({ m, emoji: mineNow === emoji ? null : emoji });
  }

  /**
   * Cevap seçiliyse her gönderime eklenir. Var olan sohbette mesaj anında (iyimser) eklenir, girdi hemen temizlenir;
   * istek arka planda gider. `preview` ekranda gösterilecek geçici içeriktir; `prepare` gönderimden önce yapılacak iş (görsel yükleme).
   */
  function sendWith(payload: Record<string, unknown>, preview: Partial<ChatMessage> = {}, prepare?: () => Promise<Record<string, unknown>>) {
    setPicker(false);
    setGifs(false);
    if (!cid) {
      send.mutate(payload);
      return;
    }
    const reply = replyTo;
    const full = reply ? { ...payload, reply_to_id: reply.id } : payload;
    setReplyTo(null);
    atBottom.current = true;
    sendOptimistic(
      qc,
      cid,
      {
        sender_id: meId,
        body: typeof payload.body === "string" ? payload.body : null,
        photo: null,
        location: null,
        image: null,
        gif: null,
        reactions: [],
        reply_to: reply ? { id: reply.id, sender_id: reply.sender_id, ...quoteOf(reply) } : null,
        ...preview,
      },
      async () => {
        const extra = prepare ? await prepare() : {};
        const m = await api<ChatMessage>(`conversations/${cid}/messages`, { method: "POST", body: { ...full, ...extra } });
        qc.invalidateQueries({ queryKey: ["conversations"] });
        qc.invalidateQueries({ queryKey: ["conversation", cid] });
        return m;
      },
    );
  }

  function submit() {
    const body = text.trim();
    if (!body) return;
    if (cid) setText("");
    sendWith({ body });
  }

  function shareLocation() {
    navigator.geolocation?.getCurrentPosition((p) => {
      const location = { latitude: +p.coords.latitude.toFixed(4), longitude: +p.coords.longitude.toFixed(4), name: null };
      sendWith({ location }, { location });
    });
  }

  async function sendImage(file: File | undefined) {
    if (fileInput.current) fileInput.current.value = "";
    if (!file) return;
    setUploadError(null);
    if (cid) {
      // Görsel anında yerel önizlemeyle eklenir; yükleme ve gönderim arka planda (hata olursa "Tekrar dene" ikisini de yineler)
      const heic = /hei[cf]/i.test(file.type) || /\.hei[cf]$/i.test(file.name);
      const url = heic ? "" : URL.createObjectURL(file);
      sendWith({}, { image: { url, width: 0, height: 0 } }, async () => ({ image_key: await uploadChatImage(file) }));
      return;
    }
    setUploading(true);
    try {
      const key = await uploadChatImage(file);
      sendWith({ image_key: key });
    } catch (e) {
      setUploadError(e instanceof ApiError && e.message ? e.message : t("upload_failed"));
    } finally {
      setUploading(false);
    }
  }

  function jumpTo(id: string) {
    const el = document.getElementById(`m-${id}`);
    if (!el) return;
    el.scrollIntoView({ behavior: "smooth", block: "center" });
    el.animate?.([{ opacity: 0.4 }, { opacity: 1 }], { duration: 700 });
  }

  const closeMsgMenu = useCallback(() => setMsgMenu(null), []);

  useEffect(() => {
    if (!plus) return;
    const close = (e: MouseEvent) => !plusRef.current?.contains(e.target as Node) && setPlus(false);
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, [plus]);

  const seenAt = conversation?.other_last_read_at ? new Date(conversation.other_last_read_at) : null;
  // "Görüldü" yalnızca en son mesaj bensem ve karşı taraf onu okuduysa
  const last = messages.at(-1); // geçici mesajlar hariç
  const seen = !!(last && last.sender_id === meId && seenAt && seenAt >= new Date(last.created_at));
  const pendingMine = conversation?.status === "request" && !conversation.is_request_to_me;

  return (
    <div className="flex h-full flex-col">
      <header className="flex items-center gap-3 bg-surface px-3 py-2.5 sm:px-4">
        <Link href="/messages" className="inline-flex h-11 w-11 items-center justify-center rounded-full hover:bg-surface-2 lg:hidden" aria-label={t("back")}><ArrowLeft className="h-5 w-5" strokeWidth={1.8} /></Link>
        <Link href={`/u/${other.username}`} className="flex min-w-0 flex-1 items-center gap-3">
          <Avatar name={other.display_name} url={other.avatar_url} size={38} />
          <span className="min-w-0">
            <span className="block truncate font-semibold">{other.display_name}</span>
            <span className="block truncate text-xs text-ink-muted">@{other.username}</span>
          </span>
        </Link>
        {cid && (
          <div className="relative">
            <button type="button" onClick={() => setMenu((x) => !x)} aria-label={t("more")} aria-expanded={menu} className="inline-flex h-11 w-11 items-center justify-center rounded-full hover:bg-surface-2"><MoreHorizontal className="h-5 w-5" /></button>
            {menu && (
              <div className="absolute right-0 top-11 z-20 w-48 rounded-box bg-surface p-1.5 shadow-float">
                <button type="button" className="block min-h-11 w-full rounded-box px-3 py-2 text-left text-[15px] text-danger hover:bg-surface-2"
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
          if (msgMenu) setMsgMenu(null);
          const el = e.currentTarget;
          atBottom.current = el.scrollHeight - el.scrollTop - el.clientHeight < 80;
          if (el.scrollTop < 120 && q.hasNextPage && !q.isFetchingNextPage) q.fetchNextPage();
        }}>
        <div ref={content}>
        {!cid && <p className="mx-auto mt-10 max-w-[44ch] text-center text-sm text-ink-muted">{t("new_hint", { name: other.display_name })}</p>}
        <div className="flex flex-col gap-2.5">
          {shown.map((m, i) => {
            const showDay = i === 0 || new Date(shown[i - 1]!.created_at).toDateString() !== new Date(m.created_at).toDateString();
            const status = "status" in m ? m.status : undefined;
            return (
              <div key={m.id} className="flex flex-col gap-2.5">
                {showDay && <p className="my-2 text-center text-[13px] font-semibold text-ink-muted">{dayLabel(m.created_at, locale)}</p>}
                {status ? (
                  <Bubble m={m} mine meId={meId} otherName={other.display_name} onJump={jumpTo}
                    status={status} error={"error" in m ? m.error : null}
                    onRetry={() => retryPending(qc, cid!, m.id)} onDiscard={() => discardPending(qc, cid!, m.id)} />
                ) : (
                  <Bubble m={m} mine={m.sender_id === meId} meId={meId} otherName={other.display_name} onJump={jumpTo}
                    onMenu={cid ? (msg, rect) => setMsgMenu({ m: msg, rect }) : undefined}
                    onReact={cid ? toggleReaction : undefined} />
                )}
              </div>
            );
          })}
        </div>
        {seen && <p className="mt-1 px-1 text-right text-[11px] text-ink-muted">{t("seen")}</p>}
        </div>
      </div>

      {conversation?.is_request_to_me && conversation.status === "request" ? (
        <div className="mx-3 mb-3 rounded-card bg-surface px-4 py-4">
          <p className="text-[15px]">{t("request_from", { name: other.display_name })}</p>
          <p className="mt-1 text-sm text-ink-muted">{t("request_hint")}</p>
          <div className="mt-3 flex flex-wrap gap-2">
            <Button busy={act.isPending && act.variables === "accept"} onClick={() => act.mutate("accept")}>{t("accept")}</Button>
            <Button variant="secondary" onClick={() => act.mutate("decline")}>{t("decline")}</Button>
            <Button variant="danger" onClick={() => window.confirm(t("block_confirm", { name: other.display_name })) && act.mutate("block")}>{t("block")}</Button>
          </div>
        </div>
      ) : (
        <div className="relative px-3 py-3 sm:px-4">
          {gifs && <GifPicker busy={send.isPending} onClose={() => setGifs(false)} onPick={(g: Gif) => sendWith({ gif: { id: g.id, kind: g.kind } }, { gif: g })} />}
          {pendingMine && <p className="mb-2 text-xs text-ink-muted">{t("pending_hint")}</p>}
          {(send.error || uploadError) && (
            <div className="mb-2">
              <Notice tone="error">{uploadError ?? (send.error instanceof ApiError && send.error.message ? send.error.message : t("error"))}</Notice>
            </div>
          )}
          {replyTo && (
            <div className="mb-2 flex items-center gap-2 rounded-box border-l-[3px] border-accent bg-surface py-1.5 pl-3 pr-1">
              <span className="min-w-0 flex-1 text-[13px]">
                <span className="block font-semibold">{replyTo.sender_id === meId ? t("replying_to_self") : t("replying_to", { name: other.display_name })}</span>
                <span className="block truncate text-ink-muted">{quoteText(quoteOf(replyTo))}</span>
              </span>
              <button type="button" onClick={() => setReplyTo(null)} aria-label={t("cancel_reply")} className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full hover:bg-surface-2">
                <X className="h-4 w-4" />
              </button>
            </div>
          )}
          {uploading && <p className="mb-2 text-xs text-ink-muted" aria-live="polite">{t("uploading")}</p>}
          <form className="flex items-end gap-2" onSubmit={(e) => { e.preventDefault(); submit(); }}>
            <div ref={plusRef} className="relative shrink-0">
              <button type="button" onClick={() => setPlus((x) => !x)} aria-label={t("attach")} aria-expanded={plus}
                className="inline-flex h-11 w-11 items-center justify-center rounded-full bg-surface text-ink hover:bg-surface-2">
                <Plus className={clsx("h-5 w-5 transition-transform", plus && "rotate-45")} />
              </button>
              {plus && (
                <div className="absolute bottom-12 left-0 z-30 w-[260px] rounded-box bg-surface p-1.5 shadow-float" role="menu">
                  <button type="button" role="menuitem" disabled={uploading} onClick={() => { setPlus(false); fileInput.current?.click(); }}
                    className="flex w-full items-start gap-3 rounded-box px-3 py-2.5 text-left hover:bg-surface-2 disabled:opacity-50">
                    <Images className="mt-0.5 h-5 w-5 shrink-0" strokeWidth={1.8} aria-hidden />
                    <span>
                      <span className="block text-[15px] font-medium">{t("attach_gallery")}</span>
                      <span className="block text-[12.5px] text-ink-muted">{t("attach_gallery_hint")}</span>
                    </span>
                  </button>
                  <button type="button" role="menuitem" onClick={() => { setPlus(false); setPicker(true); }}
                    className="flex min-h-11 w-full items-center gap-3 rounded-box px-3 py-2.5 text-left text-[15px] font-medium hover:bg-surface-2">
                    <Aperture className="h-5 w-5 shrink-0" strokeWidth={1.8} aria-hidden />
                    {t("attach_my_photos")}
                  </button>
                  <button type="button" role="menuitem" onClick={() => { setPlus(false); shareLocation(); }}
                    className="flex min-h-11 w-full items-center gap-3 rounded-box px-3 py-2.5 text-left text-[15px] font-medium hover:bg-surface-2">
                    <LocateFixed className="h-5 w-5 shrink-0" strokeWidth={1.8} aria-hidden />
                    {t("attach_location")}
                  </button>
                </div>
              )}
            </div>
            <button type="button" onClick={() => setGifs((x) => !x)} aria-label={t("gif_button")} aria-expanded={gifs}
              className={clsx("inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-full hover:bg-surface-2", gifs ? "bg-accent-tint text-accent-text" : "bg-surface text-ink")}>
              <Smile className="h-5 w-5" />
            </button>
            <input ref={fileInput} type="file" accept={IMAGE_TYPES} className="sr-only" tabIndex={-1} aria-hidden onChange={(e) => sendImage(e.target.files?.[0])} />
            <textarea
              ref={textInput}
              value={text}
              onChange={(e) => setText(e.target.value)}
              onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) { e.preventDefault(); submit(); } }}
              rows={1}
              maxLength={4000}
              placeholder={t("placeholder")}
              aria-label={t("placeholder")}
              className="max-h-40 min-h-11 flex-1 resize-none rounded-[22px] border border-transparent bg-surface px-4 py-2.5 text-[15px] leading-snug outline-none [field-sizing:content] focus:border-accent"
            />
            <button type="submit" disabled={!text.trim() || (!cid && send.isPending)} aria-label={t("send")}
              className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-accent text-accent-ink transition-opacity disabled:opacity-40">
              <SendHorizontal className="h-[18px] w-[18px]" />
            </button>
          </form>
        </div>
      )}
      {msgMenu && (
        <MessageMenu
          anchor={msgMenu.rect}
          mine={msgMenu.m.sender_id === meId}
          myEmoji={msgMenu.m.reactions?.find((r) => r.user_id === meId)?.emoji ?? null}
          onReact={(e) => { toggleReaction(msgMenu.m, e); setMsgMenu(null); }}
          onClose={closeMsgMenu}
          items={[
            { label: t("reply"), onClick: () => { setReplyTo(msgMenu.m); textInput.current?.focus(); } },
            ...(msgMenu.m.body ? [{ label: t("copy"), onClick: () => void navigator.clipboard?.writeText(msgMenu.m.body!) }] : []),
            ...(msgMenu.m.sender_id !== meId ? [{ label: t("report"), danger: true, onClick: () => setReporting(msgMenu.m.id) }] : []),
          ]}
        />
      )}
      {reporting && <ReportDialog targetType="message" targetId={reporting} open onClose={() => setReporting(null)} />}
      <MyPhotoPicker open={picker} onClose={() => setPicker(false)} title={t("attach_photo")} busy={send.isPending} onPick={(p) => sendWith({ photo_id: p.id }, { photo: p })} />
    </div>
  );
}
