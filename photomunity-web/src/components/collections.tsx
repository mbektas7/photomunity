"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import clsx from "clsx";
import { Check, ChevronDown, ChevronUp, FolderPlus, Plus, X } from "lucide-react";
import { useTranslations } from "next-intl";
import { useEffect, useRef, useState } from "react";
import { Button, Notice, TextArea, TextField } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import { useMe } from "@/lib/hooks";
import type { Collection, CollectionCard, Page, PhotoCard, Variants } from "@/lib/types";

const ratio = (v: Variants) => {
  const x = v.thumb ?? v.feed ?? v.full;
  return x && x.height ? x.width / x.height : 1.5;
};

/**
 * Kapak: ilk en fazla 3 kare kendi en-boy oranlarıyla yan yana (kırpılmadan). Kutunun oranı karelerin
 * oranları toplamıdır; boşluk payı object-contain ile emilir.
 */
export function CoverRow({ covers, className }: { covers: Variants[]; className?: string }) {
  const list = covers.slice(0, 3);
  if (!list.length) return <div className={clsx("aspect-[3/2] rounded-photo bg-surface-2", className)} aria-hidden />;
  const sum = list.reduce((s, c) => s + ratio(c), 0);
  return (
    <div className={clsx("flex gap-1", className)} style={{ aspectRatio: `${sum.toFixed(3)} / 1` }} aria-hidden>
      {list.map((c, i) => {
        const v = c.thumb ?? c.feed ?? c.full;
        return (
          <span key={i} className="block min-w-0 overflow-hidden rounded-[10px] bg-surface-2" style={{ flex: `${ratio(c).toFixed(3)} 1 0` }}>
            {v && (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={v.url} alt="" loading="lazy" className="h-full w-full object-contain" />
            )}
          </span>
        );
      })}
    </div>
  );
}

/** Profil sekmesi: koleksiyon kartları; sahibi yeni oluşturur ve sırayı değiştirir. */
export function ProfileCollections({ username, isMe }: { username: string; isMe: boolean }) {
  const t = useTranslations("collections");
  const qc = useQueryClient();
  const [creating, setCreating] = useState(false);
  const q = useQuery({ queryKey: ["collections", "user", username], queryFn: () => api<CollectionCard[]>(`users/${username}/collections`) });
  const reorder = useMutation({
    mutationFn: (ids: string[]) => api<CollectionCard[]>("me/collections/order", { method: "PUT", body: { collection_ids: ids } }),
    onMutate: (ids) => {
      const prev = q.data ?? [];
      qc.setQueryData(["collections", "user", username], ids.map((id) => prev.find((c) => c.id === id)!).filter(Boolean));
    },
    onSettled: () => qc.invalidateQueries({ queryKey: ["collections"] }),
  });
  const items = q.data ?? [];
  const move = (i: number, d: -1 | 1) => {
    const ids = items.map((c) => c.id);
    const j = i + d;
    if (j < 0 || j >= ids.length) return;
    [ids[i], ids[j]] = [ids[j]!, ids[i]!];
    reorder.mutate(ids);
  };

  return (
    <div>
      {isMe && (
        <div className="mb-4">
          <Button variant="secondary" className="bg-surface" onClick={() => setCreating(true)}>
            <Plus className="h-4 w-4" strokeWidth={2.4} aria-hidden /> {t("new")}
          </Button>
        </div>
      )}
      {q.isSuccess && items.length === 0 && (
        <div className="rounded-card bg-surface px-6 py-14 text-ink-muted">{isMe ? t("empty_me") : t("empty")}</div>
      )}
      <ul className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
        {items.map((c, i) => (
          <li key={c.id} className="relative rounded-card bg-surface p-3">
            <Link href={`/collections/${c.id}`} className="block rounded-photo">
              <CoverRow covers={c.covers} className="w-full" />
              <span className="mt-3 block px-1 text-[17px] font-semibold">{c.title}</span>
              <span className="block px-1 pb-1 text-sm text-ink-muted">{t("photo_count", { count: c.photo_count })}</span>
            </Link>
            {isMe && items.length > 1 && (
              <div className="absolute bottom-3 right-3 flex gap-1">
                <button type="button" disabled={i === 0 || reorder.isPending} onClick={() => move(i, -1)} aria-label={t("move_up", { title: c.title })} className="grid h-9 w-9 place-items-center rounded-full bg-surface-2 hover:bg-line disabled:opacity-30">
                  <ChevronUp className="h-4 w-4" aria-hidden />
                </button>
                <button type="button" disabled={i === items.length - 1 || reorder.isPending} onClick={() => move(i, 1)} aria-label={t("move_down", { title: c.title })} className="grid h-9 w-9 place-items-center rounded-full bg-surface-2 hover:bg-line disabled:opacity-30">
                  <ChevronDown className="h-4 w-4" aria-hidden />
                </button>
              </div>
            )}
          </li>
        ))}
      </ul>
      {isMe && <CollectionDialog open={creating} onClose={() => setCreating(false)} />}
    </div>
  );
}

