"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useSearchParams } from "next/navigation";
import { Suspense, useEffect, useRef } from "react";
import { AuthHeading } from "@/components/AuthForms";
import { Notice, buttonClass } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";

function Verify() {
  const t = useTranslations("auth");
  const token = useSearchParams().get("token") ?? "";
  const qc = useQueryClient();
  const started = useRef(false);
  const verify = useMutation({
    mutationFn: () => api("auth/verify-email", { method: "POST", body: { token } }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["me"] }),
  });

  useEffect(() => {
    if (token && !started.current) {
      started.current = true;
      verify.mutate();
    }
  }, [token, verify]);

  if (verify.isSuccess) {
    return (
      <>
        <Notice tone="success">{t("verified")}</Notice>
        <Link href="/feed" className={buttonClass("primary", "mt-6 h-12 w-full text-base")}>
          {t("continue")}
        </Link>
      </>
    );
  }
  if (verify.isError || !token) {
    return <Notice tone="error">{verify.error instanceof ApiError ? verify.error.message : t("invalid_link")}</Notice>;
  }
  return <p className="text-ink-muted">{t("verifying")}</p>;
}

export default function VerifyEmailPage() {
  const t = useTranslations("auth");
  return (
    <>
      <AuthHeading title={t("verify_title")} />
      <Suspense>
        <Verify />
      </Suspense>
    </>
  );
}
