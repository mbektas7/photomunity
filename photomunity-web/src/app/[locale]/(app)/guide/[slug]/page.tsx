"use client";

import { useQuery } from "@tanstack/react-query";
import { Check, Moon, X } from "lucide-react";
import { useTranslations } from "next-intl";
import { useParams } from "next/navigation";
import { CalculatorFor } from "@/components/calculators";
import { Notice, buttonClass } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";

type Guide = {
  slug: string; title: string; summary: string; calculator: string | null; planner: boolean;
  settings: Record<"mode" | "aperture" | "shutter" | "iso" | "focus" | "white_balance" | "other", string>;
  tips: string[]; mistakes: string[];
};

export default function GuidePage() {
  const { slug } = useParams<{ slug: string }>();
  const t = useTranslations("guide");
  const q = useQuery({ queryKey: ["guide", slug], queryFn: () => api<Guide>(`guides/${slug}`) });
  if (q.error) return <div className="mx-auto max-w-[680px] px-4 py-20"><Notice tone="error">{q.error instanceof ApiError ? q.error.message : "—"}</Notice></div>;
  const g = q.data;
  if (!g) return <div className="h-[60vh]" aria-busy />;
  const main = [["aperture", g.settings.aperture], ["shutter", g.settings.shutter], ["iso", g.settings.iso]] as const;
  const rest = [["mode", g.settings.mode], ["focus", g.settings.focus], ["white_balance", g.settings.white_balance], ["other", g.settings.other]] as const;

  return (
    <div className="mx-auto max-w-[860px] px-4 pt-8 sm:px-6 sm:pt-12">
      <Link href="/guide" className="text-sm text-ink-muted hover:text-ink">← {t("title")}</Link>
      <h1 className="mt-3 text-[clamp(2.2rem,5vw,3.4rem)] font-bold leading-[0.98] tracking-[-0.045em]">{g.title}</h1>
      <p className="mt-3 max-w-[60ch] text-lg text-ink-muted">{g.summary}</p>

      {/* Vizör şeridi: üç temel ayar */}
      <dl className="mt-8 grid gap-2 sm:grid-cols-3">
        {main.map(([k, v]) => (
          <div key={k} className="flex flex-col-reverse rounded-box bg-surface-2 px-5 py-5 text-ink">
            <dt className="mt-2 text-[13px] text-ink-muted">{t(`setting.${k}`)}</dt>
            <dd className="text-[19px] font-semibold leading-snug">{v}</dd>
          </div>
        ))}
      </dl>
      <dl className="divide-y divide-line overflow-hidden rounded-card bg-surface px-5">
        {rest.map(([k, v]) => (
          <div key={k} className="grid gap-1 py-3.5 sm:grid-cols-[180px_1fr]">
            <dt className="text-sm text-ink-muted">{t(`setting.${k}`)}</dt>
            <dd className="text-[15px]">{v}</dd>
          </div>
        ))}
      </dl>

      <div className="mt-10 grid gap-10 sm:grid-cols-2">
        <section>
          <h2 className="text-lg font-semibold">{t("tips")}</h2>
          <ul className="mt-3 flex flex-col gap-3">
            {g.tips.map((x) => <li key={x} className="flex gap-3 text-[15px] leading-relaxed"><Check className="mt-1 h-4 w-4 shrink-0 text-accent-text" strokeWidth={2.5} /> {x}</li>)}
          </ul>
        </section>
        <section>
          <h2 className="text-lg font-semibold">{t("mistakes")}</h2>
          <ul className="mt-3 flex flex-col gap-3">
            {g.mistakes.map((x) => <li key={x} className="flex gap-3 text-[15px] leading-relaxed"><X className="mt-1 h-4 w-4 shrink-0 text-danger" strokeWidth={2.5} /> {x}</li>)}
          </ul>
        </section>
      </div>

      {g.planner && (
        <Link href="/planner" className={buttonClass("primary", "mt-10")}><Moon className="h-4 w-4" /> {t("open_planner")}</Link>
      )}
      {g.calculator && <div className="mt-10"><CalculatorFor id={g.calculator} /></div>}
    </div>
  );
}
