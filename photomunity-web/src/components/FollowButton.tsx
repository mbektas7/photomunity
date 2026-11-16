"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { useRouter } from "@/i18n/navigation";
import { api } from "@/lib/api";
import { buttonClass } from "@/lib/button-class";
import { useMe } from "@/lib/hooks";
import type { Profile } from "@/lib/types";
import { Button } from "./ui";

/**
 * Takip et (primary) / Takip ediliyor (secondary).
 * size="sm": kart başlığındaki 36 px hap. variant="outline": önerilen listelerde tekrarlanan eylem.
 */
export function FollowButton({
  profile,
  username,
  following,
  size = "md",
  variant = "primary",
  className,
}: {
  profile?: Profile;
  username?: string;
  following?: boolean;
  size?: "sm" | "md";
  variant?: "primary" | "outline";
  className?: string;
}) {
  const t = useTranslations("profile");
  const { data: me } = useMe();
  const router = useRouter();
  const qc = useQueryClient();
  const name = profile?.username ?? username!;
  const [local, setLocal] = useState<boolean | null>(null);
  const isFollowing = local ?? profile?.is_following ?? following ?? false;

  const toggle = useMutation({
    mutationFn: (follow: boolean) => api(`users/${name}/follow`, { method: follow ? "POST" : "DELETE" }),
    onSuccess: (_d, follow) => {
      setLocal(follow);
      qc.invalidateQueries({ queryKey: ["profile", name] });
      qc.invalidateQueries({ queryKey: ["photos", "user", name] });
      qc.invalidateQueries({ queryKey: ["feed"] });
    },
  });

  const sm = size === "sm" ? "h-9 min-h-9 px-4 text-[14px]" : undefined;
  if (!me) {
    return (
      <Button className={sm ? `${sm} ${className ?? ""}` : className} variant={variant} onClick={() => router.push("/login")}>
        {t("follow")}
      </Button>
    );
  }
  return isFollowing ? (
    <button
      type="button"
      disabled={toggle.isPending}
      aria-busy={toggle.isPending}
      onClick={() => toggle.mutate(false)}
      className={buttonClass("secondary", [sm, className].filter(Boolean).join(" "))}
    >
      {t("following_button")}
    </button>
  ) : (
    <button
      type="button"
      disabled={toggle.isPending}
      aria-busy={toggle.isPending}
      onClick={() => toggle.mutate(true)}
      className={buttonClass(variant, [sm, className].filter(Boolean).join(" "))}
    >
      {t("follow")}
    </button>
  );
}
