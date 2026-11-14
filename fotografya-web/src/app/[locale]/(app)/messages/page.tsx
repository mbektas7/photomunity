"use client";

import { MessageCircle } from "lucide-react";
import { useTranslations } from "next-intl";

export default function MessagesIndex() {
  const t = useTranslations("messages");
  return (
    <div className="flex h-full flex-col items-center justify-center gap-3 px-6 text-center text-muted">
      <MessageCircle className="h-8 w-8" strokeWidth={1.6} />
      <p className="max-w-[36ch]">{t("pick")}</p>
    </div>
  );
}
