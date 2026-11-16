"use client";

import clsx from "clsx";
import { Check, Star, X } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useEffect, useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link } from "@/i18n/navigation";
import { api } from "@/lib/api";
import { remaining } from "@/lib/dates";
import { countryName, initials } from "@/lib/format";
import { useMe } from "@/lib/hooks";
import type { CommunityCard, ContestCard, ContestStatus, Page, PhotoCard } from "@/lib/types";
import { LiveBadge, useShortRemaining } from "./Countdown";
import { Button } from "./ui";

/** Topluluk logosu yuvarlatılmış karedir; kişi avatarları yuvarlaktır — kurum ve insan ilk bakışta ayrışır. */
export function CommunityLogo({ name, url, size = 48, className }: { name: string; url?: string | null; size?: number; className?: string }) {
  const style = { width: size, height: size, borderRadius: size >= 48 ? 14 : Math.round(size * 0.3), fontSize: Math.round(size * 0.36) };
  if (url) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={url} alt="" style={style} className={clsx("shrink-0 object-cover", className)} />;
  }
  return (
    <span aria-hidden style={style} className={clsx("inline-flex shrink-0 items-center justify-center bg-accent-tint font-bold text-accent-text", className)}>
      {initials(name)}
    </span>
  );
}

export function CommunityRow({ c }: { c: CommunityCard }) {
  const t = useTranslations("communities");
  const locale = useLocale();
  const place = [c.city, countryName(c.country, locale)].filter(Boolean).join(", ");
  return (
    <Link href={`/c/${c.slug}`} className="flex items-center gap-4 rounded-card bg-surface p-4 transition-colors hover:bg-surface/80">
      <CommunityLogo name={c.name} url={c.logo_url} size={52} />
      <span className="min-w-0 flex-1">
        <span className="block truncate text-[16px] font-semibold">{c.name}</span>
        <span className="mt-0.5 block truncate text-sm text-ink-muted">
          {[place, t("members_count", { count: c.member_count })].filter(Boolean).join("  ·  ")}
        </span>
      </span>
      {c.my_role && <span className="shrink-0 rounded-pill bg-surface-2 px-2.5 py-1 text-caption font-semibold text-ink-muted">{t(`role.${c.my_role}`)}</span>}
    </Link>
  );
}

/** Yarışma durumu: canlı aşamalar (katılım, oylama) turuncu live rozeti, diğerleri sakin hap. */
export function StatusBadge({ status, mode, size = "md" }: { status: ContestStatus; mode?: ContestCard["judging_mode"]; size?: "sm" | "md" }) {
  const t = useTranslations("contests");
  if (status === "open" || status === "judging") {
    const label = status === "open" ? t("phase_open") : mode === "jury" ? t("phase_jury") : t("phase_voting");
    return <LiveBadge size={size}>{label}</LiveBadge>;
  }
  return (
    <span
      className={clsx(
        "inline-flex shrink-0 items-center rounded-pill bg-surface-2 font-semibold text-ink-muted",
        size === "sm" ? "h-5 px-[7px] text-[11px]" : "h-7 px-2.5 text-[13px]",
      )}
    >
      {t(`status.${status}`)}
    </span>
  );
}

/** Kartta gösterilecek sıradaki tarih: katılım sürüyorsa son gönderim, değerlendirmedeyse oylama bitişi. */
function nextMoment(c: ContestCard): { key: string; at: string } | null {
  if (c.status === "open" || c.status === "draft") return { key: "deadline_in", at: c.submission_deadline };
  if (c.status === "judging") return { key: "voting_ends_in", at: c.voting_end };
  if (c.status === "closed") return { key: "results_in", at: c.results_at };
  return null;
}

