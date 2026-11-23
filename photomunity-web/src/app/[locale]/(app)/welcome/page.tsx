"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import clsx from "clsx";
import { Camera, Check, ImagePlus, Plus, Trash2 } from "lucide-react";
import { useTranslations } from "next-intl";
import { useSearchParams } from "next/navigation";
import { Suspense, useEffect, useRef, useState } from "react";
import { Avatar } from "@/components/Avatar";
import { ONBOARDING_STEPS, useFinishOnboarding } from "@/components/Onboarding";
import { PROFILE_IMAGE_TYPES, uploadProfileImage } from "@/components/ProfileImages";
import { Button, Notice, TextArea, TextField } from "@/components/ui";
import { useRouter } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import { SPECIALTIES } from "@/lib/format";
import { useMe } from "@/lib/hooks";
import type { Equipment, EquipmentType, Me } from "@/lib/types";

const EQUIPMENT_TYPES: EquipmentType[] = ["body", "lens", "tripod", "filter", "flash", "drone", "other"];

export default function WelcomePage() {
  return (
    <Suspense>
      <Welcome />
    </Suspense>
  );
}

function safeNext(v: string | null) {
  return v && v.startsWith("/") && !v.startsWith("//") ? v : "/feed";
}

/**
 * Kayıt sonrası tanıtım: profil fotoğrafı, hakkında, ekipman, ilk fotoğraf.
 * Her adım atlanabilir; son adımı bitirmek ya da atlamak tanıtımı kapatır (PATCH /me {onboarding_done: true}).
 */
function Welcome() {
  const t = useTranslations("onboarding");
  const router = useRouter();
  const params = useSearchParams();
  const next = safeNext(params.get("next"));
  const { data: me, isLoading } = useMe();
  const finish = useFinishOnboarding();
  const initial = Math.min(Math.max(Number(params.get("step")) || 1, 1), ONBOARDING_STEPS.length);
  const [step, setStep] = useState(initial);

  useEffect(() => {
    if (!isLoading && !me) router.replace("/login");
  }, [me, isLoading, router]);
  useEffect(() => {
    window.scrollTo({ top: 0 });
  }, [step]);

  if (!me) return <div className="h-[60vh]" aria-busy />;

  const last = step === ONBOARDING_STEPS.length;
  const done = (to = next) => finish.mutate(undefined, { onSettled: () => router.push(to) });
  const advance = () => (last ? done() : setStep((s) => s + 1));

  return (
    <div className="mx-auto max-w-[560px] px-4 pt-6 sm:px-6 sm:pt-12">
      <div className="flex gap-1.5" role="progressbar" aria-valuemin={1} aria-valuemax={ONBOARDING_STEPS.length} aria-valuenow={step} aria-label={t("step", { n: step, total: ONBOARDING_STEPS.length })}>
        {ONBOARDING_STEPS.map((s, i) => (
          <span key={s} className={clsx("h-1.5 flex-1 rounded-pill transition-colors", i < step ? "bg-accent" : "bg-line")} />
        ))}
      </div>
      <div className="mt-3 flex items-center justify-between">
        <span className="tnum text-[13.5px] font-semibold text-ink-muted">{t("step", { n: step, total: ONBOARDING_STEPS.length })}</span>
        <button
          type="button"
          onClick={advance}
          disabled={finish.isPending}
          className="inline-flex min-h-11 items-center rounded-pill px-3 text-[14.5px] font-semibold text-ink-muted hover:bg-surface hover:text-ink"
        >
          {last ? t("finish") : t("skip")}
        </button>
      </div>

      <div className="mt-4 rounded-card bg-surface p-5 sm:p-7">
        {step === 1 && <AvatarStep me={me} onNext={advance} />}
        {step === 2 && <AboutStep me={me} onNext={advance} />}
        {step === 3 && <GearStep me={me} onNext={advance} />}
        {step === 4 && <PhotoStep me={me} busy={finish.isPending} onUpload={() => done("/upload")} onFinish={() => done()} />}
      </div>
    </div>
  );
}

function StepHead({ title, body }: { title: string; body: string }) {
  return (
    <div className="mb-6">
      <h1 className="text-[clamp(1.6rem,4vw,2rem)] font-bold leading-[1.1] tracking-[-0.035em]">{title}</h1>
      <p className="mt-2 text-[15px] leading-[1.5] text-ink-muted">{body}</p>
    </div>
  );
}

function errorText(e: unknown, fallback: string) {
  return e instanceof ApiError && e.message ? e.message : fallback;
}

