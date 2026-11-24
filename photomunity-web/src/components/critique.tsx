"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import clsx from "clsx";
import { MessageSquareQuote, ThumbsUp } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useState } from "react";
import { Avatar } from "@/components/Avatar";
import { Button, Notice, Toggle } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import { useMe } from "@/lib/hooks";
import { relativeTime } from "@/lib/relative-time";
import { CRITERIA, type Critique, type CritiqueList, type Criterion, type PhotoDetail } from "@/lib/types";

/** Sahibin ayarı: eleştiriye açık + soru (yükleme ve düzenleme formlarında). */
export function CritiqueFields({ requested, question, onChange }: { requested: boolean; question: string; onChange: (v: { requested: boolean; question: string }) => void }) {
  const t = useTranslations("critique");
  return (
    <div className="flex flex-col gap-3">
      <Toggle checked={requested} onChange={(v) => onChange({ requested: v, question })} label={t("open_label")} hint={t("open_hint")} />
      {requested && (
        <div className="flex flex-col gap-1.5">
          <label htmlFor="critique-question" className="text-sm font-medium">{t("question_label")}</label>
          <textarea
            id="critique-question"
            rows={2}
            maxLength={300}
            value={question}
            placeholder={t("question_placeholder")}
            onChange={(e) => onChange({ requested, question: e.target.value })}
            className="rounded-box border border-ring-idle bg-surface px-4 py-3 text-[15px] leading-relaxed outline-none focus:border-accent"
          />
        </div>
      )}
    </div>
  );
}

/** 0–5 arası değer çubuğu. */
function Bar({ label, value }: { label: string; value: number | null }) {
  return (
    <div className="grid grid-cols-[minmax(0,1fr)_96px_24px] items-center gap-2.5 text-[13.5px]">
      <span className="truncate text-ink-muted">{label}</span>
      <span className="h-1.5 overflow-hidden rounded-full bg-line" aria-hidden>
        <span className="block h-full rounded-full bg-accent" style={{ width: `${((value ?? 0) / 5) * 100}%` }} />
      </span>
      <span className="tnum text-right font-semibold">{value == null ? "—" : Number.isInteger(value) ? value : value.toFixed(1)}</span>
    </div>
  );
}

function Scale({ label, value, onChange }: { label: string; value: number; onChange: (v: number) => void }) {
  const t = useTranslations("critique");
  return (
    <div className="flex items-center justify-between gap-3">
      <span id={`lbl-${label}`} className="text-[14px] font-medium">{label}</span>
      <div role="radiogroup" aria-labelledby={`lbl-${label}`} className="flex gap-1">
        {[1, 2, 3, 4, 5].map((n) => (
          <button
            key={n}
            type="button"
            role="radio"
            aria-checked={value === n}
            aria-label={t("score_n", { n })}
            onClick={() => onChange(n)}
            className={clsx(
              "tnum h-9 w-9 rounded-full text-[14px] font-bold transition-colors",
              n <= value ? "bg-accent text-accent-ink" : "bg-surface-2 text-ink-muted hover:bg-line",
            )}
          >
            {n}
          </button>
        ))}
      </div>
    </div>
  );
}

