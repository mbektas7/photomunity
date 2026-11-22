"use client";

import { useQuery } from "@tanstack/react-query";
import clsx from "clsx";
import { Ban, Check, ExternalLink, EyeOff, Trash2 } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useState } from "react";
import { Avatar } from "@/components/Avatar";
import { ActionButton, Card, Chip, Empty, Failed, Loading, PageHeader, Pills, errorText, useAdminAction, useConfirm } from "@/components/admin";
import { Notice } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import type { ReportContent, ReportGroup } from "@/lib/admin-types";
import { api } from "@/lib/api";
import { relativeTime } from "@/lib/relative-time";

const REASONS = ["all", "nudity", "spam", "harassment", "copyright", "violence", "other"] as const;
type Action = "hide_photo" | "disable_user" | "dismiss" | "remove_content";
const TYPES = ["all", "photo", "user", "comment", "message"] as const;

/** Yorum ve mesaj şikâyetlerinde içerik önizlemesi; görseller kırpılmaz. */
function ContentPreview({ c, kind }: { c: ReportContent; kind: "comment" | "message" }) {
  const t = useTranslations("admin");
  const locale = useLocale();
  return (
    <div className="rounded-2xl bg-surface-2 p-3.5">
      <div className="mb-1.5 flex flex-wrap items-center gap-1.5 text-[12.5px] text-ink-muted">
        <Chip>{t(kind === "comment" ? "type_comment" : "type_message")}</Chip>
        {relativeTime(c.created_at, locale)}
        {c.removed && <Chip tone="warn">{t("content_removed")}</Chip>}
      </div>
      {c.image_url && (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={c.image_url} alt="" className="mb-2 block h-auto max-h-[50vh] w-auto max-w-full rounded-xl object-contain" />
      )}
      {c.gif_url && (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={c.gif_url} alt="GIF" className="mb-2 block h-auto max-h-[240px] w-auto max-w-full rounded-xl object-contain" />
      )}
      {c.body ? (
        <p className="whitespace-pre-line break-words text-[15px] leading-[22px]">{c.body}</p>
      ) : !c.image_url && !c.gif_url ? (
        <p className="text-[14px] italic text-ink-muted">{t("content_empty")}</p>
      ) : null}
      {kind === "comment" && c.photo_id && (
        <Link href={`/p/${c.photo_id}`} className="mt-2.5 inline-flex items-center gap-1.5 text-[13px] font-bold text-accent-text hover:underline">
          <ExternalLink className="h-3.5 w-3.5" />{t("open_photo")}
        </Link>
      )}
    </div>
  );
}

function contentLine(c: ReportContent | null, t: (k: string) => string) {
  if (!c) return "—";
  if (c.body) return `“${c.body}”`;
  if (c.image_url) return t("content_image");
  if (c.gif_url) return "GIF";
  return t("content_removed");
}

function isContent(g: ReportGroup) {
  return g.target_type === "comment" || g.target_type === "message";
}

