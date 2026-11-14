"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Ban, X } from "lucide-react";
import { useTranslations } from "next-intl";
import { useParams, useSearchParams } from "next/navigation";
import { Suspense, useState } from "react";
import { Avatar } from "@/components/Avatar";
import { ContestTimeline, StatusBadge } from "@/components/community";
import { ContestForm, type ContestBody } from "@/components/ContestForm";
import { Button, Notice, TextField, buttonClass } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import type { Contest, ContestSummary, Entry, Judge, ResultRow } from "@/lib/types";

export default function ManageContestPage() {
  return (
    <Suspense>
      <Manage />
    </Suspense>
  );
}

function errorText(e: unknown, fallback: string) {
  return e instanceof ApiError && e.message ? e.message : fallback;
}

function Section({ title, lead, children }: { title: string; lead?: string; children: React.ReactNode }) {
  return (
    <section className="mt-12 border-t border-line pt-8">
      <h2 className="text-xl font-semibold tracking-[-0.02em]">{title}</h2>
      {lead && <p className="mt-1 max-w-[64ch] text-[15px] text-muted">{lead}</p>}
      <div className="mt-6">{children}</div>
    </section>
  );
}

function Manage() {
  const { id } = useParams<{ id: string }>();
  const t = useTranslations("manage");
  const tf = useTranslations("contestForm");
  const created = useSearchParams().get("created");
  const qc = useQueryClient();
  const q = useQuery({ queryKey: ["contest", id], queryFn: () => api<Contest>(`contests/${id}`) });
  const save = useMutation({
    mutationFn: (b: Partial<ContestBody>) => api<Contest>(`contests/${id}`, { method: "PATCH", body: b }),
    onSuccess: (c) => qc.setQueryData(["contest", id], c),
  });
  const publish = useMutation({
    mutationFn: () => api<Contest>(`contests/${id}/publish`, { method: "POST" }),
    onSuccess: (c) => qc.setQueryData(["contest", id], c),
  });

  const c = q.data;
  if (q.error) return <div className="mx-auto max-w-[680px] px-4 py-20"><Notice tone="error">{errorText(q.error, t("error"))}</Notice></div>;
  if (!c) return <div className="h-[60vh]" aria-busy />;
  if (c.my_role !== "admin") return <div className="mx-auto max-w-[680px] px-4 py-20"><Notice tone="error">{t("forbidden")}</Notice></div>;
  const draft = c.status === "draft";

  return (
    <div className="mx-auto max-w-[860px] px-4 pt-8 sm:px-6 sm:pt-12">
      <Link href={`/contests/${c.id}`} className="text-sm text-muted hover:text-ink">← {t("view_public")}</Link>
      <div className="mt-4 flex flex-wrap items-center gap-3">
        <StatusBadge status={c.status} />
        <span className="text-sm text-muted">{c.community.name}</span>
      </div>
      <h1 className="mt-2 text-[clamp(1.9rem,4.5vw,2.8rem)] font-bold leading-[1.02] tracking-[-0.04em]">{c.title}</h1>
      {created && <div className="mt-6"><Notice tone="success">{t("created")}</Notice></div>}
      <div className="mt-6"><ContestTimeline c={c} /></div>

      {draft && (
        <div className="mt-8 bg-mat px-5 py-5">
          <p className="font-semibold">{t("publish_title")}</p>
          <p className="mt-1 text-[15px] text-muted">{c.judging_mode === "jury" ? t("publish_body_jury") : t("publish_body")}</p>
          {publish.error && <div className="mt-3"><Notice tone="error">{errorText(publish.error, t("error"))}</Notice></div>}
          <Button className="mt-4" busy={publish.isPending} onClick={() => window.confirm(t("publish_confirm")) && publish.mutate()}>{t("publish")}</Button>
        </div>
      )}

      {c.status !== "draft" && <Summary c={c} />}
      {c.judging_mode === "jury" && <Judges c={c} />}
      {c.status !== "draft" && <Entries c={c} />}
      {(c.status === "judging" || c.status === "closed") && <Preview c={c} />}

      <Section title={t("details")} lead={draft ? undefined : t("details_locked")}>
        <ContestForm
          key={c.id + String(draft)}
          initial={c}
          locked={!draft}
          busy={save.isPending}
          error={save.error ? errorText(save.error, t("error")) : null}
          submitLabel={tf("save")}
          onSubmit={(b) => save.mutate(draft ? b : { title: b.title, description: b.description, rules: b.rules, ...(c.status === "open" ? { prizes: b.prizes } : {}) })}
        />
        {save.isSuccess && <div className="mt-4"><Notice tone="success">{t("saved")}</Notice></div>}
      </Section>
    </div>
  );
}

