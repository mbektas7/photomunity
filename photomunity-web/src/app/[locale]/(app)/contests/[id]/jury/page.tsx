"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import clsx from "clsx";
import { Check, ChevronLeft, ChevronRight, EyeOff, Loader2, Lock, ScanSearch } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";
import { StageStepper, ZoomOverlay, exifTiles, isTypingTarget, largestImage, smallImage } from "@/components/contest-ui";
import { Notice } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import { useMe } from "@/lib/hooks";
import type { Contest, Entry } from "@/lib/types";
import { HowItWorks } from "@/components/intro";

const NOTE_MAX = 1000;

/**
 * Jüri ekranı (her iki temada koyu, odaklı): kareler tek tek, büyük ve anonim.
 * 1–9 tuşları puan verir, 0 = 10, ← → gezinir; not alanına yazarken kısayollar çalışmaz.
 */
export default function JuryPage() {
  const { id } = useParams<{ id: string }>();
  const t = useTranslations("jury");
  const contest = useQuery({ queryKey: ["contest", id], queryFn: () => api<Contest>(`contests/${id}`) });
  const entries = useQuery({ queryKey: ["contest-entries", id, "jury"], queryFn: () => api<Entry[]>(`contests/${id}/entries`) });

  const c = contest.data;
  if (contest.error || entries.error) return <Center><Notice tone="error">{t("error")}</Notice></Center>;
  if (!c || !entries.data) return <div className="h-[70vh]" aria-busy />;
  if (!c.is_judge) return <Center><Notice tone="error">{t("not_judge")}</Notice></Center>;
  if (c.status !== "judging") return <Center><Notice>{t("not_open")}</Notice></Center>;
  return <Jury c={c} list={entries.data} />;
}

function Center({ children }: { children: React.ReactNode }) {
  return <div className="mx-auto max-w-[680px] px-4 py-20">{children}</div>;
}

