"use client";

import clsx from "clsx";
import {
  Aperture, Award, BadgeCheck, Bell, Calculator, CalendarDays, CalendarPlus, Camera, CircleHelp, Clock, Cloud, CloudSun,
  Compass, Crop, EyeOff, FileText, Flag, FolderOpen, Gavel, Heart, Image as ImageIcon, Inbox, Keyboard, ListOrdered,
  type LucideIcon, Map as MapIcon, MapPin, MessageSquareText, Moon, MoonStar, Newspaper, Plus,
  Send, Share2, SlidersHorizontal, Sparkles, Star, Sunrise, Tag, ThumbsUp, Trophy, Upload, UserPlus, Users, Vote,
} from "lucide-react";
import { useTranslations } from "next-intl";
import { usePathname } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { useMe } from "@/lib/hooks";
import { Button } from "./ui";

/**
 * Modül tanıtımları: her modül için 2–4 adım; her adımın bir ikonu var.
 * Metinler messages içinde `intro.<modül>.title` ve `intro.<modül>.s<n>_t / s<n>_b` anahtarlarında.
 */
export const INTROS = {
  feed: [ImageIcon, Heart, Plus],
  explore: [Compass, MessageSquareText, Sparkles],
  map: [MapIcon, MapPin, EyeOff],
  communities: [UserPlus, Newspaper, CalendarDays, Trophy],
  contests: [Upload, Gavel, Trophy, EyeOff],
  themes: [Sparkles, Send, Heart, Award],
  critique: [MessageSquareText, ListOrdered, ThumbsUp],
  collections: [FolderOpen, SlidersHorizontal, Share2],
  events: [UserPlus, Users, MoonStar],
  sky: [Star, CloudSun, Compass],
  moon: [Moon, CalendarDays],
  sunplanner: [Sunrise, MapPin, CalendarPlus],
  nightcalc: [Calculator, Aperture],
  nightplanner: [Clock, Compass, Star],
  plans: [CalendarPlus, Bell, Cloud, Users],
  dark: [MapIcon, SlidersHorizontal, CalendarPlus],
  messages: [Inbox, Send],
  gear: [Camera, SlidersHorizontal, Tag],
  upload: [Crop, FileText, MapPin, MessageSquareText],
  profile: [FolderOpen, Award, Share2],
  jury: [Star, Keyboard, Flag],
  voting: [Vote, Keyboard, BadgeCheck],
} as const satisfies Record<string, readonly LucideIcon[]>;

export type IntroModule = keyof typeof INTROS;

// Adım illüstrasyonlarının renkleri: uygulama vurgusu ve gece gökyüzü tonları
const TONES = [
  "bg-accent-tint text-accent-text",
  "bg-[linear-gradient(160deg,#1a2050,#0d1130)] text-white",
  "bg-surface-2 text-ink",
  "bg-accent text-accent-ink",
];

const storageKey = (m: IntroModule) => `intro.seen.${m}`;
/** Saklama kapalıysa bu oturumda tekrar gösterilmesin diye */
const seenThisSession = new Set<IntroModule>();
/** Aynı anda tek tanıtım açılsın */
let activeIntro: IntroModule | null = null;

function isSeen(m: IntroModule) {
  if (seenThisSession.has(m)) return true;
  try {
    return window.localStorage.getItem(storageKey(m)) === "1";
  } catch {
    return false;
  }
}

function markSeen(m: IntroModule) {
  seenThisSession.add(m);
  try {
    window.localStorage.setItem(storageKey(m), "1");
  } catch { /* saklama kapalı olabilir */ }
}

/**
 * "Nasıl çalışır" düğmesi + tanıtım penceresi. Modül ilk kez açıldığında kendiliğinden açılır
 * (giriş yapmış kullanıcıya; `publicOk` ile oturumsuz ziyaretçiye de). /welcome sırasında açılmaz.
 */
