"use client";

import clsx from "clsx";
import { ImagePlus, LocateFixed, X } from "lucide-react";
import { useTranslations } from "next-intl";
import { useEffect, useRef, useState } from "react";
import { CommentPolicyField } from "@/components/Comments";
import { CritiqueFields } from "@/components/critique";
import { LicenseFields } from "@/components/license";
import { Button, Notice, TextArea, TextField } from "@/components/ui";
import { useRouter } from "@/i18n/navigation";
import { ApiError, api, uploadToStorage } from "@/lib/api";
import { useMe } from "@/lib/hooks";
import type { CommentPolicy, License, Location } from "@/lib/types";
import { HowItWorks } from "@/components/intro";

// Backend varsayılanlarıyla aynı; sunucu yine de kesin kontrolü yapar.
const MIN_BYTES = 0;
const MAX_BYTES = 40_000_000;
const MIN_EDGE = 1080;
const TYPES: Record<string, string> = {
  "image/jpeg": "JPEG", "image/png": "PNG", "image/webp": "WebP", "image/heic": "HEIC", "image/heif": "HEIF",
};

async function precheck(file: File): Promise<string[]> {
  const codes: string[] = [];
  const type = file.type.toLowerCase() || (file.name.toLowerCase().endsWith(".heic") ? "image/heic" : "");
  if (!TYPES[type]) return ["unsupported_format"];
  if (file.size < MIN_BYTES) codes.push("file_too_small");
  if (file.size > MAX_BYTES) codes.push("file_too_large");
  if (!type.includes("hei")) {
    try {
      const bmp = await createImageBitmap(file);
      if (Math.max(bmp.width, bmp.height) < MIN_EDGE) codes.push("resolution_too_low");
      bmp.close();
    } catch {
      codes.push("corrupt_image");
    }
  }
  return codes;
}

