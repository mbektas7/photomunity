"use client";

import clsx from "clsx";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { LocateFixed, Plus, Trash2 } from "lucide-react";
import { useTranslations } from "next-intl";
import { useSearchParams } from "next/navigation";
import { Suspense, useEffect, useState } from "react";
import { NotificationSettingsForm, ProfileImages } from "@/components/ProfileImages";
import { Button, Notice, TextArea, TextField, Toggle } from "@/components/ui";
import { usePathname, useRouter } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import { useMe } from "@/lib/hooks";
import type { Equipment, EquipmentType, Me } from "@/lib/types";

const SPECIALTIES = ["astro", "landscape", "street", "portrait", "wildlife", "sports", "architecture", "documentary", "wedding", "macro", "aerial", "travel"];
const EQUIPMENT_TYPES: EquipmentType[] = ["body", "lens", "tripod", "filter", "flash", "drone", "other"];

export default function SettingsPage() {
  return (
    <Suspense>
      <Settings />
    </Suspense>
  );
}

function Settings() {
  const t = useTranslations("settings");
  const { data: me, isLoading } = useMe();
  const router = useRouter();
  const welcome = useSearchParams().get("welcome");

  useEffect(() => {
    if (!isLoading && !me) router.replace("/login");
  }, [me, isLoading, router]);
  if (!me) return <div className="h-[60vh]" aria-busy />;

  return (
    <div className="mx-auto max-w-[720px] px-4 pt-8 sm:px-6 sm:pt-12">
      <h1 className="text-[clamp(2rem,4.5vw,3rem)] font-bold leading-none tracking-[-0.04em]">{t("heading")}</h1>
      {welcome && (
        <div className="mt-6">
          <Notice tone="success">{t("welcome")}</Notice>
        </div>
      )}
      {!me.email_verified && <VerifyBanner />}
      <ProfileSection me={me} />
      <EquipmentSection initial={me.equipment} />
      <Section title={t("notifications")} lead={t("notifications_lead")}>
        <NotificationSettingsForm />
      </Section>
      <AccountSection />
    </div>
  );
}

function Section({ title, lead, children }: { title: string; lead?: string; children: React.ReactNode }) {
  return (
    <section className="mt-12 border-t border-line pt-8">
      <h2 className="text-xl font-semibold tracking-[-0.02em]">{title}</h2>
      {lead && <p className="mt-1 text-[15px] text-ink-muted">{lead}</p>}
      <div className="mt-6">{children}</div>
    </section>
  );
}

function VerifyBanner() {
  const t = useTranslations("settings");
  const resend = useMutation({ mutationFn: () => api("auth/resend-verification", { method: "POST" }) });
  return (
    <div className="mt-6">
      <Notice>
        {resend.isSuccess ? t("verify_sent") : t("verify_needed")}{" "}
        {!resend.isSuccess && (
          <button type="button" onClick={() => resend.mutate()} className="font-semibold text-ink underline underline-offset-4">
            {t("verify_resend")}
          </button>
        )}
      </Notice>
    </div>
  );
}