/** Koleksiyon oluştur / düzenle penceresi. */
export function CollectionDialog({ open, onClose, collection, photoIds, onCreated }: {
  open: boolean;
  onClose: () => void;
  collection?: Collection;
  /** Oluştururken eklenecek kareler (ör. fotoğraf detayından "yeni koleksiyon") */
  photoIds?: string[];
  onCreated?: (c: Collection) => void;
}) {
  const t = useTranslations("collections");
  const qc = useQueryClient();
  const ref = useRef<HTMLDialogElement>(null);
  const [title, setTitle] = useState(collection?.title ?? "");
  const [description, setDescription] = useState(collection?.description ?? "");
  useEffect(() => {
    if (open) {
      setTitle(collection?.title ?? "");
      setDescription(collection?.description ?? "");
      ref.current?.showModal();
    } else ref.current?.close();
  }, [open, collection]);
  const save = useMutation({
    mutationFn: () =>
      collection
        ? api<Collection>(`collections/${collection.id}`, { method: "PATCH", body: { title: title.trim(), description: description.trim() || null } })
        : api<Collection>("collections", { method: "POST", body: { title: title.trim(), description: description.trim() || null, photo_ids: photoIds ?? [] } }),
    onSuccess: (c) => {
      qc.invalidateQueries({ queryKey: ["collections"] });
      qc.setQueryData(["collection", c.id], c);
      if (!collection) onCreated?.(c);
      onClose();
    },
  });
  return (
    <dialog ref={ref} onClose={onClose} className="m-auto w-[min(520px,calc(100vw-1.5rem))] rounded-sheet bg-surface p-0 text-ink shadow-float backdrop:bg-black/55">
      <form
        className="flex flex-col gap-4 p-6"
        onSubmit={(e) => {
          e.preventDefault();
          if (title.trim()) save.mutate();
        }}
      >
        <h2 className="text-lg font-semibold">{collection ? t("edit") : t("new")}</h2>
        <TextField label={t("title_label")} name="collection-title" required maxLength={100} value={title} onChange={(e) => setTitle(e.target.value)} autoFocus />
        <TextArea label={t("description_label")} name="collection-description" rows={3} maxLength={500} value={description} onChange={(e) => setDescription(e.target.value)} />
        {save.error && <Notice tone="error">{save.error instanceof ApiError && save.error.message ? save.error.message : t("error")}</Notice>}
        <div className="flex justify-end gap-2">
          <Button type="button" variant="secondary" onClick={onClose}>{t("cancel")}</Button>
          <Button type="submit" busy={save.isPending} disabled={!title.trim()}>{t("save")}</Button>
        </div>
      </form>
    </dialog>
  );
}

/** Fotoğraf detayında (yalnızca sahibi): kareyi koleksiyonlara ekle / çıkar. */
export function AddToCollection({ photoId }: { photoId: string }) {
  const t = useTranslations("collections");
  const qc = useQueryClient();
  const ref = useRef<HTMLDialogElement>(null);
  const [open, setOpen] = useState(false);
  const [creating, setCreating] = useState(false);
  const q = useQuery({
    queryKey: ["collections", "me", photoId],
    enabled: open,
    queryFn: () => api<CollectionCard[]>(`me/collections?photo_id=${photoId}`),
  });
  const toggle = useMutation({
    mutationFn: ({ id, on }: { id: string; on: boolean }) =>
      on ? api(`collections/${id}/photos`, { method: "POST", body: { photo_id: photoId } }) : api(`collections/${id}/photos/${photoId}`, { method: "DELETE" }),
    onMutate: ({ id, on }) =>
      qc.setQueryData<CollectionCard[]>(["collections", "me", photoId], (xs) => xs?.map((c) => (c.id === id ? { ...c, contains_photo: on } : c))),
    onSettled: () => {
      qc.invalidateQueries({ queryKey: ["collections"] });
      qc.invalidateQueries({ queryKey: ["collection"] });
    },
  });
  useEffect(() => {
    if (open) ref.current?.showModal();
    else ref.current?.close();
  }, [open]);

  return (
    <>
      <Button variant="secondary" onClick={() => setOpen(true)}>
        <FolderPlus className="h-[18px] w-[18px]" strokeWidth={1.8} aria-hidden /> {t("add_to")}
      </Button>
      <dialog ref={ref} onClose={() => setOpen(false)} className="m-auto w-[min(480px,calc(100vw-1.5rem))] rounded-sheet bg-surface p-0 text-ink shadow-float backdrop:bg-black/55">
        <div className="flex items-center justify-between px-5 py-4">
          <h2 className="text-lg font-semibold">{t("add_to")}</h2>
          <button type="button" onClick={() => setOpen(false)} aria-label={t("close")} className="grid h-11 w-11 place-items-center rounded-full bg-surface-2 hover:bg-line">
            <X className="h-5 w-5" aria-hidden />
          </button>
        </div>
        <ul className="max-h-[50dvh] overflow-y-auto px-3">
          {q.isSuccess && q.data.length === 0 && <li className="px-2 py-6 text-ink-muted">{t("none_yet")}</li>}
          {q.data?.map((c) => {
            const on = !!c.contains_photo;
            return (
              <li key={c.id}>
                <button
                  type="button"
                  role="checkbox"
                  aria-checked={on}
                  onClick={() => toggle.mutate({ id: c.id, on: !on })}
                  className="flex w-full items-center gap-3 rounded-box px-2 py-2.5 text-left hover:bg-surface-2"
                >
                  <CoverRow covers={c.covers.slice(0, 1)} className="h-11 shrink-0" />
                  <span className="min-w-0 flex-1">
                    <span className="block truncate font-semibold">{c.title}</span>
                    <span className="block text-sm text-ink-muted">{t("photo_count", { count: c.photo_count })}</span>
                  </span>
                  <span className={clsx("grid h-6 w-6 place-items-center rounded-full border-2", on ? "border-accent bg-accent text-accent-ink" : "border-line")} aria-hidden>
                    {on && <Check className="h-4 w-4" strokeWidth={3} />}
                  </span>
                </button>
              </li>
            );
          })}
        </ul>
        <div className="flex justify-between gap-2 px-5 py-4">
          <Button variant="ghost" onClick={() => setCreating(true)}>
            <Plus className="h-4 w-4" aria-hidden /> {t("new")}
          </Button>
          <Button onClick={() => setOpen(false)}>{t("done")}</Button>
        </div>
      </dialog>
      <CollectionDialog open={creating} onClose={() => setCreating(false)} photoIds={[photoId]} onCreated={() => qc.invalidateQueries({ queryKey: ["collections", "me", photoId] })} />
    </>
  );
}

