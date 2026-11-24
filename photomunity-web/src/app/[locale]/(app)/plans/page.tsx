"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import clsx from "clsx";
import { CalendarDays, Plus } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useEffect, useState } from "react";
import { PlanRow } from "@/components/plans";
import { buttonClass } from "@/components/ui";
import { Link, useRouter } from "@/i18n/navigation";
import { api } from "@/lib/api";
import { useMe } from "@/lib/hooks";
import type { EventCard, Page, Plan } from "@/lib/types";

export default function PlansPage() {
  const t = useTranslations("plans");
  const locale = useLocale();
  const router = useRouter();
  const qc = useQueryClient();
  const { data: me, isLoading } = useMe();
  const [scope, setScope] = useState<"upcoming" | "past">("upcoming");

  useEffect(() => {
    if (!isLoading && !me) router.replace("/login");
  }, [me, isLoading, router]);

  const q = useQuery({ queryKey: ["plans", scope], enabled: !!me, queryFn: () => api<Page<Plan>>(`me/plans?scope=${scope}`) });
  const events = useQuery({ queryKey: ["events", "mine"], enabled: !!me, queryFn: () => api<EventCard[]>("me/events") });
  const remove = useMutation({
    mutationFn: (id: string) => api(`me/plans/${id}`, { method: "DELETE" }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["plans"] }),
  });
  const items = q.data?.items ?? [];
  const myEvents = (events.data ?? []).filter((e) => e.status === "upcoming" || e.status === "ongoing");

  return (
    <div className="mx-auto max-w-[820px] px-4 pt-8 sm:px-6 sm:pt-12">
      <Link href="/sky" className="text-sm text-ink-muted hover:text-ink">← {t("back_sky")}</Link>
      <div className="mt-3 flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-[clamp(2rem,4.5vw,3rem)] font-bold leading-none tracking-[-0.04em]">{t("title")}</h1>
          <p className="mt-3 max-w-[56ch] text-ink-muted">{t("lead")}</p>
        </div>
        <Link href="/plans/new" className={buttonClass("primary")}>
          <Plus className="h-4 w-4" strokeWidth={2.5} aria-hidden /> {t("new")}
        </Link>
      </div>

      <div className="mt-6 flex gap-1 border-b border-line" role="tablist" aria-label={t("title")}>
        {(["upcoming", "past"] as const).map((k) => (
          <button
            key={k}
            type="button"
            role="tab"
            aria-selected={scope === k}
            onClick={() => setScope(k)}
            className={clsx("-mb-px border-b-2 px-4 py-3 text-[15px] font-medium", scope === k ? "border-ink text-ink" : "border-transparent text-ink-muted hover:text-ink")}
          >
            {t(`scope.${k}`)}
          </button>
        ))}
      </div>

      {q.isSuccess && items.length === 0 && (
        <div className="mt-6 rounded-card bg-surface px-6 py-12">
          <p className="text-ink-muted">{scope === "upcoming" ? t("empty_upcoming") : t("empty_past")}</p>
          {scope === "upcoming" && (
            <Link href="/plans/new" className={buttonClass("primary", "mt-5")}>{t("new")}</Link>
          )}
        </div>
      )}
      <ul className="mt-6 flex flex-col gap-2">
        {items.map((p) => (
          <PlanRow
            key={p.id}
            plan={p}
            busy={remove.isPending && remove.variables === p.id}
            onDelete={() => window.confirm(t("delete_confirm")) && remove.mutate(p.id)}
          />
        ))}
      </ul>

      {scope === "upcoming" && myEvents.length > 0 && (
        <section aria-labelledby="my-events" className="mt-10">
          <h2 id="my-events" className="mb-3 text-heading">{t("my_events")}</h2>
          <ul className="flex flex-col gap-2">
            {myEvents.map((e) => (
              <li key={e.id}>
                <Link href={`/events/${e.id}`} className="flex items-center gap-4 rounded-card bg-surface px-5 py-4 hover:bg-surface/80">
                  <CalendarDays className="h-5 w-5 shrink-0 text-ink-muted" aria-hidden />
                  <span className="min-w-0 flex-1">
                    <span className="block truncate font-semibold">{e.title}</span>
                    <span className="tnum block truncate text-sm text-ink-muted">
                      {new Intl.DateTimeFormat(locale, { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }).format(new Date(e.starts_at))} · {e.community.name}
                    </span>
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  );
}
