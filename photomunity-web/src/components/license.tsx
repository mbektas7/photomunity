"use client";

import clsx from "clsx";
import { Copyright, Mail } from "lucide-react";
import { useTranslations } from "next-intl";
import { Toggle, buttonClass } from "@/components/ui";
import { Link } from "@/i18n/navigation";
import type { License, PhotoDetail } from "@/lib/types";

export const LICENSES: License[] = ["all_rights", "cc_by", "cc_by_nc", "contact"];

const CC_URL: Partial<Record<License, string>> = {
  cc_by: "https://creativecommons.org/licenses/by/4.0/",
  cc_by_nc: "https://creativecommons.org/licenses/by-nc/4.0/",
};

/** Lisans seçimi + indirmeyi kapat (yükleme, düzenleme ve ayarlardaki varsayılanlar). */
export function LicenseFields({ license, downloadsDisabled, onChange, name = "license" }: {
  license: License;
  downloadsDisabled: boolean;
  onChange: (v: { license: License; downloadsDisabled: boolean }) => void;
  name?: string;
}) {
  const t = useTranslations("license");
  return (
    <div className="flex flex-col gap-4">
      <fieldset>
        <legend className="mb-2 text-sm font-medium">{t("label")}</legend>
        <div className="flex flex-col gap-1.5">
          {LICENSES.map((l) => (
            <label
              key={l}
              className={clsx(
                "flex cursor-pointer items-start gap-3 rounded-box border px-3.5 py-3 transition-colors",
                license === l ? "border-accent bg-accent-tint/60" : "border-line hover:bg-surface-2",
              )}
            >
              <input
                type="radio"
                name={name}
                value={l}
                checked={license === l}
                onChange={() => onChange({ license: l, downloadsDisabled })}
                className="mt-1 accent-[var(--accent)]"
              />
              <span>
                <span className="block text-[15px] font-semibold">{t(`name.${l}`)}</span>
                <span className="block text-sm text-ink-muted">{t(`desc.${l}`)}</span>
              </span>
            </label>
          ))}
        </div>
      </fieldset>
      <Toggle
        checked={downloadsDisabled}
        onChange={(v) => onChange({ license, downloadsDisabled: v })}
        label={t("downloads_off")}
        hint={t("downloads_off_hint")}
      />
      <p className="text-xs text-ink-muted">{t("note")}</p>
    </div>
  );
}

/** Fotoğraf detayında kullanım hakları satırı; "contact" ise "Lisans iste" düğmesi. */
export function LicenseInfo({ photo, isOwner, loggedIn }: { photo: PhotoDetail; isOwner: boolean; loggedIn: boolean }) {
  const t = useTranslations("license");
  const l = photo.license ?? "all_rights";
  const url = CC_URL[l];
  const requestHref = `/messages/new?${new URLSearchParams({ to: photo.user.username, license: photo.id })}`;
  return (
    <div className="flex flex-wrap items-center gap-x-3 gap-y-2 text-[14px] text-ink-muted">
      <Copyright className="h-[18px] w-[18px] shrink-0" strokeWidth={1.8} aria-hidden />
      <span className="min-w-0 flex-1">
        {url ? (
          <a href={url} target="_blank" rel="noreferrer license" className="font-medium text-ink hover:underline">{t(`name.${l}`)}</a>
        ) : (
          <span className="font-medium text-ink">{t(`name.${l}`)}</span>
        )}
        {l === "all_rights" && <> · {t("short.all_rights", { name: photo.user.display_name })}</>}
      </span>
      {l === "contact" && !isOwner && photo.user.is_public && (
        <Link href={loggedIn ? requestHref : "/login"} className={buttonClass("secondary", "!h-9 !min-h-9 px-3.5 text-[14px]")}>
          <Mail className="h-4 w-4" aria-hidden /> {t("request")}
        </Link>
      )}
    </div>
  );
}
