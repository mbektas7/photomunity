"use client";

import { useMutation } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { AuthHeading } from "@/components/AuthForms";
import { Button, Notice, TextField } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { api } from "@/lib/api";

export default function ForgotPasswordPage() {
  const t = useTranslations("auth");
  const send = useMutation({ mutationFn: (email: string) => api("auth/forgot-password", { method: "POST", body: { email } }) });

  return (
    <>
      <AuthHeading title={t("forgot_title")} lead={t("forgot_lead")} />
      {send.isSuccess ? (
        <Notice tone="success">{t("forgot_sent")}</Notice>
      ) : (
        <form
          className="flex flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            send.mutate(String(new FormData(e.currentTarget).get("email")));
          }}
        >
          <TextField label={t("email")} name="email" type="email" autoComplete="email" required />
          <Button type="submit" busy={send.isPending} className="h-12 text-base">
            {t("forgot_submit")}
          </Button>
        </form>
      )}
      <Link href="/login" className="mt-8 inline-block text-[15px] font-semibold underline-offset-4 hover:underline">
        {t("back_to_login")}
      </Link>
    </>
  );
}