function CritiqueForm({ photoId, mine, onDone }: { photoId: string; mine: Critique | null; onDone: () => void }) {
  const t = useTranslations("critique");
  const qc = useQueryClient();
  const [scores, setScores] = useState<Record<Criterion, number>>({
    composition: mine?.composition ?? 0, light: mine?.light ?? 0, focus: mine?.focus ?? 0, editing: mine?.editing ?? 0,
  });
  const [good, setGood] = useState(mine?.good ?? "");
  const [improve, setImprove] = useState(mine?.improve ?? "");
  const save = useMutation({
    mutationFn: () => api<Critique>(`photos/${photoId}/critiques`, { method: "PUT", body: { ...scores, good: good.trim() || null, improve: improve.trim() || null } }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["critiques", photoId] });
      qc.invalidateQueries({ queryKey: ["photo", photoId] });
      onDone();
    },
  });
  const complete = CRITERIA.every((c) => scores[c] >= 1);
  const area = "w-full rounded-box border border-ring-idle bg-surface px-3.5 py-2.5 text-[14.5px] leading-relaxed outline-none focus:border-accent";
  return (
    <form
      className="flex flex-col gap-3 rounded-box bg-surface-2 p-4"
      onSubmit={(e) => {
        e.preventDefault();
        if (complete) save.mutate();
      }}
    >
      {CRITERIA.map((c) => (
        <Scale key={c} label={t(`criteria.${c}`)} value={scores[c]} onChange={(v) => setScores((prev) => ({ ...prev, [c]: v }))} />
      ))}
      <label className="flex flex-col gap-1.5 text-sm font-medium">
        {t("good")}
        <textarea rows={2} maxLength={1000} value={good} onChange={(e) => setGood(e.target.value)} className={area} placeholder={t("good_placeholder")} />
      </label>
      <label className="flex flex-col gap-1.5 text-sm font-medium">
        {t("improve")}
        <textarea rows={3} maxLength={1000} value={improve} onChange={(e) => setImprove(e.target.value)} className={area} placeholder={t("improve_placeholder")} />
      </label>
      {save.error && <Notice tone="error">{save.error instanceof ApiError && save.error.message ? save.error.message : t("error")}</Notice>}
      {!complete && <p className="text-xs text-ink-muted">{t("rate_all")}</p>}
      <div className="flex gap-2">
        <Button type="submit" busy={save.isPending} disabled={!complete}>{mine ? t("update") : t("submit")}</Button>
        <Button type="button" variant="secondary" onClick={onDone}>{t("cancel")}</Button>
      </div>
    </form>
  );
}

function CritiqueItem({ c, photoId }: { c: Critique; photoId: string }) {
  const t = useTranslations("critique");
  const ts = useTranslations("specialties");
  const locale = useLocale();
  const qc = useQueryClient();
  const { data: me } = useMe();
  const helpful = useMutation({
    mutationFn: (on: boolean) => api(`critiques/${c.id}/helpful`, { method: on ? "POST" : "DELETE" }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["critiques", photoId] }),
  });
  const remove = useMutation({
    mutationFn: () => api(c.mine ? `photos/${photoId}/critiques/me` : `critiques/${c.id}`, { method: "DELETE" }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["critiques", photoId] });
      qc.invalidateQueries({ queryKey: ["photo", photoId] });
    },
  });
  const spec = c.author_specialties.slice(0, 2).map((s) => (ts.has(s) ? ts(s) : s)).join(", ");
  const on = c.helpful_by_me;
  return (
    <li className="flex flex-col gap-3 border-t border-line pt-4">
      <div className="flex items-center gap-2.5">
        <Link href={`/u/${c.user.username}`} className="flex min-w-0 flex-1 items-center gap-2.5">
          <Avatar name={c.user.display_name} url={c.user.avatar_url} size={34} />
          <span className="min-w-0">
            <span className="block truncate text-[14.5px] font-semibold">{c.user.display_name}</span>
            <span className="block truncate text-[12.5px] text-ink-muted">
              {spec ? `${spec} · ` : ""}{relativeTime(c.created_at, locale)}
            </span>
          </span>
        </Link>
        <button
          type="button"
          aria-pressed={on}
          disabled={!me || c.mine || helpful.isPending}
          onClick={() => helpful.mutate(!on)}
          className={clsx(
            "tnum inline-flex h-9 items-center gap-1.5 rounded-full px-3 text-[13px] font-semibold transition-colors disabled:cursor-default",
            on ? "bg-accent-tint text-accent-text" : "bg-surface-2 text-ink-muted enabled:hover:bg-line",
          )}
        >
          <ThumbsUp className="h-4 w-4" fill={on ? "currentColor" : "none"} aria-hidden />
          {t("helpful", { count: c.helpful_count })}
        </button>
      </div>
      <div className="flex flex-col gap-1.5">
        {CRITERIA.map((k) => <Bar key={k} label={t(`criteria.${k}`)} value={c[k]} />)}
      </div>
      {c.good && <p className="text-[14.5px] leading-snug"><span className="font-semibold">{t("good")}:</span> {c.good}</p>}
      {c.improve && <p className="text-[14.5px] leading-snug"><span className="font-semibold">{t("improve")}:</span> {c.improve}</p>}
      {c.can_delete && (
        <button
          type="button"
          className="self-start text-[13px] font-semibold text-ink-muted hover:text-danger"
          onClick={() => window.confirm(t("delete_confirm")) && remove.mutate()}
          disabled={remove.isPending}
        >
          {t("delete")}
        </button>
      )}
    </li>
  );
}

