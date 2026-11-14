"use client";

import { useMutation } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useSearchParams } from "next/navigation";
import { Suspense } from "react";
import { AuthHeading } from "@/components/AuthForms";
import { Button, Notice, TextField, buttonClass } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";

function ResetForm() {
  const t = useTranslations("auth");
  const token = useSearchParams().get("token") ?? "";
  const reset = useMutation({
    mutationFn: (new_password: string) => api("auth/reset-password", { method: "POST", body: { token, new_password } }),
  });

  if (reset.isSuccess) {
    return (
      <>
        <Notice tone="success">{t("reset_done")}</Notice>
        <Link href="/login" className={buttonClass("primary", "mt-6 h-12 w-full text-base")}>
          {t("login_submit")}
        </Link>
      </>
    );
  }
  return (
    <form
      className="flex flex-col gap-4"
      onSubmit={(e) => {
        e.preventDefault();
        reset.mutate(String(new FormData(e.currentTarget).get("password")));
      }}
    >
      <TextField label={t("new_password")} name="password" type="password" autoComplete="new-password" minLength={8} required hint={t("password_hint")} />
      {reset.error && <Notice tone="error">{reset.error instanceof ApiError ? reset.error.message : t("generic_error")}</Notice>}
      <Button type="submit" busy={reset.isPending} disabled={!token} className="h-12 text-base">
        {t("reset_submit")}
      </Button>
    </form>
  );
}

export default function ResetPasswordPage() {
  const t = useTranslations("auth");
  return (
    <>
      <AuthHeading title={t("reset_title")} />
      <Suspense>
        <ResetForm />
      </Suspense>
    </>
  );
}
