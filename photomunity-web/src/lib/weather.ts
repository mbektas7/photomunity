/**
 * Gece çekimi için hava tahmini: Open-Meteo (https://open-meteo.com — ücretsiz, anahtarsız) doğrudan
 * tarayıcıdan çağrılır. Saatlik bulut (toplam + alçak/orta/yüksek), nem ve rüzgâr gelir; astro.ts'in
 * gece planıyla (karanlık pencere, Ay) birleştirilip 0–100 arası basit bir "çekim puanı" üretilir.
 */
import type { NightPlan } from "./astro";

const ENDPOINT = "https://api.open-meteo.com/v1/forecast";

export type Hour = { t: number; cloud: number; low: number; mid: number; high: number; humidity: number; wind: number };

/** offset: konumun UTC farkı (sn, şu anki); saatler epoch ms. */
export type Forecast = { offset: number; hours: Hour[] };

type Raw = {
  utc_offset_seconds: number;
  hourly: {
    time: number[];
    cloud_cover: (number | null)[];
    cloud_cover_low: (number | null)[];
    cloud_cover_mid: (number | null)[];
    cloud_cover_high: (number | null)[];
    relative_humidity_2m: (number | null)[];
    wind_speed_10m: (number | null)[];
  };
};

/** 7 günlük saatlik tahmin. timeformat=unixtime: saatler mutlak zaman, saat dilimi karışmaz. */
export async function fetchForecast(lat: number, lng: number, signal?: AbortSignal): Promise<Forecast> {
  const qs = new URLSearchParams({
    latitude: lat.toFixed(3),
    longitude: lng.toFixed(3),
    hourly: "cloud_cover,cloud_cover_low,cloud_cover_mid,cloud_cover_high,relative_humidity_2m,wind_speed_10m",
    timezone: "auto",
    timeformat: "unixtime",
    forecast_days: "7",
    wind_speed_unit: "kmh",
  });
  const res = await fetch(`${ENDPOINT}?${qs}`, { signal });
  if (!res.ok) throw new Error(`open-meteo ${res.status}`);
  const d = (await res.json()) as Raw;
  const h = d.hourly;
  const hours: Hour[] = [];
  h.time.forEach((t, i) => {
    const cloud = h.cloud_cover[i];
    if (cloud == null) return;
    hours.push({
      t: t * 1000,
      cloud,
      low: h.cloud_cover_low[i] ?? cloud,
      mid: h.cloud_cover_mid[i] ?? cloud,
      high: h.cloud_cover_high[i] ?? cloud,
      humidity: h.relative_humidity_2m[i] ?? 0,
      wind: h.wind_speed_10m[i] ?? 0,
    });
  });
  return { offset: d.utc_offset_seconds, hours };
}

/** Yalnızca konumun UTC farkı (EXIF'teki yerel saati mutlak zamana çevirmek için). */
export async function fetchUtcOffset(lat: number, lng: number): Promise<number> {
  const qs = new URLSearchParams({ latitude: lat.toFixed(3), longitude: lng.toFixed(3), timezone: "auto", forecast_days: "1", daily: "sunrise" });
  const res = await fetch(`${ENDPOINT}?${qs}`);
  if (!res.ok) throw new Error(`open-meteo ${res.status}`);
  return ((await res.json()) as { utc_offset_seconds: number }).utc_offset_seconds;
}

export type Span = { start: number; end: number };

const longest = (spans: Span[]) => spans.reduce<Span | null>((m, s) => (!m || s.end - s.start > m.end - m.start ? s : m), null);

function spansWhere(plan: NightPlan, ok: (s: NightPlan["samples"][number]) => boolean): Span[] {
  const out: Span[] = [];
  let open: number | null = null;
  for (const s of plan.samples) {
    if (ok(s) && open === null) open = s.t;
    if (!ok(s) && open !== null) {
      out.push({ start: open, end: s.t });
      open = null;
    }
  }
  if (open !== null) out.push({ start: open, end: plan.samples.at(-1)!.t });
  return out;
}

/**
 * Gecenin karanlık kısmı: Güneş −18° altı (astronomik karanlık). Yaz aylarında yüksek enlemlerde hiç
 * yoksa −12°, o da yoksa −6° kullanılır.
 */
export function darkSpan(plan: NightPlan): Span | null {
  for (const lvl of [-18, -12, -6]) {
    const s = longest(spansWhere(plan, (x) => x.sun.alt <= lvl));
    if (s) return s;
  }
  return null;
}

