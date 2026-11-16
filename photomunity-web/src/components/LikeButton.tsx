"use client";

import clsx from "clsx";
import { Heart } from "lucide-react";
import { useTranslations } from "next-intl";
import { useRouter } from "@/i18n/navigation";
import { useLike, useMe } from "@/lib/hooks";

/**
 * Beğeni hapı. Beğenilmişse accent-tint zemin ve accent dolgulu kalp.
 * size="md": kart altı (38 px hap). size="lg": detaydaki geniş düğme ("Beğendin, 248").
 */
export function LikeButton({
  id,
  liked,
  count,
  size = "md",
  className,
}: {
  id: string;
  liked: boolean;
  count: number;
  size?: "md" | "lg";
  className?: string;
}) {
  const t = useTranslations("photo");
  const { data: me } = useMe();
  const like = useLike();
  const router = useRouter();
  const lg = size === "lg";

  return (
    <button
      type="button"
      onClick={() => (me ? like.mutate({ id, liked: !liked }) : router.push("/login"))}
      aria-pressed={liked}
      aria-label={liked ? t("unlike_count", { count }) : t("like_count", { count })}
      className={clsx(
        "inline-flex items-center justify-center gap-1.5 font-semibold transition-colors",
        lg ? "h-[52px] rounded-box px-5 text-[16px]" : "h-[38px] rounded-pill px-3.5 text-[14.5px]",
        liked ? "bg-accent-tint text-accent-text" : "bg-surface-2 text-ink hover:bg-line",
        className,
      )}
    >
      <Heart
        className={clsx("transition-transform active:scale-90", lg ? "h-5 w-5" : "h-[19px] w-[19px]")}
        fill={liked ? "var(--accent)" : "none"}
        stroke={liked ? "var(--accent)" : "currentColor"}
        strokeWidth={1.9}
        aria-hidden
      />
      <span className="tnum">{lg && liked ? t("liked_count", { count }) : count}</span>
    </button>
  );
}
