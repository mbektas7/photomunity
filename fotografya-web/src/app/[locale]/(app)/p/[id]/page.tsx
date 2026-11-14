"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { MapPin } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useParams } from "next/navigation";
import { useState } from "react";
import { Avatar } from "@/components/Avatar";
import { LikeButton } from "@/components/LikeButton";
import { ReportButton } from "@/components/ReportDialog";
import { Viewfinder } from "@/components/Viewfinder";
import { Button, Notice, TextArea, TextField, buttonClass } from "@/components/ui";
import { Link, useRouter } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import { formatDate } from "@/lib/format";
import { useMe } from "@/lib/hooks";
import type { Location, PhotoDetail } from "@/lib/types";

function mapUrl(loc: Location) {
  return `/map?layer=photos&lat=${loc.latitude}&lng=${loc.longitude}&z=13`;
}

export default function PhotoPage() {
  const { id } = useParams<{ id: string }>();
  const t = useTranslations("photo");
  const locale = useLocale();
  const { data: me } = useMe();
  const qc = useQueryClient();
  const router = useRouter();
  const [editing, setEditing] = useState(false);

  const q = useQuery({
    queryKey: ["photo", id],
    queryFn: () => api<PhotoDetail>(`photos/${id}`),
    refetchInterval: (query) => (query.state.data?.status === "processing" ? 2000 : false),
  });

  const save = useMutation({
    mutationFn: (body: Record<string, unknown>) => api<PhotoDetail>(`photos/${id}`, { method: "PATCH", body }),
    onSuccess: (data) => {
      qc.setQueryData(["photo", id], data);
      setEditing(false);
    },
  });

  const remove = useMutation({
    mutationFn: () => api(`photos/${id}`, { method: "DELETE" }),
    onSuccess: () => {
      qc.invalidateQueries();
      router.replace(me ? `/u/${me.username}` : "/");
    },
  });

  if (q.error) {
    const e = q.error instanceof ApiError ? q.error : null;
    return (
      <div className="mx-auto max-w-[680px] px-4 py-20">
        <Notice tone="error">{e?.message || t("not_found")}</Notice>
        {e?.code === "private_profile" && (
          <p className="mt-4 text-ink-muted">{t("private_hint")}</p>
        )}
      </div>
    );
  }
  if (!q.data) return <div className="h-[70vh]" aria-busy />;

  const photo = q.data;
  const isOwner = me?.id === photo.user.id;
  const img = photo.images.full ?? photo.images.feed;

  if (photo.status === "processing" || photo.status === "pending") {
    return (
      <div className="mx-auto max-w-[680px] px-4 py-24">
        <h1 className="text-2xl font-semibold tracking-[-0.02em]">{t("processing_title")}</h1>
        <p className="mt-2 text-ink-muted">{t("processing_body")}</p>
        <div className="mt-8 h-1 overflow-hidden bg-line">
          <div className="h-full w-1/3 animate-[slide_1.2s_ease-in-out_infinite] bg-accent" />
        </div>
        <style>{`@keyframes slide{0%{transform:translateX(-100%)}100%{transform:translateX(300%)}}`}</style>
      </div>
    );
  }

  if (photo.status === "rejected") {
    return (
      <div className="mx-auto max-w-[680px] px-4 py-24">
        <h1 className="text-2xl font-semibold tracking-[-0.02em]">{t("rejected_title")}</h1>
        <ul className="mt-4 flex flex-col gap-2">
          {photo.rejection?.map((r) => (
            <li key={r.code} className="border-l-2 border-danger pl-3 text-[15px]">
              {r.message}
            </li>
          ))}
        </ul>
        <p className="mt-4 text-ink-muted">{t("rejected_body")}</p>
        <div className="mt-8 flex gap-3">
          <Link href="/upload" className={buttonClass("primary")}>
            {t("try_another")}
          </Link>
          <Button variant="ghost" onClick={() => remove.mutate()} busy={remove.isPending}>
            {t("discard")}
          </Button>
        </div>
      </div>
    );
  }

  const details = (
    <>
      {photo.width && photo.height && (
        <p className="tnum text-sm text-ink-muted">
          {photo.width} × {photo.height} px
        </p>
      )}
      {me && !isOwner && <ReportButton targetType="photo" targetId={photo.id} />}
      {isOwner && !editing && (
        <div className="flex gap-2">
          <Button variant="secondary" onClick={() => setEditing(true)}>
            {t("edit")}
          </Button>
          <Button variant="ghost" busy={remove.isPending} onClick={() => window.confirm(t("delete_confirm")) && remove.mutate()}>
            {t("delete")}
          </Button>
        </div>
      )}
    </>
  );

  return (
    <article>
      {/* Duvar: fotoğraf ekrana sığar, asla kırpılmaz */}
      <div className="flex justify-center bg-bg px-0 py-0 sm:px-6 sm:py-8">
        {img && (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={img.url}
            alt={photo.title ?? ""}
            width={img.width}
            height={img.height}
            className="fade-in block h-auto max-h-[calc(100dvh-8rem)] w-auto max-w-full object-contain"
          />
        )}
      </div>

      <div className="mx-auto grid max-w-[1100px] gap-6 px-4 pt-5 sm:px-6 lg:grid-cols-[1fr_340px] lg:gap-14 lg:pt-6">
        <div className="min-w-0">
          {photo.exif && <Viewfinder exif={photo.exif} />}

          {editing ? (
            <EditForm photo={photo} busy={save.isPending} onCancel={() => setEditing(false)} onSave={(b) => save.mutate(b)} />
          ) : (
            <div className="pt-7">
              {photo.title && <h1 className="text-[28px] font-semibold leading-tight tracking-[-0.025em]">{photo.title}</h1>}
              {photo.description && (
                <p className="mt-3 max-w-[64ch] whitespace-pre-line text-[16px] leading-relaxed">{photo.description}</p>
              )}
              {photo.tags.length > 0 && (
                <ul className="mt-5 flex flex-wrap gap-2">
                  {photo.tags.map((tag) => (
                    <li key={tag} className="rounded-full border border-line px-3 py-1 text-sm text-ink-muted">
                      #{tag}
                    </li>
                  ))}
                </ul>
              )}
              {photo.location && (
                <Link href={mapUrl(photo.location)} className="mt-5 inline-flex items-center gap-1.5 text-[15px] font-medium underline-offset-4 hover:underline">
                  <MapPin className="h-4 w-4" />
                  {photo.location.name || `${photo.location.latitude.toFixed(3)}, ${photo.location.longitude.toFixed(3)}`}
                </Link>
              )}
              {isOwner && photo.suggested_location && (
                <div className="mt-6">
                  <Notice>
                    {t("suggested_location")}{" "}
                    <button type="button" className="font-semibold text-ink underline underline-offset-4" onClick={() => save.mutate({ location: photo.suggested_location })}>
                      {t("add_location")}
                    </button>
                  </Notice>
                </div>
              )}
            </div>
          )}
        </div>

        <aside className="order-first flex flex-col gap-4 lg:order-none lg:gap-6 lg:pt-1">
          <Link href={`/u/${photo.user.username}`} className="flex items-center gap-3">
            <Avatar name={photo.user.display_name} url={photo.user.avatar_url} size={48} />
            <span className="min-w-0">
              <span className="block truncate font-semibold">{photo.user.display_name}</span>
              <span className="block truncate text-sm text-ink-muted">@{photo.user.username}</span>
            </span>
          </Link>
          <div className="flex items-center justify-between border-y border-line py-2">
            <LikeButton id={photo.id} liked={photo.liked_by_me} count={photo.like_count} size="lg" />
            <span className="px-2 text-sm text-ink-muted">{formatDate(photo.published_at, locale)}</span>
          </div>
          <div className="hidden flex-col gap-6 lg:flex">{details}</div>
        </aside>
        <div className="flex flex-col gap-6 lg:hidden">{details}</div>
      </div>
    </article>
  );
}