/** Yarışma kartı: topluluk logosu (yarışma kapak görseli API'de yok), live rozeti, başlık, topluluk ve kalan süre. */
export function ContestRow({ c, showCommunity = true }: { c: ContestCard; showCommunity?: boolean }) {
  const t = useTranslations("contests");
  const locale = useLocale();
  const next = nextMoment(c);
  const left = next ? remaining(next.at, locale) : null;
  return (
    <Link href={`/contests/${c.id}`} className="flex items-center gap-4 rounded-card bg-surface p-4 transition-colors hover:bg-surface/80 sm:p-5">
      <CommunityLogo name={c.community.name} url={c.community.logo_url} size={64} />
      <span className="min-w-0 flex-1">
        <span className="flex flex-wrap items-center gap-2">
          <StatusBadge status={c.status} mode={c.judging_mode} size="sm" />
          {next && left && <span className="tnum text-[12.5px] text-ink-muted">{t(next.key, { time: left })}</span>}
        </span>
        <span className="mt-1 block truncate text-[17px] font-bold tracking-[-0.01em]">{c.title}</span>
        <span className="mt-0.5 flex flex-wrap gap-x-3 text-caption text-ink-muted">
          {showCommunity && <span>{c.community.name}</span>}
          <span className="tnum">{t("entries_count", { count: c.entry_count })}</span>
          <span>{t(`mode.${c.judging_mode}`)}</span>
        </span>
      </span>
    </Link>
  );
}

/** Sağ sütun ve keşfette küçük canlı yarışma kartı (surface-2 zeminli satır). */
export function ContestMini({ c }: { c: ContestCard }) {
  const t = useTranslations("contests");
  const next = nextMoment(c);
  const left = useShortRemaining(next?.at);
  return (
    <Link href={`/contests/${c.id}`} className="flex items-center gap-3 rounded-[18px] bg-surface-2 p-2.5 transition-colors hover:bg-line">
      <CommunityLogo name={c.community.name} url={c.community.logo_url} size={64} />
      <span className="flex min-w-0 flex-1 flex-col gap-[3px]">
        <span className="flex items-center gap-1.5">
          <LiveBadge size="sm">{c.status === "open" ? t("live_open") : t("live_voting")}</LiveBadge>
          {left && <span className="tnum truncate text-[12px] text-ink-muted">{left.left}</span>}
        </span>
        <span className="truncate text-[15.5px] font-bold tracking-[-0.01em]">{c.title}</span>
        <span className="truncate text-caption text-ink-muted">{c.community.name}</span>
      </span>
    </Link>
  );
}

/**
 * Katılım → Oylama/Jüri → Sonuç adımları. Üstte 4 px çubuk: geçmiş accent, şu an live, gelecek line.
 */
export function ContestTimeline({ c }: { c: ContestCard }) {
  const t = useTranslations("contests");
  const locale = useLocale();
  const order: ContestStatus[] = ["open", "judging", "closed", "finished"];
  const current = Math.max(0, order.indexOf(c.status === "draft" ? "open" : c.status));
  const steps = [
    { label: t("step_entries"), at: c.submission_deadline, idx: 0 },
    { label: c.judging_mode === "jury" ? t("step_jury") : t("step_voting"), at: c.voting_end, idx: 1 },
    { label: t("step_results"), at: c.results_at, idx: 3 },
  ];
  const fmt = (iso: string) => new Intl.DateTimeFormat(locale, { day: "numeric", month: "long" }).format(new Date(iso));
  return (
    <ol className="grid grid-cols-3 gap-3.5">
      {steps.map((s) => {
        const active = current === s.idx || (s.idx === 1 && current === 2);
        const done = !active && (current > s.idx || (s.idx === 3 && current === 3));
        const note =
          s.idx === 3
            ? fmt(s.at)
            : done
              ? t("closed_on", { date: fmt(s.at) })
              : t("until_short", { date: fmt(s.at) });
        return (
          <li key={s.label} aria-current={active ? "step" : undefined} className="min-w-0">
            <span className={clsx("block h-1 rounded-pill", active ? "bg-live" : done ? "bg-accent" : "bg-line")} />
            <span className="mt-2.5 flex items-center gap-1 text-[13.5px] font-bold">
              {done && <Check className="h-3.5 w-3.5 text-accent-text" strokeWidth={3} aria-hidden />}
              {s.label}
            </span>
            <span className="tnum mt-0.5 block text-[12.5px] leading-snug text-ink-muted">{note}</span>
          </li>
        );
      })}
    </ol>
  );
}

