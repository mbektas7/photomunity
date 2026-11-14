"use client";

import clsx from "clsx";
import { Heart } from "lucide-react";
import { useTranslations } from "next-intl";
import { useRouter } from "@/i18n/navigation";
import { useLike, useMe } from "@/lib/hooks";

export function LikeButton({ id, liked, count, size = "md" }: { id: string; liked: boolean; count: number; size?: "md" | "lg" }) {
  const t = useTranslations("photo");
  const { data: me } = useMe();
  const like = useLike();
  const router = useRouter();

  return (
    <button
      type="button"
      onClick={() => (me ? like.mutate({ id, liked: !liked }) : router.push("/login"))}
      aria-pressed={liked}
      aria-label={liked ? t("unlike") : t("like")}
      className={clsx(
        "inline-flex items-center gap-1.5 rounded-full font-semibold transition-colors",
        size === "lg" ? "h-11 px-4 text-[15px]" : "h-9 px-3 text-sm",
        liked ? "text-accent" : "text-ink hover:bg-ink/5",
      )}
    >
      <Heart
        className={clsx("transition-transform active:scale-90", size === "lg" ? "h-5 w-5" : "h-[18px] w-[18px]")}
        fill={liked ? "currentColor" : "none"}
        strokeWidth={2}
      />
      <span className="tnum">{count}</span>
    </button>
  );
}
