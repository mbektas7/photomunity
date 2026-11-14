"use client";

import { useQuery } from "@tanstack/react-query";
import clsx from "clsx";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { ContestRow } from "@/components/community";
import { api } from "@/lib/api";
import type { ContestCard } from "@/lib/types";

const TABS = ["open", "judging", "finished"] as const;

export default function ContestsPage() {
  const t = useTranslations("contests");
  const [tab, setTab] = useState<(typeof TABS)[number]>("open");
  const q = useQuery({ queryKey: ["contests", tab], queryFn: () => api<ContestCard[]>(`contests?status=${tab}`) });
  return (
    <div className="mx-auto max-w-[860px] px-4 pt-8 sm:px-6 sm:pt-12">
      <h1 className="text-[clamp(2rem,4.5vw,3rem)] font-bold leading-none tracking-[-0.04em]">{t("title")}</h1>
      <p className="mt-3 max-w-[56ch] text-muted">{t("lead")}</p>
      <div className="mt-8 flex gap-1 border-b border-line">
        {TABS.map((k) => (
          <button key={k} type="button" onClick={() => setTab(k)} aria-pressed={tab === k}
            className={clsx("-mb-px border-b-2 px-4 py-3 text-[15px] font-medium", tab === k ? "border-ink" : "border-transparent text-muted hover:text-ink")}>
            {t(`tab_${k}`)}
          </button>
        ))}
      </div>
      <div className="mt-6 flex flex-col gap-2">
        {q.data?.map((c) => <ContestRow key={c.id} c={c} />)}
        {q.isSuccess && q.data.length === 0 && <p className="bg-mat px-6 py-10 text-muted">{t(`empty_${tab}`)}</p>}
      </div>
    </div>
  );
}
