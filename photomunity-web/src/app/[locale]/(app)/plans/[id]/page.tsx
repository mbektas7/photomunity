"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useParams } from "next/navigation";
import { PlanForm, SharedPlanView } from "@/components/plans";
import { Notice } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import type { Plan, SharedPlan } from "@/lib/types";

const notMine = (e: unknown) => e instanceof ApiError && (e.status === 404 || e.status === 403);

/** Kendi planım: düzenleme formu. Başkasının paylaştığı plan: salt okunur görünüm + katıl. */
export default function PlanPage() {
  const { id } = useParams<{ id: string }>();
  const t = useTranslations("plans");
  const mine = useQuery({
    queryKey: ["plans", "one", id],
    queryFn: () => api<Plan>(`me/plans/${id}`),
    retry: (n, e) => !notMine(e) && n < 2,
  });
  const other = useQuery({
    queryKey: ["plans", "shared-one", id],
    enabled: notMine(mine.error),
    queryFn: () => api<SharedPlan>(`plans/${id}`),
    retry: (n, e) => !notMine(e) && n < 2,
  });
  const error = other.error ?? (notMine(mine.error) ? null : mine.error);
  const title = mine.data ? t("edit_title") : other.data ? t("shared_title") : t("title");

  return (
    <div className="mx-auto max-w-[1100px] px-4 pt-8 sm:px-6 sm:pt-12">
      <Link href="/plans" className="text-sm text-ink-muted hover:text-ink">← {t("title")}</Link>
      <h1 className="mb-8 mt-3 text-[clamp(2rem,4.5vw,3rem)] font-bold leading-none tracking-[-0.04em]">{title}</h1>
      {error ? (
        <Notice tone="error">{error instanceof ApiError && error.message ? error.message : t("not_found")}</Notice>
      ) : mine.data ? (
        <PlanForm key={mine.data.id} plan={mine.data} />
      ) : other.data ? (
        <SharedPlanView plan={other.data} />
      ) : (
        <div className="h-[50vh]" aria-busy />
      )}
    </div>
  );
}
