"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useParams } from "next/navigation";
import { EventForm } from "@/components/events";
import { Notice } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import type { CommunityEvent } from "@/lib/types";

export default function EditEventPage() {
  const { id } = useParams<{ id: string }>();
  const t = useTranslations("events");
  const q = useQuery({ queryKey: ["event", id], queryFn: () => api<CommunityEvent>(`events/${id}`) });
  const e = q.data;
  return (
    <div className="mx-auto max-w-[760px] px-4 pb-16 pt-8 sm:px-6 sm:pt-12">
      <Link href={`/events/${id}`} className="text-sm text-ink-muted hover:text-ink">← {e?.title ?? t("kicker")}</Link>
      <h1 className="mb-8 mt-3 text-[clamp(2rem,4.5vw,3rem)] font-bold leading-none tracking-[-0.04em]">{t("edit_title")}</h1>
      {q.error ? (
        <Notice tone="error">{q.error instanceof ApiError && q.error.message ? q.error.message : t("not_found")}</Notice>
      ) : e ? (
        e.can_manage ? <EventForm key={e.id} event={e} /> : <Notice tone="error">{t("no_permission")}</Notice>
      ) : (
        <div className="h-[40vh]" aria-busy />
      )}
    </div>
  );
}