export function StarRating({ value, onChange, disabled, size = 26 }: { value: number | null; onChange: (v: number) => void; disabled?: boolean; size?: number }) {
  const t = useTranslations("contests");
  const [hover, setHover] = useState<number | null>(null);
  const shown = hover ?? value ?? 0;
  return (
    <div role="radiogroup" aria-label={t("rate")} className="flex" onMouseLeave={() => setHover(null)}>
      {[1, 2, 3, 4, 5].map((n) => (
        <button
          key={n}
          type="button"
          role="radio"
          aria-checked={value === n}
          aria-label={t("stars", { count: n })}
          disabled={disabled}
          onMouseEnter={() => setHover(n)}
          onClick={() => onChange(n)}
          className="p-1 text-accent-text transition-transform active:scale-90 disabled:opacity-40"
        >
          <Star style={{ width: size, height: size }} fill={n <= shown ? "currentColor" : "none"} strokeWidth={1.7} className={n <= shown ? "" : "text-ink-muted"} />
        </button>
      ))}
    </div>
  );
}

/** Kullanıcının yayındaki fotoğraflarından birini seçtirir (topluluk paylaşımı ve yarışma katılımı için). */
export function MyPhotoPicker({ open, onClose, onPick, busy, title }: { open: boolean; onClose: () => void; onPick: (p: PhotoCard) => void; busy?: boolean; title: string }) {
  const t = useTranslations("contests");
  const { data: me } = useMe();
  const dialog = useRef<HTMLDialogElement>(null);
  const [selected, setSelected] = useState<PhotoCard | null>(null);
  const photos = useQuery({
    queryKey: ["photos", "user", me?.username, "picker"],
    enabled: open && !!me,
    queryFn: () => api<Page<PhotoCard>>(`users/${me!.username}/photos?limit=60`),
  });

  useEffect(() => {
    if (open) dialog.current?.showModal();
    else dialog.current?.close();
  }, [open]);

  return (
    <dialog ref={dialog} onClose={onClose} className="m-auto max-h-[85dvh] w-[min(760px,calc(100vw-1.5rem))] rounded-sheet bg-surface p-0 text-ink shadow-float backdrop:bg-black/55">
      <div className="flex items-center justify-between px-5 py-4">
        <h2 className="text-lg font-semibold">{title}</h2>
        <button type="button" onClick={onClose} aria-label={t("close")} className="inline-flex h-11 w-11 items-center justify-center rounded-full bg-surface-2 hover:bg-line">
          <X className="h-5 w-5" />
        </button>
      </div>
      <div className="max-h-[58dvh] overflow-y-auto p-3">
        {photos.isSuccess && photos.data.items.length === 0 && (
          <p className="px-2 py-10 text-center text-ink-muted">
            {t("no_photos")}{" "}
            <Link href="/upload" className="font-semibold text-ink underline underline-offset-4">
              {t("upload_one")}
            </Link>
          </p>
        )}
        <div className="grid grid-cols-3 gap-2 sm:grid-cols-4">
          {photos.data?.items.map((p) => (
            <button
              key={p.id}
              type="button"
              onClick={() => setSelected(p)}
              aria-pressed={selected?.id === p.id}
              className={clsx("relative aspect-square overflow-hidden rounded-photo bg-surface-2 outline-offset-2", selected?.id === p.id && "outline outline-[3px] outline-accent")}
            >
              {p.images.thumb && (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={p.images.thumb.url} alt={p.title ?? ""} className="h-full w-full object-cover" />
              )}
            </button>
          ))}
        </div>
      </div>
      <div className="flex justify-end gap-3 px-5 py-4">
        <Button variant="secondary" onClick={onClose}>
          {t("cancel")}
        </Button>
        <Button disabled={!selected} busy={busy} onClick={() => selected && onPick(selected)}>
          {t("choose_this")}
        </Button>
      </div>
    </dialog>
  );
}
