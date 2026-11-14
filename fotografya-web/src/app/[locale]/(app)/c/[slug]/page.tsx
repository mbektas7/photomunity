"use client";

import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import clsx from "clsx";
import { MapPin, Plus, Settings } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useParams, useSearchParams } from "next/navigation";
import { Suspense, useCallback, useState } from "react";
import { Avatar } from "@/components/Avatar";
import { CommunityLogo, ContestRow, MyPhotoPicker } from "@/components/community";
import { PhotoPrint } from "@/components/PhotoPrint";
import { Button, Notice, TextArea, TextField, buttonClass } from "@/components/ui";
import { Link, usePathname, useRouter } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import { countryName } from "@/lib/format";
import { useLoadMore, useMe } from "@/lib/hooks";
import { relativeTime } from "@/lib/relative-time";
import type { Community, CommunityPost, ContestCard, Member } from "@/lib/types";

const TABS = ["feed", "contests", "members"] as const;

export default function CommunityPage() {
  return (
    <Suspense>
      <CommunityView />
    </Suspense>
  );
}

function CommunityView() {
  const { slug } = useParams<{ slug: string }>();
  const t = useTranslations("communities");
  const locale = useLocale();
  const router = useRouter();
  const pathname = usePathname();
  const tab = (useSearchParams().get("tab") as (typeof TABS)[number]) || "feed";
  const { data: me } = useMe();
  const qc = useQueryClient();

  const q = useQuery({ queryKey: ["community", slug], queryFn: () => api<Community>(`communities/${slug}`) });
  const membership = useMutation({
    mutationFn: (join: boolean) => api(`communities/${slug}/join`, { method: join ? "POST" : "DELETE" }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["community", slug] });
      qc.invalidateQueries({ queryKey: ["communities"] });
    },
  });

  if (q.error) return <div className="mx-auto max-w-[680px] px-4 py-20"><Notice tone="error">{q.error instanceof ApiError ? q.error.message : t("error")}</Notice></div>;
  const c = q.data;
  if (!c) return <div className="h-[60vh]" aria-busy />;
  const isAdmin = c.my_role === "owner" || c.my_role === "admin";
  const place = [c.city, countryName(c.country, locale)].filter(Boolean).join(", ");

  return (
    <div>
      {c.cover_url ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={c.cover_url} alt="" className="block aspect-[3/1] max-h-[340px] w-full object-cover" />
      ) : (
        <div className="h-6" />
      )}
      <section className="mx-auto max-w-[1100px] px-4 pt-8 sm:px-6">
        <div className="flex flex-wrap items-start gap-5">
          <CommunityLogo name={c.name} url={c.logo_url} size={84} />
          <div className="min-w-0 flex-1">
            <h1 className="text-[clamp(1.8rem,4vw,2.8rem)] font-bold leading-[1.02] tracking-[-0.04em]">{c.name}</h1>
            <p className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-[15px] text-ink-muted">
              {place && <span className="inline-flex items-center gap-1"><MapPin className="h-3.5 w-3.5" /> {place}</span>}
              <span className="tnum">{t("members_count", { count: c.member_count })}</span>
              {c.open_contests > 0 && <span className="font-medium text-accent-text">{t("active_contests", { count: c.open_contests })}</span>}
            </p>
          </div>
          <div className="flex gap-2">
            {isAdmin && (
              <Link href={`/c/${slug}/settings`} className={buttonClass("secondary")}>
                <Settings className="h-4 w-4" /> {t("manage")}
              </Link>
            )}
            {!me ? (
              <Button onClick={() => router.push(`/login?next=${encodeURIComponent(pathname)}`)}>{t("join")}</Button>
            ) : !c.my_role ? (
              <Button busy={membership.isPending} onClick={() => membership.mutate(true)}>{t("join")}</Button>
            ) : c.my_role === "member" ? (
              <Button variant="secondary" busy={membership.isPending} onClick={() => membership.mutate(false)}>{t("leave")}</Button>
            ) : null}
          </div>
        </div>
        {c.description && <p className="mt-6 max-w-[70ch] whitespace-pre-line leading-relaxed">{c.description}</p>}

        <nav className="mt-8 flex gap-1 border-b border-line" aria-label={t("sections")}>
          {TABS.map((key) => (
            <Link
              key={key}
              href={key === "feed" ? `/c/${slug}` : `/c/${slug}?tab=${key}`}
              aria-current={tab === key ? "page" : undefined}
              className={clsx("-mb-px border-b-2 px-4 py-3 text-[15px] font-medium", tab === key ? "border-ink text-ink" : "border-transparent text-ink-muted hover:text-ink")}
            >
              {t(`tab_${key}`)}
            </Link>
          ))}
        </nav>
      </section>

      <div className="mx-auto max-w-[1100px] px-0 pt-6 sm:px-6">
        {tab === "feed" && <FeedTab c={c} isAdmin={isAdmin} />}
        {tab === "contests" && <ContestsTab c={c} isAdmin={isAdmin} />}
        {tab === "members" && <MembersTab c={c} />}
      </div>
    </div>
  );
}

