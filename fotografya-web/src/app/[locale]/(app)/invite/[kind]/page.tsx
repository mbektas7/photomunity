"use client";

import { useMutation } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useParams, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useRef } from "react";
import { Notice, buttonClass } from "@/components/ui";
import { Link, usePathname, useRouter } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import { useMe } from "@/lib/hooks";
import type { Community, Contest } from "@/lib/types";

export default function InvitePage() {
  return (
    <Suspense>
      <Accept />
    </Suspense>
  );
}

function Accept() {
  const { kind } = useParams<{ kind: "community" | "judge" }>();
  const token = useSearchParams().get("token") ?? "";
  const t = useTranslations("invite");
  const router = useRouter();
  const pathname = usePathname();
  const { data: me, isLoading } = useMe();
  const started = useRef(false);
  const next = encodeURIComponent(`${pathname}?token=${token}`);

  const accept = useMutation({
    mutationFn: async (): Promise<string> => {
      if (kind === "judge") {
        const c = await api<Contest>("contest-judge-invites/accept", { method: "POST", body: { token } });
        return `/contests/${c.id}`;
      }
      const c = await api<Community>("community-invites/accept", { method: "POST", body: { token } });
      return `/c/${c.slug}`;
    },
    onSuccess: (path) => router.replace(path),
  });

  useEffect(() => {
    if (me && token && !started.current) {
      started.current = true;
      accept.mutate();
    }
  }, [me, token, accept]);

  return (
    <div className="mx-auto max-w-[520px] px-4 py-16">
      <h1 className="text-[34px] font-bold leading-tight tracking-[-0.035em]">{t(`${kind}_title`)}</h1>
      {!isLoading && !me && (
        <>
          <p className="mt-3 leading-relaxed text-muted">{t("login_needed")}</p>
          <div className="mt-6 flex gap-3">
            <Link href={`/register?next=${next}`} className={buttonClass("primary")}>{t("register")}</Link>
            <Link href={`/login?next=${next}`} className={buttonClass("secondary")}>{t("login")}</Link>
          </div>
        </>
      )}
      {accept.isPending && <p className="mt-4 text-muted">{t("accepting")}</p>}
      {accept.error && <div className="mt-6"><Notice tone="error">{accept.error instanceof ApiError ? accept.error.message : t("error")}</Notice></div>}
    </div>
  );
}