/** Koleksiyona kare ekleme: kendi yayındaki karelerimden çoklu seçim. */
export function MultiPhotoPicker({ open, onClose, initial, onSave, busy }: { open: boolean; onClose: () => void; initial: string[]; onSave: (ids: string[]) => void; busy?: boolean }) {
  const t = useTranslations("collections");
  const { data: me } = useMe();
  const ref = useRef<HTMLDialogElement>(null);
  const [sel, setSel] = useState<string[]>(initial);
  const photos = useQuery({
    queryKey: ["photos", "user", me?.username, "picker"],
    enabled: open && !!me,
    queryFn: () => api<Page<PhotoCard>>(`users/${me!.username}/photos?limit=60`),
  });
  useEffect(() => {
    if (open) {
      setSel(initial);
      ref.current?.showModal();
    } else ref.current?.close();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);
  return (
    <dialog ref={ref} onClose={onClose} className="m-auto max-h-[85dvh] w-[min(760px,calc(100vw-1.5rem))] rounded-sheet bg-surface p-0 text-ink shadow-float backdrop:bg-black/55">
      <div className="flex items-center justify-between px-5 py-4">
        <h2 className="text-lg font-semibold">{t("pick_photos")}</h2>
        <button type="button" onClick={onClose} aria-label={t("close")} className="grid h-11 w-11 place-items-center rounded-full bg-surface-2 hover:bg-line">
          <X className="h-5 w-5" aria-hidden />
        </button>
      </div>
      <div className="max-h-[58dvh] overflow-y-auto p-3">
        <div className="grid grid-cols-3 gap-2 sm:grid-cols-4">
          {photos.data?.items.map((p) => {
            const on = sel.includes(p.id);
            const v = p.images.thumb ?? p.images.feed;
            return (
              <button
                key={p.id}
                type="button"
                aria-pressed={on}
                aria-label={p.title ?? t("untitled")}
                onClick={() => setSel((s) => (on ? s.filter((x) => x !== p.id) : [...s, p.id]))}
                className={clsx("relative aspect-square overflow-hidden rounded-photo bg-surface-2 outline-offset-2", on && "outline outline-[3px] outline-accent")}
              >
                {v && (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={v.url} alt="" className="h-full w-full object-contain" />
                )}
                {on && (
                  <span className="tnum absolute right-1.5 top-1.5 grid h-6 min-w-6 place-items-center rounded-full bg-accent px-1 text-xs font-bold text-accent-ink">
                    {sel.indexOf(p.id) + 1}
                  </span>
                )}
              </button>
            );
          })}
        </div>
      </div>
      <div className="flex items-center justify-between gap-3 px-5 py-4">
        <span className="tnum text-sm text-ink-muted">{t("selected", { count: sel.length })}</span>
        <div className="flex gap-2">
          <Button variant="secondary" onClick={onClose}>{t("cancel")}</Button>
          <Button busy={busy} onClick={() => onSave(sel)}>{t("save")}</Button>
        </div>
      </div>
    </dialog>
  );
}
