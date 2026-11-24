/**
 * Çekim planı yardımcıları: plan türüne göre önerilen saat ve "Bu kareyi tekrar çek" araması.
 * Tüm hesaplar astro.ts / sky.ts üzerine kuruludur; saatler tarayıcının saat diliminde gösterilir.
 */
import { type AltAz, corePosition, moonIllumination, moonPosition, planNight, sunPosition } from "./astro";
import { planDay } from "./sky";
import type { PlanKind } from "./types";

const MIN = 60_000;
const DAY = 86_400_000;
/** Yıldız günü: gökyüzündeki sabit bir nokta (ör. galaktik çekirdek) aynı yere bu kadar sürede döner. */
const SIDEREAL_DAY = 86_164_090.5;

/** Gece türleri (Samanyolu, meteor): seçilen tarih "o gecenin" tarihidir; öğleden önceki saat ertesi sabahtır. */
export const isNightKind = (k: PlanKind) => k === "milkyway" || k === "meteor";

/** Gecenin karanlık kısmında çekirdeğin en yüksek olduğu an (sky sayfasındaki "bu gece" ile aynı kural). */
export function corePeakInDarkness(date: Date, lat: number, lng: number) {
  const plan = planNight(date, lat, lng);
  const dark = plan.samples.filter((x) => x.sun.alt < -18);
  const pool = dark.length ? dark : plan.samples.filter((x) => x.sun.alt < -12);
  const top = pool.reduce<(typeof pool)[number] | null>((m, x) => (!m || x.core.alt > m.core.alt ? x : m), null);
  return { plan, peak: top && top.core.alt > 0 ? { t: top.t, alt: top.core.alt, az: top.core.az } : null };
}

export type Suggestion = { t: number; note: "core_peak" | "dusk" | "golden_evening" | "golden_morning" | "blue_evening" | "blue_morning" | "moonrise" | "meteor" | null; az?: number; alt?: number };

/**
 * Plan türü ve gün için önerilen hedef zaman:
 * - Samanyolu: karanlıkta çekirdeğin en yüksek anı (yoksa astronomik karanlığın başı)
 * - Altın / mavi saat: akşamki başlangıç (yoksa sabahki)
 * - Ay doğuşu: o günkü doğuş
 * - Meteor: şafaktan (astronomik) bir saat önce — radyant en yüksekte, oran en fazla
 */
export function suggestTime(kind: PlanKind, date: Date, lat: number, lng: number): Suggestion | null {
  const day = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  if (kind === "milkyway") {
    const { plan, peak } = corePeakInDarkness(day, lat, lng);
    if (peak) return { t: peak.t, note: "core_peak", az: peak.az, alt: peak.alt };
    return plan.duskAstro ? { t: plan.duskAstro, note: "dusk" } : null;
  }
  if (kind === "meteor") {
    const plan = planNight(day, lat, lng);
    return plan.dawnAstro ? { t: plan.dawnAstro - 60 * MIN, note: "meteor" } : null;
  }
  const p = planDay(day, lat, lng);
  if (kind === "golden") {
    if (p.goldenEvening) return { t: p.goldenEvening.start, note: "golden_evening" };
    if (p.goldenMorning) return { t: p.goldenMorning.start, note: "golden_morning" };
  }
  if (kind === "blue") {
    if (p.blueEvening) return { t: p.blueEvening.start, note: "blue_evening" };
    if (p.blueMorning) return { t: p.blueMorning.start, note: "blue_morning" };
  }
  if (kind === "moonrise" && p.moonrise) return { t: p.moonrise.t, note: "moonrise", az: p.moonrise.az };
  return null;
}

// ---------------------------------------------------------------- Bu kareyi tekrar çek

export type Capture = { t: number; sun: AltAz; moon: AltAz; core: AltAz; moonFraction: number; mode: "core" | "sun" | "none" };

/**
 * Çekim anındaki gökyüzü. Gece (Güneş −12° altı) ve çekirdek ufkun üstündeyse "core" modu;
 * gündüz/alacakaranlıkta "sun" modu; çekirdeksiz gece karesi için eşleşme aranmaz ("none").
 */
export function captureSky(t: number, lat: number, lng: number): Capture {
  const sun = sunPosition(t, lat, lng);
  const core = corePosition(t, lat, lng);
  const mode = sun.alt < -12 ? (core.alt > 0 ? "core" : "none") : "sun";
  return { t, sun, core, moon: moonPosition(t, lat, lng), moonFraction: moonIllumination(t).fraction, mode };
}

export type RedoMatch = { t: number; moon: number; az: number; alt: number };

const azDiff = (a: number, b: number) => Math.abs((((a - b) % 360) + 540) % 360 - 180);

