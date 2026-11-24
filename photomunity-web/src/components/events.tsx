"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import clsx from "clsx";
import { MapPin, Plus, UsersRound } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useState } from "react";
import { PickMap } from "@/components/PickMap";
import { useMounted, useSkyLocation } from "@/components/sky";
import { Button, Notice, TextArea, TextField, Toggle, buttonClass } from "@/components/ui";
import { Link, useRouter } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import { fromLocalInput, toLocalInput } from "@/lib/dates";
import type { Community, CommunityEvent, EventCard, EventList } from "@/lib/types";

export function DateBlock({ iso, dim }: { iso: string; dim?: boolean }) {
  const locale = useLocale();
  const d = new Date(iso);
  return (
    <span className={clsx("flex w-14 shrink-0 flex-col items-center rounded-[14px] py-1.5", dim ? "bg-surface-2 text-ink-muted" : "bg-accent-tint text-accent-text")} aria-hidden>
      <span className="text-[11px] font-bold uppercase tracking-[0.06em]">{new Intl.DateTimeFormat(locale, { month: "short" }).format(d)}</span>
      <span className="tnum text-[22px] font-bold leading-tight">{d.getDate()}</span>
    </span>
  );
}

export function eventTimeRange(e: Pick<EventCard, "starts_at" | "ends_at">, locale: string) {
  const s = new Date(e.starts_at);
  const day = new Intl.DateTimeFormat(locale, { weekday: "long", day: "numeric", month: "long" }).format(s);
  const tf = new Intl.DateTimeFormat(locale, { hour: "2-digit", minute: "2-digit", hourCycle: "h23" });
  return `${day} ${tf.format(s)}${e.ends_at ? ` – ${tf.format(new Date(e.ends_at))}` : ""}`;
}

export function EventRow({ e }: { e: EventCard }) {
  const t = useTranslations("events");
  const locale = useLocale();
  const dim = e.status === "past" || e.status === "cancelled";
  return (
    <Link href={`/events/${e.id}`} className="flex items-center gap-4 rounded-card bg-surface px-4 py-3.5 hover:bg-surface/80">
      <DateBlock iso={e.starts_at} dim={dim} />
      <span className="min-w-0 flex-1">
        <span className={clsx("block truncate text-[16px] font-semibold", e.status === "cancelled" && "line-through")}>{e.title}</span>
        <span className="tnum block truncate text-sm text-ink-muted">{eventTimeRange(e, locale)}</span>
        <span className="flex items-center gap-1 truncate text-sm text-ink-muted"><MapPin className="h-3.5 w-3.5 shrink-0" aria-hidden /> {e.location_name}</span>
      </span>
      <span className="flex shrink-0 flex-col items-end gap-1 text-sm">
        {e.status === "cancelled" ? (
          <span className="rounded-full bg-danger/10 px-2.5 py-0.5 text-xs font-bold text-danger">{t("status.cancelled")}</span>
        ) : e.status === "ongoing" ? (
          <span className="rounded-full bg-live px-2.5 py-0.5 text-xs font-bold text-live-ink">{t("status.ongoing")}</span>
        ) : e.attending ? (
          <span className="rounded-full bg-accent-tint px-2.5 py-0.5 text-xs font-bold text-accent-text">{t("going")}</span>
        ) : null}
        <span className="tnum inline-flex items-center gap-1 text-ink-muted">
          <UsersRound className="h-4 w-4" aria-hidden /> {e.capacity ? `${e.attendee_count}/${e.capacity}` : e.attendee_count}
        </span>
      </span>
    </Link>
  );
}

/** Topluluk sayfasındaki "Etkinlikler" sekmesi. */
export function EventsTab({ c, isAdmin }: { c: Community; isAdmin: boolean }) {
  const t = useTranslations("events");
  const q = useQuery({ queryKey: ["community-events", c.slug], queryFn: () => api<EventList>(`communities/${c.slug}/events`) });
  const d = q.data;
  return (
    <div className="mx-auto flex max-w-[760px] flex-col gap-6 px-3 sm:px-0">
      {isAdmin && (
        <Link href={`/c/${c.slug}/events/new`} className={buttonClass("primary", "self-start")}>
          <Plus className="h-4 w-4" strokeWidth={2.5} aria-hidden /> {t("new")}
        </Link>
      )}
      {q.isError && <Notice tone="error">{t("error")}</Notice>}
      {d && d.upcoming.length === 0 && d.past.length === 0 && <p className="px-1 py-8 text-ink-muted">{t("empty")}</p>}
      {d && d.upcoming.length > 0 && (
        <section aria-labelledby="ev-upcoming">
          <h2 id="ev-upcoming" className="mb-2 text-heading">{t("upcoming")}</h2>
          <ul className="flex flex-col gap-2">{d.upcoming.map((e) => <li key={e.id}><EventRow e={e} /></li>)}</ul>
        </section>
      )}
      {d && d.past.length > 0 && (
        <section aria-labelledby="ev-past">
          <h2 id="ev-past" className="mb-2 text-heading">{t("past")}</h2>
          <ul className="flex flex-col gap-2">{d.past.map((e) => <li key={e.id}><EventRow e={e} /></li>)}</ul>
        </section>
      )}
    </div>
  );
}