export function HowItWorks({ module, auto = true, publicOk = false, tone = "default", className }: {
  module: IntroModule;
  auto?: boolean;
  publicOk?: boolean;
  /** "dark": koyu zemin üstünde */
  tone?: "default" | "dark";
  className?: string;
}) {
  const t = useTranslations("intro");
  const { data: me, isLoading } = useMe();
  const pathname = usePathname();
  const [open, setOpen] = useState(false);

  useEffect(() => {
    if (!auto || isLoading || (!me && !publicOk) || pathname.includes("/welcome")) return;
    // Hesap tanıtımı (onboarding) bitmeden modül tanıtımları kendiliğinden açılmaz
    if (me && me.onboarding_done === false) return;
    if (isSeen(module)) return;
    const id = window.setTimeout(() => {
      if (activeIntro || isSeen(module)) return;
      setOpen(true);
    }, 450);
    return () => window.clearTimeout(id);
  }, [auto, isLoading, me, publicOk, pathname, module]);

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-label={t("how")}
        title={t("how")}
        className={clsx(
          "inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-full align-middle transition-colors",
          tone === "dark" ? "bg-white/10 text-white hover:bg-white/20" : "bg-surface-2 text-ink-muted hover:bg-line hover:text-ink",
          className,
        )}
      >
        <CircleHelp className="h-[18px] w-[18px]" strokeWidth={1.9} aria-hidden />
      </button>
      {/* Başlıkların (h1) içinde durduğu için pencere body'ye taşınır: yazı stilini ve anlamı miras almasın */}
      {open && createPortal(<IntroDialog module={module} onClose={() => setOpen(false)} />, document.body)}
    </>
  );
}

function IntroDialog({ module, onClose }: { module: IntroModule; onClose: () => void }) {
  const t = useTranslations("intro");
  const dialog = useRef<HTMLDialogElement>(null);
  const [step, setStep] = useState(0);
  const icons = INTROS[module];
  const last = step === icons.length - 1;
  const Icon = icons[step]!;

  useEffect(() => {
    activeIntro = module;
    const d = dialog.current;
    if (d && !d.open) d.showModal();
    return () => {
      if (activeIntro === module) activeIntro = null;
    };
  }, [module]);

  const close = () => dialog.current?.close();

  return (
    <dialog
      ref={dialog}
      aria-labelledby={`intro-${module}-title`}
      className="m-auto w-[min(420px,calc(100vw-2rem))] rounded-sheet bg-surface p-0 text-left text-[15px] font-normal normal-case leading-normal tracking-normal text-ink shadow-float backdrop:bg-black/55"
      onClose={() => {
        markSeen(module);
        onClose();
      }}
      onKeyDown={(e) => {
        if (e.key === "ArrowRight" && !last) setStep(step + 1);
        if (e.key === "ArrowLeft" && step > 0) setStep(step - 1);
      }}
    >
      <div className="flex flex-col px-6 pb-6 pt-5">
        <p id={`intro-${module}-title`} className="text-xs font-bold uppercase tracking-[0.08em] text-ink-muted">
          {t("how")} · {t(`${module}.title`)}
        </p>
        <div key={step} className="fade-in mt-5 flex flex-col items-center text-center">
          <span className={clsx("grid h-[104px] w-[104px] place-items-center rounded-[32px]", TONES[step % TONES.length])} aria-hidden>
            <Icon className="h-11 w-11" strokeWidth={1.6} />
          </span>
          <h2 className="mt-5 text-[21px] font-bold leading-tight tracking-[-0.02em]">{t(`${module}.s${step + 1}_t`)}</h2>
          <p className="mt-2 min-h-[4.5em] text-[15px] leading-relaxed text-ink-muted">{t(`${module}.s${step + 1}_b`)}</p>
        </div>
        <div className="mt-4 flex justify-center gap-1.5" role="group" aria-label={t("step_of", { n: step + 1, total: icons.length })}>
          {icons.map((_, i) => (
            <button
              key={i}
              type="button"
              onClick={() => setStep(i)}
              aria-label={t("go_step", { n: i + 1 })}
              aria-current={i === step ? "step" : undefined}
              className="grid h-6 w-6 place-items-center"
            >
              <span className={clsx("block h-2 rounded-full transition-all", i === step ? "w-5 bg-accent" : "w-2 bg-ring-idle")} />
            </button>
          ))}
        </div>
        <div className="mt-5 flex items-center justify-between gap-3">
          {last ? <span /> : (
            <Button type="button" variant="ghost" onClick={close}>{t("skip")}</Button>
          )}
          <Button type="button" autoFocus onClick={() => (last ? close() : setStep(step + 1))}>
            {last ? t("start") : t("next")}
          </Button>
        </div>
      </div>
    </dialog>
  );
}
