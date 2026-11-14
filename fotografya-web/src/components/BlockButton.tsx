"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Ban } from "lucide-react";
import { useTranslations } from "next-intl";
import { useRouter } from "@/i18n/navigation";
import { api } from "@/lib/api";
import { useMe } from "@/lib/hooks";

export function BlockButton({ username, name }: { username: string; name: string }) {
  const t = useTranslations("messages");
  const { data: me } = useMe();
  const qc = useQueryClient();
  const router = useRouter();
  const block = useMutation({
    mutationFn: () => api(`users/${username}/block`, { method: "POST" }),
    onSuccess: () => {
      qc.invalidateQueries();
      router.push("/feed");
    },
  });
  if (!me) return null;
  return (
    <button type="button" onClick={() => window.confirm(t("block_confirm", { name })) && block.mutate()} className="inline-flex min-h-11 w-full items-center gap-2 rounded-box px-3 text-[15px] font-medium text-danger hover:bg-danger/10">
      <Ban className="h-4 w-4" /> {t("block")}
    </button>
  );
}
