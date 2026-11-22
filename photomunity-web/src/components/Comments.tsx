"use client";

import { type InfiniteData, useInfiniteQuery, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import clsx from "clsx";
import { MoreHorizontal, Quote, Reply, SendHorizontal, X } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useEffect, useRef, useState } from "react";
import { Link } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import { useMe } from "@/lib/hooks";
import { relativeTime } from "@/lib/relative-time";
import type { CommentPage, CommentPolicy, PhotoComment, PhotoDetail } from "@/lib/types";
import { Avatar } from "./Avatar";
import { ReportDialog } from "./ReportDialog";
import { Notice } from "./ui";

const POLICIES: CommentPolicy[] = ["everyone", "followers", "off"];

/** Yükleme ve düzenleme formlarında yorum ayarı seçimi. */
export function CommentPolicyField({ value, onChange }: { value: CommentPolicy; onChange: (v: CommentPolicy) => void }) {
  const t = useTranslations("comments");
  return (
    <fieldset className="flex flex-col gap-1.5">
      <legend className="mb-1.5 text-sm font-medium">{t("policy")}</legend>
      {POLICIES.map((p) => (
        <label key={p} className={clsx("flex cursor-pointer items-start gap-3 rounded-box px-3 py-2.5 hover:bg-surface-2", value === p && "bg-surface-2")}>
          <input type="radio" name="comment_policy" value={p} checked={value === p} onChange={() => onChange(p)} className="mt-1 accent-[var(--accent)]" />
          <span className="min-w-0">
            <span className="block text-[15px] font-medium">{t(`policy_${p}`)}</span>
            <span className="block text-[13px] text-ink-muted">{t(`policy_${p}_hint`)}</span>
          </span>
        </label>
      ))}
    </fieldset>
  );
}

type Target = { comment: PhotoComment; topId: string };

