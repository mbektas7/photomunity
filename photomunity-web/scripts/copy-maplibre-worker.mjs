// MapLibre'nin web worker'ını public/ altına sürüm numaralı adla kopyalar.
// Next.js paketlemesi kütüphanenin import.meta.url'e göre bulduğu worker yolunu koruyamadığı için
// harita bileşeni worker'ı bu sabit adresten yükler (setWorkerUrl).
import { copyFileSync, mkdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const pkg = JSON.parse(readFileSync(join(root, "node_modules/maplibre-gl/package.json"), "utf8"));
mkdirSync(join(root, "public/vendor"), { recursive: true });
copyFileSync(join(root, "node_modules/maplibre-gl/dist/maplibre-gl-worker.mjs"), join(root, `public/vendor/maplibre-gl-worker-${pkg.version}.mjs`));
console.log(`maplibre worker ${pkg.version} kopyalandı`);