/** Fotoğraf detayında eleştiri bölümü: soru, ortalamalar, eleştiriler ve benimki. */
export function CritiqueSection({ photo }: { photo: PhotoDetail }) {
  const t = useTranslations("critique");
  const { data: me } = useMe();
  const [writing, setWriting] = useState(false);
  const show = !!photo.critique_requested || (photo.critique_count ?? 0) > 0;
  const q = useQuery({ queryKey: ["critiques", photo.id], enabled: show, queryFn: () => api<CritiqueList>(`photos/${photo.id}/critiques`) });
  if (!show) return null;
  const d = q.data;
  const isOwner = me?.id === photo.user.id;
  const first = photo.user.display_name.split(/\s+/)[0];

  return (
    <section aria-labelledby="critique-title" className="flex flex-col gap-4 border-t border-line pt-4">
      <div className="flex flex-wrap items-center gap-2">
        <h2 id="critique-title" className="flex items-center gap-2 text-[17px] font-bold">
          <MessageSquareQuote className="h-5 w-5" strokeWidth={1.8} aria-hidden /> {t("title")}
          {d && <span className="tnum text-[14px] font-semibold text-ink-muted">{d.count}</span>}
        </h2>
        {photo.critique_requested && (
          <span className="ml-auto rounded-full bg-accent-tint px-2.5 py-1 text-xs font-bold text-accent-text">{t("open_badge")}</span>
        )}
      </div>
      {photo.critique_requested && !isOwner && <p className="-mt-2 text-sm text-ink-muted">{t("wants", { name: first! })}</p>}
      {(d?.critique_question ?? photo.critique_question) && (
        <div className="rounded-box bg-surface-2 p-3.5">
          <p className="text-xs font-bold uppercase tracking-[0.06em] text-ink-muted">{t("question")}</p>
          <p className="mt-1 text-[14.5px] leading-snug">{d?.critique_question ?? photo.critique_question}</p>
        </div>
      )}
      {d && d.count > 0 && (
        <div className="flex flex-col gap-1.5">
          <div className="mb-1 flex items-baseline justify-between">
            <span className="text-[13px] font-semibold text-ink-muted">{t("averages")}</span>
            <span className="tnum text-[22px] font-bold">{d.averages.overall?.toFixed(1) ?? "—"}<span className="text-sm text-ink-muted">/5</span></span>
          </div>
          {CRITERIA.map((k) => <Bar key={k} label={t(`criteria.${k}`)} value={d.averages[k]} />)}
        </div>
      )}

      {d && !writing && d.can_critique && (
        <Button variant="secondary" className="self-start" onClick={() => setWriting(true)}>
          {d.my_critique ? t("edit_mine") : t("write")}
        </Button>
      )}
      {!me && photo.critique_requested && (
        <p className="text-sm text-ink-muted">
          <Link href="/login" className="font-semibold text-accent-text hover:underline">{t("login")}</Link>
        </p>
      )}
      {d && writing && <CritiqueForm photoId={photo.id} mine={d.my_critique} onDone={() => setWriting(false)} />}

      {d && d.items.length > 0 && (
        <ul className="flex flex-col gap-4">
          {d.items.map((c) => <CritiqueItem key={c.id} c={c} photoId={photo.id} />)}
        </ul>
      )}
      {d && d.count === 0 && <p className="text-sm text-ink-muted">{isOwner ? t("empty_owner") : t("empty")}</p>}
    </section>
  );
}
