/**
 * Fotoğraf hesaplayıcıları. Mobilde lib/core/calculators.dart ile birebir aynıdır;
 * ikisi de aynı Python başvuru değerleriyle doğrulanır.
 */
export type SensorId = "ff" | "apsc" | "apsc_canon" | "mft" | "one_inch" | "mf";

export const SENSORS: Record<SensorId, { w: number; h: number }> = {
  ff: { w: 36, h: 24 },
  apsc: { w: 23.5, h: 15.6 },
  apsc_canon: { w: 22.3, h: 14.9 },
  mft: { w: 17.3, h: 13 },
  one_inch: { w: 13.2, h: 8.8 },
  mf: { w: 43.8, h: 32.9 },
};

const FF_DIAG = Math.hypot(36, 24);
const RAD = Math.PI / 180;

export const cropFactor = (s: SensorId) => FF_DIAG / Math.hypot(SENSORS[s].w, SENSORS[s].h);

/** Piksel aralığı (µm): sensör genişliği / yatay piksel sayısı. */
export function pixelPitch(s: SensorId, megapixels: number) {
  const { w, h } = SENSORS[s];
  return (w / Math.sqrt((megapixels * 1e6 * w) / h)) * 1000;
}

/**
 * NPF kuralı (Frédéric Michaud): yıldızların nokta kalacağı en uzun pozlama (sn).
 * Eğim (declination) 0° en hızlı hareket eden yıldızlar içindir; Samanyolu çekirdeği −29°'de olduğu için biraz daha uzun süre tanır.
 */
export function npfSeconds(s: SensorId, megapixels: number, focal: number, aperture: number, declinationDeg = 0) {
  const p = pixelPitch(s, megapixels);
  return (16.856 * aperture + 0.0997 * focal + 13.713 * p) / (focal * Math.cos(declinationDeg * RAD));
}

/** Klasik 500 kuralı (yüksek çözünürlüklü sensörlerde yıldızlar hafif uzar). */
export const rule500Seconds = (s: SensorId, focal: number) => 500 / (focal * cropFactor(s));

export const circleOfConfusion = (s: SensorId) => Math.hypot(SENSORS[s].w, SENSORS[s].h) / 1442;

/** Alan derinliği; mesafeler metre. Arka sınır hiperfokalin ötesinde sonsuzdur (null). */
export function depthOfField(s: SensorId, focal: number, aperture: number, distanceM: number) {
  const c = circleOfConfusion(s);
  const H = (focal * focal) / (aperture * c) + focal;
  const x = distanceM * 1000;
  const near = (x * (H - focal)) / (H + x - 2 * focal);
  const far = x < H ? (x * (H - focal)) / (H - x) : null;
  return { hyperfocal: H / 1000, near: near / 1000, far: far === null ? null : far / 1000 };
}

export const ndSeconds = (base: number, stops: number) => base * 2 ** stops;

export const ND_FILTERS = [
  { label: "ND8", stops: 3 },
  { label: "ND64", stops: 6 },
  { label: "ND1000", stops: 10 },
  { label: "ND32000", stops: 15 },
];

export const SHUTTER_SPEEDS = [1 / 8000, 1 / 4000, 1 / 2000, 1 / 1000, 1 / 500, 1 / 250, 1 / 125, 1 / 60, 1 / 30, 1 / 15, 1 / 8, 1 / 4, 1 / 2, 1, 2, 4, 8, 15, 30];

export function formatShutter(seconds: number, locale: string) {
  if (seconds < 0.5) return `1/${Math.round(1 / seconds)}`;
  if (seconds < 60) {
    const n = seconds < 10 ? String(Number(seconds.toFixed(1))) : String(Math.round(seconds));
    return locale === "tr" ? `${n.replace(".", ",")} sn` : `${n} s`;
  }
  const m = Math.floor(seconds / 60), s = Math.round(seconds % 60);
  if (seconds < 3600) return locale === "tr" ? `${m} dk ${s} sn` : `${m} min ${s} s`;
  const h = Math.floor(seconds / 3600), mm = Math.round((seconds % 3600) / 60);
  return locale === "tr" ? `${h} sa ${mm} dk` : `${h} h ${mm} min`;
}

export function formatDistance(m: number | null, locale: string) {
  if (m === null) return "∞";
  if (m < 1) return `${Math.round(m * 100)} cm`;
  return `${m < 10 ? m.toFixed(2) : m.toFixed(1)} m`.replace(".", locale === "tr" ? "," : ".");
}
