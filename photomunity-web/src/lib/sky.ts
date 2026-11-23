/**
 * Gökyüzü bölümü için astro.ts üzerine kurulu hesaplar: gün planı (altın/mavi saat, doğuş-batış
 * yönleri), Ay takvimi ve meteor yağmurları. Mobil uygulamadaki lib/core/sky.dart ile aynı kurallar
 * (Samanyolu bandı ve yıldız izi/timelapse hesapları yalnızca mobilde).
 */
import { type AltAz, moonIllumination, moonPosition, sunPosition } from "./astro";

const MINUTE = 60_000;

/** Bir olayın zamanı (ms) ve o anki yönü (azimut, derece). */
export type SkyEvent = { t: number; az: number };

/** Zaman aralığı (ms). */
export type Span = { start: number; end: number };

/** Takvim günü (yerel 00:00–24:00) için Güneş ve Ay planı. Zamanlar epoch ms. */
export type DayPlan = {
  date: Date;
  sunrise: SkyEvent | null;
  sunset: SkyEvent | null;
  moonrise: SkyEvent | null;
  moonset: SkyEvent | null;
  moonTransit: { t: number; alt: number; az: number } | null;
  blueMorning: Span | null;
  goldenMorning: Span | null;
  goldenEvening: Span | null;
  blueEvening: Span | null;
  civilDawn: number | null;
  civilDusk: number | null;
  astroDawn: number | null;
  astroDusk: number | null;
  sunNoonAlt: number;
};

/** Altın saat: Güneş −4°…+6°; mavi saat: −6°…−4° (PhotoPills ve yaygın tanım). */
export function planDay(date: Date, lat: number, lng: number): DayPlan {
  const start = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
  const end = new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1).getTime();
  const step = 2 * MINUTE;
  const ts: number[] = [];
  for (let t = start; t <= end; t += step) ts.push(t);
  const sun = ts.map((t) => sunPosition(t, lat, lng));
  const moon = ts.map((t) => moonPosition(t, lat, lng));

  // Seviye geçişi: yükselirken ya da alçalırken; doğrusal ara değer
  const cross = (xs: AltAz[], level: number, rising: boolean): number | null => {
    for (let i = 1; i < xs.length; i++) {
      const a = xs[i - 1]!.alt, b = xs[i]!.alt;
      if (rising ? a < level && b >= level : a >= level && b < level) {
        return Math.round(ts[i - 1]! + ((level - a) / (b - a)) * step);
      }
    }
    return null;
  };

  const event = (xs: AltAz[], level: number, rising: boolean, pos: (t: number) => AltAz): SkyEvent | null => {
    const ms = cross(xs, level, rising);
    return ms === null ? null : { t: ms, az: pos(ms).az };
  };

  const span = (lo: number, hi: number, morning: boolean): Span | null => {
    // sabah: lo'dan hi'ye yükselir; akşam: hi'den lo'ya alçalır
    const a = morning ? cross(sun, lo, true) : cross(sun, hi, false);
    const b = morning ? cross(sun, hi, true) : cross(sun, lo, false);
    if (a === null || b === null || b <= a) return null;
    return { start: a, end: b };
  };

  let top = 0;
  for (let i = 1; i < moon.length; i++) if (moon[i]!.alt > moon[top]!.alt) top = i;

  const sunPos = (t: number) => sunPosition(t, lat, lng);
  const moonPos = (t: number) => moonPosition(t, lat, lng);
  return {
    date: new Date(start),
    sunrise: event(sun, -0.833, true, sunPos),
    sunset: event(sun, -0.833, false, sunPos),
    moonrise: event(moon, 0.125, true, moonPos),
    moonset: event(moon, 0.125, false, moonPos),
    moonTransit: moon[top]!.alt > 0 ? { t: ts[top]!, alt: moon[top]!.alt, az: moon[top]!.az } : null,
    blueMorning: span(-6, -4, true),
    goldenMorning: span(-4, 6, true),
    goldenEvening: span(-4, 6, false),
    blueEvening: span(-6, -4, false),
    civilDawn: cross(sun, -6, true),
    civilDusk: cross(sun, -6, false),
    astroDawn: cross(sun, -18, true),
    astroDusk: cross(sun, -18, false),
    sunNoonAlt: Math.max(...sun.map((s) => s.alt)),
  };
}

// ------------------------------------------------------------------ Ay

export type MoonPhaseKey =
  | "new" | "waxing_crescent" | "first_quarter" | "waxing_gibbous"
  | "full" | "waning_gibbous" | "last_quarter" | "waning_crescent";

const frac = (x: number) => ((x % 1) + 1) % 1;

