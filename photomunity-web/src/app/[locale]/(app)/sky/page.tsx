"use client";

import clsx from "clsx";
import { CalendarDays, ChevronRight, Moon, Smartphone, Sparkles, Sunrise } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useMemo } from "react";
import { LocationLine, MoonShape, fmtTime, useMounted, useSkyLocation } from "@/components/sky";
import { Link } from "@/i18n/navigation";
import { compassPoint, planNight } from "@/lib/astro";
import { moonPhaseKey, upcomingShowers } from "@/lib/sky";

function Tonight({ lat, lng }: { lat: number; lng: number }) {
  const t = useTranslations("sky");
  const locale = useLocale();
  // Gece yarısından sonra (06:00'ya kadar) hâlâ içinde bulunulan gece gösterilir
  const plan = useMemo(() => {
    const now = new Date();
    return planNight(new Date(now.getFullYear(), now.getMonth(), now.getDate() - (now.getHours() < 6 ? 1 : 0)), lat, lng);
  }, [lat, lng]);
  const good = plan.bestWindows.length > 0;
  const first = plan.bestWindows[0], last = plan.bestWindows.at(-1);
  const pct = Math.round(plan.illumination * 100);
  // Ay bu gece batıyor mu doğuyor mu: öğleden öğleye penceredeki olay
  const moonNote = plan.moonset && (!plan.moonrise || plan.moonset < plan.moonrise)
    ? t("tonight.moon_sets", { time: fmtTime(plan.moonset, locale) })
    : plan.moonrise ? t("tonight.moon_rises", { time: fmtTime(plan.moonrise, locale) }) : null;
  // Çekirdeğin en yüksek anı karanlıkta (Güneş −18° altı; tam karanlık yoksa −12° altı) aranır;
  // gündüz geçişi fotoğraf için anlamsız
  const darkSamples = plan.samples.filter((x) => x.sun.alt < -18);
  const pool = darkSamples.length ? darkSamples : plan.samples.filter((x) => x.sun.alt < -12);
  const top = pool.reduce<(typeof pool)[number] | null>((m, x) => (!m || x.core.alt > m.core.alt ? x : m), null);
  const corePeak = top && top.core.alt > 0 ? { t: top.t, alt: top.core.alt, az: top.core.az } : null;
  const reason = !corePeak || corePeak.alt < 10 ? "core" : plan.illumination >= 0.25 ? "moon" : "dark";
  return (
    <div className="rounded-card bg-[#11141c] px-5 py-6 text-white sm:px-7">
      <p className="text-xs font-semibold uppercase tracking-[0.08em] text-white/60">{t("tonight.label")}</p>
      <div className="mt-4 flex items-center gap-5">
        <MoonShape phase={plan.phase} fraction={plan.illumination} size={68} />
        <div className="min-w-0">
          <p className="text-[24px] font-bold leading-tight tracking-[-0.02em]">{good ? t("tonight.good") : t("tonight.not_good")}</p>
          <p className="tnum mt-1 text-[15px] text-white/70">
            {t(`phase.${moonPhaseKey(plan.phase)}`)} · %{pct}{moonNote ? ` · ${moonNote}` : ""}
          </p>
        </div>
      </div>
      <div className="mt-6 grid gap-px overflow-hidden rounded-box bg-white/10 sm:grid-cols-2">
        <div className="bg-[#11141c] px-4 py-3">
          <p className="text-sm text-white/60">{t("tonight.window")}</p>
          <p className="tnum mt-0.5 text-[20px] font-semibold">
            {first && last ? `${fmtTime(first.start, locale)} – ${fmtTime(last.end, locale)}` : t("tonight.no_window")}
          </p>
        </div>
        <div className="bg-[#11141c] px-4 py-3">
          <p className="text-sm text-white/60">{t("tonight.core_peak")}</p>
          <p className="tnum mt-0.5 text-[20px] font-semibold">
            {corePeak
              ? `${fmtTime(corePeak.t, locale)} · ${Math.round(corePeak.alt)}° ${compassPoint(corePeak.az, locale)}`
              : t("tonight.core_below")}
          </p>
        </div>
      </div>
      {!good && <p className="mt-3 text-sm text-white/60">{t(`tonight.why_${reason}`)}</p>}
    </div>
  );
}

