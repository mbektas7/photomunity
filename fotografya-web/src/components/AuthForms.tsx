"use client";

import { useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";
import { useState } from "react";
import { useSearchParams } from "next/navigation";
import { Link, useRouter } from "@/i18n/navigation";
import { ApiError, authAction } from "@/lib/api";
import type { Me } from "@/lib/types";
import { SocialButtons } from "./SocialButtons";
import { Button, Notice, TextField } from "./ui";

export function AuthHeading({ title, lead }: { title: string; lead?: string }) {
  return (
    <div className="mb-8">
      <h1 className="text-[34px] font-bold leading-tight tracking-[-0.035em]">{title}</h1>
      {lead && <p className="mt-2 text-muted">{lead}</p>}
    </div>
  );
}

/** Yalnızca site içi yollar kabul edilir (açık yönlendirme koruması). */
export function useNextPath(fallback: string) {
  const next = useSearchParams().get("next");
  return next && next.startsWith("/") && !next.startsWith("//") ? next : fallback;
}

export function LoginForm() {
  const t = useTranslations("auth");
  const router = useRouter();
  const next = useNextPath("/feed");
  const qc = useQueryClient();
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const data = new FormData(e.currentTarget);
    setBusy(true);
    setError(null);
    try {
      await authAction<{ user: Me }>("login", { email: data.get("email"), password: data.get("password") });
      await qc.invalidateQueries({ queryKey: ["me"] });
      router.push(next);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : t("generic_error"));
      setBusy(false);
    }
  }

  return (
    <>
      <AuthHeading title={t("login_title")} />
      <SocialButtons onError={setError} />
      <form onSubmit={submit} className="flex flex-col gap-4">
        <TextField label={t("email")} name="email" type="email" autoComplete="email" required />
        <TextField label={t("password")} name="password" type="password" autoComplete="current-password" required />
        <Link href="/forgot-password" className="-mt-1 self-end text-sm font-medium text-muted hover:text-ink">
          {t("forgot")}
        </Link>
        {error && <Notice tone="error">{error}</Notice>}
        <Button type="submit" busy={busy} className="mt-1 h-12 text-base">
          {t("login_submit")}
        </Button>
      </form>
      <p className="mt-8 text-[15px] text-muted">
        {t("no_account")}{" "}
        <Link href={`/register${next !== "/feed" ? `?next=${encodeURIComponent(next)}` : ""}`} className="font-semibold text-ink underline-offset-4 hover:underline">
          {t("register_link")}
        </Link>
      </p>
    </>
  );
}

export function RegisterForm() {
  const t = useTranslations("auth");
  const locale = useLocale();
  const router = useRouter();
  const next = useNextPath("");
  const qc = useQueryClient();
  const [error, setError] = useState<ApiError | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const data = new FormData(e.currentTarget);
    setBusy(true);
    setError(null);
    try {
      await authAction("register", {
        display_name: data.get("display_name"),
        username: String(data.get("username")).toLowerCase(),
        email: data.get("email"),
        password: data.get("password"),
        locale,
      });
      await qc.invalidateQueries({ queryKey: ["me"] });
      router.push(next || "/settings?welcome=1");
    } catch (err) {
      setError(err instanceof ApiError ? err : new ApiError(0, "unknown", t("generic_error")));
      setBusy(false);
    }
  }

  const fieldError = (code: string) => (error?.code === code ? error.message : undefined);
  const general = error && !["email_taken", "username_taken"].includes(error.code) ? error.message : null;

  return (
    <>
      <AuthHeading title={t("register_title")} lead={t("register_lead")} />
      <SocialButtons onError={(m) => setError(new ApiError(0, "social", m))} />
      <form onSubmit={submit} className="flex flex-col gap-4">
        <TextField label={t("display_name")} name="display_name" autoComplete="name" required maxLength={80} />
        <TextField
          label={t("username")}
          name="username"
          autoComplete="username"
          required
          pattern="[a-zA-Z0-9_.]{3,30}"
          hint={t("username_hint")}
          error={fieldError("username_taken")}
        />
        <TextField label={t("email")} name="email" type="email" autoComplete="email" required error={fieldError("email_taken")} />
        <TextField label={t("password")} name="password" type="password" autoComplete="new-password" minLength={8} required hint={t("password_hint")} />
        {general && <Notice tone="error">{general}</Notice>}
        <Button type="submit" busy={busy} className="mt-1 h-12 text-base">
          {t("register_submit")}
        </Button>
        <p className="text-sm text-muted">{t("terms")}</p>
      </form>
      <p className="mt-8 text-[15px] text-muted">
        {t("have_account")}{" "}
        <Link href="/login" className="font-semibold text-ink underline-offset-4 hover:underline">
          {t("login_link")}
        </Link>
      </p>
    </>
  );
}
