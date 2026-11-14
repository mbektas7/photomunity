"use client";

import clsx from "clsx";
import { Plus, X } from "lucide-react";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { fromLocalInput, toLocalInput } from "@/lib/dates";
import type { Contest } from "@/lib/types";
import { Button, Notice, TextArea, TextField, Toggle } from "./ui";

export type ContestBody = {
  title: string;
  description: string;
  rules: string | null;
  submission_deadline: string;
  voting_end: string;
  results_at: string;
  judging_mode: "jury" | "public";
  anonymous: boolean;
  min_votes: number;
  prizes: { rank: number; title: string }[];
};

function defaults(): ContestBody {
  const at = (days: number) => {
    const d = new Date();
    d.setDate(d.getDate() + days);
    d.setHours(23, 59, 0, 0);
    return d.toISOString();
  };
  return { title: "", description: "", rules: "", submission_deadline: at(21), voting_end: at(28), results_at: at(30),
           judging_mode: "public", anonymous: true, min_votes: 5, prizes: [{ rank: 1, title: "" }, { rank: 2, title: "" }, { rank: 3, title: "" }] };
}

/** Yarışma oluşturma/düzenleme formu. `locked` iken yalnızca metin alanları düzenlenebilir (yayından sonra). */
export function ContestForm({ initial, locked = false, busy, error, submitLabel, onSubmit }: {
  initial?: Contest; locked?: boolean; busy: boolean; error: string | null; submitLabel: string; onSubmit: (b: ContestBody) => void;
}) {
  const t = useTranslations("contestForm");
  const [f, setF] = useState<ContestBody>(() =>
    initial
      ? { title: initial.title, description: initial.description, rules: initial.rules ?? "", submission_deadline: initial.submission_deadline,
          voting_end: initial.voting_end, results_at: initial.results_at, judging_mode: initial.judging_mode, anonymous: initial.anonymous,
          min_votes: initial.min_votes, prizes: initial.prizes.length ? initial.prizes : defaults().prizes }
      : defaults(),
  );
  const set = <K extends keyof ContestBody>(k: K, v: ContestBody[K]) => setF((x) => ({ ...x, [k]: v }));
  const order = new Date(f.submission_deadline) < new Date(f.voting_end) && new Date(f.voting_end) <= new Date(f.results_at);

  return (
    <form
      className="flex flex-col gap-10"
      onSubmit={(e) => {
        e.preventDefault();
        onSubmit({ ...f, rules: f.rules || null, prizes: f.prizes.filter((p) => p.title.trim()).map((p, i) => ({ rank: i + 1, title: p.title.trim() })) });
      }}
    >
      <fieldset className="flex flex-col gap-5">
        <legend className="mb-4 text-lg font-semibold">{t("about")}</legend>
        <TextField label={t("title")} name="title" required minLength={3} maxLength={150} placeholder={t("title_placeholder")} value={f.title} onChange={(e) => set("title", e.target.value)} />
        <TextArea label={t("description")} name="description" required maxLength={5000} hint={t("description_hint")} value={f.description} onChange={(e) => set("description", e.target.value)} />
        <TextArea label={t("rules")} name="rules" maxLength={5000} hint={t("rules_hint")} value={f.rules ?? ""} onChange={(e) => set("rules", e.target.value)} />
      </fieldset>

      <fieldset className="flex flex-col gap-5" disabled={locked}>
        <legend className="mb-1 text-lg font-semibold">{t("dates")}</legend>
        <p className="-mt-2 text-sm text-ink-muted">{locked ? t("locked_hint") : t("dates_hint")}</p>
        <div className="grid gap-5 sm:grid-cols-3">
          {(["submission_deadline", "voting_end", "results_at"] as const).map((k) => (
            <TextField key={k} label={t(k)} name={k} type="datetime-local" required value={toLocalInput(f[k])} onChange={(e) => set(k, fromLocalInput(e.target.value))} />
          ))}
        </div>
        {!order && <Notice tone="error">{t("dates_order")}</Notice>}
      </fieldset>

      <fieldset className="flex flex-col gap-4" disabled={locked}>
        <legend className="mb-4 text-lg font-semibold">{t("judging")}</legend>
        <div className="grid gap-3 sm:grid-cols-2">
          {(["public", "jury"] as const).map((m) => (
            <label key={m} className={clsx("cursor-pointer border bg-surface px-4 py-4", f.judging_mode === m ? "border-ink" : "border-line", locked && "cursor-not-allowed opacity-60")}>
              <input type="radio" name="judging_mode" value={m} checked={f.judging_mode === m} onChange={() => set("judging_mode", m)} className="sr-only" />
              <span className="block font-semibold">{t(`mode_${m}`)}</span>
              <span className="mt-1 block text-sm leading-relaxed text-ink-muted">{t(`mode_${m}_hint`)}</span>
            </label>
          ))}
        </div>
        {f.judging_mode === "jury" && <p className="text-sm text-ink-muted">{t("jury_after")}</p>}
        <Toggle checked={f.anonymous} onChange={(v) => !locked && set("anonymous", v)} label={t("anonymous")} hint={t("anonymous_hint")} />
        {f.judging_mode === "public" && (
          <TextField label={t("min_votes")} name="min_votes" type="number" min={0} max={100} hint={t("min_votes_hint")} value={String(f.min_votes)} onChange={(e) => set("min_votes", Number(e.target.value) || 0)} className="max-w-[260px]" />
        )}
      </fieldset>

      <fieldset className="flex flex-col gap-3">
        <legend className="mb-4 text-lg font-semibold">{t("prizes")}</legend>
        {f.prizes.map((p, i) => (
          <div key={i} className="flex items-center gap-3">
            <span className="tnum w-10 shrink-0 text-center text-xl font-semibold">{i + 1}.</span>
            <input
              aria-label={t("prize_n", { n: i + 1 })}
              placeholder={t("prize_placeholder")}
              value={p.title}
              maxLength={200}
              onChange={(e) => set("prizes", f.prizes.map((x, j) => (j === i ? { ...x, title: e.target.value } : x)))}
              className="h-11 min-w-0 flex-1 rounded-[10px] border border-line bg-surface px-3.5 text-[15px] outline-none focus:border-ink"
            />
            {f.prizes.length > 1 && (
              <button type="button" onClick={() => set("prizes", f.prizes.filter((_, j) => j !== i))} className="rounded-full p-2 text-ink-muted hover:bg-ink/5" aria-label={t("remove_prize")}>
                <X className="h-4 w-4" />
              </button>
            )}
          </div>
        ))}
        {f.prizes.length < 10 && (
          <Button type="button" variant="ghost" className="self-start" onClick={() => set("prizes", [...f.prizes, { rank: f.prizes.length + 1, title: "" }])}>
            <Plus className="h-4 w-4" /> {t("add_prize")}
          </Button>
        )}
      </fieldset>

      {error && <Notice tone="error">{error}</Notice>}
      <Button type="submit" busy={busy} disabled={!order} className="h-12 self-start text-base">{submitLabel}</Button>
    </form>
  );
}
