"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ArrowDown, ArrowUp, ImagePlus, Pencil, Trash2, X } from "lucide-react";
import { useTranslations } from "next-intl";
import { useParams } from "next/navigation";
import { useState } from "react";
import { Avatar } from "@/components/Avatar";
import { CollectionDialog, MultiPhotoPicker } from "@/components/collections";
import { JustifiedWall } from "@/components/JustifiedWall";
import { ShareButton } from "@/components/ShareButton";
import { Button, Notice } from "@/components/ui";
import { Link, useRouter } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import type { Collection } from "@/lib/types";

export default function CollectionPage() {
  const { id } = useParams<{ id: string }>();
  const t = useTranslations("collections");
  const router = useRouter();
  const qc = useQueryClient();
  const [editing, setEditing] = useState(false);
  const [picking, setPicking] = useState(false);
  const [ordering, setOrdering] = useState<string[] | null>(null);

  const q = useQuery({ queryKey: ["collection", id], queryFn: () => api<Collection>(`collections/${id}`) });
  const setPhotos = useMutation({
    mutationFn: (ids: string[]) => api<Collection>(`collections/${id}/photos`, { method: "PUT", body: { photo_ids: ids } }),
    onSuccess: (c) => {
      qc.setQueryData(["collection", id], c);
      qc.invalidateQueries({ queryKey: ["collections"] });
      setPicking(false);
      setOrdering(null);
    },
  });
  const remove = useMutation({
    mutationFn: () => api(`collections/${id}`, { method: "DELETE" }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["collections"] });
      router.replace(q.data ? `/u/${q.data.owner.username}?tab=collections` : "/");
    },
  });

  if (q.error) {
    return (
      <div className="mx-auto max-w-[680px] px-4 py-20">
        <Notice tone="error">{q.error instanceof ApiError && q.error.message ? q.error.message : t("not_found")}</Notice>
      </div>
    );
  }
  const c = q.data;
  if (!c) return <div className="h-[60vh]" aria-busy />;
  const hero = c.photos[0]?.images.full ?? c.photos[0]?.images.feed;
  const byId = new Map(c.photos.map((p) => [p.id, p]));
  const move = (i: number, d: -1 | 1) =>
    setOrdering((o) => {
      if (!o) return o;
      const n = [...o];
      const j = i + d;
      if (j < 0 || j >= n.length) return o;
      [n[i], n[j]] = [n[j]!, n[i]!];
      return n;
    });

  return (
    <div className="mx-auto max-w-[1440px] px-3 pb-16 sm:px-6 lg:px-10">
      <section className="grid items-center gap-6 rounded-card bg-surface p-5 sm:rounded-[28px] sm:p-8 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.3fr)]">
        <div className="flex flex-col gap-4">
          <p className="tnum text-xs font-bold uppercase tracking-[0.08em] text-ink-muted">{t("series_count", { count: c.photo_count })}</p>
          <h1 className="text-[34px] font-bold leading-none tracking-[-0.04em] sm:text-[44px]">{c.title}</h1>
          {c.description && <p className="max-w-[60ch] whitespace-pre-line text-[16px] leading-[1.55]">{c.description}</p>}
          <Link href={`/u/${c.owner.username}?tab=collections`} className="flex items-center gap-2.5 self-start rounded-box">
            <Avatar name={c.owner.display_name} url={c.owner.avatar_url} size={34} />
            <span className="font-semibold">{c.owner.display_name}</span>
          </Link>
          <div className="flex flex-wrap gap-2">
            <ShareButton title={c.title} size={44} />
            {c.is_mine && (
              <>
                <Button variant="secondary" onClick={() => setPicking(true)}><ImagePlus className="h-4 w-4" aria-hidden /> {t("add_photos")}</Button>
                {c.photos.length > 1 && !ordering && (
                  <Button variant="secondary" onClick={() => setOrdering(c.photos.map((p) => p.id))}><ArrowDown className="h-4 w-4" aria-hidden /> {t("reorder")}</Button>
                )}
                <Button variant="secondary" onClick={() => setEditing(true)}><Pencil className="h-4 w-4" aria-hidden /> {t("edit")}</Button>
                <Button variant="danger" busy={remove.isPending} onClick={() => window.confirm(t("delete_confirm")) && remove.mutate()}>
                  <Trash2 className="h-4 w-4" aria-hidden /> {t("delete")}
                </Button>
              </>
            )}
          </div>
        </div>
        {hero && (
          <div className="flex justify-center rounded-photo bg-bg">
            {/* Kapak: ilk kare, kendi oranında (kırpılmaz) */}
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={hero.url} alt={c.photos[0]?.title ?? ""} width={hero.width} height={hero.height} className="block max-h-[52vh] w-auto max-w-full object-contain" />
          </div>
        )}
      </section>

      {setPhotos.error && <div className="mt-4"><Notice tone="error">{setPhotos.error instanceof ApiError && setPhotos.error.message ? setPhotos.error.message : t("error")}</Notice></div>}

      {ordering ? (
        <section className="mt-6 rounded-card bg-surface p-4">
          <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
            <h2 className="text-heading">{t("reorder")}</h2>
            <div className="flex gap-2">
              <Button variant="secondary" onClick={() => setOrdering(null)}>{t("cancel")}</Button>
              <Button busy={setPhotos.isPending} onClick={() => setPhotos.mutate(ordering)}>{t("save")}</Button>
            </div>
          </div>
          <ol className="flex flex-col gap-1.5">
            {ordering.map((pid, i) => {
              const p = byId.get(pid);
              const v = p?.images.thumb ?? p?.images.feed;
              const name = p?.title || t("untitled");
              return (
                <li key={pid} className="flex items-center gap-3 rounded-box bg-surface-2 p-2">
                  <span className="tnum w-6 text-center text-sm font-bold text-ink-muted">{i + 1}</span>
                  {v && (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={v.url} alt="" className="h-14 w-20 shrink-0 rounded-[8px] bg-bg object-contain" />
                  )}
                  <span className="min-w-0 flex-1 truncate">{name}</span>
                  <button type="button" disabled={i === 0} onClick={() => move(i, -1)} aria-label={t("move_up", { title: name })} className="grid h-9 w-9 place-items-center rounded-full hover:bg-line disabled:opacity-30"><ArrowUp className="h-4 w-4" aria-hidden /></button>
                  <button type="button" disabled={i === ordering.length - 1} onClick={() => move(i, 1)} aria-label={t("move_down", { title: name })} className="grid h-9 w-9 place-items-center rounded-full hover:bg-line disabled:opacity-30"><ArrowDown className="h-4 w-4" aria-hidden /></button>
                  <button type="button" onClick={() => setOrdering((o) => o?.filter((x) => x !== pid) ?? null)} aria-label={t("remove_photo", { title: name })} className="grid h-9 w-9 place-items-center rounded-full hover:bg-line"><X className="h-4 w-4" aria-hidden /></button>
                </li>
              );
            })}
          </ol>
        </section>
      ) : c.photos.length === 0 ? (
        <div className="mt-6 rounded-card bg-surface px-6 py-14 text-ink-muted">{c.is_mine ? t("detail_empty_me") : t("detail_empty")}</div>
      ) : (
        <div className="mt-6">
          <JustifiedWall photos={c.photos} target={340} />
        </div>
      )}

      {c.is_mine && (
        <>
          <CollectionDialog open={editing} onClose={() => setEditing(false)} collection={c} />
          <MultiPhotoPicker open={picking} onClose={() => setPicking(false)} initial={c.photos.map((p) => p.id)} busy={setPhotos.isPending} onSave={(ids) => setPhotos.mutate(ids)} />
        </>
      )}
    </div>
  );
}
