"use client";

import { useQuery } from "@tanstack/react-query";
import clsx from "clsx";
import { Plus, Search } from "lucide-react";
import { useTranslations } from "next-intl";
import { useDeferredValue, useState } from "react";
import { CommunityRow } from "@/components/community";
import { buttonClass } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { api } from "@/lib/api";
import { useMe } from "@/lib/hooks";
import type { CommunityCard } from "@/lib/types";

export default function CommunitiesPage() {
  const t = useTranslations("communities");
  const { data: me } = useMe();
  const [q, setQ] = useState("");
  const [mine, setMine] = useState(false);
  const query = useDeferredValue(q.trim());
  const list = useQuery({
    queryKey: ["communities", query, mine],
    queryFn: () => api<CommunityCard[]>(`communities?limit=60${query ? `&q=${encodeURIComponent(query)}` : ""}${mine ? "&mine=true" : ""}`),
  });

  return (
    <div className="mx-auto max-w-[860px] px-4 pt-8 sm:px-6 sm:pt-12">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-[clamp(2rem,4.5vw,3rem)] font-bold leading-none tracking-[-0.04em]">{t("title")}</h1>
          <p className="mt-3 max-w-[52ch] text-muted">{t("lead")}</p>
        </div>
        {me && (
          <Link href="/communities/new" className={buttonClass("primary")}>
            <Plus className="h-4 w-4" strokeWidth={2.5} /> {t("create")}
          </Link>
        )}
      </div>

      <div className="mt-8 flex flex-wrap items-center gap-3">
        <label className="relative min-w-[220px] flex-1">
          <span className="sr-only">{t("search")}</span>
          <Search className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder={t("search_placeholder")}
            className="h-11 w-full rounded-full border border-line bg-mat pl-10 pr-4 text-[15px] outline-none focus:border-ink"
          />
        </label>
        {me && (
          <div className="flex rounded-full border border-line bg-mat p-1">
            {[false, true].map((v) => (
              <button
                key={String(v)}
                type="button"
                onClick={() => setMine(v)}
                aria-pressed={mine === v}
                className={clsx("h-9 rounded-full px-4 text-sm font-medium", mine === v ? "bg-ink text-mat" : "text-muted hover:text-ink")}
              >
                {v ? t("mine") : t("all")}
              </button>
            ))}
          </div>
        )}
      </div>

      <div className="mt-6 flex flex-col gap-2">
        {list.data?.map((c) => <CommunityRow key={c.id} c={c} />)}
        {list.isSuccess && list.data.length === 0 && (
          <div className="bg-mat px-6 py-10 text-muted">{mine ? t("empty_mine") : query ? t("no_results") : t("empty")}</div>
        )}
      </div>
    </div>
  );
}
