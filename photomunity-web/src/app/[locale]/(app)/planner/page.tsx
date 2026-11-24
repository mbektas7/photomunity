"use client";

import { useTranslations } from "next-intl";
import { SkyPlanner } from "@/components/SkyPlanner";
import { Link } from "@/i18n/navigation";
import { HowItWorks } from "@/components/intro";

export default function PlannerPage() {
  const t = useTranslations("planner");
  return (
    <div className="mx-auto max-w-[1000px] px-4 pt-8 sm:px-6 sm:pt-12">
      <Link href="/guide" className="text-sm text-ink-muted hover:text-ink">← {t("back")}</Link>
      <h1 className="mt-3 flex items-center gap-3 text-[clamp(2rem,4.5vw,3rem)] font-bold leading-none tracking-[-0.04em]">{t("title")} <HowItWorks module="nightplanner" /></h1>
      <p className="mt-3 max-w-[62ch] text-ink-muted">{t("lead")}</p>
      <div className="mt-8"><SkyPlanner /></div>
    </div>
  );
}
