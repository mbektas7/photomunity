"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useParams } from "next/navigation";
import { ThemeView } from "@/components/themes";
import { Notice } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import type { Theme } from "@/lib/types";

export default function ThemePage() {
  const { id } = useParams<{ id: string }>();
  const t = useTranslations("theme");
  const q = useQuery({ queryKey: ["theme", id], queryFn: () => api<Theme>(`themes/${id}`) });
  return (
    <div className="mx-auto flex max-w-[1440px] flex-col gap-4 px-3 pb-16 pt-2 sm:px-6 sm:pt-4 lg:px-10">
      <Link href="/themes" className="text-sm text-ink-muted hover:text-ink">← {t("all_themes")}</Link>
      {q.error ? (
        <Notice tone="error">{q.error instanceof ApiError && q.error.message ? q.error.message : t("not_found")}</Notice>
      ) : q.data ? (
        <ThemeView theme={q.data} />
      ) : (
        <div className="h-[40vh]" aria-busy />
      )}
    </div>
  );
}
