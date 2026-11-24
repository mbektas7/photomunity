"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Backpack, MapPin, Pencil, UsersRound } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useParams } from "next/navigation";
import { useMemo, useState } from "react";
import { Avatar } from "@/components/Avatar";
import { CommunityLogo } from "@/components/community";
import { DateBlock, eventTimeRange } from "@/components/events";
import { StaticMap } from "@/components/PickMap";
import { MoonShape, fmtTime, useMounted } from "@/components/sky";
import { Button, Notice, buttonClass } from "@/components/ui";
import { CloudLine, useForecast } from "@/components/weather";
import { Link } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import { planNight } from "@/lib/astro";
import { pct } from "@/lib/format";
import { useMe } from "@/lib/hooks";
import { moonPhaseKey } from "@/lib/sky";
import type { CommunityEvent, UserCard } from "@/lib/types";
import { nightWeather, shootingWindow } from "@/lib/weather";
import { HowItWorks } from "@/components/intro";

const DAY = 86_400_000;

/** O gecenin Ay evresi, karanlık çekim penceresi ve (7 gün içindeyse) bulut tahmini. */
function NightSky({ e }: { e: CommunityEvent }) {
  const t = useTranslations("events");
  const ts = useTranslations("sky");
  const tw = useTranslations("weather");
  const locale = useLocale();
  const mounted = useMounted();
  const lat = e.latitude!, lng = e.longitude!;
  const start = new Date(e.starts_at);
  const plan = useMemo(() => {
    if (!mounted) return null;
    const night = new Date(start.getFullYear(), start.getMonth(), start.getDate() - (start.getHours() < 12 ? 1 : 0));
    return planNight(night, lat, lng);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mounted, e.starts_at, lat, lng]);
  const soon = start.getTime() - Date.now() < 7 * DAY && (e.ends_at ? new Date(e.ends_at).getTime() : start.getTime() + 3 * 3_600_000) > Date.now();
  const forecast = useForecast(lat, lng, soon);
  if (!plan) return null;
  const win = shootingWindow(plan);
  const span = { start: start.getTime(), end: e.ends_at ? new Date(e.ends_at).getTime() : start.getTime() + 3 * 3_600_000 };
  const wx = forecast.data ? nightWeather(forecast.data, span) : null;
  return (
    <div className="flex flex-wrap items-center gap-x-4 gap-y-2 rounded-box bg-[#11141c] px-4 py-3 text-[14px] text-white">
      <MoonShape phase={plan.phase} fraction={plan.illumination} size={28} />
      <span className="tnum">{ts(`phase.${moonPhaseKey(plan.phase)}`)} {pct(plan.illumination * 100, locale)}</span>
      {wx && <span className="text-white/80"><CloudLine value={wx.cloud} /></span>}
      <span className="tnum text-white/80">
        {win ? t("dark_window", { range: `${fmtTime(win.start, locale)}–${fmtTime(win.end, locale)}` }) : ts("tonight.no_window")}
      </span>
      {forecast.isError && <span className="text-white/60">{tw("unavailable")}</span>}
    </div>
  );
}