function ProfileSection({ me }: { me: Me }) {
  const t = useTranslations("settings");
  const ts = useTranslations("specialties");
  const qc = useQueryClient();
  const router = useRouter();
  const pathname = usePathname();
  const [form, setForm] = useState({
    display_name: me.display_name,
    username: me.username,
    bio: me.bio ?? "",
    website: me.website ?? "",
    city: me.city ?? "",
    country: me.country ?? "",
    is_public: me.is_public,
    specialties: me.specialties,
    locale: me.locale,
    latitude: me.latitude,
    longitude: me.longitude,
  });
  const set = <K extends keyof typeof form>(k: K, v: (typeof form)[K]) => setForm((f) => ({ ...f, [k]: v }));

  const save = useMutation({
    mutationFn: () =>
      api<Me>("me", {
        method: "PATCH",
        body: {
          ...form,
          bio: form.bio || null,
          website: form.website ? (/^https?:\/\//.test(form.website) ? form.website : `https://${form.website}`) : null,
          city: form.city || null,
          country: form.country ? form.country.toUpperCase() : null,
        },
      }),
    onSuccess: (data) => {
      qc.setQueryData(["me"], data);
      qc.invalidateQueries({ queryKey: ["profile"] });
      if (data.locale !== document.documentElement.lang) router.replace(pathname, { locale: data.locale });
    },
  });

  function locate() {
    navigator.geolocation?.getCurrentPosition((p) => {
      set("latitude", p.coords.latitude);
      set("longitude", p.coords.longitude);
    });
  }

  const err = save.error instanceof ApiError ? save.error : null;

  return (
    <Section title={t("profile")} lead={t("profile_lead")}>
      <div className="mb-10">
        <ProfileImages me={me} />
      </div>
      <form
        className="flex flex-col gap-5"
        onSubmit={(e) => {
          e.preventDefault();
          save.mutate();
        }}
      >
        <div className="grid gap-5 sm:grid-cols-2">
          <TextField label={t("display_name")} name="display_name" required maxLength={80} value={form.display_name} onChange={(e) => set("display_name", e.target.value)} />
          <TextField
            label={t("username")}
            name="username"
            required
            pattern="[a-zA-Z0-9_.]{3,30}"
            value={form.username}
            error={err?.code === "username_taken" ? err.message : undefined}
            onChange={(e) => set("username", e.target.value.toLowerCase())}
          />
        </div>
        <TextArea label={t("bio")} name="bio" maxLength={500} value={form.bio} onChange={(e) => set("bio", e.target.value)} />
        <TextField label={t("website")} name="website" inputMode="url" value={form.website} onChange={(e) => set("website", e.target.value)} />
        <div className="grid gap-5 sm:grid-cols-[1fr_140px]">
          <TextField label={t("city")} name="city" value={form.city} onChange={(e) => set("city", e.target.value)} />
          <TextField label={t("country")} name="country" hint={t("country_hint")} maxLength={2} value={form.country} onChange={(e) => set("country", e.target.value.toUpperCase())} />
        </div>
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-[10px] border border-line px-4 py-3">
          <span className="text-[15px]">
            <span className="block font-medium">{t("map_location")}</span>
            <span className="block text-sm text-ink-muted">
              {form.latitude != null ? t("map_location_set") : t("map_location_hint")}
            </span>
          </span>
          {form.latitude != null ? (
            <Button type="button" variant="ghost" onClick={() => (set("latitude", null), set("longitude", null))}>
              {t("remove")}
            </Button>
          ) : (
            <Button type="button" variant="secondary" onClick={locate}>
              <LocateFixed className="h-4 w-4" /> {t("use_my_location")}
            </Button>
          )}
        </div>

        <fieldset>
          <legend className="text-sm font-medium">{t("specialties")}</legend>
          <div className="mt-2.5 flex flex-wrap gap-2">
            {SPECIALTIES.map((s) => {
              const on = form.specialties.includes(s);
              return (
                <button
                  key={s}
                  type="button"
                  aria-pressed={on}
                  onClick={() => set("specialties", on ? form.specialties.filter((x) => x !== s) : [...form.specialties, s].slice(0, 10))}
                  className={clsx(
                    "rounded-full border px-3.5 py-1.5 text-sm transition-colors",
                    on ? "border-ink bg-ink text-surface" : "border-line hover:border-ink",
                  )}
                >
                  {ts(s)}
                </button>
              );
            })}
          </div>
        </fieldset>

        <Toggle checked={form.is_public} onChange={(v) => set("is_public", v)} label={t("public")} hint={form.is_public ? t("public_on") : t("public_off")} />

        <div className="flex flex-col gap-1.5">
          <label htmlFor="locale" className="text-sm font-medium">
            {t("language")}
          </label>
          <select
            id="locale"
            value={form.locale}
            onChange={(e) => set("locale", e.target.value as Me["locale"])}
            className="h-11 rounded-[10px] border border-line bg-surface px-3 text-[15px]"
          >
            <option value="tr">Türkçe</option>
            <option value="en">English</option>
          </select>
        </div>

        {err && err.code !== "username_taken" && <Notice tone="error">{err.message}</Notice>}
        {save.isSuccess && <Notice tone="success">{t("saved")}</Notice>}
        <Button type="submit" busy={save.isPending} className="self-start">
          {t("save")}
        </Button>
      </form>
    </Section>
  );
}

function EquipmentSection({ initial }: { initial: Equipment[] }) {
  const t = useTranslations("settings");
  const te = useTranslations("equipment");
  const qc = useQueryClient();
  const [items, setItems] = useState(initial.map(({ type, brand, model }) => ({ type, brand, model })));

  const save = useMutation({
    mutationFn: () => api<Equipment[]>("me/equipment", { method: "PUT", body: items.filter((i) => i.brand.trim() && i.model.trim()) }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["me"] });
      qc.invalidateQueries({ queryKey: ["profile"] });
    },
  });

  const update = (i: number, patch: Partial<(typeof items)[number]>) =>
    setItems((list) => list.map((it, j) => (j === i ? { ...it, ...patch } : it)));

  return (
    <Section title={t("equipment")} lead={t("equipment_lead")}>
      <div className="flex flex-col gap-3">
        {items.map((it, i) => (
          <div key={i} className="grid grid-cols-[110px_1fr_auto] gap-2 sm:grid-cols-[130px_1fr_1.4fr_auto]">
            <select
              aria-label={t("equipment_type")}
              value={it.type}
              onChange={(e) => update(i, { type: e.target.value as EquipmentType })}
              className="h-11 rounded-[10px] border border-line bg-surface px-2.5 text-[15px]"
            >
              {EQUIPMENT_TYPES.map((type) => (
                <option key={type} value={type}>
                  {te(type)}
                </option>
              ))}
            </select>
            <input
              aria-label={t("brand")}
              placeholder={t("brand")}
              value={it.brand}
              onChange={(e) => update(i, { brand: e.target.value })}
              className="h-11 min-w-0 rounded-[10px] border border-line bg-surface px-3 text-[15px] outline-none focus:border-ink"
            />
            <input
              aria-label={t("model")}
              placeholder={t("model")}
              value={it.model}
              onChange={(e) => update(i, { model: e.target.value })}
              className="col-span-2 row-start-2 h-11 min-w-0 rounded-[10px] border border-line bg-surface px-3 text-[15px] outline-none focus:border-ink sm:col-span-1 sm:row-start-auto"
            />
            <button
              type="button"
              onClick={() => setItems((list) => list.filter((_, j) => j !== i))}
              aria-label={t("remove")}
              className="col-start-3 row-start-1 inline-flex h-11 w-11 items-center justify-center rounded-full text-ink-muted hover:bg-ink/5 hover:text-ink sm:col-start-auto sm:row-start-auto"
            >
              <Trash2 className="h-4 w-4" />
            </button>
          </div>
        ))}
        <div className="mt-2 flex flex-wrap gap-3">
          <Button type="button" variant="secondary" onClick={() => setItems((l) => [...l, { type: l.length ? "lens" : "body", brand: "", model: "" }])}>
            <Plus className="h-4 w-4" /> {t("add_equipment")}
          </Button>
          <Button type="button" busy={save.isPending} onClick={() => save.mutate()}>
            {t("save_equipment")}
          </Button>
        </div>
        {save.isSuccess && <Notice tone="success">{t("saved")}</Notice>}
      </div>
    </Section>
  );
}

