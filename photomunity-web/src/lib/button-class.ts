import clsx from "clsx";

/**
 * Düğme türleri (design/components/Button.md):
 * - primary: ekrandaki tek birincil eylem (accent dolgu)
 * - secondary: yanındaki ikincil eylem (surface-2)
 * - outline: liste içinde tekrarlanan eylemler
 * - large: ekranın altındaki ana çağrı (56 px, radius-box)
 * - danger: tehlikeli eylem (metin düğmesi)
 * - ghost: araç çubuğu ve menülerde zeminsiz düğme
 */
export type ButtonVariant = "primary" | "secondary" | "outline" | "large" | "danger" | "ghost";

export const buttonClass = (variant: ButtonVariant = "primary", extra?: string) =>
  clsx(
    "inline-flex min-h-11 items-center justify-center gap-2 whitespace-nowrap font-semibold transition-colors disabled:cursor-not-allowed disabled:opacity-50",
    variant !== "large" && "h-11 rounded-pill px-5 text-[15px]",
    variant === "primary" && "bg-accent text-accent-ink hover:brightness-110",
    variant === "secondary" && "bg-surface-2 text-ink hover:bg-line",
    variant === "outline" && "border-[1.5px] border-ink bg-transparent text-ink hover:bg-surface-2",
    variant === "large" && "h-14 w-full rounded-box bg-accent px-6 text-[17px] font-bold text-accent-ink hover:brightness-110",
    variant === "danger" && "px-3 text-danger hover:bg-danger/10",
    variant === "ghost" && "text-ink hover:bg-surface-2",
    extra,
  );
