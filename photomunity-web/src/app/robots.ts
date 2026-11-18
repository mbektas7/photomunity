import type { MetadataRoute } from "next";

const SITE = process.env.NEXT_PUBLIC_SITE_URL || "https://photomunity.com";

export default function robots(): MetadataRoute.Robots {
  return {
    // Kişisel sayfalar ve API vekili taranmaz
    rules: { userAgent: "*", allow: "/", disallow: ["/api/", "/*/messages", "/*/settings", "/*/notifications", "/*/upload", "/*/feed"] },
    sitemap: `${SITE}/sitemap.xml`,
  };
}
