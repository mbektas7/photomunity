"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useRouter } from "@/i18n/navigation";
import { api } from "@/lib/api";
import { useMe } from "@/lib/hooks";
import type { Profile } from "@/lib/types";
import { Button } from "./ui";

export function FollowButton({ profile }: { profile: Profile }) {
  const t = useTranslations("profile");
  const { data: me } = useMe();
  const router = useRouter();
  const qc = useQueryClient();
  const key = ["profile", profile.username];

  const toggle = useMutation({
    mutationFn: (follow: boolean) => api(`users/${profile.username}/follow`, { method: follow ? "POST" : "DELETE" }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: key });
      qc.invalidateQueries({ queryKey: ["photos", "user", profile.username] });
      qc.invalidateQueries({ queryKey: ["feed"] });
    },
  });

  if (!me) return <Button onClick={() => router.push("/login")}>{t("follow")}</Button>;
  return profile.is_following ? (
    <Button variant="secondary" busy={toggle.isPending} onClick={() => toggle.mutate(false)}>
      {t("following_button")}
    </Button>
  ) : (
    <Button busy={toggle.isPending} onClick={() => toggle.mutate(true)}>
      {t("follow")}
    </Button>
  );
}
