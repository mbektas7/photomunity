"use client";

import clsx from "clsx";
import { Share2 } from "lucide-react";
import { useTranslations } from "next-intl";
import { useState } from "react";

/** Yuvarlak ikincil Paylaş düğmesi: varsa sistem paylaşımı, yoksa bağlantıyı kopyalar. */
export function ShareButton({
  url,
  title,
  size = 38,
  tone = "surface-2",
  className,
}: {
  url?: string;
  title?: string;
  size?: number;
  tone?: "surface-2" | "surface" | "scrim";
  className?: string;
}) {
  const t = useTranslations("ui");
  const [copied, setCopied] = useState(false);

  async function share() {
    const href = url ? new URL(url, window.location.href).toString() : window.location.href;
    if (navigator.share) {
      try {
        await navigator.share({ title, url: href });
        return;
      } catch {
        /* kullanıcı vazgeçti */
        return;
      }
    }
    await navigator.clipboard.writeText(href);
    setCopied(true);
    setTimeout(() => setCopied(false), 1800);
  }

  return (
    <button
      type="button"
      onClick={share}
      aria-label={copied ? t("link_copied") : t("share")}
      title={copied ? t("link_copied") : undefined}
      style={{ width: Math.max(size, 38), height: Math.max(size, 38) }}
      className={clsx(
        "inline-flex shrink-0 items-center justify-center rounded-full text-ink transition-colors",
        tone === "surface-2" && "bg-surface-2 hover:bg-line",
        tone === "surface" && "bg-surface hover:bg-surface-2",
        tone === "scrim" && "scrim",
        className,
      )}
    >
      <Share2 className="h-[17px] w-[17px]" strokeWidth={1.8} aria-hidden />
      <span role="status" className="sr-only">
        {copied ? t("link_copied") : ""}
      </span>
    </button>
  );
}
