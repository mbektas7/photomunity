import type { NextConfig } from "next";
import createNextIntlPlugin from "next-intl/plugin";

const withNextIntl = createNextIntlPlugin("./src/i18n/request.ts");

const nextConfig: NextConfig = {
  reactStrictMode: true,
  // Docker imajı için: yalnızca çalışma zamanında gereken dosyalar (.next/standalone)
  output: "standalone",
};

export default withNextIntl(nextConfig);
