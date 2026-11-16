"use client";

import { type InfiniteData, useQueryClient } from "@tanstack/react-query";
import { useEffect } from "react";
import { api } from "./api";
import { useMe } from "./hooks";
import type { ChatMessage, MessagePageData } from "./types";

const WS_URL = process.env.NEXT_PUBLIC_WS_URL || "ws://localhost:8000/api/v1/ws";

/**
 * Oturum açıkken API'ye WebSocket ile bağlanır; gelen mesajları sorgu önbelleğine işler.
 * Bağlantı koparsa artan aralıklarla yeniden dener; o sürede sayfalar periyodik yenilemeyle çalışmaya devam eder.
 */
export function RealtimeBridge() {
  const { data: me } = useMe();
  const qc = useQueryClient();

  useEffect(() => {
    if (!me) return;
    let ws: WebSocket | null = null;
    let stopped = false;
    let attempt = 0;
    let ping: ReturnType<typeof setInterval> | undefined;
    let retry: ReturnType<typeof setTimeout> | undefined;

    async function connect() {
      try {
        const { ticket } = await api<{ ticket: string }>("realtime/ticket", { method: "POST" });
        if (stopped) return;
        ws = new WebSocket(`${WS_URL}?ticket=${encodeURIComponent(ticket)}`);
      } catch {
        schedule();
        return;
      }
      ws.onopen = () => {
        attempt = 0;
        ping = setInterval(() => ws?.readyState === WebSocket.OPEN && ws.send("ping"), 25_000);
      };
      ws.onmessage = (ev) => {
        const e = JSON.parse(ev.data);
        if (e.type === "message") {
          const m: ChatMessage = e.message;
          qc.setQueryData<InfiniteData<MessagePageData>>(["messages", e.conversation_id], (data) => {
            if (!data || data.pages[0]?.items.some((x) => x.id === m.id)) return data;
            const [first, ...rest] = data.pages;
            return { ...data, pages: [{ ...first!, items: [...first!.items, m] }, ...rest] };
          });
          qc.invalidateQueries({ queryKey: ["conversations"] });
          qc.invalidateQueries({ queryKey: ["conversation", e.conversation_id] });
          qc.invalidateQueries({ queryKey: ["messages-unread"] });
        } else if (e.type === "read") {
          qc.invalidateQueries({ queryKey: ["conversation", e.conversation_id] });
        }
      };
      ws.onclose = () => {
        clearInterval(ping);
        schedule();
      };
    }

    function schedule() {
      if (stopped) return;
      attempt += 1;
      retry = setTimeout(connect, Math.min(30_000, 1000 * 2 ** attempt));
    }

    connect();
    return () => {
      stopped = true;
      clearInterval(ping);
      clearTimeout(retry);
      ws?.close();
    };
  }, [me, qc]);

  return null;
}
