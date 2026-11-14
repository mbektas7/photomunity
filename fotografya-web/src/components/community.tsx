"use client";

import clsx from "clsx";
import { Check, Star, X } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useEffect, useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link } from "@/i18n/navigation";
import { api } from "@/lib/api";
import { formatDateTime, remaining } from "@/lib/dates";
import { countryName, initials } from "@/lib/format";
import { useMe } from "@/lib/hooks";
import type { CommunityCard, ContestCard, ContestStatus, Page, PhotoCard } from "@/lib/types";
import { Button } from "./ui";

/** Topluluk logosu yuvarlatılmış karedir; kişi avatarları yuvarlaktır — kurum ve insan ilk bakışta ayrışır. */
export function CommunityLogo({ name, url, size = 48, className }: { name: string; url?: string | null; size?: number; className?: string }) {
  const style = { width: size, height: size, borderRadius: Math.round(size * 0.24), fontSize: Math.round(size * 0.36) };
  if (url) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={url} alt="" style={style} className={clsx("shrink-0 object-cover", className)} />;
  }
  return (
    <span aria-hidden style={style} className={clsx("inline-flex shrink-0 items-center justify-center bg-accent font-semibold text-accent-ink", className)}>
      {initials(name)}
    </span>
  );
}

export function CommunityRow({ c }: { c: CommunityCard }) {
  const t = useTranslations("communities");
  const locale = useLocale();
  const place = [c.city, countryName(c.country, locale)].filter(Boolean).join(", ");
  return (
    <Link href={`/c/${c.slug}`} className="flex items-center gap-4 bg-surface px-4 py-4 transition-colors hover:bg-surface/70">
      <CommunityLogo name={c.name} url={c.logo_url} size={52} />
      <span className="min-w-0 flex-1">
        <span className="block truncate text-[16px] font-semibold">{c.name}</span>
        <span className="mt-0.5 block truncate text-sm text-ink-muted">
          {[place, t("members_count", { count: c.member_count })].filter(Boolean).join("  ·  ")}
        </span>
      </span>
      {c.my_role && <span className="shrink-0 rounded-full border border-line px-2.5 py-1 text-xs text-ink-muted">{t(`role.${c.my_role}`)}</span>}
    </Link>
  );
}

export function StatusBadge({ status }: { status: ContestStatus }) {
  const t = useTranslations("contests");
  return (
    <span
      className={clsx(
        "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold",
        status === "open" && "bg-accent text-accent-ink",
        status === "judging" && "bg-ink text-surface",
        status === "closed" && "border border-line text-ink-muted",
        status === "finished" && "border border-ink text-ink",
        status === "draft" && "border border-dashed border-line text-ink-muted",
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

export function ContestRow({ c, showCommunity = true }: { c: ContestCard; showCommunity?: boolean }) {
  const t = useTranslations("contests");
  const locale = useLocale();
  const next = nextMoment(c);
  const left = next ? remaining(next.at, locale) : null;
  return (
    <Link href={`/contests/${c.id}`} className="block bg-surface px-5 py-5 transition-colors hover:bg-surface/70">
      <div className="flex items-center gap-2">
        <StatusBadge status={c.status} />
        <span className="text-xs text-ink-muted">{t(`mode.${c.judging_mode}`)}</span>
      </div>
      <h3 className="mt-3 text-[19px] font-semibold leading-snug tracking-[-0.015em]">{c.title}</h3>
      <p className="mt-1.5 flex flex-wrap gap-x-3 gap-y-1 text-sm text-ink-muted">
        {showCommunity && <span>{c.community.name}</span>}
        <span className="tnum">{t("entries_count", { count: c.entry_count })}</span>
        {next && left && <span className="tnum text-ink">{t(next.key, { time: left })}</span>}
      </p>
    </Link>
  );
}

/** Katılım → Değerlendirme → Sonuç adımları; bulunulan adım vurgulanır. */
export function ContestTimeline({ c }: { c: ContestCard }) {
  const t = useTranslations("contests");
  const locale = useLocale();
  const order: ContestStatus[] = ["open", "judging", "closed", "finished"];
  const current = Math.max(0, order.indexOf(c.status === "draft" ? "open" : c.status));
  const steps = [
    { label: t("step_entries"), at: c.submission_deadline, until: true, idx: 0 },
    { label: c.judging_mode === "jury" ? t("step_jury") : t("step_voting"), at: c.voting_end, until: true, idx: 1 },
    { label: t("step_results"), at: c.results_at, until: false, idx: 3 },
  ];
  return (
    <ol className="grid grid-cols-3 gap-px bg-line">
      {steps.map((s) => {
        const done = current > s.idx || (s.idx === 3 && current === 3);
        const active = current === s.idx || (s.idx === 1 && current === 2);
        return (
          <li key={s.label} className={clsx("px-3 py-3 sm:px-4", active ? "bg-ink text-surface" : "bg-surface")}>
            <span className={clsx("flex items-center gap-1.5 text-[13px] font-semibold", !active && !done && "text-ink-muted")}>
              {done && !active && <Check className="h-3.5 w-3.5" strokeWidth={3} />}
              {s.label}
            </span>
            <span className={clsx("tnum mt-1 block text-[12px] leading-snug", active ? "text-surface/75" : "text-ink-muted")}>
              {s.until ? t("until", { date: formatDateTime(s.at, locale) }) : formatDateTime(s.at, locale)}
            </span>
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
    <dialog ref={dialog} onClose={onClose} className="m-auto max-h-[85dvh] w-[min(760px,calc(100vw-1.5rem))] border border-line bg-surface p-0 text-ink backdrop:bg-black/55">
      <div className="flex items-center justify-between border-b border-line px-5 py-4">
        <h2 className="text-lg font-semibold">{title}</h2>
        <button type="button" onClick={onClose} aria-label={t("close")} className="rounded-full p-1.5 hover:bg-ink/5">
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
        <div className="grid grid-cols-3 gap-1.5 sm:grid-cols-4">
          {photos.data?.items.map((p) => (
            <button
              key={p.id}
              type="button"
              onClick={() => setSelected(p)}
              aria-pressed={selected?.id === p.id}
              className={clsx("relative aspect-square overflow-hidden bg-ink/5 outline-offset-2", selected?.id === p.id && "outline outline-[3px] outline-accent")}
            >
              {p.images.thumb && (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={p.images.thumb.url} alt={p.title ?? ""} className="h-full w-full object-cover" />
              )}
            </button>
          ))}
        </div>
      </div>
      <div className="flex justify-end gap-3 border-t border-line px-5 py-4">
        <Button variant="ghost" onClick={onClose}>
          {t("cancel")}
        </Button>
        <Button disabled={!selected} busy={busy} onClick={() => selected && onPick(selected)}>
          {t("choose_this")}
        </Button>
      </div>
    </dialog>
  );
}
