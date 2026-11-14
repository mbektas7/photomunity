import { Check, MapPin } from "lucide-react";
import type { Metadata } from "next";
import { getTranslations, setRequestLocale } from "next-intl/server";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { Avatar } from "@/components/Avatar";
import { ContestRow, ContestTimeline } from "@/components/community";
import { JustifiedWall } from "@/components/JustifiedWall";
import { PlannerTeaser } from "@/components/landing/PlannerTeaser";
import { buttonClass } from "@/lib/button-class";
import { Viewfinder } from "@/components/Viewfinder";
import { Link } from "@/i18n/navigation";
import { routing } from "@/i18n/routing";
import { formatShutter, npfSeconds } from "@/lib/calculators";
import { serverGet } from "@/lib/server-api";
import type { ContestCard, Page, PhotoCard, PhotoDetail } from "@/lib/types";

const SITE = process.env.NEXT_PUBLIC_SITE_URL || "https://fotografya.app";
const STATS_MIN = Number(process.env.NEXT_PUBLIC_STATS_MIN ?? 20); // erken dönemde küçük sayıları göstermemek için
const APP_STORE = process.env.NEXT_PUBLIC_APP_STORE_URL;
const PLAY_STORE = process.env.NEXT_PUBLIC_PLAY_STORE_URL;

type Stats = { photographers: number; photos: number; communities: number; countries: number; open_contests: number };
type GuideCard = { slug: string; title: string };

export async function generateMetadata({ params }: { params: Promise<{ locale: string }> }): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "landing" });
  const languages = Object.fromEntries(routing.locales.map((l) => [l, `${SITE}/${l}`]));
  return {
    title: { absolute: t("meta_title") },
    description: t("meta_description"),
    alternates: { canonical: `${SITE}/${locale}`, languages: { ...languages, "x-default": `${SITE}/${routing.defaultLocale}` } },
    // Sayfanın kendi openGraph nesnesi dosyadan üretilen görseli ezdiği için görsel açıkça verilir
    openGraph: { type: "website", url: `${SITE}/${locale}`, siteName: "Fotografya", title: t("meta_title"), description: t("meta_description"),
      locale: locale === "tr" ? "tr_TR" : "en_US", images: [{ url: `${SITE}/${locale}/opengraph-image`, width: 1200, height: 630, alt: t("meta_title") }] },
    twitter: { card: "summary_large_image", title: t("meta_title"), description: t("meta_description"), images: [`${SITE}/${locale}/opengraph-image`] },
  };
}

