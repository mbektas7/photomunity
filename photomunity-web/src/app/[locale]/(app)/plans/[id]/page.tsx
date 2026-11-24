"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useParams } from "next/navigation";
import { PlanForm } from "@/components/plans";
import { Notice } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import type { Plan } from "@/lib/types";

export default function EditPlanPage() {
  const { id } = useParams<{ id: string }>();
  const t = useTranslations("plans");
  const q = useQuery({ queryKey: ["plans", "one", id], queryFn: () => api<Plan>(`me/plans/${id}`) });
  return (
    <div className="mx-auto max-w-[1100px] px-4 pt-8 sm:px-6 sm:pt-12">
      <Link href="/plans" className="text-sm text-ink-muted hover:text-ink">← {t("title")}</Link>
      <h1 className="mb-8 mt-3 text-[clamp(2rem,4.5vw,3rem)] font-bold leading-none tracking-[-0.04em]">{t("edit_title")}</h1>
      {q.error ? (
        <Notice tone="error">{q.error instanceof ApiError && q.error.message ? q.error.message : t("not_found")}</Notice>
      ) : q.data ? (
        <PlanForm key={q.data.id} plan={q.data} />
      ) : (
        <div className="h-[50vh]" aria-busy />
      )}
    </div>
  );
}
