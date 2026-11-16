import clsx from "clsx";
import { Link } from "@/i18n/navigation";
import { initials } from "@/lib/format";

export type RingState = "live" | "accent" | "idle";

/**
 * Akışın üstündeki yuvarlak topluluk / yarışma kısayolu. Halka rengi durumu söyler:
 * live = açık yarışma (altında kalan süre rozeti), accent = toplulukta yeni içerik, idle = yeni bir şey yok.
 * Görsel daire içinde kırpılır (fotoğraf kırpılmaz kuralının istisnası).
 */
export function StoryRing({
  href,
  label,
  image,
  state,
  badge,
  ariaLabel,
  size = 70,
}: {
  href: string;
  label: string;
  image?: string | null;
  state: RingState;
  badge?: string | null;
  ariaLabel?: string;
  size?: number;
}) {
  return (
    <Link href={href} aria-label={ariaLabel} className="flex w-[78px] flex-none flex-col items-center gap-2 rounded-box">
      <span
        className={clsx(
          "relative rounded-full p-[3px]",
          state === "live" && "bg-live",
          state === "accent" && "bg-accent",
          state === "idle" && "bg-ring-idle",
        )}
        style={{ width: size, height: size }}
      >
        {image ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={image} alt="" className="h-full w-full rounded-full border-2 border-bg object-cover" />
        ) : (
          <span className="flex h-full w-full items-center justify-center rounded-full border-2 border-bg bg-surface-2 text-[18px] font-bold text-ink-muted">
            {initials(label)}
          </span>
        )}
        {badge && (
          <span className="absolute -bottom-[5px] left-1/2 -translate-x-1/2 whitespace-nowrap rounded-[9px] border-2 border-bg bg-live px-[7px] py-[2px] text-[10.5px] font-bold leading-[13px] text-live-ink">
            {badge}
          </span>
        )}
      </span>
      <span className="line-clamp-2 text-center text-[12px] font-medium leading-[14px]">{label}</span>
    </Link>
  );
}
