"use client";

import { useMutation } from "@tanstack/react-query";
import { Flag } from "lucide-react";
import { useTranslations } from "next-intl";
import { useRef, useState } from "react";
import { ApiError, api } from "@/lib/api";
import { Button, Notice } from "./ui";

const REASONS = ["spam", "nudity", "violence", "harassment", "copyright", "other"] as const;

export function ReportButton({ targetType, targetId }: { targetType: "photo" | "user"; targetId: string }) {
  const t = useTranslations("report");
  const dialog = useRef<HTMLDialogElement>(null);
  const [reason, setReason] = useState<(typeof REASONS)[number] | null>(null);
  const [note, setNote] = useState("");
  const send = useMutation({
    mutationFn: () => api("reports", { method: "POST", body: { target_type: targetType, target_id: targetId, reason, note: note || null } }),
  });
  const already = send.error instanceof ApiError && send.error.code === "already_reported";

  return (
    <>
      <button type="button" onClick={() => dialog.current?.showModal()} className="inline-flex min-h-11 items-center gap-2 rounded-box px-3 text-[14.5px] font-medium text-ink-muted hover:bg-surface-2 hover:text-ink">
        <Flag className="h-4 w-4" /> {t("button")}
      </button>
      <dialog
        ref={dialog}
        className="m-auto w-[min(440px,calc(100vw-2rem))] rounded-sheet bg-surface p-6 text-ink shadow-float backdrop:bg-black/50"
        onClose={() => send.reset()}
      >
        <h2 className="text-heading">{t("title")}</h2>
        {send.isSuccess || already ? (
          <>
            <p className="mt-3 text-ink-muted">{already ? send.error?.message : t("thanks")}</p>
            <Button className="mt-6" onClick={() => dialog.current?.close()}>
              {t("close")}
            </Button>
          </>
        ) : (
          <form
            className="mt-4 flex flex-col gap-4"
            onSubmit={(e) => {
              e.preventDefault();
              if (reason) send.mutate();
            }}
          >
            <fieldset className="flex flex-col gap-1">
              <legend className="sr-only">{t("reason")}</legend>
              {REASONS.map((r) => (
                <label key={r} className="flex cursor-pointer items-center gap-3 min-h-11 rounded-box px-3 py-2 hover:bg-surface-2">
                  <input type="radio" name="reason" value={r} checked={reason === r} onChange={() => setReason(r)} className="accent-[var(--accent)]" />
                  <span className="text-[15px]">{t(`reasons.${r}`)}</span>
                </label>
              ))}
            </fieldset>
            <textarea
              value={note}
              onChange={(e) => setNote(e.target.value)}
              maxLength={1000}
              rows={3}
              placeholder={t("note")}
              className="rounded-box border border-ring-idle bg-surface px-4 py-3 text-[15px] outline-none focus:border-accent"
            />
            {send.error && !already && <Notice tone="error">{send.error.message}</Notice>}
            <div className="flex gap-3">
              <Button type="submit" disabled={!reason} busy={send.isPending}>
                {t("submit")}
              </Button>
              <Button type="button" variant="ghost" onClick={() => dialog.current?.close()}>
                {t("cancel")}
              </Button>
            </div>
          </form>
        )}
      </dialog>
    </>
  );
}
