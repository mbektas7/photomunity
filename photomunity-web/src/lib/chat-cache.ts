import type { InfiniteData, QueryClient } from "@tanstack/react-query";
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
