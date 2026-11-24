"use client";

import { useTranslations } from "next-intl";
import { PastThemes, ThemeView, useCurrentTheme, usePreviousTheme } from "@/components/themes";
import { Notice } from "@/components/ui";

export default function ThemesPage() {
  const t = useTranslations("theme");
  const q = useCurrentTheme();
  const prev = usePreviousTheme();
  return (
    <div className="mx-auto flex max-w-[1440px] flex-col gap-10 px-3 pb-16 pt-2 sm:px-6 sm:pt-4 lg:px-10">
      {q.isError && <Notice tone="error">{t("error")}</Notice>}
      {q.isLoading && <div className="h-[40vh]" aria-busy />}
      {q.isSuccess && q.data && <ThemeView theme={q.data} previous={prev.data?.items[0] ?? null} />}
      {q.isSuccess && !q.data && (
        <div className="rounded-card bg-surface px-6 py-14">
          <h1 className="text-title">{t("none_title")}</h1>
          <p className="mt-2 text-ink-muted">{t("none_body")}</p>
        </div>
      )}
      <PastThemes />
    </div>
  );
}