export default async function Landing({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  // Oturum çerezi olan kullanıcı tanıtımı görmeden akışa gider
  if ((await cookies()).get("fg_rt")) redirect(`/${locale}/feed`);

  const t = await getTranslations("landing");
  const [stats, wall, openContests, judging, guides] = await Promise.all([
    serverGet<Stats>("stats/public", locale),
    serverGet<Page<PhotoCard>>("explore?limit=40", locale),
    serverGet<ContestCard[]>("contests?status=open&limit=1", locale),
    serverGet<ContestCard[]>("contests?status=judging&limit=1", locale),
    serverGet<GuideCard[]>("guides", locale),
  ]);
  // EXIF bölümü için ayarları dolu, yatay bir gerçek kare
  let exifPhoto: PhotoDetail | null = null;
  for (const p of (wall?.items ?? []).slice(0, 12)) {
    const img = p.images.feed;
    if (!img || img.width < img.height) continue;
    const d = await serverGet<PhotoDetail>(`photos/${p.id}`, locale);
    if (d?.exif?.shutter_display && d.exif.aperture && d.exif.iso) {
      exifPhoto = d;
      break;
    }
  }
  const featured = openContests?.[0] ?? judging?.[0] ?? null;
  const nf = new Intl.NumberFormat(locale);
  const readouts = stats && stats.photographers >= STATS_MIN
    ? ([["photographers", stats.photographers], ["photos", stats.photos], ["communities", stats.communities], ["countries", stats.countries], ["open_contests", stats.open_contests]] as const).filter(([, n]) => n > 0)
    : [];
  const npf = formatShutter(npfSeconds("ff", 24, 14, 1.8), locale);
  const jsonLd = {
    "@context": "https://schema.org",
    "@graph": [
      { "@type": "WebSite", name: "Fotografya", url: SITE, inLanguage: locale, potentialAction: { "@type": "SearchAction", target: `${SITE}/${locale}/communities?q={q}`, "query-input": "required name=q" } },
      { "@type": "SoftwareApplication", name: "Fotografya", applicationCategory: "PhotographyApplication", operatingSystem: "iOS, Android, Web",
        offers: { "@type": "Offer", price: "0", priceCurrency: "USD" }, description: t("meta_description") },
    ],
  };

  return (
    <>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }} />

      {/* Giriş */}
      <section className="mx-auto max-w-[1400px] px-4 pb-10 pt-14 sm:px-6 sm:pt-20">
        <h1 className="max-w-[13ch] text-[clamp(2.8rem,8vw,6.4rem)] font-bold leading-[0.93] tracking-[-0.05em]">{t("title")}</h1>
        <p className="mt-7 max-w-[54ch] text-[17px] leading-relaxed text-ink-muted sm:text-lg">{t("lead")}</p>
        <div className="mt-8 flex flex-wrap items-center gap-3">
          <Link href="/register" className={buttonClass("primary", "h-12 px-6 text-base")}>{t("cta")}</Link>
          <Link href="/explore" className={buttonClass("secondary", "h-12 px-6 text-base")}>{t("explore")}</Link>
          {APP_STORE && <a href={APP_STORE} className="ml-2 text-[15px] font-medium underline-offset-4 hover:underline">{t("ios")}</a>}
          {PLAY_STORE && <a href={PLAY_STORE} className="text-[15px] font-medium underline-offset-4 hover:underline">{t("android")}</a>}
        </div>
      </section>

      {/* Vizör şeridi: sitedeki gerçek sayılar, makinenin ayar göstergesi gibi */}
      {readouts.length > 0 && (
        <section aria-label={t("stats_label")} className="bg-black text-[#f2f2ee]">
          <dl className="mx-auto flex max-w-[1400px] flex-wrap gap-x-12 gap-y-5 px-4 py-6 sm:px-6">
            {readouts.map(([k, n]) => (
              <div key={k} className="flex flex-col-reverse">
                <dt className="mt-1 text-[13px] text-[#8d8d88]">{t(`stat.${k}`)}</dt>
                <dd className="tnum text-[30px] font-semibold leading-none tracking-tight sm:text-[36px]">{nf.format(n)}</dd>
              </div>
            ))}
          </dl>
        </section>
      )}

      {wall && wall.items.length > 0 && (
        <section aria-label={t("wall")} className="px-1.5 pt-1.5">
          <JustifiedWall photos={wall.items} target={330} completeRowsOnly maxRows={4} />
        </section>
      )}

      {/* EXIF ve kalite */}
      <section className="mx-auto grid max-w-[1200px] items-center gap-10 px-4 pt-24 sm:px-6 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.15fr)] lg:gap-16">
        <div>
          <h2 className="text-[clamp(1.9rem,4vw,2.9rem)] font-bold leading-[1.02] tracking-[-0.04em]">{t("exif_title")}</h2>
          <p className="mt-4 max-w-[48ch] text-[17px] leading-relaxed text-ink-muted">{t("exif_body")}</p>
          <ul className="mt-6 flex flex-col gap-3 text-[15px]">
            {(["exif_point_quality", "exif_point_uncropped", "exif_point_location"] as const).map((k) => (
              <li key={k} className="flex gap-3"><Check className="mt-0.5 h-4 w-4 shrink-0 text-accent-text" strokeWidth={3} /> {t(k)}</li>
            ))}
          </ul>
        </div>
        {exifPhoto && exifPhoto.images.feed && exifPhoto.exif && (
          <figure className="bg-surface p-3">
            <Link href={`/p/${exifPhoto.id}`}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={exifPhoto.images.feed.url} alt={exifPhoto.title ?? ""} width={exifPhoto.images.feed.width} height={exifPhoto.images.feed.height} className="block h-auto w-full" />
            </Link>
            <Viewfinder exif={exifPhoto.exif} />
            <figcaption className="px-1 pt-2.5 text-sm text-ink-muted">{[exifPhoto.title, exifPhoto.user.display_name].filter(Boolean).join(", ")}</figcaption>
          </figure>
        )}
      </section>

      {/* Topluluklar ve yarışmalar */}
      <section className="mx-auto grid max-w-[1200px] items-center gap-10 px-4 pt-28 sm:px-6 lg:grid-cols-[minmax(0,1.15fr)_minmax(0,1fr)] lg:gap-16">
        <div className="order-last lg:order-first">
          {featured ? (
            <div className="flex flex-col gap-px bg-line">
              <ContestTimeline c={featured} />
              <ContestRow c={featured} />
            </div>
          ) : (
            <div className="bg-surface px-6 py-10 text-ink-muted">{t("contest_empty")}</div>
          )}
        </div>
        <div>
          <h2 className="text-[clamp(1.9rem,4vw,2.9rem)] font-bold leading-[1.02] tracking-[-0.04em]">{t("community_title")}</h2>
          <p className="mt-4 max-w-[48ch] text-[17px] leading-relaxed text-ink-muted">{t("community_body")}</p>
          <dl className="mt-6 grid max-w-[480px] gap-4 sm:grid-cols-2">
            <div><dt className="font-semibold">{t("jury_title")}</dt><dd className="mt-1 text-[15px] text-ink-muted">{t("jury_body")}</dd></div>
            <div><dt className="font-semibold">{t("public_title")}</dt><dd className="mt-1 text-[15px] text-ink-muted">{t("public_body")}</dd></div>
          </dl>
          <div className="mt-7 flex flex-wrap gap-3">
            <Link href="/contests" className={buttonClass("secondary")}>{t("see_contests")}</Link>
            <Link href="/communities" className={buttonClass("ghost")}>{t("see_communities")}</Link>
          </div>
        </div>
      </section>

      {/* Harita ve mesajlar */}
      <section className="mx-auto grid max-w-[1200px] items-center gap-10 px-4 pt-28 sm:px-6 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.15fr)] lg:gap-16">
        <div>
          <h2 className="text-[clamp(1.9rem,4vw,2.9rem)] font-bold leading-[1.02] tracking-[-0.04em]">{t("map_title")}</h2>
          <p className="mt-4 max-w-[48ch] text-[17px] leading-relaxed text-ink-muted">{t("map_body")}</p>
          <p className="mt-4 max-w-[48ch] text-[15px] text-ink-muted">{t("map_privacy")}</p>
          <Link href="/map" className={buttonClass("secondary", "mt-7")}><MapPin className="h-4 w-4" /> {t("open_map")}</Link>
        </div>
        <MapIllustration t={t} />
      </section>

      {/* Gökyüzü planlayıcı */}
      <section className="mx-auto grid max-w-[1200px] items-center gap-10 px-4 pt-28 sm:px-6 lg:grid-cols-[minmax(0,1.15fr)_minmax(0,1fr)] lg:gap-16">
        <div className="order-last lg:order-first"><PlannerTeaser /></div>
        <div>
          <h2 className="text-[clamp(1.9rem,4vw,2.9rem)] font-bold leading-[1.02] tracking-[-0.04em]">{t("sky_title")}</h2>
          <p className="mt-4 max-w-[48ch] text-[17px] leading-relaxed text-ink-muted">{t("sky_body")}</p>
          <p className="mt-4 max-w-[48ch] text-[15px] text-ink-muted">{t("sky_ar")}</p>
        </div>
      </section>

      {/* Rehber ve hesaplayıcılar */}
      <section className="mx-auto max-w-[1200px] px-4 pt-28 sm:px-6">
        <div className="grid gap-10 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.15fr)] lg:gap-16">
          <div>
            <h2 className="text-[clamp(1.9rem,4vw,2.9rem)] font-bold leading-[1.02] tracking-[-0.04em]">{t("guide_title")}</h2>
            <p className="mt-4 max-w-[48ch] text-[17px] leading-relaxed text-ink-muted">{t("guide_body")}</p>
            <div className="mt-6 inline-flex flex-col bg-black px-5 py-4 text-[#f2f2ee]">
              <span className="tnum text-[30px] font-semibold leading-none">{npf}</span>
              <span className="mt-2 text-[13px] text-[#8d8d88]">{t("guide_npf_example")}</span>
            </div>
          </div>
          {guides && guides.length > 0 && (
            <ul className="grid content-start gap-1 sm:grid-cols-2">
              {guides.map((g) => (
                <li key={g.slug} className="bg-surface">
                  <Link href={`/guide/${g.slug}`} className="block px-5 py-4 text-[16px] font-medium hover:bg-ink/[0.03]">{g.title}</Link>
                </li>
              ))}
            </ul>
          )}
        </div>
      </section>

      {/* Fiyat */}
      <section id="pricing" className="mx-auto max-w-[1200px] scroll-mt-20 px-4 pt-28 sm:px-6">
        <h2 className="text-[clamp(1.9rem,4vw,2.9rem)] font-bold leading-[1.02] tracking-[-0.04em]">{t("pricing_title")}</h2>
        <div className="mt-8 grid gap-px bg-line md:grid-cols-2">
          <div className="bg-surface p-6">
            <p className="text-lg font-semibold">{t("free_title")}</p>
            <p className="tnum mt-2 text-[34px] font-bold tracking-tight">{t("free_price")}</p>
            <ul className="mt-5 flex flex-col gap-2.5 text-[15px]">
              {(["free_1", "free_2", "free_3", "free_4"] as const).map((k) => <li key={k} className="flex gap-3"><Check className="mt-0.5 h-4 w-4 shrink-0 text-ink-muted" strokeWidth={3} /> {t(k)}</li>)}
            </ul>
            <Link href="/register" className={buttonClass("secondary", "mt-7")}>{t("cta")}</Link>
          </div>
          <div className="bg-ink p-6 text-surface">
            <p className="text-lg font-semibold">Pro</p>
            <p className="tnum mt-2 text-[34px] font-bold tracking-tight">{t("pro_price")}</p>
            <ul className="mt-5 flex flex-col gap-2.5 text-[15px]">
              {(["pro_1", "pro_2", "pro_3"] as const).map((k) => <li key={k} className="flex gap-3"><Check className="mt-0.5 h-4 w-4 shrink-0 text-accent-text" strokeWidth={3} /> {t(k)}</li>)}
            </ul>
            <Link href="/pro" className={buttonClass("secondary", "mt-7 border-surface/30 bg-transparent text-surface hover:border-surface")}>{t("pro_cta")}</Link>
          </div>
        </div>
      </section>

      {/* SSS */}
      <section className="mx-auto max-w-[1200px] px-4 pt-28 sm:px-6">
        <h2 className="text-[clamp(1.9rem,4vw,2.9rem)] font-bold leading-[1.02] tracking-[-0.04em]">{t("faq_title")}</h2>
        <div className="mt-6 max-w-[860px] divide-y divide-line border-y border-line">
          {(["free", "rights", "location", "contests", "formats"] as const).map((k) => (
            <details key={k} className="group py-4">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-4 text-[17px] font-semibold [&::-webkit-details-marker]:hidden">
                {t(`faq.${k}_q`)}
                <span aria-hidden className="text-2xl font-normal leading-none text-ink-muted transition-transform group-open:rotate-45">+</span>
              </summary>
              <p className="mt-3 max-w-[64ch] text-[15px] leading-relaxed text-ink-muted">{t(`faq.${k}_a`)}</p>
            </details>
          ))}
        </div>
      </section>

      {/* Kapanış */}
      <section className="mx-auto max-w-[1400px] px-4 pb-10 pt-28 sm:px-6">
        <h2 className="max-w-[14ch] text-[clamp(2.4rem,6.5vw,5rem)] font-bold leading-[0.95] tracking-[-0.05em]">{t("final_title")}</h2>
        <div className="mt-8 flex flex-wrap gap-3">
          <Link href="/register" className={buttonClass("primary", "h-12 px-6 text-base")}>{t("cta")}</Link>
          <Link href="/explore" className={buttonClass("secondary", "h-12 px-6 text-base")}>{t("explore")}</Link>
        </div>
      </section>

      <footer className="mx-auto mt-16 max-w-[1400px] border-t border-line px-4 py-8 text-sm text-ink-muted sm:px-6">
        <nav aria-label={t("footer_nav")} className="flex flex-wrap gap-x-6 gap-y-2">
          {([["/explore", "foot_explore"], ["/communities", "foot_communities"], ["/contests", "foot_contests"], ["/map", "foot_map"], ["/guide", "foot_guide"], ["/pro", "foot_pro"]] as const).map(([href, k]) => (
            <Link key={href} href={href} className="hover:text-ink">{t(k)}</Link>
          ))}
          <Link href="/" locale={locale === "tr" ? "en" : "tr"} className="hover:text-ink">{locale === "tr" ? "English" : "Türkçe"}</Link>
        </nav>
        <p className="mt-4">© {new Date().getFullYear()} Fotografya</p>
      </footer>
    </>
  );
}