function EditForm({ photo, busy, onCancel, onSave }: { photo: PhotoDetail; busy: boolean; onCancel: () => void; onSave: (b: Record<string, unknown>) => void }) {
  const t = useTranslations("photo");
  const tu = useTranslations("upload");
  const [title, setTitle] = useState(photo.title ?? "");
  const [description, setDescription] = useState(photo.description ?? "");
  const [tags, setTags] = useState(photo.tags.join(", "));

  return (
    <form
      className="flex flex-col gap-5 pt-7"
      onSubmit={(e) => {
        e.preventDefault();
        onSave({ title, description, tags: tags.split(",").map((s) => s.trim()).filter(Boolean) });
      }}
    >
      <TextField label={tu("title")} name="title" value={title} maxLength={150} onChange={(e) => setTitle(e.target.value)} />
      <TextArea label={tu("description")} name="description" value={description} maxLength={2000} onChange={(e) => setDescription(e.target.value)} />
      <TextField label={tu("tags")} hint={tu("tags_hint")} name="tags" value={tags} onChange={(e) => setTags(e.target.value)} />
      {photo.location && (
        <Button type="button" variant="ghost" className="self-start" onClick={() => onSave({ clear_location: true })}>
          {t("remove_location")}
        </Button>
      )}
      <div className="flex gap-3">
        <Button type="submit" busy={busy}>
          {t("save")}
        </Button>
        <Button type="button" variant="ghost" onClick={onCancel}>
          {t("cancel")}
        </Button>
      </div>
    </form>
  );
}