function AvatarStep({ me, onNext }: { me: Me; onNext: () => void }) {
  const t = useTranslations("onboarding");
  const qc = useQueryClient();
  const input = useRef<HTMLInputElement>(null);
  const upload = useMutation({
    mutationFn: (file: File) => uploadProfileImage("avatar", file),
    onSuccess: (data) => {
      qc.setQueryData(["me"], data);
      qc.invalidateQueries({ queryKey: ["profile"] });
    },
  });

  return (
    <>
      <StepHead title={t("avatar_title")} body={t("avatar_body")} />
      <div className="flex flex-col items-center gap-4 py-2">
        <button
          type="button"
          onClick={() => input.current?.click()}
          disabled={upload.isPending}
          aria-label={me.avatar_url ? t("avatar_change") : t("avatar_pick")}
          className="relative rounded-full"
        >
          {me.avatar_url ? (
            <Avatar name={me.display_name} url={me.avatar_url} size={132} className={upload.isPending ? "opacity-50" : undefined} />
          ) : (
            <span className={clsx("flex h-[132px] w-[132px] items-center justify-center rounded-full border-2 border-dashed border-line bg-surface-2 text-ink-muted", upload.isPending && "opacity-50")}>
              <Camera className="h-9 w-9" strokeWidth={1.6} aria-hidden />
            </span>
          )}
          <span className="absolute bottom-1 right-1 inline-flex h-10 w-10 items-center justify-center rounded-full bg-accent text-accent-ink ring-4 ring-surface">
            <Plus className="h-5 w-5" strokeWidth={2.2} aria-hidden />
          </span>
        </button>
        <p className="max-w-[40ch] text-center text-[13.5px] text-ink-muted" aria-live="polite">
          {upload.isPending ? t("uploading") : t("avatar_hint")}
        </p>
        {upload.error && <Notice tone="error">{errorText(upload.error, t("upload_failed"))}</Notice>}
      </div>
      <div className="mt-6 flex flex-col gap-2.5">
        {me.avatar_url ? (
          <>
            <Button variant="large" onClick={onNext} disabled={upload.isPending}>
              {t("continue")}
            </Button>
            <Button variant="ghost" onClick={() => input.current?.click()} busy={upload.isPending}>
              {t("avatar_change")}
            </Button>
          </>
        ) : (
          <Button variant="large" onClick={() => input.current?.click()} busy={upload.isPending}>
            {t("avatar_pick")}
          </Button>
        )}
      </div>
      <input
        ref={input}
        type="file"
        accept={PROFILE_IMAGE_TYPES.join(",")}
        className="sr-only"
        tabIndex={-1}
        aria-hidden
        onChange={(e) => {
          const file = e.target.files?.[0];
          e.target.value = "";
          if (file && PROFILE_IMAGE_TYPES.includes(file.type || "image/heic")) upload.mutate(file);
        }}
      />
    </>
  );
}

function AboutStep({ me, onNext }: { me: Me; onNext: () => void }) {
  const t = useTranslations("onboarding");
  const ts = useTranslations("specialties");
  const qc = useQueryClient();
  const [bio, setBio] = useState(me.bio ?? "");
  const [city, setCity] = useState(me.city ?? "");
  const [specialties, setSpecialties] = useState(me.specialties);

  const save = useMutation({
    mutationFn: () => api<Me>("me", { method: "PATCH", body: { bio: bio.trim() || null, city: city.trim() || null, specialties } }),
    onSuccess: (data) => {
      qc.setQueryData(["me"], data);
      qc.invalidateQueries({ queryKey: ["profile"] });
      onNext();
    },
  });

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        save.mutate();
      }}
    >
      <StepHead title={t("about_title")} body={t("about_body")} />
      <div className="flex flex-col gap-5">
        <div>
          <TextArea label={t("bio")} name="bio" maxLength={500} placeholder={t("bio_placeholder")} value={bio} onChange={(e) => setBio(e.target.value)} />
          <p className="tnum mt-1 text-right text-[12px] text-ink-muted">{bio.length}/500</p>
        </div>
        <fieldset>
          <legend className="text-sm font-medium">{t("specialties")}</legend>
          <div className="mt-2.5 flex flex-wrap gap-2">
            {SPECIALTIES.map((s) => {
              const on = specialties.includes(s);
              return (
                <button
                  key={s}
                  type="button"
                  aria-pressed={on}
                  onClick={() => setSpecialties((list) => (on ? list.filter((x) => x !== s) : [...list, s].slice(0, 10)))}
                  className={clsx("rounded-full border px-3.5 py-1.5 text-sm transition-colors", on ? "border-ink bg-ink text-surface" : "border-line hover:border-ink")}
                >
                  {ts(s)}
                </button>
              );
            })}
          </div>
        </fieldset>
        <TextField label={t("city")} name="city" maxLength={120} autoComplete="address-level2" value={city} onChange={(e) => setCity(e.target.value)} />
        {save.error && <Notice tone="error">{errorText(save.error, t("error"))}</Notice>}
        <Button type="submit" variant="large" busy={save.isPending}>
          {t("continue")}
        </Button>
      </div>
    </form>
  );
}

type GearRow = Pick<Equipment, "type" | "brand" | "model">;

