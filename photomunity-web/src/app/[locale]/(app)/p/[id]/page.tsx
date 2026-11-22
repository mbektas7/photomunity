"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Camera, MapPin } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useParams } from "next/navigation";
import { useState } from "react";
import { Avatar } from "@/components/Avatar";
import { CommentPolicyField, Comments } from "@/components/Comments";
import { LikeButton } from "@/components/LikeButton";
import { ReportButton } from "@/components/ReportDialog";
import { ExifChip, ExifGrid } from "@/components/ExifChip";
import { FollowButton } from "@/components/FollowButton";
import { JustifiedWall } from "@/components/JustifiedWall";
import { ShareButton } from "@/components/ShareButton";
import { Button, Notice, TextArea, TextField, buttonClass } from "@/components/ui";
import { Link, useRouter } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import { formatDateTime } from "@/lib/dates";
import { cameraName, countryName, genitive } from "@/lib/format";
import { useMe } from "@/lib/hooks";
import type { CommentPolicy, Location, Page, PhotoCard as PhotoCardData, PhotoDetail, Profile } from "@/lib/types";

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

  const author = q.data?.user.username;
  const profile = useQuery({
    queryKey: ["profile", author],
    enabled: !!author,
    queryFn: () => api<Profile>(`users/${author}`),
  });
  const others = useQuery({
    queryKey: ["photos", "user", author, "more"],
    enabled: !!author && q.data?.status === "published",
    queryFn: () => api<Page<PhotoCardData>>(`users/${author}/photos?limit=6`),
    retry: false,
  });

  const save = useMutation({
    mutationFn: (body: Record<string, unknown>) => api<PhotoDetail>(`photos/${id}`, { method: "PATCH", body }),
    onSuccess: (data) => {
      qc.setQueryData(["photo", id], data);
      qc.invalidateQueries({ queryKey: ["comments", id] });
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
  const more = (others.data?.items ?? []).filter((p) => p.id !== photo.id).slice(0, 5);
  const isOwner = me?.id === photo.user.id;
  const img = photo.images.full ?? photo.images.feed;

  if (photo.status === "processing" || photo.status === "pending") {
    return (
      <div className="mx-auto max-w-[680px] px-4 py-24">
        <h1 className="text-title">{t("processing_title")}</h1>
        <p className="mt-2 text-ink-muted">{t("processing_body")}</p>
        <div className="mt-8 h-1.5 overflow-hidden rounded-pill bg-surface-2">
          <div className="h-full w-1/3 animate-[slide_1.2s_ease-in-out_infinite] rounded-pill bg-accent" />
        </div>
        <style>{`@keyframes slide{0%{transform:translateX(-100%)}100%{transform:translateX(300%)}}`}</style>
      </div>
    );
  }

  if (photo.status === "rejected") {
    return (
      <div className="mx-auto max-w-[680px] px-4 py-24">
        <h1 className="text-title">{t("rejected_title")}</h1>
        <ul className="mt-4 flex flex-col gap-2">
          {photo.rejection?.map((r) => (
            <li key={r.code} className="rounded-box bg-danger/10 px-4 py-3 text-[15px] text-danger">
              {r.message}
            </li>
          ))}
        </ul>
        <p className="mt-4 text-ink-muted">{t("rejected_body")}</p>
        <div className="mt-8 flex gap-3">
          <Link href="/upload" className={buttonClass("primary")}>
            {t("try_another")}
          </Link>
          <Button variant="danger" onClick={() => remove.mutate()} busy={remove.isPending}>
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

  const place = profile.data?.city ?? countryName(profile.data?.country ?? null, locale);
  const authorMeta = [place, profile.data ? t("followers_count", { count: profile.data.followers_count }) : null].filter(Boolean).join(", ");
  const camera = photo.exif ? [cameraName(photo.exif.camera_make, photo.exif.camera_model), photo.exif.lens].filter(Boolean).join(", ") : "";
  const when = photo.exif?.taken_at ?? photo.published_at;
  const firstName = photo.user.display_name.split(/\s+/)[0];

  return (
    <article className="mx-auto max-w-[1440px] px-0 sm:px-6 lg:px-10">
      <div className="grid items-start gap-5 lg:grid-cols-[minmax(0,1fr)_408px] lg:gap-6">
        {/* Fotoğraf kendi oranında; asla kırpılmaz */}
        <div className="flex justify-center">
          {img && (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={img.url}
              alt={photo.title ?? ""}
              width={img.width}
              height={img.height}
              className="fade-in print-placeholder block h-auto max-h-[calc(100dvh-7rem)] w-auto max-w-full object-contain sm:rounded-card"
            />
          )}
        </div>

        <aside className="mx-3 flex flex-col gap-4 rounded-card bg-surface p-5 sm:mx-0 sm:p-6">
          <div className="flex items-center gap-3">
            <Link href={`/u/${photo.user.username}`} className="flex min-w-0 flex-1 items-center gap-3 rounded-box">
              <Avatar name={photo.user.display_name} url={photo.user.avatar_url} size={46} />
              <span className="min-w-0">
                <span className="block truncate text-[16px] font-semibold">{photo.user.display_name}</span>
                {authorMeta && <span className="tnum block truncate text-[13px] text-ink-muted">{authorMeta}</span>}
              </span>
            </Link>
            {profile.data && !profile.data.is_me && <FollowButton profile={profile.data} size="sm" />}
          </div>

          {editing ? (
            <EditForm photo={photo} busy={save.isPending} onCancel={() => setEditing(false)} onSave={(b) => save.mutate(b)} />
          ) : (
            <>
              <div>
                {photo.title && <h1 className="text-[34px] font-bold leading-[38px] tracking-[-0.035em] max-sm:text-[30px] max-sm:leading-[34px]">{photo.title}</h1>}
                {when && <p className="tnum mt-2 text-[13px] text-ink-muted">{formatDateTime(when, locale)}</p>}
              </div>
              {photo.description && <p className="whitespace-pre-line text-[15px] leading-[23px]">{photo.description}</p>}
              {photo.tags.length > 0 && (
                <ul className="flex flex-wrap gap-1.5">
                  {photo.tags.map((tag) => (
                    <li key={tag}>
                      <ExifChip>#{tag}</ExifChip>
                    </li>
                  ))}
                </ul>
              )}
              {photo.exif && (
                <ExifGrid
                  exif={photo.exif}
                  locale={locale}
                  labels={{ shutter: t("shutter"), aperture: t("aperture"), iso: "ISO", focal: t("focal") }}
                />
              )}
              {camera && (
                <p className="flex items-center gap-2.5 text-[14px] text-ink-muted">
                  <Camera className="h-[18px] w-[18px] shrink-0" strokeWidth={1.8} aria-hidden />
                  {camera}
                </p>
              )}
              {photo.location && (
                <div className="flex items-center gap-3 rounded-box bg-surface-2 p-3">
                  <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-[12px] bg-accent-tint text-accent-text">
                    <MapPin className="h-5 w-5" strokeWidth={1.8} aria-hidden />
                  </span>
                  <span className="min-w-0 flex-1 truncate text-[15px] font-semibold">
                    {photo.location.name || `${photo.location.latitude.toFixed(3)}, ${photo.location.longitude.toFixed(3)}`}
                  </span>
                  <Link href={mapUrl(photo.location)} className="inline-flex min-h-11 items-center rounded-box px-2 text-[14.5px] font-semibold text-accent-text hover:underline">
                    {t("see_on_map")}
                  </Link>
                </div>
              )}
              {isOwner && photo.suggested_location && (
                <Notice>
                  {t("suggested_location")}{" "}
                  <button type="button" className="font-semibold text-accent-text underline underline-offset-4" onClick={() => save.mutate({ location: photo.suggested_location })}>
                    {t("add_location")}
                  </button>
                </Notice>
              )}
              <div className="flex items-center gap-2.5">
                <LikeButton id={photo.id} liked={photo.liked_by_me} count={photo.like_count} size="lg" className="flex-1" />
                <ShareButton title={photo.title ?? undefined} size={52} />
              </div>
              {(isOwner || (me && !isOwner)) && (
                <div className="flex flex-wrap items-center gap-2 border-t border-line pt-4">
                  {photo.width && photo.height && (
                    <span className="tnum mr-auto text-caption text-ink-muted">
                      {photo.width} × {photo.height} px
                    </span>
                  )}
                  {me && !isOwner && <ReportButton targetType="photo" targetId={photo.id} />}
                  {isOwner && (
                    <>
                      <Button variant="secondary" onClick={() => setEditing(true)}>
                        {t("edit")}
                      </Button>
                      <Button variant="danger" busy={remove.isPending} onClick={() => window.confirm(t("delete_confirm")) && remove.mutate()}>
                        {t("delete")}
                      </Button>
                    </>
                  )}
                </div>
              )}
              <Comments photo={photo} />
            </>
          )}
        </aside>
      </div>

      {more.length > 0 && (
        <section aria-labelledby="more" className="mt-10 px-3 sm:px-0">
          <div className="mb-3.5 flex items-center justify-between">
            <h2 id="more" className="text-[21px] font-bold tracking-[-0.02em]">
              {t("more_from", { name: genitive(firstName!, locale) })}
            </h2>
            <Link href={`/u/${photo.user.username}`} className="inline-flex min-h-11 items-center text-[14.5px] font-semibold text-accent-text hover:underline">
              {t("go_profile")}
            </Link>
          </div>
          <JustifiedWall photos={more} target={260} maxRows={1} />
        </section>
      )}
    </article>
  );
}

function EditForm({ photo, busy, onCancel, onSave }: { photo: PhotoDetail; busy: boolean; onCancel: () => void; onSave: (b: Record<string, unknown>) => void }) {
  const t = useTranslations("photo");
  const tu = useTranslations("upload");
  const [title, setTitle] = useState(photo.title ?? "");
  const [description, setDescription] = useState(photo.description ?? "");
  const [tags, setTags] = useState(photo.tags.join(", "));
  const [policy, setPolicy] = useState<CommentPolicy>(photo.comment_policy ?? "everyone");

  return (
    <form
      className="flex flex-col gap-5"
      onSubmit={(e) => {
        e.preventDefault();
        onSave({ title, description, tags: tags.split(",").map((s) => s.trim()).filter(Boolean), comment_policy: policy });
      }}
    >
      <TextField label={tu("title")} name="title" value={title} maxLength={150} onChange={(e) => setTitle(e.target.value)} />
      <TextArea label={tu("description")} name="description" value={description} maxLength={2000} onChange={(e) => setDescription(e.target.value)} />
      <TextField label={tu("tags")} hint={tu("tags_hint")} name="tags" value={tags} onChange={(e) => setTags(e.target.value)} />
      <CommentPolicyField value={policy} onChange={setPolicy} />
      {photo.location && (
        <Button type="button" variant="secondary" className="self-start" onClick={() => onSave({ clear_location: true })}>
          {t("remove_location")}
        </Button>
      )}
      <div className="flex gap-3">
        <Button type="submit" busy={busy}>
          {t("save")}
        </Button>
        <Button type="button" variant="secondary" onClick={onCancel}>
          {t("cancel")}
        </Button>
      </div>
    </form>
  );
}
