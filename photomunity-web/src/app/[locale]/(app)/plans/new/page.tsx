"use client";

import { useTranslations } from "next-intl";
import { useSearchParams } from "next/navigation";
import { Suspense, useEffect } from "react";
import { type PlanPrefill, PlanForm } from "@/components/plans";
import { Link, useRouter } from "@/i18n/navigation";
import { useMe } from "@/lib/hooks";
import { PLAN_KINDS, type PlanKind } from "@/lib/types";

export default function NewPlanPage() {
  return (
    <Suspense>
      <NewPlan />
    </Suspense>
  );
}

const num = (v: string | null) => (v != null && v !== "" && Number.isFinite(+v) ? +v : undefined);

function NewPlan() {
  const t = useTranslations("plans");
  const params = useSearchParams();
  const router = useRouter();
  const { data: me, isLoading } = useMe();

  useEffect(() => {
    if (!isLoading && !me) router.replace("/login");
  }, [me, isLoading, router]);

  const kind = params.get("kind");
  const lat = num(params.get("lat")), lng = num(params.get("lng"));
  const prefill: PlanPrefill = {
    kind: PLAN_KINDS.includes(kind as PlanKind) ? (kind as PlanKind) : undefined,
    lat: lat != null && Math.abs(lat) <= 90 ? lat : undefined,
    lng: lng != null && Math.abs(lng) <= 180 ? lng : undefined,
    place: params.get("place") ?? undefined,
    at: num(params.get("at")),
    title: params.get("title") ?? undefined,
  };

  if (!me) return <div className="h-[60vh]" aria-busy />;
  return (
    <div className="mx-auto max-w-[1100px] px-4 pt-8 sm:px-6 sm:pt-12">
      <Link href="/plans" className="text-sm text-ink-muted hover:text-ink">← {t("title")}</Link>
      <h1 className="mb-8 mt-3 text-[clamp(2rem,4.5vw,3rem)] font-bold leading-none tracking-[-0.04em]">{t("new_title")}</h1>
      <PlanForm prefill={prefill} />
    </div>
  );
}