function Composer({ c, isAdmin }: { c: Community; isAdmin: boolean }) {
  const t = useTranslations("communities");
  const qc = useQueryClient();
  const [picker, setPicker] = useState(false);
  const [news, setNews] = useState(false);
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const done = () => qc.invalidateQueries({ queryKey: ["community-posts", c.slug] });
  const post = useMutation({
    mutationFn: (payload: Record<string, unknown>) => api(`communities/${c.slug}/posts`, { method: "POST", body: payload }),
    onSuccess: () => {
      setPicker(false);
      setNews(false);
      setTitle("");
      setBody("");
      done();
    },
  });

  return (
    <div className="mb-6 bg-surface px-4 py-4 sm:px-5">
      {!news ? (
        <div className="flex flex-wrap gap-2">
          <Button variant="secondary" onClick={() => setPicker(true)}><Plus className="h-4 w-4" /> {t("share_photo")}</Button>
          {isAdmin && <Button variant="secondary" onClick={() => setNews(true)}>{t("write_news")}</Button>}
        </div>
      ) : (
        <form className="flex flex-col gap-4" onSubmit={(e) => { e.preventDefault(); post.mutate({ kind: "news", title, body: body || null }); }}>
          <TextField label={t("news_title")} name="news_title" required maxLength={200} value={title} onChange={(e) => setTitle(e.target.value)} />
          <TextArea label={t("news_body")} name="news_body" maxLength={5000} value={body} onChange={(e) => setBody(e.target.value)} />
          <div className="flex gap-2">
            <Button type="submit" busy={post.isPending}>{t("publish")}</Button>
            <Button type="button" variant="ghost" onClick={() => setNews(false)}>{t("cancel")}</Button>
          </div>
        </form>
      )}
      {post.error && <div className="mt-3"><Notice tone="error">{post.error instanceof ApiError ? post.error.message : t("error")}</Notice></div>}
      <MyPhotoPicker open={picker} onClose={() => setPicker(false)} title={t("share_photo")} busy={post.isPending} onPick={(p) => post.mutate({ kind: "photo", photo_id: p.id })} />
    </div>
  );
}