/** Çekim penceresi: karanlık + Ay ufkun altında (ya da %25'ten az aydınlık). Yoksa karanlık pencerenin tamamı. */
export function shootingWindow(plan: NightPlan): Span | null {
  const dark = darkSpan(plan);
  if (!dark) return null;
  const moonOk = (x: NightPlan["samples"][number]) => x.moon.alt < 0 || plan.illumination < 0.25;
  return longest(spansWhere(plan, (x) => x.t >= dark.start && x.t <= dark.end && moonOk(x))) ?? dark;
}

/** Karanlık pencere boyunca Ay ışığı: aydınlanma × Ay'ın ufkun üstünde olduğu sürenin oranı (0–1). */
export function moonLight(plan: NightPlan, span: Span | null): number {
  if (!span) return plan.illumination;
  const inside = plan.samples.filter((s) => s.t >= span.start && s.t <= span.end);
  if (!inside.length) return plan.illumination;
  return plan.illumination * (inside.filter((s) => s.moon.alt > 0).length / inside.length);
}

export type NightWeather = { cloud: number; effectiveCloud: number; humidity: number; wind: number; hours: number };

/** Karanlık penceredeki saatlerin ortalaması; pencere tahmin aralığında değilse null. */
export function nightWeather(f: Forecast, span: Span | null): NightWeather | null {
  if (!span) return null;
  // Saatlik değer o saatin başını temsil eder; pencereye yarım saat pay tanı
  const hrs = f.hours.filter((h) => h.t >= span.start - 1_800_000 && h.t <= span.end + 1_800_000);
  if (!hrs.length) return null;
  const avg = (k: (h: Hour) => number) => hrs.reduce((s, h) => s + k(h), 0) / hrs.length;
  return {
    cloud: avg((h) => h.cloud),
    effectiveCloud: avg(effectiveCloud),
    humidity: avg((h) => h.humidity),
    wind: avg((h) => h.wind),
    hours: hrs.length,
  };
}

/**
 * Gökyüzünü gerçekten kapatan bulut: alçak ve orta bulut yıldızları tamamen örter, yüksek ince bulut
 * (sirrus) yarı geçirgendir. Toplam örtü ile katmanların en kötüsünün ortalaması alınır.
 */
export function effectiveCloud(h: Hour): number {
  const worst = Math.max(h.low, 0.85 * h.mid, 0.5 * h.high);
  return Math.min(100, (h.cloud + worst) / 2);
}

/** Yalnızca bulut örtüsünden saatlik değer (bir anlık hedef için: plan ve etkinlik). */
export function cloudAt(f: Forecast, t: number): number | null {
  let best: Hour | null = null;
  for (const h of f.hours) if (!best || Math.abs(h.t - t) < Math.abs(best.t - t)) best = h;
  return best && Math.abs(best.t - t) <= 90 * 60_000 ? best.cloud : null;
}

/**
 * Gece çekimi puanı (0–100). Çarpımsal; her etken ayrı ayrı puanı düşürür:
 *
 *   puan = 100 × açıklık^1.5 × ayFaktörü × nemFaktörü × rüzgârFaktörü
 *
 * - açıklık = 1 − etkinBulut/100. Üs 1.5: %30 bulut bile puanı belirgin düşürür (≈%59), %70 bulutta ≈%16.
 * - ayFaktörü = 1 − 0.6 × ayIşığı. ayIşığı = aydınlanma × Ay'ın karanlık pencerede ufkun üstünde kaldığı oran.
 *   Dolunay bütün gece gökteyse puan %40'a iner (Ay'lı manzara hâlâ çekilebilir, sıfırlamıyoruz).
 * - nemFaktörü: %70'e kadar 1; %100'de 0.8'e doğrusal iner (pus, lenste çiy).
 * - rüzgârFaktörü: 15 km/s'e kadar 1; 40 km/s ve üstünde 0.75'e doğrusal iner (tripod titremesi).
 *
 * Etiketler: ≥70 iyi, 40–69 orta, <40 kötü.
 */
export function shootScore(w: NightWeather, moon: number): number {
  const clear = 1 - Math.max(0, Math.min(100, w.effectiveCloud)) / 100;
  const moonF = 1 - 0.6 * Math.max(0, Math.min(1, moon));
  const humF = w.humidity <= 70 ? 1 : 1 - 0.2 * Math.min(1, (w.humidity - 70) / 30);
  const windF = w.wind <= 15 ? 1 : 1 - 0.25 * Math.min(1, (w.wind - 15) / 25);
  return Math.round(100 * Math.pow(clear, 1.5) * moonF * humF * windF);
}

export type ScoreLabel = "good" | "fair" | "poor";
export const scoreLabel = (score: number): ScoreLabel => (score >= 70 ? "good" : score >= 40 ? "fair" : "poor");

/** Başlık için daha ince ayrım. */
export const scoreVerdict = (score: number) => (score >= 85 ? "excellent" : score >= 70 ? "good" : score >= 40 ? "fair" : "poor");
