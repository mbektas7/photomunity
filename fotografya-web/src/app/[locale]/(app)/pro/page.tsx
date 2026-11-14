"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import clsx from "clsx";
import { Check } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useSearchParams } from "next/navigation";
import { Suspense, useEffect, useState } from "react";
import { ProBadge } from "@/components/AdSlot";
import { Button, Notice } from "@/components/ui";
import { usePathname, useRouter } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import { formatDate } from "@/lib/format";
import { useMe } from "@/lib/hooks";
import type { BillingStatus } from "@/lib/types";

export default function ProPage() {
  return (
    <Suspense>
      <Pro />
    </Suspense>
  );
}

function Pro() {
  const t = useTranslations("pro");
  const locale = useLocale();
  const router = useRouter();
  const pathname = usePathname();
  const qc = useQueryClient();
  const returned = useSearchParams().get("status") === "success";
  const { data: me } = useMe();
  const [plan, setPlan] = useState<"monthly" | "yearly">("yearly");
  const [polls, setPolls] = useState(0);

  const status = useQuery({
    queryKey: ["billing"],
    enabled: !!me,
    queryFn: () => api<BillingStatus>("billing/status"),
    // Stripe'tan dönüşte webhook birkaç saniye gecikebilir: Pro açılana kadar kısa süre yokla
    refetchInterval: (q) => (returned && !q.state.data?.is_pro && polls < 15 ? 2000 : false),
  });
  useEffect(() => {
    if (returned && status.dataUpdatedAt) setPolls((n) => n + 1);
    if (status.data?.is_pro) qc.invalidateQueries({ queryKey: ["me"] });
  }, [status.dataUpdatedAt, returned, status.data?.is_pro, qc]);

  const checkout = useMutation({
    mutationFn: () => api<{ url: string }>("billing/checkout", { method: "POST", body: { plan } }),
    onSuccess: ({ url }) => { window.location.href = url; },
  });
  const portal = useMutation({
    mutationFn: () => api<{ url: string }>("billing/portal", { method: "POST" }),
    onSuccess: ({ url }) => { window.location.href = url; },
  });

  const s = status.data;
  const prices = s?.prices ?? { monthly: "$1.99", yearly: "$17.99" };
  const num = (p: string) => Number(p.replace(/[^0-9.]/g, ""));
  const saving = Math.round((1 - num(prices.yearly) / (num(prices.monthly) * 12)) * 100);
  const perks = ["no_ads", "badge", "uploads", "support"] as const;

  return (
    <div className="mx-auto max-w-[920px] px-4 pt-10 sm:px-6 sm:pt-16">
      <div className="flex items-center gap-3"><ProBadge className="px-2 py-0.5 text-[12px]" /><span className="text-sm text-muted">Fotografya Pro</span></div>
      <h1 className="mt-4 max-w-[16ch] text-[clamp(2.4rem,6vw,4.2rem)] font-bold leading-[0.98] tracking-[-0.045em]">{t("title")}</h1>
      <p className="mt-4 max-w-[52ch] text-lg text-muted">{t("lead")}</p>

      {returned && !s?.is_pro && <div className="mt-8"><Notice>{t("activating")}</Notice></div>}

      <div className="mt-10 grid gap-10 md:grid-cols-[minmax(0,1fr)_380px]">
        <ul className="flex flex-col gap-5">
          {perks.map((k) => (
            <li key={k} className="flex gap-4">
              <span className="mt-0.5 inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-accent text-accent-ink"><Check className="h-4 w-4" strokeWidth={3} /></span>
              <span>
                <span className="block text-[17px] font-semibold">{t(`perk.${k}`)}</span>
                <span className="mt-0.5 block text-[15px] text-muted">{t(`perk.${k}_body`)}</span>
              </span>
            </li>
          ))}
        </ul>

        <div className="order-first self-start bg-mat p-5 md:order-none">
          {s?.is_pro ? (
            <>
              <p className="flex items-center gap-2 text-lg font-semibold"><Check className="h-5 w-5 text-accent" strokeWidth={3} /> {t("you_are_pro")}</p>
              {s.period_end && (
                <p className="mt-2 text-[15px] text-muted">
                  {s.will_renew ? t("renews", { date: formatDate(s.period_end, locale) ?? "" }) : t("ends", { date: formatDate(s.period_end, locale) ?? "" })}
                </p>
              )}
              {s.status === "grace" && <div className="mt-3"><Notice tone="error">{t("payment_issue")}</Notice></div>}
              {s.can_manage_on_web ? (
                <Button variant="secondary" className="mt-5 w-full" busy={portal.isPending} onClick={() => portal.mutate()}>{t("manage")}</Button>
              ) : (
                <p className="mt-5 text-sm text-muted">{t(s.store === "play_store" ? "manage_play" : "manage_apple")}</p>
              )}
            </>
          ) : (
            <>
              <div role="radiogroup" aria-label={t("plan")} className="grid grid-cols-2 gap-2">
                {(["monthly", "yearly"] as const).map((p) => (
                  <button key={p} type="button" role="radio" aria-checked={plan === p} onClick={() => setPlan(p)}
                    className={clsx("relative border px-3 py-3 text-left", plan === p ? "border-ink" : "border-line hover:border-ink/40")}>
                    <span className="block text-sm text-muted">{t(p)}</span>
                    <span className="tnum mt-1 block text-[22px] font-semibold">{prices[p]}</span>
                    <span className="block text-xs text-muted">{t(`per_${p}`)}</span>
                    {p === "yearly" && saving > 0 && (
                      <span className="absolute -top-2.5 right-2 bg-accent px-1.5 py-0.5 text-[11px] font-semibold text-accent-ink">{t("save", { pct: saving })}</span>
                    )}
                  </button>
                ))}
              </div>
              {checkout.error && <div className="mt-4"><Notice tone="error">{checkout.error instanceof ApiError ? checkout.error.message : t("error")}</Notice></div>}
              <Button className="mt-5 h-12 w-full text-base" busy={checkout.isPending}
                onClick={() => (me ? checkout.mutate() : router.push(`/login?next=${encodeURIComponent(pathname)}`))}>
                {t("cta")}
              </Button>
              <p className="mt-3 text-xs leading-relaxed text-muted">{t("fine_print")}</p>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