export default function EventPage() {
  const { id } = useParams<{ id: string }>();
  const t = useTranslations("events");
  const locale = useLocale();
  const qc = useQueryClient();
  const { data: me } = useMe();
  const [showAll, setShowAll] = useState(false);
  const q = useQuery({ queryKey: ["event", id], queryFn: () => api<CommunityEvent>(`events/${id}`) });
  const all = useQuery({ queryKey: ["event", id, "attendees"], enabled: showAll, queryFn: () => api<UserCard[]>(`events/${id}/attendees`) });
  const refresh = () => {
    qc.invalidateQueries({ queryKey: ["event", id] });
    qc.invalidateQueries({ queryKey: ["community-events"] });
    qc.invalidateQueries({ queryKey: ["events"] });
  };
  const attend = useMutation({
    mutationFn: (on: boolean) => (on ? api<CommunityEvent>(`events/${id}/attend`, { method: "POST" }) : api(`events/${id}/attend`, { method: "DELETE" })),
    onSuccess: refresh,
  });
  const cancel = useMutation({ mutationFn: () => api<CommunityEvent>(`events/${id}/cancel`, { method: "POST" }), onSuccess: refresh });

  if (q.error) {
    return <div className="mx-auto max-w-[680px] px-4 py-20"><Notice tone="error">{q.error instanceof ApiError && q.error.message ? q.error.message : t("not_found")}</Notice></div>;
  }
  const e = q.data;
  if (!e) return <div className="h-[60vh]" aria-busy />;
  const open = e.status === "upcoming" || e.status === "ongoing";
  const full = e.capacity != null && e.attendee_count >= e.capacity;
  const err = attend.error ?? cancel.error;
  const people = showAll && all.data ? all.data : e.attendees_preview;

  return (
    <div className="mx-auto max-w-[1000px] px-4 pb-16 pt-6 sm:px-6 sm:pt-10">
      <Link href={`/c/${e.community.slug}?tab=events`} className="inline-flex items-center gap-2 text-sm text-ink-muted hover:text-ink">
        <CommunityLogo name={e.community.name} url={e.community.logo_url} size={24} /> {e.community.name}
      </Link>
      <div className="mt-4 grid gap-6 lg:grid-cols-[minmax(0,1fr)_340px]">
        <div className="flex flex-col gap-5">
          <div className="flex items-start gap-4">
            <DateBlock iso={e.starts_at} dim={!open} />
            <div className="min-w-0">
              <p className="flex items-center gap-2 text-xs font-bold uppercase tracking-[0.08em] text-ink-muted">{t("kicker")} <HowItWorks module="events" /></p>
              <h1 className="text-[30px] font-bold leading-tight tracking-[-0.03em] sm:text-[38px]">{e.title}</h1>
              <p className="tnum mt-1 text-ink-muted">{eventTimeRange(e, locale)}</p>
            </div>
          </div>
          {e.status === "cancelled" && <Notice tone="error">{t("cancelled_notice")}</Notice>}
          {e.status === "past" && <Notice>{t("past_notice")}</Notice>}
          <p className="flex items-start gap-2 text-[15px]"><MapPin className="mt-0.5 h-5 w-5 shrink-0 text-ink-muted" aria-hidden /> {e.location_name}</p>
          {e.latitude != null && e.longitude != null && (
            <>
              <StaticMap lat={e.latitude} lng={e.longitude} />
              <NightSky e={e} />
            </>
          )}
          {e.bring && (
            <div className="rounded-box bg-surface p-4">
              <p className="flex items-center gap-2 text-sm font-bold"><Backpack className="h-4 w-4" aria-hidden /> {t("bring")}</p>
              <p className="mt-1 whitespace-pre-line text-[15px] leading-relaxed">{e.bring}</p>
            </div>
          )}
          {e.description && <p className="whitespace-pre-line text-[15.5px] leading-relaxed">{e.description}</p>}
        </div>

        <aside className="flex flex-col gap-4 self-start rounded-card bg-surface p-5">
          <p className="flex items-baseline gap-2">
            <UsersRound className="h-5 w-5 self-center text-ink-muted" aria-hidden />
            <span className="tnum text-[26px] font-bold">{e.attendee_count}</span>
            <span className="text-ink-muted">{e.capacity ? t("going_of", { n: e.capacity }) : t("going_count")}</span>
          </p>
          {people.length > 0 && (
            <ul className="flex flex-wrap gap-1.5">
              {people.map((u) => (
                <li key={u.id}>
                  <Link href={`/u/${u.username}`} title={u.display_name} aria-label={u.display_name} className="block rounded-full">
                    <Avatar name={u.display_name} url={u.avatar_url} size={36} />
                  </Link>
                </li>
              ))}
            </ul>
          )}
          {!showAll && e.attendee_count > e.attendees_preview.length && (
            <button type="button" className="self-start text-sm font-semibold text-accent-text hover:underline" onClick={() => setShowAll(true)}>{t("see_all")}</button>
          )}
          {open && me && e.my_role && (
            e.attending ? (
              <Button variant="secondary" busy={attend.isPending} onClick={() => attend.mutate(false)}>{t("leave")}</Button>
            ) : (
              <Button variant="large" busy={attend.isPending} disabled={full} onClick={() => attend.mutate(true)}>{full ? t("full") : t("attend")}</Button>
            )
          )}
          {open && me && !e.my_role && (
            <p className="text-sm text-ink-muted">
              {t("members_only")}{" "}
              <Link href={`/c/${e.community.slug}`} className="font-semibold text-accent-text hover:underline">{t("join_community")}</Link>
            </p>
          )}
          {open && !me && <Link href="/login" className={buttonClass("primary")}>{t("login_to_attend")}</Link>}
          {e.attending && open && <p className="text-sm font-semibold text-accent-text">{t("you_are_going")}</p>}
          {err && <Notice tone="error">{err instanceof ApiError && err.message ? err.message : t("error")}</Notice>}
          {e.can_manage && open && (
            <div className="flex flex-wrap gap-2 border-t border-line pt-4">
              <Link href={`/events/${e.id}/edit`} className={buttonClass("secondary")}><Pencil className="h-4 w-4" aria-hidden /> {t("edit")}</Link>
              <Button variant="danger" busy={cancel.isPending} onClick={() => window.confirm(t("cancel_confirm")) && cancel.mutate()}>{t("cancel_event")}</Button>
            </div>
          )}
          {e.created_by && <p className="text-xs text-ink-muted">{t("organized_by", { name: e.created_by.display_name })}</p>}
        </aside>
      </div>
    </div>
  );
}
