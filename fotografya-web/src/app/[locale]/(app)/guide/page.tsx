"use client";

import { useQuery } from "@tanstack/react-query";
import { Aperture, Calculator, Moon, Timer } from "lucide-react";
import { useTranslations } from "next-intl";
import { AdSlot } from "@/components/AdSlot";
import { Link } from "@/i18n/navigation";
import { api } from "@/lib/api";

type GuideCard = { slug: string; category: string; title: string; summary: string; calculator: string | null; planner: boolean };
const CATEGORIES = ["night", "landscape", "action", "people"];

export default function GuideHub() {
  const t = useTranslations("guide");
  const q = useQuery({ queryKey: ["guides"], queryFn: () => api<GuideCard[]>("guides") });
  const tools = [
    { href: "/planner", icon: Moon, title: t("planner_title"), body: t("planner_body"), accent: true },
    { href: "/tools#npf", icon: Timer, title: t("npf_title"), body: t("npf_body") },
    { href: "/tools#dof", icon: Aperture, title: t("dof_title"), body: t("dof_body") },
    { href: "/tools#nd", icon: Calculator, title: t("nd_title"), body: t("nd_body") },
  ];
  return (
    <div className="mx-auto max-w-[1100px] px-4 pt-8 sm:px-6 sm:pt-12">
      <h1 className="text-[clamp(2rem,4.5vw,3rem)] font-bold leading-none tracking-[-0.04em]">{t("title")}</h1>
      <p className="mt-3 max-w-[60ch] text-ink-muted">{t("lead")}</p>

      <div className="mt-8 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {tools.map(({ href, icon: Icon, title, body, accent }) => (
          <Link key={href} href={href} className={accent ? "rounded-card bg-accent px-5 py-5 text-accent-ink hover:brightness-110" : "rounded-card bg-surface px-5 py-5 hover:bg-surface/80"}>
            <Icon className="h-6 w-6" strokeWidth={1.7} />
            <p className="mt-4 font-semibold">{title}</p>
            <p className={accent ? "mt-1 text-sm text-accent-ink/85" : "mt-1 text-sm text-ink-muted"}>{body}</p>
          </Link>
        ))}
      </div>

      {CATEGORIES.map((cat) => {
        const items = q.data?.filter((g) => g.category === cat) ?? [];
        if (!items.length) return null;
        return (
          <section key={cat} className="mt-12">
            <h2 className="text-lg font-semibold">{t(`category.${cat}`)}</h2>
            <div className="mt-4 grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
              {items.map((g) => (
                <Link key={g.slug} href={`/guide/${g.slug}`} className="rounded-card bg-surface px-5 py-5 transition-colors hover:bg-surface/70">
                  <p className="text-[17px] font-semibold tracking-[-0.01em]">{g.title}</p>
                  <p className="mt-1 text-sm leading-relaxed text-ink-muted">{g.summary}</p>
                </Link>
              ))}
            </div>
          </section>
        );
      })}
      <AdSlot kind="banner" className="mt-12" />
    </div>
  );
}
