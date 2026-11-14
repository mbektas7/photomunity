"use client";

import { useQuery } from "@tanstack/react-query";
import { useParams } from "next/navigation";
import { Thread } from "@/components/Thread";
import { Notice } from "@/components/ui";
import { ApiError, api } from "@/lib/api";
import { useMe } from "@/lib/hooks";
import type { Conversation } from "@/lib/types";

export default function ConversationPage() {
  const { id } = useParams<{ id: string }>();
  const { data: me } = useMe();
  const q = useQuery({ queryKey: ["conversation", id], queryFn: () => api<Conversation>(`conversations/${id}`) });
  if (q.error) return <div className="p-6"><Notice tone="error">{q.error instanceof ApiError ? q.error.message : "—"}</Notice></div>;
  if (!q.data || !me) return <div className="h-full" aria-busy />;
  return <Thread key={id} conversation={q.data} other={q.data.other} meId={me.id} />;
}
