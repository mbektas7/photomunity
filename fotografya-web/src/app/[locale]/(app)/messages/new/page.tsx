"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useSearchParams } from "next/navigation";
import { Suspense, useEffect } from "react";
import { Thread } from "@/components/Thread";
import { Notice } from "@/components/ui";
import { useRouter } from "@/i18n/navigation";
import { api } from "@/lib/api";
import { useMe } from "@/lib/hooks";
import type { Conversation, Profile } from "@/lib/types";

export default function NewMessagePage() {
  return (
    <Suspense>
      <NewMessage />
    </Suspense>
  );
}

function NewMessage() {
  const t = useTranslations("messages");
  const to = useSearchParams().get("to") ?? "";
  const router = useRouter();
  const { data: me } = useMe();
  const profile = useQuery({ queryKey: ["profile", to], enabled: !!to, queryFn: () => api<Profile>(`users/${to}`) });
  const existing = useQuery({ queryKey: ["conversation-with", to], enabled: !!to && !!me, queryFn: () => api<Conversation | null>(`conversations/with/${to}`) });

  useEffect(() => {
    if (existing.data) router.replace(`/messages/${existing.data.id}`);
  }, [existing.data, router]);

  if (!me || !profile.data || existing.isLoading || existing.data) return <div className="h-full" aria-busy />;
  if (!profile.data.is_public) return <div className="p-6"><Notice>{t("private_cannot")}</Notice></div>;
  return <Thread conversation={null} other={profile.data} meId={me.id} />;
}