function AccountSection() {
  const t = useTranslations("settings");
  const router = useRouter();
  const qc = useQueryClient();
  const [current, setCurrent] = useState("");
  const [next, setNext] = useState("");

  const change = useMutation({
    mutationFn: () => api("auth/change-password", { method: "POST", body: { current_password: current || null, new_password: next } }),
    onSuccess: () => (setCurrent(""), setNext("")),
  });
  const del = useMutation({
    mutationFn: () => api("auth/account", { method: "DELETE" }),
    onSuccess: () => {
      qc.clear();
      router.replace("/");
    },
  });

  return (
    <Section title={t("account")}>
      <form
        className="flex flex-col gap-4"
        onSubmit={(e) => {
          e.preventDefault();
          change.mutate();
        }}
      >
        <h3 className="font-semibold">{t("change_password")}</h3>
        <p className="-mt-2 text-sm text-ink-muted">{t("change_password_hint")}</p>
        <div className="grid gap-4 sm:grid-cols-2">
          <TextField label={t("current_password")} name="current" type="password" autoComplete="current-password" value={current} onChange={(e) => setCurrent(e.target.value)} />
          <TextField label={t("new_password")} name="new" type="password" autoComplete="new-password" minLength={8} required value={next} onChange={(e) => setNext(e.target.value)} />
        </div>
        {change.error instanceof ApiError && <Notice tone="error">{change.error.message}</Notice>}
        {change.isSuccess && <Notice tone="success">{t("password_changed")}</Notice>}
        <Button type="submit" variant="secondary" busy={change.isPending} className="self-start">
          {t("change_password")}
        </Button>
      </form>

      <div className="mt-10 rounded-[10px] border border-danger/30 px-5 py-5">
        <h3 className="font-semibold">{t("delete_account")}</h3>
        <p className="mt-1 text-sm text-ink-muted">{t("delete_account_body")}</p>
        <Button
          type="button"
          variant="danger"
          className="mt-4"
          busy={del.isPending}
          onClick={() => window.confirm(t("delete_account_confirm")) && del.mutate()}
        >
          {t("delete_account")}
        </Button>
      </div>
    </Section>
  );
}
