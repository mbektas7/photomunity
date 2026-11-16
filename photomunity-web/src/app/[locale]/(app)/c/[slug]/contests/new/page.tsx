"use client";

import { useMutation, useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useParams } from "next/navigation";
import { ContestForm, type ContestBody } from "@/components/ContestForm";
import { Link, useRouter } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import type { Community, Contest } from "@/lib/types";

export default function NewContestPage() {
  const { slug } = useParams<{ slug: string }>();
  const t = useTranslations("contestForm");
  const router = useRouter();
  const community = useQuery({ queryKey: ["community", slug], queryFn: () => api<Community>(`communities/${slug}`) });
  const create = useMutation({
    mutationFn: (body: ContestBody) => api<Contest>(`communities/${slug}/contests`, { method: "POST", body }),
    onSuccess: (c) => router.replace(`/contests/${c.id}/manage?created=1`),
  });
  return (
    <div className="mx-auto max-w-[760px] px-4 pt-8 sm:px-6 sm:pt-12">
      {community.data && <Link href={`/c/${slug}?tab=contests`} className="text-sm text-ink-muted hover:text-ink">← {community.data.name}</Link>}
      <h1 className="mt-3 text-[clamp(2rem,4.5vw,3rem)] font-bold leading-none tracking-[-0.04em]">{t("new_title")}</h1>
      <p className="mt-3 max-w-[60ch] text-ink-muted">{t("new_lead")}</p>
      <div className="mt-10">
        <ContestForm
          busy={create.isPending}
          error={create.error ? (create.error instanceof ApiError ? create.error.message : t("error")) : null}
          submitLabel={t("save_draft")}
          onSubmit={(b) => create.mutate(b)}
        />
      </div>
    </div>
  );
}