/** Etkinlik oluştur / düzenle (topluluk sahibi ve yöneticileri). */
export function EventForm({ slug, event }: { slug?: string; event?: CommunityEvent }) {
  const t = useTranslations("events");
  const router = useRouter();
  const qc = useQueryClient();
  const mounted = useMounted();
  const { loc } = useSkyLocation();
  const [f, setF] = useState({
    title: event?.title ?? "",
    description: event?.description ?? "",
    starts: toLocalInput(event?.starts_at),
    ends: toLocalInput(event?.ends_at),
    place: event?.location_name ?? "",
    capacity: event?.capacity ? String(event.capacity) : "",
    bring: event?.bring ?? "",
  });
  const [pin, setPin] = useState<{ lat: number; lng: number } | null>(
    event?.latitude != null && event.longitude != null ? { lat: event.latitude, lng: event.longitude } : null,
  );
  const set = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => setF({ ...f, [k]: e.target.value });

  const save = useMutation({
    mutationFn: () => {
      const body = {
        title: f.title.trim(),
        description: f.description.trim() || null,
        starts_at: fromLocalInput(f.starts),
        ends_at: f.ends ? fromLocalInput(f.ends) : null,
        location_name: f.place.trim(),
        latitude: pin?.lat ?? null,
        longitude: pin?.lng ?? null,
        capacity: f.capacity ? Math.max(1, Math.round(+f.capacity)) : null,
        bring: f.bring.trim() || null,
      };
      return event
        ? api<CommunityEvent>(`events/${event.id}`, { method: "PATCH", body })
        : api<CommunityEvent>(`communities/${slug}/events`, { method: "POST", body });
    },
    onSuccess: (e) => {
      qc.setQueryData(["event", e.id], e);
      qc.invalidateQueries({ queryKey: ["community-events"] });
      qc.invalidateQueries({ queryKey: ["events"] });
      router.push(`/events/${e.id}`);
    },
  });
  const valid = f.title.trim() && f.place.trim() && f.starts && (!f.ends || f.ends > f.starts);

  return (
    <form
      className="flex max-w-[680px] flex-col gap-5"
      onSubmit={(e) => {
        e.preventDefault();
        if (valid) save.mutate();
      }}
    >
      <TextField label={t("f_title")} name="title" required maxLength={150} value={f.title} onChange={set("title")} />
      <div className="grid gap-4 sm:grid-cols-2">
        <TextField label={t("f_starts")} name="starts" type="datetime-local" required value={f.starts} onChange={set("starts")} />
        <TextField label={t("f_ends")} name="ends" type="datetime-local" value={f.ends} min={f.starts || undefined} onChange={set("ends")} hint={t("optional")} />
      </div>
      <TextField label={t("f_place")} name="place" required maxLength={200} value={f.place} onChange={set("place")} placeholder={t("f_place_placeholder")} />
      <div className="flex flex-col gap-3">
        <Toggle
          checked={!!pin}
          onChange={(v) => setPin(v ? { lat: loc.lat, lng: loc.lng } : null)}
          label={t("f_pin")}
          hint={t("f_pin_hint")}
        />
        {pin && mounted && <PickMap lat={pin.lat} lng={pin.lng} onPick={(lat, lng) => setPin({ lat, lng })} label={t("f_pin")} />}
      </div>
      <TextField label={t("f_capacity")} name="capacity" type="number" min={1} max={10000} inputMode="numeric" value={f.capacity} onChange={set("capacity")} hint={t("f_capacity_hint")} />
      <TextArea label={t("f_bring")} name="bring" rows={2} maxLength={500} value={f.bring} onChange={set("bring")} hint={t("f_bring_hint")} />
      <TextArea label={t("f_description")} name="description" rows={5} maxLength={3000} value={f.description} onChange={set("description")} />
      {save.error && <Notice tone="error">{save.error instanceof ApiError && save.error.message ? save.error.message : t("error")}</Notice>}
      <div className="flex gap-3">
        <Button type="submit" busy={save.isPending} disabled={!valid}>{event ? t("save") : t("create")}</Button>
        <Button type="button" variant="secondary" onClick={() => router.back()}>{t("cancel")}</Button>
      </div>
    </form>
  );
}
