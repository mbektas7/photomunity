import clsx from "clsx";
import { initials } from "@/lib/format";

export function Avatar({ name, url, size = 40, className }: { name: string; url?: string | null; size?: number; className?: string }) {
  const style = { width: size, height: size, fontSize: Math.round(size * 0.38) };
  if (url) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={url} alt="" style={style} className={clsx("shrink-0 rounded-full object-cover", className)} />;
  }
  return (
    <span
      aria-hidden
      style={style}
      className={clsx("inline-flex shrink-0 items-center justify-center rounded-full bg-ink font-semibold text-surface", className)}
    >
      {initials(name)}
    </span>
  );
}
