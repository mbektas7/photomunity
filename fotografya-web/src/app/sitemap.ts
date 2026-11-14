import type { MetadataRoute } from "next";
import { routing } from "@/i18n/routing";

const SITE = process.env.NEXT_PUBLIC_SITE_URL || "https://fotografya.app";
const API = process.env.API_URL ?? "http://localhost:8000/api/v1";
const STATIC = ["", "/explore", "/communities", "/contests", "/map", "/guide", "/tools", "/planner", "/pro"];

/** Herkese açık sayfalar, her dil için hreflang alternatifleriyle. Rehber senaryoları API'den gelir. */
export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  let guides: string[] = [];
  try {
    const r = await fetch(`${API}/guides`, { next: { revalidate: 86400 } });
    if (r.ok) guides = ((await r.json()) as { slug: string }[]).map((g) => `/guide/${g.slug}`);
  } catch {
    /* API erişilemezse statik sayfalarla devam */
  }
  return [...STATIC, ...guides].map((path) => ({
    url: `${SITE}/${routing.defaultLocale}${path}`,
    changeFrequency: path === "" || path === "/explore" ? "daily" : "weekly",
    priority: path === "" ? 1 : 0.6,
    alternates: { languages: Object.fromEntries(routing.locales.map((l) => [l, `${SITE}/${l}${path}`])) },
  }));
}
