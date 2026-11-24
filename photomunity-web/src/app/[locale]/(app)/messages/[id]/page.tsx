"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useParams, useSearchParams } from "next/navigation";
import { Suspense } from "react";
import { Thread } from "@/components/Thread";
import { Notice } from "@/components/ui";
import { ApiError, api } from "@/lib/api";
import { useMe } from "@/lib/hooks";
import type { Conversation } from "@/lib/types";

export default function ConversationPage() {
  return (
    <Suspense>
      <ConversationView />
    </Suspense>
  );
}

function ConversationView() {
  const { id } = useParams<{ id: string }>();
  const t = useTranslations("messages");
  // ?license=<fotoğraf id>: "Lisans iste" ile gelindi; taslak metin hazır
  const license = useSearchParams().get("license");
  const { data: me } = useMe();
  const q = useQuery({ queryKey: ["conversation", id], queryFn: () => api<Conversation>(`conversations/${id}`) });
  if (q.error) return <div className="p-6"><Notice tone="error">{q.error instanceof ApiError ? q.error.message : "—"}</Notice></div>;
  if (!q.data || !me) return <div className="h-full" aria-busy />;
  const draft = license ? t("license_request", { url: `${typeof window === "undefined" ? "" : window.location.origin}/p/${license}` }) : "";
  return <Thread key={id} conversation={q.data} other={q.data.other} meId={me.id} initialText={draft} />;
}
