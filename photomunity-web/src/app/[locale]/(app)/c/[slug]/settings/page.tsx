"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Camera, X } from "lucide-react";
import { useTranslations } from "next-intl";
import { useParams, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useRef, useState } from "react";
import { Avatar } from "@/components/Avatar";
import { CommunityLogo } from "@/components/community";
import { Button, Notice, TextArea, TextField } from "@/components/ui";
import { Link, useRouter } from "@/i18n/navigation";
import { ApiError, api } from "@/lib/api";
import { useMe } from "@/lib/hooks";
import { uploadImage } from "@/lib/upload-image";
import type { Community } from "@/lib/types";

const TYPES = "image/jpeg,image/png,image/webp,image/heic,image/heif";

export default function CommunitySettingsPage() {
  return (
    <Suspense>
      <SettingsView />
    </Suspense>
  );
}

function SettingsView() {
  const { slug } = useParams<{ slug: string }>();
  const t = useTranslations("communities");
  const created = useSearchParams().get("created");
  const router = useRouter();
  const { data: me } = useMe();
  const q = useQuery({ queryKey: ["community", slug], queryFn: () => api<Community>(`communities/${slug}`) });
  const c = q.data;

  useEffect(() => {
    if (c && c.my_role !== "owner" && c.my_role !== "admin") router.replace(`/c/${slug}`);
  }, [c, slug, router]);
  if (!c || !me) return <div className="h-[60vh]" aria-busy />;

  return (
    <div className="mx-auto max-w-[720px] px-4 pt-8 sm:px-6 sm:pt-12">
      <Link href={`/c/${slug}`} className="text-sm text-ink-muted hover:text-ink">← {c.name}</Link>
      <h1 className="mt-3 text-[clamp(2rem,4.5vw,3rem)] font-bold leading-none tracking-[-0.04em]">{t("settings_title")}</h1>
      {created && <div className="mt-6"><Notice tone="success">{t("created")}</Notice></div>}
      <Images c={c} />
      <Info c={c} />
      {c.my_role === "owner" && <Admins c={c} />}
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

function Images({ c }: { c: Community }) {
  const t = useTranslations("communities");
  const qc = useQueryClient();
  const logo = useRef<HTMLInputElement>(null);
  const cover = useRef<HTMLInputElement>(null);
  const up = useMutation({
    mutationFn: ({ kind, file }: { kind: "logo" | "cover"; file: File }) => uploadImage<Community>(`communities/${c.slug}`, kind, file),
    onSuccess: (data) => qc.setQueryData(["community", c.slug], data),
  });
  const pick = (kind: "logo" | "cover") => (e: React.ChangeEvent<HTMLInputElement>) => {
    const f = e.target.files?.[0];
    e.target.value = "";
    if (f) up.mutate({ kind, file: f });
  };
  return (
    <div className="mt-8">
      <div className="relative">
        <button type="button" onClick={() => cover.current?.click()} className="group relative block aspect-[3/1] w-full overflow-hidden bg-surface-2" aria-label={t("change_cover")}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          {c.cover_url && <img src={c.cover_url} alt="" className="h-full w-full object-cover" />}
          <span className="absolute inset-0 flex items-center justify-center gap-2 text-sm font-semibold text-ink-muted group-hover:bg-black/35 group-hover:text-white">
            <Camera className="h-4 w-4" /> {up.isPending && up.variables?.kind === "cover" ? t("uploading") : c.cover_url ? t("change_cover") : t("add_cover")}
          </span>
        </button>
        <button type="button" onClick={() => logo.current?.click()} className="absolute -bottom-8 left-5 rounded-[22px] ring-4 ring-bg" aria-label={t("change_logo")}>
          <CommunityLogo name={c.name} url={c.logo_url} size={88} />
          <span className="absolute -bottom-1 -right-1 inline-flex h-8 w-8 items-center justify-center rounded-full bg-ink text-surface"><Camera className="h-4 w-4" /></span>
        </button>
      </div>
      <p className="mt-12 text-sm text-ink-muted">{t("images_hint")}</p>
      {up.error && <div className="mt-3"><Notice tone="error">{up.error instanceof ApiError ? up.error.message : t("error")}</Notice></div>}
      <input ref={logo} type="file" accept={TYPES} className="sr-only" onChange={pick("logo")} />
      <input ref={cover} type="file" accept={TYPES} className="sr-only" onChange={pick("cover")} />
    </div>
  );
}

function Info({ c }: { c: Community }) {
  const t = useTranslations("communities");
  const qc = useQueryClient();
  const [form, setForm] = useState({ name: c.name, description: c.description ?? "", city: c.city ?? "", country: c.country ?? "" });
  const save = useMutation({
    mutationFn: () => api<Community>(`communities/${c.slug}`, { method: "PATCH", body: { ...form, description: form.description || null, city: form.city || null, country: form.country || null } }),
    onSuccess: (data) => qc.setQueryData(["community", c.slug], data),
  });
  return (
    <Section title={t("info")}>
      <form className="flex flex-col gap-5" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
        <TextField label={t("name")} name="name" required minLength={3} maxLength={100} value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
        <TextArea label={t("description")} name="description" maxLength={3000} value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} />
        <div className="grid gap-5 sm:grid-cols-[1fr_140px]">
          <TextField label={t("city")} name="city" value={form.city} onChange={(e) => setForm({ ...form, city: e.target.value })} />
          <TextField label={t("country")} name="country" maxLength={2} value={form.country} onChange={(e) => setForm({ ...form, country: e.target.value.toUpperCase() })} />
        </div>
        {save.isSuccess && <Notice tone="success">{t("saved")}</Notice>}
        <Button type="submit" busy={save.isPending} className="self-start">{t("save")}</Button>
      </form>
    </Section>
  );
}

function Admins({ c }: { c: Community }) {
  const t = useTranslations("communities");
  const qc = useQueryClient();
  const [username, setUsername] = useState("");
  const [email, setEmail] = useState("");
  const [notice, setNotice] = useState<string | null>(null);
  const refresh = () => qc.invalidateQueries({ queryKey: ["community", c.slug] });

  const add = useMutation({
    mutationFn: () => api(`communities/${c.slug}/admins`, { method: "POST", body: { username: username.replace(/^@/, "").trim() } }),
    onSuccess: () => { setUsername(""); setNotice(t("admin_added")); refresh(); },
  });
  const invite = useMutation({
    mutationFn: () => api<{ status: "added" | "invited" }>(`communities/${c.slug}/invites`, { method: "POST", body: { email } }),
    onSuccess: (r) => { setEmail(""); setNotice(r.status === "added" ? t("admin_added") : t("invite_sent")); refresh(); },
  });
  const remove = useMutation({
    mutationFn: (u: string) => api(`communities/${c.slug}/admins/${u}`, { method: "DELETE" }),
    onSuccess: refresh,
  });
  const err = add.error ?? invite.error;

  return (
    <Section title={t("admins")} lead={t("admins_lead")}>
      <ul className="divide-y divide-line overflow-hidden rounded-card bg-surface">
        <li className="flex items-center gap-3 py-3">
          <Avatar name={c.owner.display_name} url={c.owner.avatar_url} size={36} />
          <span className="flex-1 font-medium">{c.owner.display_name}</span>
          <span className="text-sm text-ink-muted">{t("role.owner")}</span>
        </li>
        {c.admins.map((a) => (
          <li key={a.id} className="flex items-center gap-3 py-3">
            <Avatar name={a.display_name} url={a.avatar_url} size={36} />
            <span className="flex-1"><span className="font-medium">{a.display_name}</span> <span className="text-sm text-ink-muted">@{a.username}</span></span>
            <button type="button" onClick={() => remove.mutate(a.username)} className="rounded-full p-2 text-ink-muted hover:bg-surface-2 hover:text-ink" aria-label={t("remove_admin", { name: a.display_name })}>
              <X className="h-4 w-4" />
            </button>
          </li>
        ))}
      </ul>
      <div className="mt-6 grid gap-6 sm:grid-cols-2">
        <form className="flex flex-col gap-3" onSubmit={(e) => { e.preventDefault(); setNotice(null); add.mutate(); }}>
          <TextField label={t("add_by_username")} name="admin_username" placeholder="@kullanici" value={username} onChange={(e) => setUsername(e.target.value)} required />
          <Button type="submit" variant="secondary" busy={add.isPending} className="self-start">{t("add_admin")}</Button>
        </form>
        <form className="flex flex-col gap-3" onSubmit={(e) => { e.preventDefault(); setNotice(null); invite.mutate(); }}>
          <TextField label={t("invite_by_email")} name="admin_email" type="email" hint={t("invite_hint")} value={email} onChange={(e) => setEmail(e.target.value)} required />
          <Button type="submit" variant="secondary" busy={invite.isPending} className="self-start">{t("send_invite")}</Button>
        </form>
      </div>
      {notice && <div className="mt-4"><Notice tone="success">{notice}</Notice></div>}
      {err && <div className="mt-4"><Notice tone="error">{err instanceof ApiError ? err.message : t("error")}</Notice></div>}
    </Section>
  );
}