function Jury({ c, list }: { c: Contest; list: Entry[] }) {
  const t = useTranslations("jury");
  const locale = useLocale();
  const { data: me } = useMe();
  const qc = useQueryClient();
  const key = ["contest-entries", c.id, "jury"];
  const [i, setI] = useState(() => Math.max(0, list.findIndex((e) => !e.my_score && !e.mine)));
  const [zoom, setZoom] = useState(false);
  const current = list[i];

  // Not taslağı: kare değişince kayıtlı nota döner
  const [note, setNote] = useState(current?.my_note ?? "");
  const [savedFor, setSavedFor] = useState<string | null>(null);
  useEffect(() => {
    setNote(list[i]?.my_note ?? "");
    setSavedFor(null);
  }, [i]); // yalnızca kare değişince; arka plan yenilemesi yazılan notu silmesin
  const noteDirty = !!current && note !== (current.my_note ?? "");

  const save = useMutation({
    mutationFn: ({ entry, score, note }: { entry: string; score: number; note?: string }) =>
      api(`contests/${c.id}/jury/scores/${entry}`, { method: "PUT", body: note === undefined ? { score } : { score, note } }),
    onMutate: ({ entry, score, note }) => {
      qc.setQueryData<Entry[]>(key, (l) => l?.map((e) => (e.id === entry ? { ...e, my_score: score, ...(note !== undefined ? { my_note: note || null } : {}) } : e)));
    },
    onSuccess: (_d, v) => setSavedFor(v.entry),
    onError: () => qc.invalidateQueries({ queryKey: key }),
  });

  // Bir sonraki puanlanmamış kareye geç (yoksa sıradakine)
  const advance = useCallback(
    (from: number) => {
      const next = list.findIndex((e, j) => j > from && !e.my_score && !e.mine);
      setI(next >= 0 ? next : Math.min(from + 1, list.length - 1));
    },
    [list],
  );

  const give = useCallback(
    (value: number) => {
      if (!current || current.mine) return;
      save.mutate({ entry: current.id, score: value, ...(noteDirty ? { note: note.trim() } : {}) });
      const from = i;
      setTimeout(() => advance(from), 220);
    },
    [current, save, noteDirty, note, i, advance],
  );

  // Not alanından çıkınca, puan varsa notu kaydet
  const flushNote = () => {
    if (current && noteDirty && current.my_score) save.mutate({ entry: current.id, score: current.my_score, note: note.trim() });
  };

  const go = useCallback((d: number) => setI((x) => Math.min(Math.max(x + d, 0), list.length - 1)), [list.length]);

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (zoom || e.metaKey || e.ctrlKey || e.altKey || isTypingTarget(e.target)) return;
      if (e.key === "ArrowRight") go(1);
      else if (e.key === "ArrowLeft") go(-1);
      else if (/^[0-9]$/.test(e.key)) {
        e.preventDefault();
        give(e.key === "0" ? 10 : Number(e.key));
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [go, give, zoom]);

  // Tam ekran katman açıkken arkadaki sayfa kaymasın
  useEffect(() => {
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = prev;
    };
  }, []);

  // Film şeridinde seçili kare görünür kalsın
  const strip = useRef<HTMLDivElement>(null);
  useEffect(() => {
    strip.current?.querySelector<HTMLElement>(`[data-idx="${i}"]`)?.scrollIntoView({ block: "nearest", inline: "center", behavior: "smooth" });
  }, [i]);

  const scorable = list.filter((e) => !e.mine);
  const done = scorable.filter((e) => e.my_score).length;
  const pct = scorable.length ? Math.round((done / scorable.length) * 100) : 0;
  const img = current ? largestImage(current) : undefined;
  const tiles = exifTiles(current?.exif, locale, { camera: t("exif_camera"), lens: t("exif_lens"), exposure: t("exif_exposure"), iso: t("exif_iso") });

  const status = save.isPending
    ? { tone: "muted", text: t("saving") }
    : save.error
      ? { tone: "error", text: save.error instanceof ApiError && save.error.message ? save.error.message : t("save_error") }
      : current && savedFor === current.id
        ? { tone: "ok", text: t("saved_status", { done, left: scorable.length - done }) }
        : { tone: "muted", text: t("status_line", { done, left: scorable.length - done }) };

  return (
    <div className="fixed inset-0 z-40 flex flex-col bg-[#07080d] text-white">
      {/* Üst çubuk */}
      <header className="flex h-[64px] shrink-0 items-center gap-3 border-b border-white/[.08] px-4 sm:px-6 lg:h-[72px] lg:gap-[18px] lg:px-8">
        <Link href={`/contests/${c.id}`} aria-label={t("back")} className="inline-flex h-[38px] w-[38px] shrink-0 items-center justify-center rounded-full border border-white/15 hover:bg-white/10">
          <ChevronLeft className="h-[18px] w-[18px]" aria-hidden />
        </Link>
        <div className="min-w-0">
          <h1 className="truncate text-[16px] font-bold sm:text-[17px]">{c.title}</h1>
          <p className="truncate text-caption text-white/60">{me ? t("subtitle_named", { name: me.display_name }) : t("subtitle")}</p>
        </div>
        <HowItWorks module="jury" tone="dark" />
        <div className="hidden flex-1 justify-center xl:flex">
          <StageStepper status={c.status} tone="dark" />
        </div>
        <div className="ml-auto flex shrink-0 items-center gap-2.5 xl:ml-0">
          <span className="tnum text-[13.5px] text-white/75">{t("progress", { done, total: scorable.length })}</span>
          <div className="h-1.5 w-[72px] rounded-pill bg-white/[.12] sm:w-[140px]" role="progressbar" aria-valuenow={pct} aria-valuemin={0} aria-valuemax={100} aria-label={t("progress_label")}>
            <div className="h-full rounded-pill bg-accent transition-[width]" style={{ width: `${pct}%` }} />
          </div>
        </div>
      </header>

      <div className="flex min-h-0 flex-1 flex-col overflow-y-auto lg:flex-row lg:overflow-hidden">
        {/* Fotoğraf sahnesi */}
        <section aria-label={t("stage")} className="relative flex min-h-[56vh] flex-1 items-center justify-center overflow-hidden lg:min-h-0">
          {img && (
            <>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={img.url} alt="" aria-hidden className="absolute inset-0 h-full w-full scale-110 object-cover opacity-90" style={{ filter: "blur(60px) brightness(.35)" }} />
              <div className="absolute inset-x-4 inset-y-16 flex items-center justify-center sm:inset-x-20 sm:inset-y-[72px]">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  key={current!.id}
                  src={img.url}
                  alt={current!.title ?? t("entry_n", { n: current?.number ?? i + 1 })}
                  width={img.width}
                  height={img.height}
                  className="fade-in block h-auto max-h-full w-auto max-w-full rounded-[6px] object-contain shadow-[0_30px_80px_rgba(0,0,0,.6)]"
                />
              </div>
            </>
          )}
          <div className="absolute left-4 top-4 flex flex-wrap gap-2 sm:left-8 sm:top-[22px]">
            <span className="tnum rounded-pill bg-black/50 px-3 py-[7px] text-[13px] font-bold">{t("entry_n", { n: current?.number ?? i + 1 })}</span>
            {c.anonymous && (
              <span className="inline-flex items-center gap-1.5 rounded-pill bg-black/50 px-3 py-[7px] text-[13px]">
                <EyeOff className="h-3.5 w-3.5" aria-hidden /> {t("anonymous")}
              </span>
            )}
          </div>
          {img && (
            <button
              type="button"
              onClick={() => setZoom(true)}
              className="absolute right-4 top-4 inline-flex items-center gap-1.5 rounded-pill bg-black/50 px-3 py-[7px] text-[13px] hover:bg-black/70 sm:right-8 sm:top-[22px]"
            >
              <ScanSearch className="h-4 w-4" aria-hidden /> {t("zoom")}
            </button>
          )}
          <button type="button" onClick={() => go(-1)} disabled={i === 0} aria-label={t("prev")} className="absolute left-3 top-1/2 inline-flex h-[46px] w-[46px] -translate-y-1/2 items-center justify-center rounded-full bg-white/10 hover:bg-white/20 disabled:opacity-0 sm:left-6">
            <ChevronLeft className="h-6 w-6" aria-hidden />
          </button>
          <button type="button" onClick={() => go(1)} disabled={i === list.length - 1} aria-label={t("next")} className="absolute right-3 top-1/2 inline-flex h-[46px] w-[46px] -translate-y-1/2 items-center justify-center rounded-full bg-white/10 hover:bg-white/20 disabled:opacity-0 sm:right-6">
            <ChevronRight className="h-6 w-6" aria-hidden />
          </button>
          {list.length === 0 && <p className="relative text-white/70">{t("empty")}</p>}
        </section>

        {/* Puan paneli */}
        {current && (
          <aside aria-label={t("panel")} className="flex w-full shrink-0 flex-col gap-4 border-white/[.06] bg-[#10131c] p-5 lg:w-[360px] lg:overflow-y-auto lg:border-l lg:p-[22px]">
            <div>
              <p className="text-[12px] font-bold uppercase tracking-[.4px] text-white/55">{t("title_label")}</p>
              <p className="mt-0.5 text-[20px] font-bold leading-tight">{current.title || t("untitled")}</p>
            </div>
            {tiles.length > 0 && (
              <dl className="grid grid-cols-2 gap-2">
                {tiles.map((x) => (
                  <div key={x.label} className="flex min-w-0 flex-col-reverse rounded-[12px] bg-white/[.05] px-[11px] py-[9px]">
                    <dd className="truncate text-[14px] font-bold" title={x.value}>{x.value}</dd>
                    <dt className="text-[11.5px] text-white/55">{x.label}</dt>
                  </div>
                ))}
              </dl>
            )}

            {current.mine ? (
              <p className="rounded-[14px] bg-white/[.05] px-4 py-3 text-[14px]">{t("own_entry")}</p>
            ) : (
              <div>
                <div className="flex items-baseline justify-between">
                  <p id="score-label" className="text-[12px] font-bold uppercase tracking-[.4px] text-white/55">{t("your_score")}</p>
                  <p className="tnum text-[44px] font-bold leading-none" aria-live="polite">
                    {current.my_score ?? "–"}
                    <span className="text-[18px] text-white/50">/10</span>
                  </p>
                </div>
                <div role="radiogroup" aria-labelledby="score-label" className="mt-2.5 grid grid-cols-5 gap-1.5">
                  {Array.from({ length: 10 }, (_, k) => k + 1).map((v) => (
                    <button
                      key={v}
                      type="button"
                      role="radio"
                      aria-checked={current.my_score === v}
                      aria-label={t("score_n", { n: v })}
                      onClick={() => give(v)}
                      className={clsx(
                        "tnum h-[54px] rounded-[14px] border text-[20px] font-bold transition-colors",
                        current.my_score === v ? "border-transparent bg-accent text-accent-ink" : "border-white/10 bg-white/[.07] hover:bg-white/[.14]",
                      )}
                    >
                      {v}
                    </button>
                  ))}
                </div>
                <p className="mt-2 text-[12px] text-white/55">{t("keys")}</p>
              </div>
            )}

            {!current.mine && (
              <div className="flex flex-col gap-1.5 rounded-[14px] bg-white/[.05] p-3">
                <label htmlFor="jury-note" className="flex items-center gap-1.5 text-[12px] font-bold text-white/70">
                  <Lock className="h-3.5 w-3.5" aria-hidden /> {t("note_label")}
                </label>
                <textarea
                  id="jury-note"
                  value={note}
                  maxLength={NOTE_MAX}
                  rows={3}
                  onChange={(e) => setNote(e.target.value)}
                  onBlur={flushNote}
                  placeholder={current.my_score ? t("note_placeholder") : t("note_needs_score")}
                  aria-describedby="jury-note-hint"
                  className="resize-none bg-transparent text-[13.5px] leading-relaxed text-white/90 outline-none placeholder:text-white/35"
                />
                <p id="jury-note-hint" className="tnum flex justify-between text-[11px] text-white/45">
                  <span>{noteDirty ? (current.my_score ? t("note_unsaved") : t("note_saves_with_score")) : ""}</span>
                  <span>{note.length}/{NOTE_MAX}</span>
                </p>
              </div>
            )}

            <p
              role="status"
              className={clsx(
                "mt-auto flex items-center gap-2 text-[13px]",
                status.tone === "ok" && "text-[#7fe0c0]",
                status.tone === "error" && "text-[#ff8a80]",
                status.tone === "muted" && "text-white/60",
              )}
            >
              {save.isPending ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden /> : status.tone === "ok" ? <Check className="h-4 w-4" aria-hidden /> : null}
              {status.text}
            </p>
          </aside>
        )}
      </div>

      {/* Film şeridi */}
      <nav aria-label={t("filmstrip")} className="h-[76px] shrink-0 border-t border-white/[.06] bg-[#0b0d14] lg:h-[84px]">
        <div ref={strip} className="no-scrollbar flex h-full items-center gap-2.5 overflow-x-auto px-4 sm:px-8">
          {list.map((e, j) => {
            const th = smallImage(e);
            return (
              <button
                key={e.id}
                type="button"
                data-idx={j}
                onClick={() => setI(j)}
                aria-current={j === i ? "true" : undefined}
                aria-label={[t("entry_n", { n: j + 1 }), e.my_score ? t("score_n", { n: e.my_score }) : e.mine ? t("own_short") : t("unscored")].join(", ")}
                className={clsx(
                  "relative h-[54px] w-[78px] shrink-0 overflow-hidden rounded-[8px] bg-black transition-opacity",
                  j === i ? "opacity-100 outline outline-2 outline-offset-2 outline-white" : "opacity-55 hover:opacity-90",
                )}
              >
                {th && (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={th.url} alt="" loading="lazy" className="h-full w-full object-contain" />
                )}
                {e.my_score ? (
                  <span className="tnum absolute bottom-[3px] right-1 rounded-[6px] bg-black/60 px-[5px] py-px text-[10.5px] font-bold">{e.my_score}</span>
                ) : null}
              </button>
            );
          })}
        </div>
      </nav>

      {zoom && img && current && <ZoomOverlay img={img} alt={current.title ?? ""} onClose={() => setZoom(false)} />}
    </div>
  );
}