function Summary({ c }: { c: Contest }) {
  const t = useTranslations("manage");
  const q = useQuery({ queryKey: ["contest-summary", c.id], queryFn: () => api<ContestSummary>(`contests/${c.id}/summary`), refetchInterval: 30_000 });
  if (!q.data) return null;
  const s = q.data;
  const stats = [
    { n: s.entries - s.disqualified, label: t("stat_entries") },
    ...(c.judging_mode === "public" ? [{ n: s.voters, label: t("stat_voters") }, { n: s.votes, label: t("stat_votes") }] : []),
  ];
  return (
    <Section title={t("summary")}>
      <dl className="grid grid-cols-3 gap-px bg-line">
        {stats.map((x) => (
          <div key={x.label} className="flex flex-col-reverse bg-mat px-4 py-4">
            <dt className="text-sm text-muted">{x.label}</dt>
            <dd className="tnum text-[28px] font-semibold leading-none">{x.n}</dd>
          </div>
        ))}
      </dl>
      {s.suspicious_ips > 0 && <div className="mt-4"><Notice tone="error">{t("suspicious", { count: s.suspicious_ips })}</Notice></div>}
    </Section>
  );
}

function Judges({ c }: { c: Contest }) {
  const t = useTranslations("manage");
  const qc = useQueryClient();
  const key = ["contest-judges", c.id];
  const q = useQuery({ queryKey: key, queryFn: () => api<Judge[]>(`contests/${c.id}/judges`) });
  const [who, setWho] = useState("");
  const [weight, setWeight] = useState("1");
  const locked = c.status === "closed" || c.status === "finished";
  const set = (data: Judge[]) => qc.setQueryData(key, data);
  const add = useMutation({
    mutationFn: () => {
      const v = who.trim();
      const body = v.includes("@") && !v.startsWith("@") ? { email: v, weight: Number(weight) } : { username: v.replace(/^@/, ""), weight: Number(weight) };
      return api<Judge[]>(`contests/${c.id}/judges`, { method: "POST", body });
    },
    onSuccess: (d) => { set(d); setWho(""); setWeight("1"); },
  });
  const update = useMutation({ mutationFn: ({ id, w }: { id: string; w: number }) => api<Judge[]>(`contests/${c.id}/judges/${id}`, { method: "PATCH", body: { weight: w } }), onSuccess: set });
  const remove = useMutation({ mutationFn: (id: string) => api(`contests/${c.id}/judges/${id}`, { method: "DELETE" }), onSuccess: () => qc.invalidateQueries({ queryKey: key }) });
  const judges = q.data ?? [];
  const total = judges.reduce((s, j) => s + (j.pending ? 0 : j.weight), 0);

  return (
    <Section title={t("judges")} lead={t("judges_lead")}>
      {judges.length > 0 && (
        <ul className="divide-y divide-line border-y border-line">
          {judges.map((j) => (
            <li key={j.id} className="flex flex-wrap items-center gap-3 py-3">
              {j.user ? <Avatar name={j.user.display_name} url={j.user.avatar_url} size={36} /> : <span className="h-9 w-9 rounded-full border border-dashed border-line" />}
              <span className="min-w-0 flex-1">
                <span className="block truncate font-medium">{j.user ? j.user.display_name : j.email}</span>
                <span className="block text-sm text-muted">{j.pending ? t("invite_pending") : t("scored", { count: j.scored })}</span>
              </span>
              <label className="flex items-center gap-2 text-sm text-muted">
                {t("weight")}
                <input
                  type="number" min={0.1} max={10} step={0.5} defaultValue={j.weight} disabled={locked}
                  onBlur={(e) => Number(e.target.value) !== j.weight && update.mutate({ id: j.id, w: Number(e.target.value) })}
                  className="tnum h-9 w-20 rounded-[8px] border border-line bg-mat px-2 text-ink"
                />
              </label>
              <span className="tnum w-14 text-right text-sm text-muted">{!j.pending && total ? `%${Math.round((j.weight / total) * 100)}` : ""}</span>
              {!locked && (
                <button type="button" onClick={() => remove.mutate(j.id)} className="rounded-full p-2 text-muted hover:bg-ink/5" aria-label={t("remove_judge")}>
                  <X className="h-4 w-4" />
                </button>
              )}
            </li>
          ))}
        </ul>
      )}
      {!locked && (
        <form className="mt-5 flex flex-wrap items-end gap-3" onSubmit={(e) => { e.preventDefault(); add.mutate(); }}>
          <TextField label={t("judge_who")} name="judge" placeholder={t("judge_placeholder")} required value={who} onChange={(e) => setWho(e.target.value)} className="min-w-[240px] flex-1" />
          <TextField label={t("weight")} name="weight" type="number" min={0.1} max={10} step={0.5} value={weight} onChange={(e) => setWeight(e.target.value)} className="w-24" />
          <Button type="submit" variant="secondary" busy={add.isPending}>{t("add_judge")}</Button>
        </form>
      )}
      {add.error && <div className="mt-3"><Notice tone="error">{errorText(add.error, t("error"))}</Notice></div>}
      <p className="mt-4 text-sm text-muted">{t("weight_hint")}</p>
    </Section>
  );
}

