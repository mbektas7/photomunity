"use client";

import { useMutation } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useEffect, useState } from "react";
import { Button, Notice, TextArea, TextField } from "@/components/ui";
import { useRouter } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import { useMe } from "@/lib/hooks";
import type { Community } from "@/lib/types";

export default function NewCommunityPage() {
  const t = useTranslations("communities");
  const router = useRouter();
  const { data: me, isLoading } = useMe();
  const [form, setForm] = useState({ name: "", description: "", city: "", country: "" });

  useEffect(() => {
    if (!isLoading && !me) router.replace("/login?next=/communities/new");
  }, [me, isLoading, router]);

  const create = useMutation({
    mutationFn: () =>
      api<Community>("communities", {
        method: "POST",
        body: { name: form.name.trim(), description: form.description || null, city: form.city || null, country: form.country || null },
      }),
    onSuccess: (c) => router.replace(`/c/${c.slug}/settings?created=1`),
  });

  return (
    <div className="mx-auto max-w-[620px] px-4 pt-8 sm:pt-12">
      <h1 className="text-[clamp(2rem,4.5vw,3rem)] font-bold leading-none tracking-[-0.04em]">{t("new_title")}</h1>
      <p className="mt-3 text-ink-muted">{t("new_lead")}</p>
      <form
        className="mt-8 flex flex-col gap-5"
        onSubmit={(e) => {
          e.preventDefault();
          create.mutate();
        }}
      >
        <TextField label={t("name")} name="name" required minLength={3} maxLength={100} placeholder={t("name_placeholder")} value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
        <TextArea label={t("description")} name="description" maxLength={3000} value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} />
        <div className="grid gap-5 sm:grid-cols-[1fr_140px]">
          <TextField label={t("city")} name="city" value={form.city} onChange={(e) => setForm({ ...form, city: e.target.value })} />
          <TextField label={t("country")} name="country" maxLength={2} hint="TR, DE" value={form.country} onChange={(e) => setForm({ ...form, country: e.target.value.toUpperCase() })} />
        </div>
        {create.error && <Notice tone="error">{create.error instanceof ApiError ? create.error.message : t("error")}</Notice>}
        <Button type="submit" busy={create.isPending} className="h-12 self-start text-base">
          {t("create")}
        </Button>
      </form>
    </div>
  );
}