function GearStep({ me, onNext }: { me: Me; onNext: () => void }) {
  const t = useTranslations("onboarding");
  const ts = useTranslations("settings");
  const te = useTranslations("equipment");
  const qc = useQueryClient();
  const [items, setItems] = useState<GearRow[]>(
    me.equipment.length ? me.equipment.map(({ type, brand, model }) => ({ type, brand, model })) : [{ type: "body", brand: "", model: "" }],
  );
  const update = (i: number, patch: Partial<GearRow>) => setItems((list) => list.map((it, j) => (j === i ? { ...it, ...patch } : it)));
  const filled = items.filter((i) => i.brand.trim() && i.model.trim());

  const save = useMutation({
    mutationFn: () => api<Equipment[]>("me/equipment", { method: "PUT", body: filled.map((i) => ({ ...i, brand: i.brand.trim(), model: i.model.trim() })) }),
    onSuccess: (equipment) => {
      qc.setQueryData<Me | null>(["me"], (old) => (old ? { ...old, equipment } : old));
      qc.invalidateQueries({ queryKey: ["me"] });
      qc.invalidateQueries({ queryKey: ["profile"] });
      onNext();
    },
  });

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        // Hiçbir şey girilmediyse ve kayıtlı ekipman da yoksa istek atmadan geç
        if (!filled.length && !me.equipment.length) onNext();
        else save.mutate();
      }}
    >
      <StepHead title={t("gear_title")} body={t("gear_body")} />
      <div className="flex flex-col gap-3">
        {items.map((it, i) => (
          <div key={i} className="grid grid-cols-[110px_1fr_auto] gap-2 sm:grid-cols-[120px_1fr_1.3fr_auto]">
            <select
              aria-label={ts("equipment_type")}
              value={it.type}
              onChange={(e) => update(i, { type: e.target.value as EquipmentType })}
              className="h-11 rounded-box border border-ring-idle bg-surface px-2.5 text-[15px]"
            >
              {EQUIPMENT_TYPES.map((type) => (
                <option key={type} value={type}>
                  {te(type)}
                </option>
              ))}
            </select>
            <input
              aria-label={ts("brand")}
              placeholder={ts("brand")}
              value={it.brand}
              maxLength={80}
              onChange={(e) => update(i, { brand: e.target.value })}
              className="h-11 min-w-0 rounded-box border border-ring-idle bg-surface px-3 text-[15px] outline-none focus:border-accent"
            />
            <input
              aria-label={ts("model")}
              placeholder={ts("model")}
              value={it.model}
              maxLength={120}
              onChange={(e) => update(i, { model: e.target.value })}
              className="col-span-2 row-start-2 h-11 min-w-0 rounded-box border border-ring-idle bg-surface px-3 text-[15px] outline-none focus:border-accent sm:col-span-1 sm:row-start-auto"
            />
            <button
              type="button"
              onClick={() => setItems((list) => list.filter((_, j) => j !== i))}
              aria-label={ts("remove")}
              className="col-start-3 row-start-1 inline-flex h-11 w-11 items-center justify-center rounded-full text-ink-muted hover:bg-surface-2 hover:text-ink sm:col-start-auto sm:row-start-auto"
            >
              <Trash2 className="h-4 w-4" />
            </button>
          </div>
        ))}
        <Button
          type="button"
          variant="secondary"
          className="self-start"
          onClick={() => setItems((l) => [...l, { type: l.some((x) => x.type === "body") ? "lens" : "body", brand: "", model: "" }])}
        >
          <Plus className="h-4 w-4" /> {t("gear_add")}
        </Button>
        {save.error && <Notice tone="error">{errorText(save.error, t("error"))}</Notice>}
        <Button type="submit" variant="large" busy={save.isPending} className="mt-3">
          {t("continue")}
        </Button>
      </div>
    </form>
  );
}

function PhotoStep({ me, busy, onUpload, onFinish }: { me: Me; busy: boolean; onUpload: () => void; onFinish: () => void }) {
  const t = useTranslations("onboarding");
  const tu = useTranslations("upload");
  return (
    <>
      <StepHead title={t("photo_title")} body={t("photo_body")} />
      {me.has_photos ? (
        <p className="flex items-center gap-2.5 rounded-box bg-accent-tint px-4 py-3 text-[15px] font-semibold text-accent-text">
          <Check className="h-5 w-5 shrink-0" strokeWidth={2.4} aria-hidden /> {t("photo_done")}
        </p>
      ) : (
        <button
          type="button"
          onClick={onUpload}
          disabled={busy}
          className="flex w-full flex-col items-center gap-2 rounded-card border-2 border-dashed border-line px-6 py-10 text-center hover:border-ink"
        >
          <ImagePlus className="h-8 w-8 text-ink-muted" strokeWidth={1.6} aria-hidden />
          <span className="text-[16px] font-semibold">{tu("choose")}</span>
          <span className="max-w-[40ch] text-[13.5px] text-ink-muted">{t("photo_hint")}</span>
          <span className="max-w-[40ch] text-[13.5px] text-ink-muted">{tu("requirements")}</span>
        </button>
      )}
      <div className="mt-6">
        {me.has_photos ? (
          <Button variant="large" busy={busy} onClick={onFinish}>
            {t("finish")}
          </Button>
        ) : (
          <Button variant="large" busy={busy} onClick={onUpload}>
            {t("photo_go")}
          </Button>
        )}
      </div>
    </>
  );
}