export default function SkyHub() {
  const t = useTranslations("sky");
  const locale = useLocale();
  const mounted = useMounted();
  const { loc } = useSkyLocation();
  const next = useMemo(() => (mounted ? upcomingShowers(new Date(), 1)[0] : undefined), [mounted]);

  const cards = [
    { href: "/sky/moon", icon: CalendarDays, title: t("hub.moon_title"), body: t("hub.moon_body") },
    { href: "/sky/planner", icon: Sunrise, title: t("hub.sun_title"), body: t("hub.sun_body") },
    { href: "/planner", icon: Moon, title: t("hub.night_title"), body: t("hub.night_body") },
  ];

  return (
    <div className="mx-auto max-w-[1000px] px-4 pt-8 sm:px-6 sm:pt-12">
      <Link href="/guide" className="text-sm text-ink-muted hover:text-ink">← {t("back_guide")}</Link>
      <h1 className="mt-3 text-[clamp(2rem,4.5vw,3rem)] font-bold leading-none tracking-[-0.04em]">{t("title")}</h1>
      <p className="mt-3 max-w-[62ch] text-ink-muted">{t("lead")}</p>
      <div className="mt-4"><LocationLine loc={loc} /></div>

      <div className="mt-6">
        {mounted ? <Tonight lat={loc.lat} lng={loc.lng} /> : <div className="h-[260px] rounded-card bg-[#11141c]" />}
      </div>

      <div className="mt-3 grid gap-3 sm:grid-cols-3">
        {cards.map(({ href, icon: Icon, title, body }) => (
          <Link key={href} href={href} className="group rounded-card bg-surface px-5 py-5 transition-colors hover:bg-surface/80">
            <Icon className="h-6 w-6" strokeWidth={1.7} />
            <p className="mt-4 flex items-center gap-1 font-semibold">{title} <ChevronRight className="h-4 w-4 text-ink-muted transition-transform group-hover:translate-x-0.5" /></p>
            <p className="mt-1 text-sm text-ink-muted">{body}</p>
          </Link>
        ))}
      </div>

      <Link href="/sky/meteors" className="mt-3 flex items-center gap-4 rounded-card bg-surface px-5 py-5 transition-colors hover:bg-surface/80">
        <Sparkles className="h-6 w-6 shrink-0" strokeWidth={1.7} />
        <div className="min-w-0 flex-1">
          <p className="text-sm text-ink-muted">{t("hub.next_shower")}</p>
          {next ? (
            <>
              <p className="font-semibold">
                {t(`meteor.${next.s.key}`)} · {new Intl.DateTimeFormat(locale, { day: "numeric", month: "long" }).formatRange(new Date(next.peak.getFullYear(), next.peak.getMonth(), next.peak.getDate() - 1), next.peak)}
              </p>
              <p className="tnum text-sm text-ink-muted">
                {t("meteors.zhr", { n: next.s.zhr })} · {t("meteors.moon", { pct: Math.round(next.moon * 100) })} ·{" "}
                <span className={clsx(next.moon < 0.35 ? "text-accent-text" : "text-ink-muted")}>{next.moon < 0.35 ? t("meteors.good") : t("meteors.bright")}</span>
              </p>
            </>
          ) : <p className="font-semibold">—</p>}
        </div>
        <ChevronRight className="h-5 w-5 shrink-0 text-ink-muted" />
      </Link>

      <div className="mt-3 flex items-start gap-4 rounded-card bg-surface-2 px-5 py-4">
        <Smartphone className="mt-0.5 h-5 w-5 shrink-0 text-ink-muted" strokeWidth={1.7} />
        <p className="text-sm text-ink-muted"><span className="font-semibold text-ink">{t("hub.ar_title")}</span> {t("hub.ar_body")}</p>
      </div>
      <p className="mt-6 text-xs text-ink-muted">{t("accuracy")}</p>
    </div>
  );
}
