import { BookOpen, Check, MapPin, Moon, Plus } from "lucide-react";
import type { Metadata } from "next";
import { getTranslations, setRequestLocale } from "next-intl/server";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { Avatar } from "@/components/Avatar";
import { Countdown, LiveBadge } from "@/components/Countdown";
import { ExifChips, ExifGrid } from "@/components/ExifChip";
import { StoryRing } from "@/components/StoryRing";
import { JustifiedWall } from "@/components/JustifiedWall";
import { PlannerTeaser } from "@/components/landing/PlannerTeaser";
import { buttonClass } from "@/lib/button-class";
import { Link } from "@/i18n/navigation";
import { routing } from "@/i18n/routing";
import { formatShutter, npfSeconds } from "@/lib/calculators";
import { serverGet } from "@/lib/server-api";
import type { CommunityCard, ContestCard, Page, PhotoCard, PhotoDetail } from "@/lib/types";

const SITE = process.env.NEXT_PUBLIC_SITE_URL || "https://photomunity.com";
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
    openGraph: { type: "website", url: `${SITE}/${locale}`, siteName: "Photomunity", title: t("meta_title"), description: t("meta_description"),
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
  const [stats, wall, openContests, judging, guides, communities] = await Promise.all([
    serverGet<Stats>("stats/public", locale),
    serverGet<Page<PhotoCard>>("explore?limit=40", locale),
    serverGet<ContestCard[]>("contests?status=open&limit=1", locale),
    serverGet<ContestCard[]>("contests?status=judging&limit=1", locale),
    serverGet<GuideCard[]>("guides", locale),
    serverGet<CommunityCard[]>("communities?limit=4", locale),
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
  const featured = judging?.[0] ?? openContests?.[0] ?? null;
  const nf = new Intl.NumberFormat(locale);
  const readouts = stats && stats.photographers >= STATS_MIN
    ? ([["photographers", stats.photographers], ["photos", stats.photos], ["communities", stats.communities], ["countries", stats.countries], ["open_contests", stats.open_contests]] as const).filter(([, n]) => n > 0)
    : [];
  const npf = formatShutter(npfSeconds("ff", 24, 14, 1.8), locale);
  const jsonLd = {
    "@context": "https://schema.org",
    "@graph": [
      { "@type": "WebSite", name: "Photomunity", url: SITE, inLanguage: locale, potentialAction: { "@type": "SearchAction", target: `${SITE}/${locale}/communities?q={q}`, "query-input": "required name=q" } },
      { "@type": "SoftwareApplication", name: "Photomunity", applicationCategory: "PhotographyApplication", operatingSystem: "iOS, Android, Web",
        offers: { "@type": "Offer", price: "0", priceCurrency: "USD" }, description: t("meta_description") },
    ],
  };

  const heroImg = exifPhoto?.images.feed;
  const featuredAt = featured ? (featured.status === "open" ? featured.submission_deadline : featured.voting_end) : null;
  const featuredDays = featuredAt ? Math.max(0, Math.ceil((new Date(featuredAt).getTime() - Date.now()) / 86_400_000)) : 0;
  const tc = await getTranslations("contests");
  const tp = await getTranslations("photo");
  const H2 = "text-[clamp(2rem,4vw,2.6rem)] font-bold leading-[1.02] tracking-[-0.04em]";

  return (
    <>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }} />

      {/* Giriş */}
      <section className="mx-auto grid max-w-[1440px] items-center gap-12 px-5 pb-12 pt-8 sm:px-10 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.05fr)] lg:pt-14">
        <div>
          <h1 className="max-w-[12ch] text-[clamp(2.9rem,6.4vw,5.3rem)] font-bold leading-[0.93] tracking-[-0.055em]">{t("title")}</h1>
          <p className="mt-7 max-w-[52ch] text-[17px] leading-[1.6] text-ink-muted">{t("lead")}</p>
          <div className="mt-8 flex flex-wrap items-center gap-3">
            <Link href="/register" className={buttonClass("primary", "h-14 rounded-box px-5 text-[16px] font-bold")}>{t("cta")}</Link>
            <Link href="/explore" className={buttonClass("ghost", "h-14 rounded-box bg-surface px-5 text-[16px] font-bold hover:bg-surface-2")}>{t("explore")}</Link>
          </div>
          <p className="mt-7 flex flex-wrap gap-x-4 gap-y-1 text-[14px] text-ink-muted">
            <span>{t("platforms")}</span>
            {APP_STORE && <a href={APP_STORE} className="font-semibold text-accent-text hover:underline">{t("ios")}</a>}
            {PLAY_STORE && <a href={PLAY_STORE} className="font-semibold text-accent-text hover:underline">{t("android")}</a>}
          </p>
          {readouts.length > 0 && (
            <dl aria-label={t("stats_label")} className="mt-6 flex flex-wrap gap-2">
              {readouts.map(([k, n]) => (
                <div key={k} className="flex flex-col-reverse rounded-box bg-surface px-4 py-2.5">
                  <dt className="text-caption text-ink-muted">{t(`stat.${k}`)}</dt>
                  <dd className="tnum text-[22px] font-bold tracking-[-0.03em]">{nf.format(n)}</dd>
                </div>
              ))}
            </dl>
          )}
        </div>

        {/* Gerçek bir kare ve canlı yarışma; tanıtımın vitrini */}
        <div className="relative pb-24 lg:pb-28">
          {exifPhoto && heroImg && (
            <article className="ml-auto w-full max-w-[500px] rounded-card bg-surface p-3.5 shadow-float">
              <header className="flex items-center gap-3 px-1 pb-3">
                <Avatar name={exifPhoto.user.display_name} url={exifPhoto.user.avatar_url} size={40} />
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-[15px] font-semibold">{exifPhoto.user.display_name}</span>
                  {exifPhoto.location?.name && <span className="block truncate text-[12.5px] text-ink-muted">{exifPhoto.location.name}</span>}
                </span>
                <Link href={`/u/${exifPhoto.user.username}`} className={buttonClass("primary", "h-9 min-h-9 px-4 text-[14px]")}>{tp("view_profile")}</Link>
              </header>
              <Link href={`/p/${exifPhoto.id}`} className="block rounded-photo">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={heroImg.url} alt={exifPhoto.title ?? ""} width={heroImg.width} height={heroImg.height} className="block h-auto w-full rounded-photo" />
              </Link>
              <footer className="flex justify-end px-1 pt-3">
                <ExifChips exif={exifPhoto.exif} locale={locale} />
              </footer>
            </article>
          )}
          {featured && featuredAt && (
            <Link
              href={`/contests/${featured.id}`}
              className="absolute bottom-0 left-0 w-[min(366px,92%)] rounded-card bg-surface p-[18px] shadow-float lg:left-[-14px]"
            >
              <span className="flex items-center gap-2">
                <LiveBadge size="sm">{featured.status === "open" ? tc("phase_open") : tc("phase_voting")}</LiveBadge>
                <span className="truncate text-[12.5px] text-ink-muted">{featured.community.name}</span>
              </span>
              <span className="mt-2 block text-[21px] font-bold tracking-[-0.02em]">{featured.title}</span>
              <Countdown until={featuredAt} srLabel={featured.status === "open" ? tc("countdown_deadline") : tc("countdown_voting")} className="mt-3" />
            </Link>
          )}
        </div>
      </section>

      {/* Üç özellik kartı */}
      <section className="mx-auto grid max-w-[1440px] gap-4 px-5 sm:px-10 lg:grid-cols-3">
        <article className="flex flex-col gap-4 rounded-card bg-surface p-5 sm:p-6">
          {exifPhoto?.exif && (
            <ExifGrid exif={exifPhoto.exif} locale={locale} labels={{ shutter: tp("shutter"), aperture: tp("aperture"), iso: "ISO", focal: tp("focal_short") }} />
          )}
          <h2 className="text-[20px] font-bold tracking-[-0.02em]">{t("exif_title")}</h2>
          <p className="text-[15px] leading-[1.55] text-ink-muted">{t("exif_body")}</p>
        </article>
        <article className="flex flex-col gap-4 rounded-card bg-surface p-5 sm:p-6">
          <div className="no-scrollbar flex gap-2 overflow-x-auto pt-2">
            {featured && (
              <StoryRing href={`/contests/${featured.id}`} label={featured.title} image={featured.community.logo_url} state="live" badge={featuredDays ? t("days_badge", { count: featuredDays }) : null} size={64} />
            )}
            {(communities ?? []).slice(0, featured ? 3 : 4).map((c) => (
              <StoryRing key={c.id} href={`/c/${c.slug}`} label={c.name} image={c.logo_url} state="accent" size={64} />
            ))}
          </div>
          <h2 className="text-[20px] font-bold tracking-[-0.02em]">{t("community_title")}</h2>
          <p className="text-[15px] leading-[1.55] text-ink-muted">{t("community_body")}</p>
          <div className="mt-auto flex flex-wrap gap-2">
            <Link href="/contests" className={buttonClass("secondary", "h-10 min-h-10 px-4 text-[14px]")}>{t("see_contests")}</Link>
            <Link href="/communities" className={buttonClass("ghost", "h-10 min-h-10 px-4 text-[14px]")}>{t("see_communities")}</Link>
          </div>
        </article>
        <article className="flex flex-col gap-4 rounded-card bg-surface p-5 sm:p-6">
          <MapIllustration photos={wall?.items ?? []} />
          <h2 className="text-[20px] font-bold tracking-[-0.02em]">{t("map_title")}</h2>
          <p className="text-[15px] leading-[1.55] text-ink-muted">{t("map_body")} {t("map_privacy")}</p>
          <Link href="/map" className={buttonClass("secondary", "mt-auto h-10 min-h-10 self-start px-4 text-[14px]")}><MapPin className="h-4 w-4" strokeWidth={1.8} aria-hidden /> {t("open_map")}</Link>
        </article>
      </section>

      {/* Gökyüzü planlayıcı */}
      <section className="mx-auto max-w-[1440px] px-5 pt-8 sm:px-10">
        <div className="grid items-center gap-8 rounded-card bg-surface p-6 sm:rounded-[28px] sm:p-9 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.05fr)]">
          <div>
            <h2 className={H2}>{t("sky_title")}</h2>
            <p className="mt-4 max-w-[60ch] text-[16px] leading-[1.6] text-ink-muted">{t("sky_body")} {t("sky_ar")}</p>
            <div className="mt-6 flex flex-wrap gap-2.5">
              <Link href="/planner" className={buttonClass("primary")}><Moon className="h-[18px] w-[18px]" strokeWidth={1.9} aria-hidden /> {t("planner_open")}</Link>
              <Link href="/guide" className={buttonClass("secondary")}><BookOpen className="h-[18px] w-[18px]" strokeWidth={1.8} aria-hidden /> {t("guide_link")}</Link>
            </div>
          </div>
          <PlannerTeaser />
        </div>
      </section>

      {/* Son paylaşılanlar (gerçek veri) */}
      {wall && wall.items.length > 0 && (
        <section aria-labelledby="wall-title" className="mx-auto max-w-[1440px] px-5 pt-16 sm:px-10">
          <h2 id="wall-title" className={H2}>{t("wall")}</h2>
          <div className="mt-6">
            <JustifiedWall photos={wall.items} target={300} completeRowsOnly maxRows={3} />
          </div>
        </section>
      )}

      {/* Fiyat */}
      <section id="pricing" className="mx-auto max-w-[1440px] scroll-mt-20 px-5 pt-16 sm:px-10">
        <h2 className={H2}>{t("pricing_title")}</h2>
        <div className="mt-7 grid gap-4 md:grid-cols-2">
          <div className="flex flex-col rounded-card bg-surface p-6 sm:p-7">
            <p className="text-[17px] font-bold">{t("free_title")}</p>
            <p className="tnum mt-3 flex items-baseline gap-2 text-[40px] font-bold leading-none tracking-[-0.04em]">{t("free_price")} <span className="text-[14px] font-medium tracking-normal text-ink-muted">{t("free_period")}</span></p>
            <ul className="mt-5 flex flex-col gap-2.5 text-[15px]">
              {(["free_1", "free_2", "free_3", "free_4"] as const).map((k) => <li key={k} className="flex gap-3"><Check className="mt-0.5 h-[18px] w-[18px] shrink-0" strokeWidth={2.1} aria-hidden /> {t(k)}</li>)}
            </ul>
            <Link href="/register" className={buttonClass("large", "mt-8 !bg-surface-2 !text-ink hover:!bg-line")}>{t("free_cta")}</Link>
          </div>
          <div className="flex flex-col rounded-card bg-accent p-6 text-accent-ink sm:p-7">
            <p className="text-[17px] font-bold">Pro</p>
            <p className="tnum mt-3 flex items-baseline gap-2 text-[40px] font-bold leading-none tracking-[-0.04em]">{t("pro_price_amount")} <span className="text-[14px] font-medium tracking-normal opacity-85">{t("pro_period")}</span></p>
            <ul className="mt-5 flex flex-col gap-2.5 text-[15px]">
              {(["pro_1", "pro_2", "pro_3"] as const).map((k) => <li key={k} className="flex gap-3"><Check className="mt-0.5 h-[18px] w-[18px] shrink-0" strokeWidth={2.1} aria-hidden /> {t(k)}</li>)}
            </ul>
            <Link href="/pro" className={buttonClass("large", "mt-8 !bg-white !text-[#2a55f5] hover:!bg-white/90")}>{t("pro_cta")}</Link>
          </div>
        </div>
      </section>

      {/* Rehber ve SSS */}
      <section className="mx-auto grid max-w-[1440px] gap-4 px-5 pt-16 sm:px-10 lg:grid-cols-2">
        <div className="rounded-card bg-surface p-6 sm:p-7">
          <h2 className="text-[22px] font-bold tracking-[-0.02em]">{t("guide_title")}</h2>
          <p className="mt-2 text-[15px] leading-[1.55] text-ink-muted">{t("guide_body")}</p>
          <p className="mt-4 inline-flex flex-col rounded-box bg-surface-2 px-4 py-3">
            <span className="tnum text-numeral">{npf}</span>
            <span className="mt-1.5 text-caption text-ink-muted">{t("guide_npf_example")}</span>
          </p>
          {guides && guides.length > 0 && (
            <ul className="mt-5 grid gap-2 sm:grid-cols-2">
              {guides.map((g) => (
                <li key={g.slug}>
                  <Link href={`/guide/${g.slug}`} className="flex min-h-11 items-center rounded-box bg-surface-2 px-4 py-2.5 text-[15px] font-semibold hover:bg-line">{g.title}</Link>
                </li>
              ))}
            </ul>
          )}
        </div>
        <div className="rounded-card bg-surface p-6 sm:p-7">
          <h2 className="text-[22px] font-bold tracking-[-0.02em]">{t("faq_title")}</h2>
          <div className="mt-3">
            {(["free", "rights", "location", "contests", "formats"] as const).map((k) => (
              <details key={k} className="group border-t border-line py-3.5 first:border-t-0">
                <summary className="flex min-h-11 cursor-pointer list-none items-center justify-between gap-4 text-[16px] font-semibold [&::-webkit-details-marker]:hidden">
                  {t(`faq.${k}_q`)}
                  <Plus className="h-5 w-5 shrink-0 text-ink-muted transition-transform group-open:rotate-45" strokeWidth={1.8} aria-hidden />
                </summary>
                <p className="mt-1 text-[15px] leading-[1.55] text-ink-muted">{t(`faq.${k}_a`)}</p>
              </details>
            ))}
          </div>
        </div>
      </section>

      {/* Kapanış */}
      <section className="mx-auto max-w-[1440px] px-5 pt-16 sm:px-10">
        <div className="flex flex-wrap items-center justify-between gap-6 border-t border-line pt-10">
          <h2 className="text-[clamp(2.4rem,5vw,3.6rem)] font-bold leading-[0.95] tracking-[-0.05em]">{t("final_title")}</h2>
          <div className="flex flex-wrap gap-3">
            <Link href="/register" className={buttonClass("primary", "h-14 rounded-box px-5 text-[16px] font-bold")}>{t("cta")}</Link>
            <Link href="/explore" className={buttonClass("ghost", "h-14 rounded-box bg-surface px-5 text-[16px] font-bold hover:bg-surface-2")}>{t("explore")}</Link>
          </div>
        </div>
      </section>

      <footer className="mx-auto mt-14 max-w-[1440px] px-5 py-8 text-sm text-ink-muted sm:px-10">
        <nav aria-label={t("footer_nav")} className="flex flex-wrap gap-x-6 gap-y-2">
          {([["/explore", "foot_explore"], ["/communities", "foot_communities"], ["/contests", "foot_contests"], ["/map", "foot_map"], ["/guide", "foot_guide"], ["/pro", "foot_pro"], ["/privacy", "foot_privacy"], ["/terms", "foot_terms"]] as const).map(([href, k]) => (
            <Link key={href} href={href} className="inline-flex min-h-11 items-center hover:text-ink">{t(k)}</Link>
          ))}
          <Link href="/" locale={locale === "tr" ? "en" : "tr"} className="inline-flex min-h-11 items-center hover:text-ink">{locale === "tr" ? "English" : "Türkçe"}</Link>
        </nav>
        <p className="mt-2">© {new Date().getFullYear()} Photomunity</p>
      </footer>
    </>
  );
}

