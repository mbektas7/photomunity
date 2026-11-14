"use client";

import clsx from "clsx";
import { useTranslations } from "next-intl";
import { useParams, useSearchParams } from "next/navigation";
import { Suspense, useEffect } from "react";
import { ConversationList, useMessageUnread } from "@/components/messages";
import { Link, usePathname, useRouter } from "@/i18n/navigation";
import { useMe } from "@/lib/hooks";

/** İki panelli düzen: masaüstünde liste solda, sohbet sağda; mobilde ikisi ayrı ekran. */
export default function MessagesLayout({ children }: { children: React.ReactNode }) {
  return (
    <Suspense>
      <Shell>{children}</Shell>
    </Suspense>
  );
}

function Shell({ children }: { children: React.ReactNode }) {
  const t = useTranslations("messages");
  const pathname = usePathname();
  const router = useRouter();
  const params = useParams<{ id?: string }>();
  const folder = useSearchParams().get("folder") === "requests" ? "requests" : "inbox";
  const { data: me, isLoading } = useMe();
  const unread = useMessageUnread(!!me);
  const atRoot = pathname === "/messages";

  useEffect(() => {
    if (!isLoading && !me) router.replace(`/login?next=${encodeURIComponent(pathname)}`);
  }, [me, isLoading, router, pathname]);

  return (
    <div data-fullbleed className="mx-auto grid h-[calc(100dvh-4rem-4.5rem)] max-w-[1200px] md:h-[calc(100dvh-4rem)] lg:grid-cols-[360px_minmax(0,1fr)] lg:border-x lg:border-line">
      <aside className={clsx("flex min-h-0 flex-col border-line lg:border-r", !atRoot && "hidden lg:flex")}>
        <div className="px-4 pb-3 pt-6">
          <h1 className="text-[28px] font-bold tracking-[-0.035em]">{t("title")}</h1>
          <div className="mt-4 flex gap-1">
            {(["inbox", "requests"] as const).map((f) => (
              <Link
                key={f}
                href={f === "inbox" ? pathname : `${pathname}?folder=requests`}
                aria-current={folder === f ? "page" : undefined}
                className={clsx("flex h-9 items-center gap-1.5 rounded-full px-4 text-sm font-medium", folder === f ? "bg-ink text-surface" : "text-ink-muted hover:text-ink")}
              >
                {t(f)}
                {f === "requests" && (unread.data?.requests ?? 0) > 0 && (
                  <span className={clsx("rounded-full px-1.5 text-[11px] font-semibold", folder === f ? "bg-surface text-ink" : "bg-accent text-accent-ink")}>{unread.data?.requests}</span>
                )}
              </Link>
            ))}
          </div>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto">{me && <ConversationList folder={folder} meId={me.id} activeId={params.id} />}</div>
      </aside>
      <section className={clsx("min-h-0", atRoot && "hidden lg:block")}>{children}</section>
    </div>
  );
}
