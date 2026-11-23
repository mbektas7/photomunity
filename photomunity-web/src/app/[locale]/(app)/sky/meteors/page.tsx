"use client";

import clsx from "clsx";
import { useLocale, useTranslations } from "next-intl";
import { useMemo } from "react";
import { MoonShape, useMounted } from "@/components/sky";
import { Link } from "@/i18n/navigation";
import { moonIllumination } from "@/lib/astro";
import { upcomingShowers } from "@/lib/sky";

/** Ay %35'in altındaysa (karanlık gece tanımı) zirve gecesi iyi sayılır. */
const GOOD = 0.35;

function List() {
  const t = useTranslations("sky");
  const locale = useLocale();
  const list = useMemo(() => upcomingShowers(new Date(), 10), []);
  const thisYear = new Date().getFullYear();
  const range = new Intl.DateTimeFormat(locale, { day: "numeric", month: "long" });
  const rangeY = new Intl.DateTimeFormat(locale, { day: "numeric", month: "long", year: "numeric" });
  const short = new Intl.DateTimeFormat(locale, { day: "numeric", month: "short" });
  return (
    <ul className="mt-8 flex flex-col gap-2">
      {list.map(({ s, peak, moon }) => {
        // Zirve gecesi: zirve gününden önceki akşamdan zirve sabahına
        const eve = new Date(peak.getFullYear(), peak.getMonth(), peak.getDate() - 1);
        const good = moon < GOOD;
        const from = new Date(peak.getFullYear() - (s.activeFrom[0] > s.month ? 1 : 0), s.activeFrom[0] - 1, s.activeFrom[1]);
        const to = new Date(peak.getFullYear() + (s.activeTo[0] < s.month ? 1 : 0), s.activeTo[0] - 1, s.activeTo[1]);
        const phase = moonIllumination(peak.getTime()).phase;
        return (
          <li key={s.key} className="flex items-center gap-4 rounded-card bg-surface px-5 py-4">
            <MoonShape phase={phase} fraction={moon} size={40} className="shrink-0" />
            <div className="min-w-0 flex-1">
              <p className="flex flex-wrap items-baseline gap-x-2 font-semibold">
                {t(`meteor.${s.key}`)}
                <span className="tnum text-[15px] font-normal text-ink-muted">{(peak.getFullYear() !== thisYear ? rangeY : range).formatRange(eve, peak)}</span>
              </p>
              <p className="tnum text-sm text-ink-muted">
                {t("meteors.zhr", { n: s.zhr })} · {t("meteors.moon", { pct: Math.round(moon * 100) })} · {t("meteors.active", { range: short.formatRange(from, to) })}
              </p>
            </div>
            <span className={clsx("shrink-0 rounded-pill px-3 py-1 text-sm font-semibold", good ? "bg-accent-tint text-accent-text" : "bg-surface-2 text-ink-muted")}>
              {good ? t("meteors.good") : t("meteors.bright")}
            </span>
          </li>
        );
      })}
    </ul>
  );
}

export default function MeteorsPage() {
  const t = useTranslations("sky");
  const mounted = useMounted();
  return (
    <div className="mx-auto max-w-[900px] px-4 pt-8 sm:px-6 sm:pt-12">
      <Link href="/sky" className="text-sm text-ink-muted hover:text-ink">← {t("title")}</Link>
      <h1 className="mt-3 text-[clamp(2rem,4.5vw,3rem)] font-bold leading-none tracking-[-0.04em]">{t("meteors.title")}</h1>
      <p className="mt-3 max-w-[62ch] text-ink-muted">{t("meteors.lead")}</p>
      {mounted ? <List /> : <div className="mt-8 h-[600px] rounded-card bg-surface" />}
      <p className="mt-6 text-sm text-ink-muted">{t("meteors.tip")}</p>
      <p className="mt-2 text-xs text-ink-muted">{t("meteors.note")}</p>
    </div>
  );
}
