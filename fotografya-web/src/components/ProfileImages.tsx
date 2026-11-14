"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Camera } from "lucide-react";
import { useTranslations } from "next-intl";
import { useRef } from "react";
import { ApiError, api, uploadToStorage } from "@/lib/api";
import type { Me } from "@/lib/types";
import { Avatar } from "./Avatar";
import { Notice } from "./ui";

const TYPES = ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"];

async function uploadProfileImage(kind: "avatar" | "cover", file: File) {
  const contentType = file.type || "image/heic";
  const slot = await api<{ upload_url: string; fields: Record<string, string> }>("me/images/upload-url", {
    method: "POST",
    body: { kind, content_type: contentType, size_bytes: file.size },
  });
  await uploadToStorage(slot.upload_url, slot.fields, file, () => undefined);
  return api<Me>("me/images/complete", { method: "POST", body: { kind, key: slot.fields.key } });
}

export function ProfileImages({ me }: { me: Me }) {
  const t = useTranslations("settings");
  const qc = useQueryClient();
  const avatarInput = useRef<HTMLInputElement>(null);
  const coverInput = useRef<HTMLInputElement>(null);

  const done = (data: Me) => {
    qc.setQueryData(["me"], data);
    qc.invalidateQueries({ queryKey: ["profile"] });
  };
  const upload = useMutation({ mutationFn: ({ kind, file }: { kind: "avatar" | "cover"; file: File }) => uploadProfileImage(kind, file), onSuccess: done });
  const remove = useMutation({ mutationFn: (kind: "avatar" | "cover") => api<Me>(`me/images/${kind}`, { method: "DELETE" }), onSuccess: done });

  const pick = (kind: "avatar" | "cover") => (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (file && TYPES.includes(file.type || "image/heic")) upload.mutate({ kind, file });
  };
  const busy = (kind: string) => upload.isPending && upload.variables?.kind === kind;

  return (
    <div className="flex flex-col gap-5">
      <div className="relative">
        <button
          type="button"
          onClick={() => coverInput.current?.click()}
          className="group relative block aspect-[3/1] w-full overflow-hidden bg-surface-2"
          aria-label={t("change_cover")}
        >
          {me.cover_url && (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={me.cover_url} alt="" className="h-full w-full object-cover" />
          )}
          <span className="absolute inset-0 flex items-center justify-center gap-2 bg-black/0 text-sm font-semibold text-white opacity-0 transition group-hover:bg-black/35 group-hover:opacity-100 group-focus-visible:bg-black/35 group-focus-visible:opacity-100">
            <Camera className="h-4 w-4" /> {busy("cover") ? t("uploading") : t("change_cover")}
          </span>
          {!me.cover_url && !busy("cover") && (
            <span className="absolute inset-0 flex items-center justify-center text-sm text-ink-muted group-hover:opacity-0">{t("add_cover")}</span>
          )}
        </button>
        <button
          type="button"
          onClick={() => avatarInput.current?.click()}
          className="absolute -bottom-8 left-5 rounded-full ring-4 ring-bg"
          aria-label={t("change_avatar")}
        >
          <Avatar name={me.display_name} url={me.avatar_url} size={88} className={busy("avatar") ? "opacity-50" : undefined} />
          <span className="absolute bottom-0 right-0 inline-flex h-8 w-8 items-center justify-center rounded-full bg-ink text-surface">
            <Camera className="h-4 w-4" />
          </span>
        </button>
      </div>
      <div className="flex flex-wrap gap-x-5 gap-y-1 pl-[120px] text-sm">
        {me.avatar_url && (
          <button type="button" className="text-ink-muted hover:text-ink" onClick={() => remove.mutate("avatar")}>
            {t("remove_avatar")}
          </button>
        )}
        {me.cover_url && (
          <button type="button" className="text-ink-muted hover:text-ink" onClick={() => remove.mutate("cover")}>
            {t("remove_cover")}
          </button>
        )}
      </div>
      {upload.error && (
        <Notice tone="error">{upload.error instanceof ApiError && upload.error.message ? upload.error.message : t("upload_failed")}</Notice>
      )}
      <p className="text-sm text-ink-muted">{t("images_hint")}</p>
      <input ref={avatarInput} type="file" accept={TYPES.join(",")} className="sr-only" onChange={pick("avatar")} />
      <input ref={coverInput} type="file" accept={TYPES.join(",")} className="sr-only" onChange={pick("cover")} />
    </div>
  );
}

const PUSH_TYPES = ["new_follower", "photo_liked", "photo_published", "photo_rejected", "contest_new", "contest_deadline", "contest_results"] as const;

export function NotificationSettingsForm() {
  const t = useTranslations("settings");
  const qc = useQueryClient();
  const key = ["notification-settings"];
  const { data } = useQuery({ queryKey: key, queryFn: () => api<{ push: Record<string, boolean> }>("me/notification-settings") });
  const save = useMutation({
    mutationFn: (push: Record<string, boolean>) => api<{ push: Record<string, boolean> }>("me/notification-settings", { method: "PATCH", body: { push } }),
    onMutate: (push) => qc.setQueryData(key, { push: { ...data?.push, ...push } }),
    onSuccess: (res) => qc.setQueryData(key, res),
  });
  if (!data) return null;
  return (
    <ul className="divide-y divide-line overflow-hidden rounded-card bg-surface">
      {PUSH_TYPES.map((type) => (
        <li key={type} className="flex items-center justify-between gap-6 py-3">
          <span className="text-[15px]">{t(`push.${type}`)}</span>
          <label className="relative inline-flex shrink-0 cursor-pointer">
            <input
              type="checkbox"
              className="peer sr-only"
              checked={!!data.push[type]}
              onChange={(e) => save.mutate({ [type]: e.target.checked })}
              aria-label={t(`push.${type}`)}
            />
            <span className="h-7 w-12 rounded-full bg-line transition-colors peer-checked:bg-accent peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-accent" />
            <span className="absolute left-1 top-1 h-5 w-5 rounded-full bg-surface transition-transform peer-checked:translate-x-5" />
          </label>
        </li>
      ))}
    </ul>
  );
}

