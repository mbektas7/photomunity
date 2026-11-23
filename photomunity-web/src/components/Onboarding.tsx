"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import clsx from "clsx";
import { Check, ChevronRight, X } from "lucide-react";
import { useTranslations } from "next-intl";
import { useEffect, useRef } from "react";
import { Link } from "@/i18n/navigation";
import { api } from "@/lib/api";
import type { Me } from "@/lib/types";

export const ONBOARDING_STEPS = ["avatar", "about", "gear", "photo"] as const;
export type OnboardingStep = (typeof ONBOARDING_STEPS)[number];

/** Hangi adımların tamamlandığı yalnızca profil verisinden çıkarılır. */
export function onboardingProgress(me: Me): Record<OnboardingStep, boolean> {
  return {
    avatar: !!me.avatar_url,
    about: !!me.bio?.trim() || me.specialties.length > 0,
    gear: me.equipment.length > 0,
    photo: me.has_photos,
  };
}

/** Tanıtımı bitirir ya da kapatır (PATCH /me {onboarding_done: true}). */
export function useFinishOnboarding() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: () => api<Me>("me", { method: "PATCH", body: { onboarding_done: true } }),
    onSuccess: (data) => qc.setQueryData(["me"], data),
  });
}

/** Eksik adımın gideceği yer: ilk üçü tanıtım sayfasındaki adım, sonuncusu yükleme sayfası. */
function stepHref(step: OnboardingStep) {
  return step === "photo" ? "/upload" : `/welcome?step=${ONBOARDING_STEPS.indexOf(step) + 1}`;
}

/**
 * Ana sayfadaki "Profilini tamamla" kartı. Yalnızca tanıtımı bitmemiş (yeni) hesaplarda görünür.
 * Dört adım da tamamlanınca tanıtım kendiliğinden bitmiş sayılır; X kartı kalıcı olarak kapatır.
 */
export function ProfileCompleteCard({ me }: { me: Me }) {
  const t = useTranslations("onboarding");
  const qc = useQueryClient();
  const finish = useFinishOnboarding();
  const progress = onboardingProgress(me);
  const done = ONBOARDING_STEPS.filter((s) => progress[s]).length;
  const autoFinished = useRef(false);

  // Fotoğraf yükleme gibi başka sayfalardaki değişiklikler için profil bir kez tazelenir
  useEffect(() => {
    qc.invalidateQueries({ queryKey: ["me"] });
  }, [qc]);

  useEffect(() => {
    if (done === ONBOARDING_STEPS.length && !autoFinished.current) {
      autoFinished.current = true;
      finish.mutate();
    }
  }, [done, finish]);

  if (me.onboarding_done || done === ONBOARDING_STEPS.length) return null;

  return (
    <section aria-labelledby="profile-complete" className="rounded-card bg-surface p-4 sm:p-5">
      <div className="flex items-start gap-3">
        <div className="min-w-0 flex-1">
          <h2 id="profile-complete" className="text-[17px] font-bold tracking-[-0.01em]">
            {t("card_title")}
          </h2>
          <p className="tnum mt-0.5 text-[13px] text-ink-muted">{t("card_progress", { done, total: ONBOARDING_STEPS.length })}</p>
        </div>
        <button
          type="button"
          onClick={() => finish.mutate()}
          disabled={finish.isPending}
          aria-label={t("card_close")}
          className="-mr-1.5 -mt-1.5 inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-full text-ink-muted hover:bg-surface-2 hover:text-ink"
        >
          <X className="h-[18px] w-[18px]" strokeWidth={2} />
        </button>
      </div>
      <div
        role="progressbar"
        aria-valuemin={0}
        aria-valuemax={ONBOARDING_STEPS.length}
        aria-valuenow={done}
        aria-label={t("card_title")}
        className="mb-1.5 mt-3 h-1.5 overflow-hidden rounded-pill bg-surface-2"
      >
        <div className="h-full rounded-pill bg-accent transition-[width]" style={{ width: `${(done / ONBOARDING_STEPS.length) * 100}%` }} />
      </div>
      <ul>
        {ONBOARDING_STEPS.map((step) => {
          const ok = progress[step];
          const icon = (
            <span
              className={clsx(
                "flex h-6 w-6 shrink-0 items-center justify-center rounded-full",
                ok ? "bg-accent text-accent-ink" : "border-2 border-line",
              )}
              aria-hidden
            >
              {ok && <Check className="h-3.5 w-3.5" strokeWidth={2.6} />}
            </span>
          );
          return (
            <li key={step}>
              {ok ? (
                <span className="flex min-h-11 items-center gap-2.5 py-1">
                  {icon}
                  <span className="flex-1 text-[14.5px] text-ink-muted line-through">{t(`card_step_${step}`)}</span>
                  <span className="sr-only">{t("card_done")}</span>
                </span>
              ) : (
                <Link href={stepHref(step)} className="group flex min-h-11 items-center gap-2.5 rounded-box py-1">
                  {icon}
                  <span className="flex-1 text-[14.5px] font-semibold group-hover:underline">{t(`card_step_${step}`)}</span>
                  <ChevronRight className="h-[18px] w-[18px] text-ink-muted" aria-hidden />
                </Link>
              )}
            </li>
          );
        })}
      </ul>
    </section>
  );
}
