import type { InfiniteData, QueryClient } from "@tanstack/react-query";
import { ApiError } from "./api";
import type { ChatMessage, MessagePageData, Reaction } from "./types";

/** Sohbet önbelleğinde tek mesajın tepkilerini günceller (yanıt ya da WebSocket olayı). */
export function setMessageReactions(qc: QueryClient, cid: string, mid: string, reactions: Reaction[]) {
  qc.setQueryData<InfiniteData<MessagePageData>>(["messages", cid], (data) => {
    if (!data) return data;
    return {
      ...data,
      pages: data.pages.map((p) =>
        p.items.some((x) => x.id === mid) ? { ...p, items: p.items.map((x) => (x.id === mid ? { ...x, reactions } : x)) } : p,
      ),
    };
  });
}

/** Yeni mesajı ilk (en yeni) sayfanın sonuna ekler; zaten varsa dokunmaz. */
export function appendMessage(qc: QueryClient, cid: string, m: ChatMessage) {
  qc.setQueryData<InfiniteData<MessagePageData>>(["messages", cid], (data) => {
    if (!data || data.pages[0]?.items.some((x) => x.id === m.id)) return data;
    const [first, ...rest] = data.pages;
    return { ...data, pages: [{ ...first!, items: [...first!.items, m] }, ...rest] };
  });
}

/** Gövdesi, fotoğrafı, görseli, GIF'i ve konumu olmayan mesaj moderasyonla kaldırılmıştır. */
export function isRemoved(m: ChatMessage) {
  return !m.body && !m.photo && !m.image && !m.gif && !m.location;
}

// ---------- Anında gönderim ----------
// Gönderilen mesaj, sunucu yanıtı gelmeden ayrı bir önbellek girdisinde ("messages-pending") tutulur.
// Sohbet sorgusu her yenilendiğinde sayfalar sunucudan gelenle değiştiği için geçici mesajlar oraya yazılmaz;
// böylece "gönderilemedi" durumundaki mesaj da yenilemede kaybolmaz.

export type PendingStatus = "sending" | "failed";
export type PendingMessage = ChatMessage & {
  status: PendingStatus;
  /** Gönderim anında sohbetteki son sunucu mesajı; WebSocket yankısını eşlemek için */
  after_id: string | null;
  /** Hata yanıtındaki açıklama (ör. istek sınırı) */
  error?: string | null;
};

export const pendingKey = (cid: string) => ["messages-pending", cid] as const;

/** Geçici mesajın sunucuya gönderim işi; "Tekrar dene" aynı işi yeniden çalıştırır. Sayfa değişse de kalır. */
const senders = new Map<string, () => Promise<ChatMessage>>();

export function getPending(qc: QueryClient, cid: string) {
  return qc.getQueryData<PendingMessage[]>(pendingKey(cid)) ?? [];
}

function setPending(qc: QueryClient, cid: string, fn: (list: PendingMessage[]) => PendingMessage[]) {
  qc.setQueryData<PendingMessage[]>(pendingKey(cid), (list) => fn(list ?? []));
}

function release(m: PendingMessage | undefined) {
  if (m?.image?.url.startsWith("blob:")) URL.revokeObjectURL(m.image.url);
}

/** Geçici mesajı gönderir (ya da yeniden dener). Başarıda sunucu mesajıyla değiştirir; WebSocket yankısı appendMessage'da tekilleşir. */
async function run(qc: QueryClient, cid: string, tempId: string) {
  const send = senders.get(tempId);
  if (!send) return;
  setPending(qc, cid, (list) => list.map((x) => (x.id === tempId ? { ...x, status: "sending", error: null } : x)));
  try {
    const m = await send();
    const done = getPending(qc, cid).find((x) => x.id === tempId);
    senders.delete(tempId);
    setPending(qc, cid, (list) => list.filter((x) => x.id !== tempId));
    appendMessage(qc, cid, m);
    release(done);
  } catch (e) {
    // İstemci hatalarında (ör. istek sınırı, engel) sunucunun açıklaması gösterilir; ağ hatasında yalnızca "Tekrar dene"
    const error = e instanceof ApiError && e.status >= 400 && e.status < 500 && e.message ? e.message : null;
    setPending(qc, cid, (list) => list.map((x) => (x.id === tempId ? { ...x, status: "failed", error } : x)));
  }
}

/** Mesajı anında sohbete ekler ve arka planda gönderir. */
export function sendOptimistic(qc: QueryClient, cid: string, draft: Omit<PendingMessage, "id" | "status" | "after_id" | "created_at" | "conversation_id">, send: () => Promise<ChatMessage>) {
  const id = `tmp-${typeof crypto !== "undefined" && "randomUUID" in crypto ? crypto.randomUUID() : Date.now().toString(36) + Math.random().toString(36).slice(2)}`;
  const pages = qc.getQueryData<InfiniteData<MessagePageData>>(["messages", cid])?.pages;
  const after = pages?.[0]?.items.at(-1)?.id ?? null;
  senders.set(id, send);
  setPending(qc, cid, (list) => [
    ...list,
    { ...draft, id, conversation_id: cid, created_at: new Date().toISOString(), status: "sending", after_id: after },
  ]);
  void run(qc, cid, id);
}

export function retryPending(qc: QueryClient, cid: string, tempId: string) {
  void run(qc, cid, tempId);
}

export function discardPending(qc: QueryClient, cid: string, tempId: string) {
  release(getPending(qc, cid).find((x) => x.id === tempId));
  senders.delete(tempId);
  setPending(qc, cid, (list) => list.filter((x) => x.id !== tempId));
}

function signature(m: ChatMessage) {
  return [m.body?.trim() ?? "", m.gif?.id ?? "", m.photo?.id ?? "", m.location ? "loc" : "", m.image ? "img" : ""].join("|");
}

/**
 * Ekranda gösterilecek geçici mesajlar. Sunucu kendi mesajımızı WebSocket ile de yolladığı için yanıt gelmeden
 * önce yankı düşebilir: gönderim anından sonra gelen, aynı içerikli kendi mesajımız varsa geçici kopya gizlenir.
 */
export function visiblePending(server: ChatMessage[], pending: PendingMessage[]) {
  const claimed = new Set<string>();
  return pending.filter((p) => {
    if (p.status !== "sending") return true;
    const start = p.after_id ? server.findIndex((m) => m.id === p.after_id) + 1 : 0;
    const sig = signature(p);
    const hit = server.slice(start).find((m) => m.sender_id === p.sender_id && !claimed.has(m.id) && signature(m) === sig);
    if (!hit) return true;
    claimed.add(hit.id);
    return false;
  });
}