export function Comments({ photo }: { photo: PhotoDetail }) {
  const t = useTranslations("comments");
  const qc = useQueryClient();
  const { data: me } = useMe();
  const key = ["comments", photo.id];
  const [text, setText] = useState("");
  const [replyTo, setReplyTo] = useState<Target | null>(null);
  const [quoting, setQuoting] = useState<PhotoComment | null>(null);
  const [open, setOpen] = useState<Set<string>>(new Set());
  const input = useRef<HTMLTextAreaElement>(null);
  const off = photo.comment_policy === "off";

  const q = useInfiniteQuery({
    queryKey: key,
    enabled: !off,
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) => api<CommentPage>(`photos/${photo.id}/comments${pageParam ? `?before=${encodeURIComponent(pageParam)}` : ""}`),
    getNextPageParam: (last) => last.next_cursor,
  });
  const items = q.data?.pages.flatMap((p) => p.items) ?? [];
  const total = q.data?.pages[0]?.total ?? photo.comment_count;

  function refresh(topId?: string) {
    qc.invalidateQueries({ queryKey: key });
    if (topId) qc.invalidateQueries({ queryKey: ["comment-replies", topId] });
    qc.invalidateQueries({ queryKey: ["photo", photo.id] });
  }

  const post = useMutation({
    mutationFn: () =>
      api<PhotoComment>(`photos/${photo.id}/comments`, {
        method: "POST",
        body: { body: text.trim(), parent_id: replyTo?.comment.id ?? null, quote_id: quoting?.id ?? null },
      }),
    onSuccess: (c) => {
      const topId = c.parent_id ?? undefined;
      if (topId) setOpen((s) => new Set(s).add(topId));
      else
        qc.setQueryData<InfiniteData<CommentPage>>(key, (data) => {
          if (!data) return data;
          const [first, ...rest] = data.pages;
          return { ...data, pages: [{ ...first!, items: [c, ...first!.items], total: first!.total + 1 }, ...rest] };
        });
      setText("");
      setReplyTo(null);
      setQuoting(null);
      refresh(topId);
    },
  });

  function startReply(c: PhotoComment, topId: string) {
    setReplyTo({ comment: c, topId });
    input.current?.focus();
  }
  function startQuote(c: PhotoComment) {
    setQuoting(c);
    input.current?.focus();
  }

  const actions = { onReply: startReply, onQuote: startQuote, onDeleted: refresh, canAct: photo.can_comment };

  return (
    <section aria-labelledby="comments" className="flex flex-col gap-3 border-t border-line pt-4">
      <h2 id="comments" className="text-[17px] font-bold tracking-[-0.01em]">
        {t("title")}
        {!off && total > 0 && <span className="tnum ml-1.5 font-semibold text-ink-muted">{total}</span>}
      </h2>

      {off ? (
        <p className="text-[14.5px] text-ink-muted">{t("off")}</p>
      ) : (
        <>
          {photo.can_comment ? (
            <form
              className="flex flex-col gap-2"
              onSubmit={(e) => {
                e.preventDefault();
                if (text.trim()) post.mutate();
              }}
            >
              {(replyTo || quoting) && (
                <div className="flex flex-wrap gap-1.5">
                  {replyTo && (
                    <TargetChip label={t("replying_to", { name: replyTo.comment.user.display_name })} onClear={() => setReplyTo(null)} clearLabel={t("cancel_reply")} />
                  )}
                  {quoting && <TargetChip label={t("quoting", { name: quoting.user.display_name })} onClear={() => setQuoting(null)} clearLabel={t("cancel_quote")} />}
                </div>
              )}
              <div className="flex items-end gap-2">
                <textarea
                  ref={input}
                  value={text}
                  onChange={(e) => setText(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) {
                      e.preventDefault();
                      if (text.trim() && !post.isPending) post.mutate();
                    }
                  }}
                  rows={1}
                  maxLength={2000}
                  placeholder={t("placeholder")}
                  aria-label={t("placeholder")}
                  className="max-h-40 min-h-11 flex-1 resize-none rounded-[22px] border border-transparent bg-surface-2 px-4 py-2.5 text-[15px] leading-snug outline-none [field-sizing:content] focus:border-accent"
                />
                <button
                  type="submit"
                  disabled={!text.trim() || post.isPending}
                  aria-label={t("send")}
                  className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-accent text-accent-ink transition-opacity disabled:opacity-40"
                >
                  <SendHorizontal className="h-[18px] w-[18px]" />
                </button>
              </div>
              {post.error && <Notice tone="error">{post.error instanceof ApiError && post.error.message ? post.error.message : t("error")}</Notice>}
            </form>
          ) : !me ? (
            <p className="text-[14.5px] text-ink-muted">
              <Link href="/login" className="font-semibold text-accent-text hover:underline">
                {t("sign_in")}
              </Link>{" "}
              {t("sign_in_hint")}
            </p>
          ) : photo.comment_policy === "followers" ? (
            <p className="text-[14.5px] text-ink-muted">{t("followers_only")}</p>
          ) : (
            <p className="text-[14.5px] text-ink-muted">{t("not_allowed")}</p>
          )}

          {q.isSuccess && items.length === 0 && photo.can_comment && <p className="text-[14.5px] text-ink-muted">{t("empty")}</p>}
          {q.error && <Notice tone="error">{q.error instanceof ApiError && q.error.message ? q.error.message : t("load_error")}</Notice>}

          <ul className="flex flex-col gap-4">
            {items.map((c) => (
              <li key={c.id}>
                <CommentItem c={c} topId={c.id} {...actions} />
                {c.reply_count > 0 && (
                  <Replies
                    parent={c}
                    open={open.has(c.id)}
                    onToggle={() =>
                      setOpen((s) => {
                        const n = new Set(s);
                        if (n.has(c.id)) n.delete(c.id);
                        else n.add(c.id);
                        return n;
                      })
                    }
                    {...actions}
                  />
                )}
              </li>
            ))}
          </ul>
          {q.hasNextPage && (
            <button
              type="button"
              onClick={() => q.fetchNextPage()}
              disabled={q.isFetchingNextPage}
              className="inline-flex min-h-11 items-center self-start rounded-box text-[14.5px] font-semibold text-accent-text hover:underline disabled:opacity-50"
            >
              {t("more")}
            </button>
          )}
        </>
      )}
    </section>
  );
}

function TargetChip({ label, onClear, clearLabel }: { label: string; onClear: () => void; clearLabel: string }) {
  return (
    <span className="inline-flex max-w-full items-center gap-1 rounded-pill bg-accent-tint py-1 pl-3 pr-1 text-[13px] font-medium text-accent-text">
      <span className="truncate">{label}</span>
      <button type="button" onClick={onClear} aria-label={clearLabel} className="inline-flex h-6 w-6 shrink-0 items-center justify-center rounded-full hover:bg-black/10">
        <X className="h-3.5 w-3.5" />
      </button>
    </span>
  );
}

type Actions = {
  onReply: (c: PhotoComment, topId: string) => void;
  onQuote: (c: PhotoComment) => void;
  onDeleted: (topId?: string) => void;
  canAct: boolean;
};

