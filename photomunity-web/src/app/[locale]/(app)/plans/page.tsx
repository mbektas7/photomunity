"use client";

import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import clsx from "clsx";
import { CalendarDays, Plus } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useCallback, useEffect, useState } from "react";
import { HowItWorks } from "@/components/intro";
import { PlanRow, SharedPlanRow } from "@/components/plans";
import { buttonClass } from "@/components/ui";
import { Link, useRouter } from "@/i18n/navigation";
import { api } from "@/lib/api";
import { useLoadMore, useMe } from "@/lib/hooks";
import type { EventCard, Page, Plan, SharedPlan } from "@/lib/types";

export default function PlansPage() {
  const t = useTranslations("plans");
  const locale = useLocale();
  const router = useRouter();
  const qc = useQueryClient();
  const { data: me, isLoading } = useMe();
  const [scope, setScope] = useState<"upcoming" | "past" | "friends">("upcoming");

  useEffect(() => {
    if (!isLoading && !me) router.replace("/login");
  }, [me, isLoading, router]);

  const q = useQuery({ queryKey: ["plans", scope], enabled: !!me && scope !== "friends", queryFn: () => api<Page<Plan>>(`me/plans?scope=${scope}`) });
  const events = useQuery({ queryKey: ["events", "mine"], enabled: !!me, queryFn: () => api<EventCard[]>("me/events") });
  const remove = useMutation({
    mutationFn: (id: string) => api(`me/plans/${id}`, { method: "DELETE" }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["plans"] }),
  });
  const shared = useInfiniteQuery({
    queryKey: ["plans", "shared"],
    enabled: !!me && scope === "friends",
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) => api<Page<SharedPlan>>(pageParam ? `plans/shared?limit=20&cursor=${encodeURIComponent(pageParam)}` : "plans/shared?limit=20"),
    getNextPageParam: (last) => last.next_cursor,
  });
  const { fetchNextPage, hasNextPage, isFetchingNextPage } = shared;
  const loadMore = useCallback(() => !isFetchingNextPage && fetchNextPage(), [fetchNextPage, isFetchingNextPage]);
  const sentinel = useLoadMore(loadMore, scope === "friends" && !!hasNextPage);
  const sharedItems = shared.data?.pages.flatMap((p) => p.items) ?? [];
  const items = scope === "friends" ? [] : q.data?.items ?? [];
  const myEvents = (events.data ?? []).filter((e) => e.status === "upcoming" || e.status === "ongoing");

  return (
    <div className="mx-auto max-w-[820px] px-4 pt-8 sm:px-6 sm:pt-12">
      <Link href="/sky" className="text-sm text-ink-muted hover:text-ink">← {t("back_sky")}</Link>
      <div className="mt-3 flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="flex items-center gap-3 text-[clamp(2rem,4.5vw,3rem)] font-bold leading-none tracking-[-0.04em]">{t("title")} <HowItWorks module="plans" /></h1>
          <p className="mt-3 max-w-[56ch] text-ink-muted">{t("lead")}</p>
        </div>
        <Link href="/plans/new" className={buttonClass("primary")}>
          <Plus className="h-4 w-4" strokeWidth={2.5} aria-hidden /> {t("new")}
        </Link>
      </div>

      <div className="mt-6 flex gap-1 border-b border-line" role="tablist" aria-label={t("title")}>
        {(["upcoming", "friends", "past"] as const).map((k) => (
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

      {scope === "friends" && (
        <>
          {shared.isError && <p className="mt-6 rounded-card bg-surface px-6 py-12 text-ink-muted">{t("shared_error")}</p>}
          {shared.isSuccess && sharedItems.length === 0 && (
            <p className="mt-6 rounded-card bg-surface px-6 py-12 text-ink-muted">{t("empty_friends")}</p>
          )}
          <ul className="mt-6 flex flex-col gap-2">
            {sharedItems.map((p) => <SharedPlanRow key={p.id} plan={p} />)}
          </ul>
          <div ref={sentinel} className="h-px" />
        </>
      )}

      {scope !== "friends" && q.isSuccess && items.length === 0 && (
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
