"use client";

import { useQuery } from "@tanstack/react-query";
import { ChevronLeft, ChevronRight, X } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { Avatar } from "@/components/Avatar";
import { CommunityLogo } from "@/components/community";
import { Notice } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import { relativeTime } from "@/lib/relative-time";
import type { Community, CommunityPost, NewsImage } from "@/lib/types";

export default function NewsDetailPage() {
  const { slug, id } = useParams<{ slug: string; id: string }>();
  const t = useTranslations("communities");
  const locale = useLocale();
  const [open, setOpen] = useState<number | null>(null);
  const cq = useQuery({ queryKey: ["community", slug], queryFn: () => api<Community>(`communities/${slug}`) });
  const pq = useQuery({ queryKey: ["community-post", slug, id], queryFn: () => api<CommunityPost>(`communities/${slug}/posts/${id}`) });

  if (pq.error) return <div className="mx-auto max-w-[760px] px-4 py-20"><Notice tone="error">{pq.error instanceof ApiError ? pq.error.message : t("error")}</Notice></div>;
  const p = pq.data;
  const c = cq.data;
  if (!p) return <div className="h-[60vh]" aria-busy />;

  return (
    <article className="mx-auto max-w-[760px] px-4 py-8 sm:px-6">
      <Link href={`/c/${slug}`} className="inline-flex items-center gap-3 text-sm">
        <ChevronLeft className="h-4 w-4 text-ink-muted" />
        {c && <CommunityLogo name={c.name} url={c.logo_url} size={36} />}
        <span>
          <span className="block font-semibold">{c?.name ?? t("back_to_community")}</span>
          <span className="block text-ink-muted">{t("news_label")} · {relativeTime(p.created_at, locale)}</span>
        </span>
      </Link>

      {p.title && <h1 className="mt-6 text-[30px] font-semibold leading-[1.15] tracking-[-0.02em] sm:text-[36px]">{p.title}</h1>}
      <div className="mt-3 flex items-center gap-2 text-sm text-ink-muted">
        <Avatar name={p.author.display_name} url={p.author.avatar_url} size={28} />
        <Link href={`/u/${p.author.username}`} className="hover:underline">{p.author.display_name}</Link>
      </div>

      {p.images.length > 0 && (
        <div className="-mx-4 mt-6 flex snap-x snap-mandatory gap-3 overflow-x-auto px-4 pb-2 sm:-mx-6 sm:px-6">
          {p.images.map((img, i) => (
            <button key={img.key} type="button" onClick={() => setOpen(i)}
              className={`shrink-0 snap-start self-start overflow-hidden rounded-photo ${p.images.length === 1 ? "w-full" : ""}`}>
              {/* Kırpılmadan: kendi oranında */}
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={img.url} alt={`${p.title ?? ""} ${i + 1}`} width={img.width} height={img.height} className={p.images.length === 1 ? "block h-auto max-h-[75vh] w-full object-contain" : "block h-[min(60vh,460px)] w-auto max-w-[85vw]"} />
            </button>
          ))}
        </div>
      )}

      {p.body && <div className="mt-6 whitespace-pre-line rounded-card bg-surface px-5 py-5 text-[16px] leading-relaxed">{p.body}</div>}

      {open !== null && <Lightbox images={p.images} start={open} onClose={() => setOpen(null)} />}
    </article>
  );
}

function Lightbox({ images, start, onClose }: { images: NewsImage[]; start: number; onClose: () => void }) {
  const t = useTranslations("communities");
  const [i, setI] = useState(start);
  const prev = useCallback(() => setI((n) => (n - 1 + images.length) % images.length), [images.length]);
  const next = useCallback(() => setI((n) => (n + 1) % images.length), [images.length]);
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
      else if (e.key === "ArrowLeft") prev();
      else if (e.key === "ArrowRight") next();
    };
    window.addEventListener("keydown", onKey);
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = "";
    };
  }, [onClose, prev, next]);
  const img = images[i];
  const btn = "grid h-11 w-11 place-items-center rounded-full bg-white/10 text-white hover:bg-white/20";
  return (
    <div role="dialog" aria-modal="true" className="fixed inset-0 z-50 flex flex-col bg-black/95" onClick={onClose}>
      <div className="flex items-center justify-between px-4 py-3 text-sm text-white/80" onClick={(e) => e.stopPropagation()}>
        <span>{i + 1} / {images.length}</span>
        <button type="button" aria-label={t("gallery_close")} onClick={onClose} className={btn}><X className="h-5 w-5" /></button>
      </div>
      <div className="relative flex min-h-0 flex-1 items-center justify-center px-2 pb-6">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={img.url} alt="" className="max-h-full max-w-full object-contain" onClick={(e) => e.stopPropagation()} />
        {images.length > 1 && (
          <>
            <button type="button" aria-label={t("gallery_prev")} onClick={(e) => { e.stopPropagation(); prev(); }} className={`${btn} absolute left-3 top-1/2 -translate-y-1/2`}><ChevronLeft className="h-6 w-6" /></button>
            <button type="button" aria-label={t("gallery_next")} onClick={(e) => { e.stopPropagation(); next(); }} className={`${btn} absolute right-3 top-1/2 -translate-y-1/2`}><ChevronRight className="h-6 w-6" /></button>
          </>
        )}
      </div>
    </div>
  );
}