function Replies({ parent, open, onToggle, ...actions }: { parent: PhotoComment; open: boolean; onToggle: () => void } & Actions) {
  const t = useTranslations("comments");
  const q = useQuery({
    queryKey: ["comment-replies", parent.id],
    enabled: open,
    queryFn: () => api<PhotoComment[]>(`comments/${parent.id}/replies`),
  });
  return (
    <div className="ml-11 mt-2">
      <button type="button" onClick={onToggle} aria-expanded={open} className="inline-flex min-h-8 items-center gap-2 text-[13.5px] font-semibold text-ink-muted hover:text-ink">
        <span aria-hidden className="h-px w-6 bg-line" />
        {open ? t("hide_replies") : t("show_replies", { count: parent.reply_count })}
      </button>
      {open && (
        <ul className="mt-2 flex flex-col gap-3.5">
          {q.data?.map((r) => (
            <li key={r.id}>
              <CommentItem c={r} topId={parent.id} small {...actions} />
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function CommentItem({ c, topId, small, onReply, onQuote, onDeleted, canAct }: { c: PhotoComment; topId: string; small?: boolean } & Actions) {
  const t = useTranslations("comments");
  const locale = useLocale();
  const { data: me } = useMe();
  const [menu, setMenu] = useState(false);
  const [report, setReport] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);
  const mine = me?.id === c.user.id;

  useEffect(() => {
    if (!menu) return;
    const close = (e: MouseEvent) => !menuRef.current?.contains(e.target as Node) && setMenu(false);
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, [menu]);

  const remove = useMutation({
    mutationFn: () => api(`comments/${c.id}`, { method: "DELETE" }),
    onSuccess: () => onDeleted(c.parent_id ? topId : undefined),
  });

  const showMenu = c.can_delete || (me && !mine);

  return (
    <div className={clsx("flex gap-2.5", remove.isPending && "opacity-50")}>
      <Link href={`/u/${c.user.username}`} className="shrink-0">
        <Avatar name={c.user.display_name} url={c.user.avatar_url} size={small ? 28 : 34} />
      </Link>
      <div className="min-w-0 flex-1">
        <p className="flex flex-wrap items-center gap-x-1.5 text-[13.5px]">
          <Link href={`/u/${c.user.username}`} className="font-semibold hover:underline">
            {c.user.display_name}
          </Link>
          {c.by_photo_owner && <span className="rounded-pill bg-accent-tint px-2 py-px text-[11.5px] font-semibold text-accent-text">{t("photographer")}</span>}
          <span className="text-ink-muted">{relativeTime(c.created_at, locale)}</span>
        </p>
        {c.quote && (
          <blockquote className="mt-1 rounded-box border-l-[3px] border-line bg-surface-2 px-3 py-1.5 text-[13.5px]">
            <span className="block font-semibold">{c.quote.user.display_name}</span>
            {c.quote.body === null ? <span className="italic text-ink-muted">{t("quote_deleted")}</span> : <span className="line-clamp-3 whitespace-pre-line text-ink-muted">{c.quote.body}</span>}
          </blockquote>
        )}
        <p className="mt-0.5 whitespace-pre-line break-words text-[15px] leading-[22px]">{c.body}</p>
        <div className="-ml-1.5 mt-0.5 flex items-center gap-0.5">
          {canAct && (
            <>
              <button type="button" onClick={() => onReply(c, topId)} className="inline-flex min-h-8 items-center gap-1 rounded-box px-1.5 text-[13px] font-semibold text-ink-muted hover:text-ink">
                <Reply className="h-3.5 w-3.5" aria-hidden /> {t("reply")}
              </button>
              <button type="button" onClick={() => onQuote(c)} className="inline-flex min-h-8 items-center gap-1 rounded-box px-1.5 text-[13px] font-semibold text-ink-muted hover:text-ink">
                <Quote className="h-3.5 w-3.5" aria-hidden /> {t("quote")}
              </button>
            </>
          )}
          {showMenu && (
            <div ref={menuRef} className="relative">
              <button type="button" onClick={() => setMenu((x) => !x)} aria-label={t("more_actions")} aria-expanded={menu}
                className="inline-flex h-8 w-8 items-center justify-center rounded-full text-ink-muted hover:bg-surface-2 hover:text-ink">
                <MoreHorizontal className="h-4 w-4" />
              </button>
              {menu && (
                <div className="absolute left-0 top-8 z-20 w-44 rounded-box bg-surface p-1.5 shadow-float">
                  {me && !mine && (
                    <button type="button" className="block min-h-10 w-full rounded-box px-3 py-2 text-left text-[14.5px] hover:bg-surface-2"
                      onClick={() => (setMenu(false), setReport(true))}>
                      {t("report")}
                    </button>
                  )}
                  {c.can_delete && (
                    <button type="button" className="block min-h-10 w-full rounded-box px-3 py-2 text-left text-[14.5px] text-danger hover:bg-surface-2"
                      onClick={() => {
                        setMenu(false);
                        if (window.confirm(c.parent_id ? t("delete_confirm") : t("delete_confirm_thread"))) remove.mutate();
                      }}>
                      {t("delete")}
                    </button>
                  )}
                </div>
              )}
            </div>
          )}
        </div>
        {remove.error && <p className="text-[13px] text-danger">{remove.error instanceof ApiError && remove.error.message ? remove.error.message : t("error")}</p>}
      </div>
      {me && !mine && <ReportDialog targetType="comment" targetId={c.id} open={report} onClose={() => setReport(false)} />}
    </div>
  );
}
