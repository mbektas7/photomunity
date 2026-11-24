"use client";

import { useQuery } from "@tanstack/react-query";
import clsx from "clsx";
import { CalendarDays, ChevronRight, ClipboardList, Map as MapIcon, Moon, Smartphone, Sparkles, Sunrise } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useMemo } from "react";
import { LocationLine, MoonShape, fmtTime, useMounted, useSkyLocation } from "@/components/sky";
import { CloudBar, ScoreChip, useForecast } from "@/components/weather";
import { Link } from "@/i18n/navigation";
import { api } from "@/lib/api";
import { compassPoint, planNight } from "@/lib/astro";
import { pct } from "@/lib/format";
import { useMe } from "@/lib/hooks";
import { moonPhaseKey, upcomingShowers } from "@/lib/sky";
import type { Page, Plan } from "@/lib/types";
import { type Forecast, darkSpan, moonLight, nightWeather, scoreLabel, scoreVerdict, shootScore, shootingWindow } from "@/lib/weather";
import { HowItWorks } from "@/components/intro";

function Tonight({ lat, lng }: { lat: number; lng: number }) {
  const t = useTranslations("sky");
  const tw = useTranslations("weather");
  const locale = useLocale();
  // Gece yarısından sonra (06:00'ya kadar) hâlâ içinde bulunulan gece gösterilir
  const night = useMemo(() => {
    const now = new Date();
    return new Date(now.getFullYear(), now.getMonth(), now.getDate() - (now.getHours() < 6 ? 1 : 0));
  }, []);
  const plan = useMemo(() => planNight(night, lat, lng), [night, lat, lng]);
  const forecast = useForecast(lat, lng);
  const good = plan.bestWindows.length > 0;
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

  const win = shootingWindow(plan);
  const wx = forecast.data ? nightWeather(forecast.data, darkSpan(plan)) : null;
  const score = wx ? shootScore(wx, moonLight(plan, darkSpan(plan))) : null;
  const sky = wx ? (wx.cloud < 20 ? tw("sky_clear") : wx.cloud < 60 ? tw("sky_partly") : tw("sky_cloudy")) : null;
  const ring = score == null ? "#ffffff33" : score >= 70 ? "#7fe0c0" : score >= 40 ? "#f5c27a" : "#ff9b92";

  const tiles = [
    { k: "cloud", label: tw("cloud"), value: wx ? pct(wx.cloud, locale) : "—" },
    { k: "humidity", label: tw("humidity"), value: wx ? pct(wx.humidity, locale) : "—" },
    { k: "wind", label: tw("wind"), value: wx ? tw("kmh", { n: Math.round(wx.wind) }) : "—" },
    { k: "window", label: tw("window"), value: win ? `${fmtTime(win.start, locale)}–${fmtTime(win.end, locale)}` : t("tonight.no_window") },
  ];

  return (
    <div className="rounded-card bg-[linear-gradient(160deg,#1a2050,#0d1130)] px-5 py-6 text-white sm:px-7">
      <div className="flex items-center gap-4 sm:gap-5">
        <MoonShape phase={plan.phase} fraction={plan.illumination} size={60} />
        <div className="min-w-0 flex-1">
          <p className="text-xs font-semibold uppercase tracking-[0.08em] text-white/60">{t("tonight.label")}</p>
          <p className="text-[22px] font-bold leading-tight tracking-[-0.02em] sm:text-[24px]">
            {score != null ? tw(`verdict.${scoreVerdict(score)}`) : good ? t("tonight.good") : t("tonight.not_good")}
          </p>
          <p className="tnum mt-1 text-[14.5px] text-white/70">
            {sky ? `${sky} · ` : ""}{t(`phase.${moonPhaseKey(plan.phase)}`)} {pct(plan.illumination * 100, locale)}{moonNote ? ` · ${moonNote}` : ""}
          </p>
        </div>
        <div
          className="tnum grid h-[58px] w-[58px] shrink-0 place-items-center rounded-full border-4 text-[18px] font-bold"
          style={{ borderColor: ring }}
          role="img"
          aria-label={score != null ? tw("score_aria", { n: score }) : tw("score_loading")}
          title={tw("score_hint")}
        >
          {score ?? "…"}
        </div>
      </div>
      <dl className="mt-5 grid grid-cols-2 gap-1.5 sm:grid-cols-4">
        {tiles.map((x) => (
          <div key={x.k} className="rounded-[14px] bg-white/[0.08] px-3 py-2.5">
            <dt className="text-[12px] text-white/65">{x.label}</dt>
            <dd className="tnum mt-0.5 text-[16px] font-bold">{x.value}</dd>
          </div>
        ))}
      </dl>
      <p className="tnum mt-3 text-sm text-white/70">
        {t("tonight.core_peak")}:{" "}
        <span className="font-semibold text-white">
          {corePeak ? `${fmtTime(corePeak.t, locale)} · ${Math.round(corePeak.alt)}° ${compassPoint(corePeak.az, locale)}` : t("tonight.core_below")}
        </span>
      </p>
      {!good && <p className="mt-1 text-sm text-white/60">{t(`tonight.why_${reason}`)}</p>}
      {forecast.isError && <p className="mt-1 text-sm text-white/60">{tw("unavailable")}</p>}
      <NextNights lat={lat} lng={lng} from={night} forecast={forecast.data ?? null} />
    </div>
  );
}