function Entries({ c }: { c: Contest }) {
  const t = useTranslations("manage");
  const qc = useQueryClient();
  const key = ["contest-entries", c.id, "admin"];
  const q = useQuery({ queryKey: key, queryFn: () => api<Entry[]>(`contests/${c.id}/entries?view=admin`) });
  const dq = useMutation({
    mutationFn: ({ id, reason }: { id: string; reason: string }) => api(`contests/${c.id}/entries/${id}/disqualify`, { method: "POST", body: { reason } }),
    onSuccess: () => { qc.invalidateQueries({ queryKey: key }); qc.invalidateQueries({ queryKey: ["contest-summary", c.id] }); },
  });
  const list = q.data ?? [];
  return (
    <Section title={t("entries", { count: list.filter((e) => !e.disqualified).length })} lead={c.status === "open" ? t("entries_private") : undefined}>
      {list.length === 0 && <p className="text-muted">{t("no_entries")}</p>}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        {list.map((e) => (
          <figure key={e.id} className={e.disqualified ? "opacity-40" : undefined}>
            {e.images.thumb && (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={e.images.thumb.url} alt={e.title ?? ""} className="aspect-[4/3] w-full bg-ink/5 object-contain" />
            )}
            <figcaption className="mt-1.5 flex items-center justify-between gap-2 text-sm">
              <span className="min-w-0 truncate">{e.user?.display_name}</span>
              {e.disqualified ? (
                <span className="shrink-0 text-xs text-danger">{t("disqualified")}</span>
              ) : c.status !== "finished" ? (
                <button
                  type="button"
                  className="shrink-0 rounded-full p-1.5 text-muted hover:bg-ink/5 hover:text-danger"
                  aria-label={t("disqualify")}
                  title={t("disqualify")}
                  onClick={() => { const reason = window.prompt(t("disqualify_reason")); if (reason?.trim()) dq.mutate({ id: e.id, reason: reason.trim() }); }}
                >
                  <Ban className="h-4 w-4" />
                </button>
              ) : null}
            </figcaption>
          </figure>
        ))}
      </div>
    </Section>
  );
}

function Preview({ c }: { c: Contest }) {
  const t = useTranslations("manage");
  const q = useQuery({ queryKey: ["contest-preview", c.id], queryFn: () => api<ResultRow[]>(`contests/${c.id}/results`), refetchInterval: 30_000 });
  return (
    <Section title={t("preview")} lead={t("preview_lead")}>
      <ol className="divide-y divide-line border-y border-line">
        {q.data?.map((r) => (
          <li key={r.entry.id} className="flex items-center gap-4 py-2.5">
            <span className="tnum w-8 text-right text-lg font-semibold">{r.rank ?? "–"}</span>
            {r.entry.images.thumb && (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={r.entry.images.thumb.url} alt="" className="h-12 w-16 bg-ink/5 object-contain" />
            )}
            <span className="min-w-0 flex-1 truncate">{r.entry.user?.display_name}</span>
            <span className="tnum text-sm text-muted">{r.score !== null ? r.score.toFixed(2) : "–"} · {c.judging_mode === "jury" ? t("judges_count", { count: r.count }) : t("votes_count", { count: r.count })}</span>
          </li>
        ))}
      </ol>
      <Link href={`/contests/${c.id}`} className={buttonClass("ghost", "mt-4 -ml-4")}>{t("view_public")}</Link>
    </Section>
  );
}
