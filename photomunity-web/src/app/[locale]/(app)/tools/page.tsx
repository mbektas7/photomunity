"use client";

import { useTranslations } from "next-intl";
import { DofCalculator, NdCalculator, NpfCalculator } from "@/components/calculators";
import { Link } from "@/i18n/navigation";

export default function ToolsPage() {
  const t = useTranslations("tools");
  return (
    <div className="mx-auto max-w-[900px] px-4 pt-8 sm:px-6 sm:pt-12">
      <Link href="/guide" className="text-sm text-ink-muted hover:text-ink">← {t("back")}</Link>
      <h1 className="mt-3 text-[clamp(2rem,4.5vw,3rem)] font-bold leading-none tracking-[-0.04em]">{t("title")}</h1>
      <div className="mt-8 flex flex-col gap-6">
        <NpfCalculator />
        <DofCalculator />
        <NdCalculator />
      </div>
    </div>
  );
}