/** Önümüzdeki 5 gece: bulut çubuğu, Ay, puan etiketi. */
function NextNights({ lat, lng, from, forecast }: { lat: number; lng: number; from: Date; forecast: Forecast | null }) {
  const tw = useTranslations("weather");
  const locale = useLocale();
  const nights = useMemo(
    () => Array.from({ length: 5 }, (_, i) => {
      const date = new Date(from.getFullYear(), from.getMonth(), from.getDate() + i);
      const plan = planNight(date, lat, lng);
      return { date, plan, dark: darkSpan(plan) };
    }),
    [from, lat, lng],
  );
  const day = new Intl.DateTimeFormat(locale, { weekday: "short" });
  return (
    <section aria-labelledby="next-nights" className="mt-5 border-t border-white/10 pt-4">
      <div className="mb-2 flex items-baseline justify-between">
        <h2 id="next-nights" className="text-[15px] font-bold">{tw("next_nights")}</h2>
        <span className="text-xs text-white/55">{tw("cloud_moon")}</span>
      </div>
      <ul className="flex flex-col">
        {nights.map(({ date, plan, dark }, i) => {
          const wx = forecast ? nightWeather(forecast, dark) : null;
          const score = wx ? shootScore(wx, moonLight(plan, dark)) : null;
          return (
            <li key={i} className="grid grid-cols-[72px_minmax(0,1fr)_44px_28px_64px] items-center gap-3 py-2 text-[14px] sm:grid-cols-[110px_minmax(0,1fr)_52px_28px_72px]">
              <span className={clsx("font-semibold", i > 0 && "capitalize")}>{i === 0 ? tw("tonight") : day.format(date)}</span>
              {wx ? <CloudBar value={wx.cloud} className="text-white" /> : <span className="text-xs text-white/45">{tw("no_forecast")}</span>}
              <span className="tnum text-right text-white/80">{wx ? pct(wx.cloud, locale) : "—"}</span>
              <MoonShape phase={plan.phase} fraction={plan.illumination} size={22} />
              <span className="text-right">{score != null ? <ScoreChip label={scoreLabel(score)} /> : null}</span>
            </li>
          );
        })}
      </ul>
    </section>
  );
}

/** Planlarım girişi (yalnızca giriş yapmış kullanıcıya). */
function PlansEntry() {
  const tp = useTranslations("plans");
  const { data: me } = useMe();
  const q = useQuery({
    queryKey: ["plans", "upcoming"],
    enabled: !!me,
    queryFn: () => api<Page<Plan>>("me/plans?scope=upcoming"),
  });
  if (!me) return null;
  const n = q.data?.items.length ?? 0;
  return (
    <Link href="/plans" className="mt-3 flex items-center gap-4 rounded-card bg-surface px-5 py-5 transition-colors hover:bg-surface/80">
      <ClipboardList className="h-6 w-6 shrink-0" strokeWidth={1.7} aria-hidden />
      <div className="min-w-0 flex-1">
        <p className="font-semibold">{tp("title")}</p>
        <p className="text-sm text-ink-muted">{q.isSuccess ? tp("upcoming_count", { count: n }) : tp("lead_short")}</p>
      </div>
      {n > 0 && <span className="tnum grid h-7 min-w-7 place-items-center rounded-full bg-accent px-2 text-sm font-bold text-accent-ink">{n}</span>}
      <ChevronRight className="h-5 w-5 shrink-0 text-ink-muted" />
    </Link>
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
    { href: "/sky/dark", icon: MapIcon, title: t("hub.dark_title"), body: t("hub.dark_body") },
  ];

  return (
    <div className="mx-auto max-w-[1000px] px-4 pt-8 sm:px-6 sm:pt-12">
      <Link href="/guide" className="text-sm text-ink-muted hover:text-ink">← {t("back_guide")}</Link>
      <h1 className="mt-3 flex items-center gap-3 text-[clamp(2rem,4.5vw,3rem)] font-bold leading-none tracking-[-0.04em]">{t("title")} <HowItWorks module="sky" /></h1>
      <p className="mt-3 max-w-[62ch] text-ink-muted">{t("lead")}</p>
      <div className="mt-4"><LocationLine loc={loc} /></div>

      <div className="mt-6">
        {mounted ? <Tonight lat={loc.lat} lng={loc.lng} /> : <div className="h-[460px] rounded-card bg-[#11141c]" />}
      </div>

      <PlansEntry />

      <div className="mt-3 grid gap-3 sm:grid-cols-2">
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