export default function AdminReports() {
  const t = useTranslations("admin");
  const locale = useLocale();
  const [status, setStatus] = useState<"open" | "resolved" | "all">("open");
  const [type, setType] = useState<(typeof TYPES)[number]>("all");
  const [reason, setReason] = useState<(typeof REASONS)[number]>("all");
  const [picked, setPicked] = useState<string | null>(null);
  const [dialog, confirm] = useConfirm();

  const params = new URLSearchParams({ status });
  if (type !== "all") params.set("target_type", type);
  if (reason !== "all") params.set("reason", reason);
  const q = useQuery({ queryKey: ["admin", "reports", status, type, reason], queryFn: () => api<ReportGroup[]>(`admin/report-groups?${params}`) });
  const groups = q.data ?? [];
  const g = groups.find((x) => x.target_id === picked) ?? groups[0];
  const openCount = status === "open" ? groups.length : undefined;

  const resolve = useAdminAction((v: { g: ReportGroup; action: Action; note: string }) =>
    api("admin/report-groups/resolve", { method: "POST", body: { target_type: v.g.target_type, target_id: v.g.target_id, action: v.action, note: v.note || null } }),
    () => setPicked(null));

  async function decide(action: Action, label: string, danger = false) {
    if (!g) return;
    const r = await confirm({ title: label, body: t("decision_hint"), confirm: label, danger });
    if (r) resolve.mutate({ g, action, note: r.note });
  }

  return (
    <>
      {dialog}
      <PageHeader
        title={t("nav_reports")}
        sub={t("reports_sub")}
        right={<Pills value={status} onChange={(v) => { setStatus(v); setPicked(null); }} items={[
          { key: "open", label: openCount !== undefined ? `${t("tab_open")} ${openCount}` : t("tab_open") },
          { key: "resolved", label: t("tab_resolved") },
          { key: "all", label: t("tab_all") },
        ]} />}
      />
      <div className="mb-3.5 flex flex-wrap gap-2.5">
        <Pills value={type} onChange={setType} items={TYPES.map((k) => ({ key: k, label: t(`type_${k}` as "type_all") }))} />
        <div className="flex-1" />
        <Pills value={reason} onChange={setReason} items={REASONS.map((r) => ({ key: r, label: t(`reason_${r}` as "reason_all") }))} />
      </div>
      {q.error && <Failed error={q.error} />}
      {q.isLoading ? <Loading /> : groups.length === 0 ? <Card><Empty /></Card> : (
        <div className="flex flex-col items-start gap-3.5 lg:flex-row">
          <Card pad="p-3.5" className="w-full lg:w-[400px] lg:shrink-0">
            <div className="mb-2.5 flex items-center justify-between px-1">
              <h2 className="text-[16px] font-bold">{t("queue")}</h2>
              {status === "open" && <Chip tone="danger">{t("n_open", { n: groups.length })}</Chip>}
            </div>
            <ul className="flex flex-col gap-1">
              {groups.map((x) => {
                const on = x.target_id === g?.target_id;
                const thumb = x.photo?.images.thumb ?? x.photo?.images.feed;
                return (
                  <li key={x.target_id}>
                    <button type="button" onClick={() => setPicked(x.target_id)} aria-current={on}
                      className={clsx("flex w-full items-center gap-3 rounded-2xl p-3 text-left", on ? "bg-accent-tint outline outline-2 outline-accent" : "hover:bg-surface-2")}>
                      {thumb ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img src={thumb.url} alt="" className="h-[52px] w-[52px] shrink-0 rounded-xl object-cover" />
                      ) : x.owner ? <Avatar name={x.owner.display_name} url={x.owner.avatar_url} size={52} /> : null}
                      <span className="min-w-0 flex-1">
                        <span className="block truncate text-[14.5px] font-bold">
                          {x.photo ? `“${x.photo.title ?? "—"}”` : isContent(x) ? contentLine(x.content, t) : `@${x.owner?.username}`}
                        </span>
                        <span className="block truncate text-[12.5px] text-ink-muted">
                          {x.photo || isContent(x) ? `${isContent(x) ? `${t(`type_${x.target_type}` as "type_all")} · ` : ""}@${x.owner?.username ?? "—"}` : t("type_user")} · {relativeTime(x.first_at, locale)}
                        </span>
                        <span className="mt-1.5 flex flex-wrap gap-1.5">
                          {x.reasons.map((r) => <Chip key={r} tone="danger">{t(`reason_${r}` as "reason_all")}</Chip>)}
                          <Chip>{t("n_people", { n: x.reports.length })}</Chip>
                          {x.photo?.hidden && <Chip tone="warn">{t("auto_hidden")}</Chip>}
                          {x.content?.removed && <Chip tone="warn">{t("content_removed")}</Chip>}
                        </span>
                      </span>
                    </button>
                  </li>
                );
              })}
            </ul>
          </Card>

          {g && (
            <Card className="w-full min-w-0 flex-1">
              <div className="flex flex-col gap-5 md:flex-row">
                <div className="md:w-[340px] md:shrink-0">
                  {g.photo ? (
                    <div className="relative overflow-hidden rounded-2xl bg-[#0b0d12]">
                      {/* Şikâyet edilen fotoğraf kırpılmadan */}
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img src={(g.photo.images.feed ?? g.photo.images.full ?? g.photo.images.thumb)?.url} alt={g.photo.title ?? ""} className="block h-auto max-h-[60vh] w-full object-contain" />
                      {g.photo.hidden && <span className="absolute left-2.5 top-2.5"><Chip tone="warn">{t("auto_hidden")}</Chip></span>}
                    </div>
                  ) : isContent(g) ? (
                    g.content ? <ContentPreview c={g.content} kind={g.target_type as "comment" | "message"} /> : <Notice>{t("content_missing")}</Notice>
                  ) : g.owner && <Avatar name={g.owner.display_name} url={g.owner.avatar_url} size={96} />}
                  {g.owner && (
                    <div className="mt-3 flex items-center gap-2.5">
                      <Avatar name={g.owner.display_name} url={g.owner.avatar_url} size={34} />
                      <div className="min-w-0 flex-1">
                        <div className="truncate font-bold">{g.owner.display_name}</div>
                        <div className="truncate text-[12.5px] text-ink-muted">{t("owner_meta", { username: g.owner.username, photos: g.owner.photo_count, prior: g.owner_prior_reports })}</div>
                      </div>
                      <Link href={`/admin/users?user=${g.owner.id}`} className="inline-flex h-[34px] items-center gap-1.5 rounded-full border border-line px-3 text-[13px] font-bold hover:bg-surface-2">
                        <ExternalLink className="h-3.5 w-3.5" />{t("profile")}
                      </Link>
                    </div>
                  )}
                </div>
                <div className="min-w-0 flex-1">
                  <h2 className="text-[20px] font-bold">{g.photo ? `“${g.photo.title ?? "—"}”` : isContent(g) ? t(`type_${g.target_type}` as "type_all") : `@${g.owner?.username}`}</h2>
                  <p className="mt-0.5 text-[13px] text-ink-muted">
                    {g.photo
                      ? t("photo_meta", { when: relativeTime(g.photo.created_at, locale), n: g.reports.length })
                      : isContent(g)
                        ? t(g.target_type === "comment" ? "comment_meta" : "message_meta", { username: g.owner?.username ?? "—", n: g.reports.length })
                        : t("user_target_meta", { n: g.reports.length })}
                  </p>
                  <h3 className="mt-4 text-[13px] font-bold text-ink-muted">{t("reporters")}</h3>
                  <ul>
                    {g.reports.map((r) => (
                      <li key={r.id} className="flex items-center gap-2.5 border-b border-line py-2.5">
                        {r.reporter && <Avatar name={r.reporter.display_name} url={r.reporter.avatar_url} size={30} />}
                        <div className="min-w-0 flex-1 text-[13.5px]">
                          <b>{r.reporter?.display_name ?? "—"}</b> · {t(`reason_${r.reason}` as "reason_all")}
                          <div className="text-[12.5px] text-ink-muted">{r.note ? `“${r.note}”` : t("no_note")}</div>
                        </div>
                        <span className="text-xs text-ink-muted">{relativeTime(r.created_at, locale)}</span>
                      </li>
                    ))}
                  </ul>
                  {g.status === "open" ? (
                    <>
                      <h3 className="mt-5 text-[13px] font-bold text-ink-muted">{t("decision")}</h3>
                      <div className="mt-2 flex flex-wrap gap-2">
                        {isContent(g) && !g.content?.removed && (
                          <ActionButton tone="dark" icon={Trash2} disabled={resolve.isPending} onClick={() => decide("remove_content", t("act_remove_content"), true)}>{t("act_remove_content")}</ActionButton>
                        )}
                        {g.photo && <ActionButton tone="dark" icon={EyeOff} disabled={resolve.isPending} onClick={() => decide("hide_photo", t("act_hide_photo"))}>{t("act_hide_photo")}</ActionButton>}
                        <ActionButton tone="danger" icon={Ban} disabled={resolve.isPending} onClick={() => decide("disable_user", t("act_disable_user"), true)}>{t("act_disable_user")}</ActionButton>
                        <ActionButton icon={Check} disabled={resolve.isPending} onClick={() => decide("dismiss", g.photo ? t("act_dismiss_photo") : t("act_dismiss"))}>
                          {g.photo ? t("act_dismiss_photo") : t("act_dismiss")}
                        </ActionButton>
                      </div>
                      <p className="mt-2.5 text-[12.5px] text-ink-muted">{t("decision_hint")}</p>
                    </>
                  ) : (
                    <p className="mt-5"><Chip tone="ok">{t("resolved_as", { action: t(`a_report_${g.resolution ?? "dismiss"}` as "a_report_dismiss") })}</Chip></p>
                  )}
                  {resolve.error && <div className="mt-3"><Notice tone="error">{errorText(resolve.error, t("error"))}</Notice></div>}
                </div>
              </div>
            </Card>
          )}
        </div>
      )}
    </>
  );
}