export default function UploadPage() {
  const t = useTranslations("upload");
  const tq = useTranslations("quality");
  const router = useRouter();
  const { data: me, isLoading } = useMe();
  const input = useRef<HTMLInputElement>(null);

  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [issues, setIssues] = useState<string[]>([]);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [tags, setTags] = useState("");
  const [location, setLocation] = useState<Location | null>(null);
  const [commentPolicy, setCommentPolicy] = useState<CommentPolicy>("everyone");
  const [critique, setCritique] = useState({ requested: false, question: "" });
  // Kullanım hakları: kullanıcının varsayılanlarıyla başlar (Ayarlar → Kullanım hakları)
  const [rights, setRights] = useState<{ license: License; downloadsDisabled: boolean } | null>(null);
  const effectiveRights = rights ?? { license: me?.default_license ?? "all_rights", downloadsDisabled: !!me?.default_downloads_disabled };
  const [locating, setLocating] = useState(false);
  const [progress, setProgress] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [dragging, setDragging] = useState(false);

  useEffect(() => {
    if (!isLoading && !me) router.replace("/login");
  }, [me, isLoading, router]);

  useEffect(() => () => void (preview && URL.revokeObjectURL(preview)), [preview]);

  async function choose(f: File | undefined) {
    if (!f) return;
    setError(null);
    setFile(f);
    setPreview(f.type.includes("hei") ? null : URL.createObjectURL(f));
    setIssues(await precheck(f));
  }

  function locate() {
    if (!navigator.geolocation) return;
    setLocating(true);
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setLocation({ latitude: +pos.coords.latitude.toFixed(5), longitude: +pos.coords.longitude.toFixed(5), name: location?.name ?? "" });
        setLocating(false);
      },
      () => setLocating(false),
      { enableHighAccuracy: true, timeout: 10_000 },
    );
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!file || issues.length) return;
    setError(null);
    setProgress(0);
    try {
      const contentType = file.type || "image/heic";
      const slot = await api<{ photo_id: string; upload_url: string; fields: Record<string, string> }>("photos/upload-url", {
        method: "POST",
        body: { content_type: contentType, size_bytes: file.size },
      });
      await uploadToStorage(slot.upload_url, slot.fields, file, setProgress);
      await api(`photos/${slot.photo_id}/complete`, {
        method: "POST",
        body: {
          title: title || null,
          description: description || null,
          tags: tags.split(",").map((s) => s.trim()).filter(Boolean),
          location: location ? { ...location, name: location.name || null } : null,
          comment_policy: commentPolicy,
          critique_requested: critique.requested,
          critique_question: critique.requested ? critique.question.trim() || null : null,
          license: effectiveRights.license,
          downloads_disabled: effectiveRights.downloadsDisabled,
        },
      });
      router.push(`/p/${slot.photo_id}`);
    } catch (err) {
      setProgress(null);
      setError(err instanceof ApiError ? err.message : t("upload_failed"));
    }
  }

  const uploading = progress !== null;

  return (
    <div className="mx-auto max-w-[1100px] px-4 pt-8 sm:px-6 sm:pt-12">
      <h1 className="flex items-center gap-3 text-[clamp(2rem,4.5vw,3rem)] font-bold leading-none tracking-[-0.04em]">{t("heading")} <HowItWorks module="upload" /></h1>
      <p className="mt-3 max-w-[60ch] text-ink-muted">{t("requirements")}</p>

      <form onSubmit={submit} className="mt-8 grid gap-8 lg:grid-cols-[minmax(0,1fr)_380px]">
        <div>
          {!file ? (
            <button
              type="button"
              onClick={() => input.current?.click()}
              onDragOver={(e) => (e.preventDefault(), setDragging(true))}
              onDragLeave={() => setDragging(false)}
              onDrop={(e) => {
                e.preventDefault();
                setDragging(false);
                choose(e.dataTransfer.files[0]);
              }}
              className={clsx(
                "flex aspect-[3/2] w-full flex-col items-center justify-center gap-3 border-2 border-dashed bg-surface text-center transition-colors",
                dragging ? "border-accent" : "border-line hover:border-ink",
              )}
            >
              <ImagePlus className="h-8 w-8" strokeWidth={1.6} />
              <span className="text-lg font-semibold">{t("choose")}</span>
              <span className="text-sm text-ink-muted">{t("drop")}</span>
            </button>
          ) : (
            <div className="rounded-card bg-surface p-3 sm:p-5">
              <div className="relative flex justify-center bg-bg">
                {preview ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={preview} alt="" className="max-h-[62vh] w-auto max-w-full object-contain" />
                ) : (
                  <p className="px-6 py-24 text-ink-muted">{t("no_preview")}</p>
                )}
                {!uploading && (
                  <button
                    type="button"
                    onClick={() => (setFile(null), setPreview(null), setIssues([]))}
                    className="absolute right-3 top-3 inline-flex h-9 w-9 items-center justify-center rounded-full bg-black/60 text-white"
                    aria-label={t("remove")}
                  >
                    <X className="h-4 w-4" />
                  </button>
                )}
              </div>
              <p className="tnum mt-3 truncate text-sm text-ink-muted">
                {file.name}   {(file.size / 1_000_000).toFixed(1)} MB
              </p>
            </div>
          )}
          <input
            ref={input}
            type="file"
            accept="image/jpeg,image/png,image/webp,image/heic,image/heif,.heic"
            className="sr-only"
            onChange={(e) => choose(e.target.files?.[0])}
          />

          {issues.length > 0 && (
            <div className="mt-4">
              <Notice tone="error">
                <ul className="flex flex-col gap-1">
                  {issues.map((c) => (
                    <li key={c}>{tq(c, { min_mb: MIN_BYTES / 1e6, max_mb: MAX_BYTES / 1e6, min_px: MIN_EDGE })}</li>
                  ))}
                </ul>
              </Notice>
            </div>
          )}
        </div>

        <div className="flex flex-col gap-5">
          <TextField label={t("title")} name="title" value={title} maxLength={150} onChange={(e) => setTitle(e.target.value)} />
          <TextArea label={t("description")} name="description" value={description} maxLength={2000} onChange={(e) => setDescription(e.target.value)} />
          <TextField label={t("tags")} name="tags" hint={t("tags_hint")} value={tags} onChange={(e) => setTags(e.target.value)} />

          <fieldset className="flex flex-col gap-3 border-t border-line pt-5">
            <legend className="sr-only">{t("location")}</legend>
            <div className="flex items-center justify-between gap-3">
              <span className="text-sm font-medium">{t("location")}</span>
              {location ? (
                <button type="button" onClick={() => setLocation(null)} className="text-sm font-medium text-ink-muted hover:text-ink">
                  {t("remove_location")}
                </button>
              ) : (
                <button type="button" onClick={locate} disabled={locating} className="inline-flex items-center gap-1.5 text-sm font-semibold">
                  <LocateFixed className="h-4 w-4" />
                  {locating ? t("locating") : t("use_my_location")}
                </button>
              )}
            </div>
            {location ? (
              <>
                <p className="tnum text-sm text-ink-muted">
                  {location.latitude}, {location.longitude}
                </p>
                <TextField
                  label={t("place_name")}
                  name="place"
                  placeholder={t("place_placeholder")}
                  value={location.name ?? ""}
                  onChange={(e) => setLocation({ ...location, name: e.target.value })}
                />
              </>
            ) : (
              <p className="text-sm text-ink-muted">{t("location_hint")}</p>
            )}
          </fieldset>

          <div className="border-t border-line pt-5">
            <CommentPolicyField value={commentPolicy} onChange={setCommentPolicy} />
          </div>

          <div className="border-t border-line pt-5">
            <CritiqueFields requested={critique.requested} question={critique.question} onChange={setCritique} />
          </div>

          <details className="border-t border-line pt-5">
            <summary className="cursor-pointer text-sm font-medium">
              {t("rights")}
            </summary>
            <div className="mt-4">
              <LicenseFields license={effectiveRights.license} downloadsDisabled={effectiveRights.downloadsDisabled} onChange={setRights} name="upload-license" />
            </div>
          </details>

          {error && <Notice tone="error">{error}</Notice>}

          {uploading && (
            <div aria-live="polite">
              <div className="h-1 bg-line">
                <div className="h-full bg-accent transition-[width]" style={{ width: `${Math.round((progress ?? 0) * 100)}%` }} />
              </div>
              <p className="tnum mt-2 text-sm text-ink-muted">{t("uploading", { pct: Math.round((progress ?? 0) * 100) })}</p>
            </div>
          )}

          <Button type="submit" className="h-12 text-base" disabled={!file || issues.length > 0} busy={uploading}>
            {t("publish")}
          </Button>
          <p className="text-sm text-ink-muted">{t("quality_note")}</p>
        </div>
      </form>
    </div>
  );
}
