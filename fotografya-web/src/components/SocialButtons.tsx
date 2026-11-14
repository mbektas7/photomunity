"use client";

import { useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";
import { useEffect, useRef, useState } from "react";
import { useRouter } from "@/i18n/navigation";
import { ApiError, authAction } from "@/lib/api";
import type { Me } from "@/lib/types";

const GOOGLE_ID = process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID;
const APPLE_ID = process.env.NEXT_PUBLIC_APPLE_CLIENT_ID;
const APPLE_REDIRECT = process.env.NEXT_PUBLIC_APPLE_REDIRECT_URI;

type GoogleId = {
  initialize(opts: { client_id: string; callback: (r: { credential: string }) => void; ux_mode?: string }): void;
  renderButton(el: HTMLElement, opts: Record<string, unknown>): void;
};
type AppleAuth = {
  init(opts: Record<string, unknown>): void;
  signIn(): Promise<{ authorization: { id_token: string }; user?: { name?: { firstName?: string; lastName?: string } } }>;
};
declare global {
  interface Window {
    google?: { accounts: { id: GoogleId } };
    AppleID?: { auth: AppleAuth };
  }
}

function loadScript(src: string) {
  return new Promise<void>((resolve, reject) => {
    if (document.querySelector(`script[src="${src}"]`)) return resolve();
    const s = document.createElement("script");
    s.src = src;
    s.async = true;
    s.onload = () => resolve();
    s.onerror = () => reject(new Error(src));
    document.head.appendChild(s);
  });
}

export function SocialButtons({ onError }: { onError: (message: string) => void }) {
  const t = useTranslations("auth");
  const locale = useLocale();
  const router = useRouter();
  const qc = useQueryClient();
  const googleRef = useRef<HTMLDivElement>(null);
  const [busy, setBusy] = useState(false);

  async function finish(provider: "google" | "apple", body: Record<string, unknown>) {
    setBusy(true);
    try {
      const res = await authAction<{ user: Me; is_new_user: boolean }>(provider, { ...body, locale });
      await qc.invalidateQueries({ queryKey: ["me"] });
      router.push(res.is_new_user ? "/settings?welcome=1" : "/feed");
    } catch (e) {
      onError(e instanceof ApiError ? e.message : t("social_failed"));
    } finally {
      setBusy(false);
    }
  }

  useEffect(() => {
    if (!GOOGLE_ID || !googleRef.current) return;
    const el = googleRef.current;
    loadScript("https://accounts.google.com/gsi/client")
      .then(() => {
        const gid = window.google?.accounts.id;
        if (!gid) return;
        gid.initialize({ client_id: GOOGLE_ID, callback: (r) => finish("google", { id_token: r.credential }) });
        gid.renderButton(el, {
          theme: window.matchMedia("(prefers-color-scheme: dark)").matches ? "filled_black" : "outline",
          size: "large",
          shape: "pill",
          text: "continue_with",
          width: Math.min(el.clientWidth || 360, 400),
          locale,
        });
      })
      .catch(() => undefined);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [locale]);

  async function apple() {
    try {
      await loadScript("https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js");
      const auth = window.AppleID!.auth;
      auth.init({ clientId: APPLE_ID, scope: "name email", redirectURI: APPLE_REDIRECT, usePopup: true });
      const r = await auth.signIn();
      const n = r.user?.name;
      const display = n ? [n.firstName, n.lastName].filter(Boolean).join(" ") : undefined;
      await finish("apple", { id_token: r.authorization.id_token, display_name: display || undefined });
    } catch {
      // Kullanıcı açılır pencereyi kapattıysa sessizce geç
    }
  }

  if (!GOOGLE_ID && !APPLE_ID) return null;

  return (
    <div className="flex flex-col gap-3" aria-busy={busy}>
      {GOOGLE_ID && <div ref={googleRef} className="flex min-h-11 justify-center" />}
      {APPLE_ID && (
        <button
          type="button"
          onClick={apple}
          disabled={busy}
          className="inline-flex h-11 items-center justify-center gap-2 rounded-full bg-ink text-[15px] font-semibold text-surface"
        >
          <svg viewBox="0 0 17 20" className="h-[18px] w-[18px]" fill="currentColor" aria-hidden>
            <path d="M14.1 10.6c0-2.6 2.1-3.8 2.2-3.9-1.2-1.8-3.1-2-3.7-2-1.6-.2-3.1.9-3.9.9-.8 0-2-.9-3.4-.9C3.6 4.8 2 5.8 1.1 7.4c-1.8 3.2-.5 7.9 1.3 10.5.9 1.3 1.9 2.7 3.2 2.6 1.3-.1 1.8-.8 3.3-.8 1.6 0 2 .8 3.4.8 1.4 0 2.3-1.3 3.1-2.6 1-1.5 1.4-2.9 1.4-3-.1 0-2.7-1-2.7-4.3zM11.5 3c.7-.9 1.2-2 1.1-3.2-1 0-2.3.7-3 1.6-.7.8-1.2 2-1.1 3.1 1.2.1 2.3-.6 3-1.5z" />
          </svg>
          {t("continue_apple")}
        </button>
      )}
      <div className="my-2 flex items-center gap-3 text-sm text-ink-muted">
        <span className="h-px flex-1 bg-line" />
        {t("or_email")}
        <span className="h-px flex-1 bg-line" />
      </div>
    </div>
  );
}
