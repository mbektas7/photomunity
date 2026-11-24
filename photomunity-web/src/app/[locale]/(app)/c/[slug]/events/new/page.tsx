"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useParams } from "next/navigation";
import { EventForm } from "@/components/events";
import { Notice } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { api } from "@/lib/api";
import type { Community } from "@/lib/types";

export default function NewEventPage() {
  const { slug } = useParams<{ slug: string }>();
  const t = useTranslations("events");
  const q = useQuery({ queryKey: ["community", slug], queryFn: () => api<Community>(`communities/${slug}`) });
  const c = q.data;
  const isAdmin = c?.my_role === "owner" || c?.my_role === "admin";
  return (
    <div className="mx-auto max-w-[760px] px-4 pb-16 pt-8 sm:px-6 sm:pt-12">
      <Link href={`/c/${slug}?tab=events`} className="text-sm text-ink-muted hover:text-ink">← {c?.name ?? ""}</Link>
      <h1 className="mb-8 mt-3 text-[clamp(2rem,4.5vw,3rem)] font-bold leading-none tracking-[-0.04em]">{t("new")}</h1>
      {c && !isAdmin ? <Notice tone="error">{t("no_permission")}</Notice> : c ? <EventForm slug={slug} /> : <div className="h-[40vh]" aria-busy />}
    </div>
  );
}