/** Harita ve mesajlaşmayı anlatan çizim: gerçek ekranların sadeleştirilmiş hali (veri içermez). */
function MapIllustration({ t }: { t: (k: string) => string }) {
  const pins = [
    { x: 18, y: 38, n: "Deniz Şahin" }, { x: 44, y: 30, n: "Kerem Aydın" }, { x: 63, y: 46, n: "Burak Çelik" },
    { x: 81, y: 33, n: "Ece Yıldız" }, { x: 30, y: 64, n: "Selin Kaya" },
  ];
  return (
    <div aria-hidden className="relative">
      <div className="relative aspect-[4/3] overflow-hidden bg-surface" style={{ backgroundImage: "radial-gradient(color-mix(in srgb, var(--ink) 16%, transparent) 1.2px, transparent 1.3px)", backgroundSize: "14px 14px" }}>
        {pins.map((p, i) => (
          <span key={p.n} className="absolute -translate-x-1/2 -translate-y-1/2" style={{ left: `${p.x}%`, top: `${p.y}%` }}>
            <span className={i === 3 ? "block rounded-full ring-[3px] ring-accent" : "block rounded-full ring-[3px] ring-white"}><Avatar name={p.n} size={40} /></span>
          </span>
        ))}
        <span className="absolute left-[58%] top-[18%] inline-flex h-12 w-12 items-center justify-center rounded-full bg-ink text-[14px] font-semibold text-surface ring-4 ring-ink/15">12</span>
      </div>
      <div className="absolute -bottom-8 right-3 flex w-[min(320px,85%)] flex-col gap-2 sm:right-[-12px]">
        <p className="self-start rounded-[18px] rounded-bl-[6px] bg-surface px-3.5 py-2 text-[14px] shadow-[0_10px_30px_-12px_rgba(0,0,0,0.35)]">{t("chat_1")}</p>
        <p className="self-end rounded-[18px] rounded-br-[6px] bg-ink px-3.5 py-2 text-[14px] text-surface shadow-[0_10px_30px_-12px_rgba(0,0,0,0.35)]">{t("chat_2")}</p>
      </div>
    </div>
  );
}