/** Harita kartındaki sade çizim: gerçek kareler iğne olarak, bir küme rozeti (veri değil, süs). */
function MapIllustration({ photos }: { photos: PhotoCard[] }) {
  const spots = [
    { x: 64, y: 34 }, { x: 19, y: 74 }, { x: 53, y: 80 }, { x: 77, y: 70 },
  ];
  const thumbs = photos.map((p) => p.images.thumb?.url).filter(Boolean).slice(0, 4) as string[];
  return (
    <div aria-hidden className="relative h-[150px] overflow-hidden rounded-photo bg-surface-2">
      <span className="absolute -left-6 -top-14 h-[110px] w-[200px] rounded-full bg-accent-tint" />
      {thumbs.map((src, i) => (
        // eslint-disable-next-line @next/next/no-img-element
        <img key={src} src={src} alt="" className={`absolute h-9 w-9 -translate-x-1/2 -translate-y-1/2 rounded-full border-[3px] object-cover ${i === 3 ? "border-accent" : "border-surface"}`} style={{ left: `${spots[i]!.x}%`, top: `${spots[i]!.y}%` }} />
      ))}
      <span className="absolute left-[37%] top-[45%] inline-flex h-11 w-11 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full bg-accent text-[14px] font-bold text-accent-ink ring-[5px] ring-accent/25">12</span>
    </div>
  );
}