/**
 * Önümüzdeki 12 ay içinde aynı görünümün yakalanabileceği en fazla `count` an.
 *
 * - core: çekirdek her yıldız gününde aynı azimut/yüksekliğe döner (T0 + n × yıldız günü). Her aday
 *   etrafında ±40 dk taranır; azimut ve yükseklik ±5° içinde, Güneş −18° altında (astronomik karanlık)
 *   ve Ay aydınlanması %35'in altında olan, hedefe en yakın an seçilir.
 * - sun: her gün için çekim saatinin ±3 saati 4 dk adımla taranır; Güneş azimutu ±3°, yüksekliği
 *   ±2° içindeki en yakın an seçilir. Güneş aynı konuma yılda iki kez gelir (simetrik tarihler).
 *
 * Ardışık günler neredeyse aynı olduğu için eşleşmeler kümelenir (aralarında en fazla 2 gün boşluk
 * olan günler bir küme); her kümeden hedefe en yakın gün alınır ve ilk `count` küme döner.
 */
export function findRedoDates(cap: Capture, lat: number, lng: number, now = Date.now(), count = 3): RedoMatch[] {
  const hits: (RedoMatch & { err: number })[] = [];
  const horizon = now + 365 * DAY;
  const push = (m: RedoMatch & { err: number }) => hits.push(m);

  if (cap.mode === "core") {
    let n = Math.max(1, Math.ceil((now - cap.t) / SIDEREAL_DAY));
    for (;; n++) {
      const base = cap.t + n * SIDEREAL_DAY;
      if (base > horizon) break;
      let best: (RedoMatch & { err: number }) | null = null;
      for (let dt = -40 * MIN; dt <= 40 * MIN; dt += 5 * MIN) {
        const t = base + dt;
        if (t < now) continue;
        const c = corePosition(t, lat, lng);
        const err = Math.max(azDiff(c.az, cap.core.az), Math.abs(c.alt - cap.core.alt));
        if (err > 5) continue;
        if (sunPosition(t, lat, lng).alt > -18) continue;
        const moon = moonIllumination(t).fraction;
        if (moon >= 0.35) continue;
        if (!best || err < best.err) best = { t, moon, az: c.az, alt: c.alt, err };
      }
      if (best) push(best);
    }
    return clusterBest(hits, count);
  }

  if (cap.mode === "sun") {
    const ref = new Date(cap.t);
    const minutes = ref.getUTCHours() * 60 + ref.getUTCMinutes();
    const today = new Date(now);
    const start = Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate());
    for (let d = 0; d <= 365; d++) {
      const center = start + d * DAY + minutes * MIN;
      let best: (RedoMatch & { err: number }) | null = null;
      for (let dt = -180 * MIN; dt <= 180 * MIN; dt += 4 * MIN) {
        const t = center + dt;
        if (t < now) continue;
        const s = sunPosition(t, lat, lng);
        const da = azDiff(s.az, cap.sun.az), dh = Math.abs(s.alt - cap.sun.alt);
        if (da > 3 || dh > 2) continue;
        const err = da / 3 + dh / 2;
        if (!best || err < best.err) best = { t, moon: moonIllumination(t).fraction, az: s.az, alt: s.alt, err };
      }
      if (best) push(best);
    }
  }
  return clusterBest(hits, count);
}

/** Kronolojik eşleşmeleri kümele (≤ 3 gün arayla), her kümenin en iyisini al. */
function clusterBest(hits: (RedoMatch & { err: number })[], count: number): RedoMatch[] {
  const out: (RedoMatch & { err: number })[] = [];
  let cur: (RedoMatch & { err: number }) | null = null;
  let last = -Infinity;
  for (const h of hits) {
    if (h.t - last > 3 * DAY) {
      if (cur) out.push(cur);
      if (out.length >= count) return out.map(({ err: _e, ...m }) => m);
      cur = h;
    } else if (!cur || h.err < cur.err) cur = h;
    last = h.t;
  }
  if (cur && out.length < count) out.push(cur);
  return out.map(({ err: _e, ...m }) => m);
}

/**
 * EXIF taken_at saat dilimi bilgisi taşımaz (kameranın yerel saati). Konumun UTC farkıyla mutlak zamana
 * çevrilir: "2025-07-14T00:51:00" + offset(sn) → epoch ms.
 */
export function naiveToEpoch(naive: string, offsetSeconds: number): number | null {
  const m = naive.match(/^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?/);
  if (!m) return null;
  const utc = Date.UTC(+m[1]!, +m[2]! - 1, +m[3]!, +m[4]!, +m[5]!, +(m[6] ?? 0));
  return utc - offsetSeconds * 1000;
}

/** Çevrimdışı yedek: boylamdan kaba saat dilimi (15° = 1 saat). */
export const offsetFromLongitude = (lng: number) => Math.round(lng / 15) * 3600;
