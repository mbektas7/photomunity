"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import clsx from "clsx";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { useTranslations } from "next-intl";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { Notice } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import type { Contest, Entry } from "@/lib/types";

/** Jüri ekranı: kareler tek tek, büyük ve anonim. 1–9 tuşları puan verir, 0 = 10, oklar gezinir. */
export default function JuryPage() {
  const { id } = useParams<{ id: string }>();
  const t = useTranslations("jury");
  const qc = useQueryClient();
  const contest = useQuery({ queryKey: ["contest", id], queryFn: () => api<Contest>(`contests/${id}`) });
  const key = ["contest-entries", id, "jury"];
  const entries = useQuery({ queryKey: key, queryFn: () => api<Entry[]>(`contests/${id}/entries`) });
  const [i, setI] = useState(0);
  const list = entries.data ?? [];
  const current = list[i];

  const score = useMutation({
    mutationFn: ({ entry, value }: { entry: string; value: number }) => api(`contests/${id}/jury/scores/${entry}`, { method: "PUT", body: { score: value } }),
    onMutate: ({ entry, value }) => qc.setQueryData<Entry[]>(key, (l) => l?.map((e) => (e.id === entry ? { ...e, my_score: value } : e))),
    onError: () => qc.invalidateQueries({ queryKey: key }),
  });

  const give = useCallback((value: number) => {
    if (!current || current.mine) return;
    score.mutate({ entry: current.id, value });
    // Puan sonrası sıradaki puanlanmamış kareye geç
    const next = list.findIndex((e, j) => j > i && !e.my_score && !e.mine);
    setTimeout(() => setI(next >= 0 ? next : Math.min(i + 1, list.length - 1)), 180);
  }, [current, list, i, score]);

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;
      if (e.key === "ArrowRight") setI((x) => Math.min(x + 1, list.length - 1));
      else if (e.key === "ArrowLeft") setI((x) => Math.max(x - 1, 0));
      else if (/^[0-9]$/.test(e.key)) give(e.key === "0" ? 10 : Number(e.key));
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [list.length, give]);

  const c = contest.data;
  if (contest.error || entries.error) return <div className="mx-auto max-w-[680px] px-4 py-20"><Notice tone="error">{t("error")}</Notice></div>;
  if (!c || !entries.data) return <div className="h-[70vh]" aria-busy />;
  if (!c.is_judge) return <div className="mx-auto max-w-[680px] px-4 py-20"><Notice tone="error">{t("not_judge")}</Notice></div>;
  if (c.status !== "judging") return <div className="mx-auto max-w-[680px] px-4 py-20"><Notice>{t("not_open")}</Notice></div>;

  const scorable = list.filter((e) => !e.mine);
  const done = scorable.filter((e) => e.my_score).length;
  const img = current?.images.full ?? current?.images.feed;

  return (
    <div className="mx-auto max-w-[1400px] px-4 pt-6 sm:px-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <Link href={`/contests/${c.id}`} className="text-sm text-muted hover:text-ink">← {c.title}</Link>
        <span className="tnum text-sm font-medium">{t("progress", { done, total: scorable.length })}</span>
      </div>
      <div className="mt-2 h-1 bg-line"><div className="h-full bg-accent transition-[width]" style={{ width: `${scorable.length ? (done / scorable.length) * 100 : 0}%` }} /></div>

      {current && img && (
        <>
          <div className="relative mt-5 flex items-center justify-center bg-black">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img key={current.id} src={img.url} alt="" className="fade-in max-h-[calc(100dvh-17rem)] w-auto max-w-full object-contain" />
            <button type="button" onClick={() => setI((x) => Math.max(x - 1, 0))} disabled={i === 0} aria-label={t("prev")} className="absolute left-2 top-1/2 -translate-y-1/2 rounded-full bg-black/50 p-2 text-white disabled:opacity-0">
              <ChevronLeft className="h-6 w-6" />
            </button>
            <button type="button" onClick={() => setI((x) => Math.min(x + 1, list.length - 1))} disabled={i === list.length - 1} aria-label={t("next")} className="absolute right-2 top-1/2 -translate-y-1/2 rounded-full bg-black/50 p-2 text-white disabled:opacity-0">
              <ChevronRight className="h-6 w-6" />
            </button>
          </div>
          <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
            <span className="tnum text-sm text-muted">{t("position", { n: i + 1, total: list.length })}</span>
            {current.mine ? <span className="rounded-full bg-ink/[0.06] px-4 py-2.5 text-sm font-medium">{t("own_entry")}</span> : (
            <div role="radiogroup" aria-label={t("score")} className="grid grid-cols-10 gap-1">
              {Array.from({ length: 10 }, (_, k) => k + 1).map((v) => (
                <button
                  key={v}
                  type="button"
                  role="radio"
                  aria-checked={current.my_score === v}
                  onClick={() => give(v)}
                  className={clsx("tnum h-11 w-11 rounded-[10px] border text-[16px] font-semibold transition-colors sm:h-12 sm:w-12",
                    current.my_score === v ? "border-accent bg-accent text-accent-ink" : "border-line bg-mat hover:border-ink")}
                >
                  {v}
                </button>
              ))}
            </div>
            )}
          </div>
          <p className="mt-2 text-right text-xs text-muted">{t("keys")}</p>
        </>
      )}
      {score.error && <div className="mt-3"><Notice tone="error">{score.error instanceof ApiError ? score.error.message : t("error")}</Notice></div>}

      <div className="mt-6 flex gap-1.5 overflow-x-auto pb-2">
        {list.map((e, j) => (
          <button key={e.id} type="button" onClick={() => setI(j)} aria-label={t("position", { n: j + 1, total: list.length })}
            className={clsx("relative h-14 w-20 shrink-0 bg-ink/5", j === i && "outline outline-2 outline-offset-2 outline-ink")}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            {e.images.thumb && <img src={e.images.thumb.url} alt="" className={clsx("h-full w-full object-cover", !e.my_score && "opacity-60")} />}
            {e.my_score && <span className="tnum absolute bottom-0.5 right-0.5 rounded bg-black/70 px-1 text-[11px] font-semibold text-white">{e.my_score}</span>}
          </button>
        ))}
      </div>
    </div>
  );
}
