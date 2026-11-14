import clsx from "clsx";

/** Sunucu ve istemci bileşenlerinin ortak kullandığı düğme sınıfları. */
export const buttonClass = (variant: "primary" | "secondary" | "ghost" | "danger" = "primary", extra?: string) =>
  clsx(
    "inline-flex h-11 items-center justify-center gap-2 whitespace-nowrap rounded-full px-5 text-[15px] font-semibold transition-colors disabled:cursor-not-allowed disabled:opacity-50",
    variant === "primary" && "bg-ink text-mat hover:bg-accent hover:text-accent-ink",
    variant === "secondary" && "border border-line bg-mat text-ink hover:border-ink",
    variant === "ghost" && "text-ink hover:bg-ink/5",
    variant === "danger" && "border border-danger text-danger hover:bg-danger hover:text-mat",
    extra,
  );