/** Evre adı anahtarı. phase: 0 yeni ay → 0.5 dolunay → 1. */
export function moonPhaseKey(phase: number): MoonPhaseKey {
  const p = frac(phase);
  if (p < 0.03 || p > 0.97) return "new";
  if (p < 0.22) return "waxing_crescent";
  if (p < 0.28) return "first_quarter";
  if (p < 0.47) return "waxing_gibbous";
  if (p < 0.53) return "full";
  if (p < 0.72) return "waning_gibbous";
  if (p < 0.78) return "last_quarter";
  return "waning_crescent";
}

/** Ay'ın yaşı (gün, yeni aydan bu yana). */
export const moonAgeDays = (phase: number) => frac(phase) * 29.530588;

/** Takvimdeki bir gün: o akşam (yerel 22:00) için Ay durumu. */
export type MoonDay = {
  date: Date;
  fraction: number;
  phase: number;
  /** Samanyolu ve yıldız çekimi için karanlık gece (Ay %35 altı). */
  dark: boolean;
};

/** month: 1–12 */
export function moonMonth(year: number, month: number): MoonDay[] {
  const days = new Date(year, month, 0).getDate();
  const out: MoonDay[] = [];
  for (let d = 1; d <= days; d++) {
    const i = moonIllumination(new Date(year, month - 1, d, 22).getTime());
    out.push({ date: new Date(year, month - 1, d), fraction: i.fraction, phase: i.phase, dark: i.fraction < 0.35 });
  }
  return out;
}

/** Verilen andan sonraki ilk yeni ay ya da dolunay (saat hassasiyetinde). */
export function nextPhase(from: Date, full = false): Date {
  const target = full ? 0.5 : 0;
  const diff = (t: number) => frac(moonIllumination(t).phase - target + 1.5) - 0.5; // −0.5…0.5, hedefte − → +
  let t = from.getTime();
  let prev = diff(t);
  for (let i = 0; i < 24 * 32; i++) {
    const n = t + 3_600_000;
    const d = diff(n);
    if (prev < 0 && d >= 0 && Math.abs(d - prev) < 0.5) return new Date(n);
    prev = d;
    t = n;
  }
  return new Date(t);
}

// ------------------------------------------------------------------ Meteor yağmurları

/** IMO takvimi: zirve (ay, gün), ZHR, radyantın RA/Dec (derece), etkinlik aralığı [ay, gün]. */
export type MeteorShower = {
  key: string;
  month: number;
  day: number;
  zhr: number;
  ra: number;
  dec: number;
  activeFrom: [number, number];
  activeTo: [number, number];
};

const shower = (key: string, month: number, day: number, zhr: number, ra: number, dec: number, activeFrom: [number, number], activeTo: [number, number]): MeteorShower =>
  ({ key, month, day, zhr, ra, dec, activeFrom, activeTo });

export const meteorShowers: MeteorShower[] = [
  shower("quadrantids", 1, 3, 80, 230, 49, [12, 28], [1, 12]),
  shower("lyrids", 4, 22, 18, 271, 34, [4, 14], [4, 30]),
  shower("eta_aquariids", 5, 6, 50, 338, -1, [4, 19], [5, 28]),
  shower("delta_aquariids", 7, 30, 25, 340, -16, [7, 12], [8, 23]),
  shower("perseids", 8, 12, 100, 48, 58, [7, 17], [8, 24]),
  shower("draconids", 10, 8, 10, 262, 54, [10, 6], [10, 10]),
  shower("orionids", 10, 21, 20, 95, 16, [10, 2], [11, 7]),
  shower("leonids", 11, 17, 15, 152, 22, [11, 6], [11, 30]),
  shower("geminids", 12, 14, 150, 112, 33, [12, 4], [12, 20]),
  shower("ursids", 12, 22, 10, 217, 76, [12, 17], [12, 26]),
];

/** Zirve anı: o yılın zirve gününde yerel 02:00. */
export const peakIn = (s: MeteorShower, year: number) => new Date(year, s.month - 1, s.day, 2);

export type UpcomingShower = { s: MeteorShower; peak: Date; moon: number };

/** Bugünden itibaren sıradaki yağmurlar (en yakın zirve önce). */
export function upcomingShowers(now: Date, count = 10): UpcomingShower[] {
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  return meteorShowers
    .map((s) => {
      let peak = peakIn(s, now.getFullYear());
      if (peak < today) peak = peakIn(s, now.getFullYear() + 1);
      return { s, peak, moon: moonIllumination(peak.getTime()).fraction };
    })
    .sort((a, b) => a.peak.getTime() - b.peak.getTime())
    .slice(0, count);
}