function FeedTab({ c, isAdmin }: { c: Community; isAdmin: boolean }) {
  const t = useTranslations("communities");
  const locale = useLocale();
  const q = useInfiniteQuery({
    queryKey: ["community-posts", c.slug],
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) => api<{ items: CommunityPost[]; next_cursor: string | null }>(`communities/${c.slug}/posts${pageParam ? `?before=${encodeURIComponent(pageParam)}` : ""}`),
    getNextPageParam: (last) => last.next_cursor,
  });
  const { fetchNextPage, hasNextPage, isFetchingNextPage } = q;
  const loadMore = useCallback(() => !isFetchingNextPage && fetchNextPage(), [fetchNextPage, isFetchingNextPage]);
  const sentinel = useLoadMore(loadMore, !!hasNextPage);
  const items = q.data?.pages.flatMap((p) => p.items) ?? [];

  return (
    <div className="mx-auto max-w-[680px]">
      {c.my_role && <Composer c={c} isAdmin={isAdmin} />}
      {q.isSuccess && items.length === 0 && <p className="px-4 py-10 text-ink-muted">{t("feed_empty")}</p>}
      <div className="flex flex-col gap-6 sm:gap-8">
        {items.map((p) =>
          p.kind === "photo" && p.photo ? (
            <PhotoPrint key={p.id} photo={p.photo} />
          ) : p.kind === "contest" && p.contest ? (
            <div key={p.id}>
              <p className="mb-2 px-4 text-sm text-ink-muted sm:px-0">{t("contest_announced", { time: relativeTime(p.created_at, locale) })}</p>
              <ContestRow c={p.contest} showCommunity={false} />
            </div>
          ) : (
            <article key={p.id} className="bg-surface px-5 py-5">
              <header className="flex items-center gap-3">
                <Avatar name={p.author.display_name} url={p.author.avatar_url} size={32} />
                <span className="text-sm"><span className="font-semibold">{p.author.display_name}</span> <span className="text-ink-muted">· {relativeTime(p.created_at, locale)}</span></span>
              </header>
              {p.title && <h3 className="mt-4 text-[20px] font-semibold leading-snug tracking-[-0.015em]">{p.title}</h3>}
              {p.body && <p className="mt-2 whitespace-pre-line leading-relaxed">{p.body}</p>}
            </article>
          ),
        )}
      </div>
      <div ref={sentinel} className="h-px" />
    </div>
  );
}

function ContestsTab({ c, isAdmin }: { c: Community; isAdmin: boolean }) {
  const t = useTranslations("communities");
  const q = useQuery({ queryKey: ["community-contests", c.slug], queryFn: () => api<ContestCard[]>(`communities/${c.slug}/contests`) });
  return (
    <div className="mx-auto max-w-[760px]">
      {isAdmin && (
        <Link href={`/c/${c.slug}/contests/new`} className={buttonClass("primary", "mb-6")}>
          <Plus className="h-4 w-4" strokeWidth={2.5} /> {t("new_contest")}
        </Link>
      )}
      <div className="flex flex-col gap-2">
        {q.data?.map((x) => <ContestRow key={x.id} c={x} showCommunity={false} />)}
        {q.isSuccess && q.data.length === 0 && <p className="px-4 py-10 text-ink-muted">{t("contests_empty")}</p>}
      </div>
    </div>
  );
}

function MembersTab({ c }: { c: Community }) {
  const t = useTranslations("communities");
  const q = useQuery({ queryKey: ["community-members", c.slug], queryFn: () => api<{ items: Member[] }>(`communities/${c.slug}/members?limit=200`) });
  const order = { owner: 0, admin: 1, member: 2 } as const;
  const members = [...(q.data?.items ?? [])].sort((a, b) => order[a.role] - order[b.role]);
  return (
    <ul className="mx-auto grid max-w-[900px] gap-px bg-line sm:grid-cols-2">
      {members.map((m) => (
        <li key={m.user.id} className="bg-surface">
          <Link href={`/u/${m.user.username}`} className="flex items-center gap-3 px-4 py-3">
            <Avatar name={m.user.display_name} url={m.user.avatar_url} size={40} />
            <span className="min-w-0 flex-1">
              <span className="block truncate font-semibold">{m.user.display_name}</span>
              <span className="block truncate text-sm text-ink-muted">@{m.user.username}</span>
            </span>
            {m.role !== "member" && <span className="rounded-full border border-line px-2.5 py-1 text-xs text-ink-muted">{t(`role.${m.role}`)}</span>}
          </Link>
        </li>
      ))}
    </ul>
  );
}
