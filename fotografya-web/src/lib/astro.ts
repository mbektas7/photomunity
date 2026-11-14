/**
 * Güneş, Ay ve Samanyolu çekirdeğinin gökyüzündeki konumu (düşük hassasiyetli efemeris).
 *
 * Doğruluk (ephem kütüphanesine karşı, ufuk üstü, 600 rastgele konum/zaman): Güneş ≤0.22°,
 * Ay ≤0.57°, Samanyolu çekirdeği ≤0.11°. Planlama ve AR için fazlasıyla yeterli; telefon pusulası
 * zaten birkaç derece hata yapar. Ay için Meeus (Astronomical Algorithms, bölüm 47) terimleri kullanılır.
 * Aynı formüller mobil uygulamada (lib/core/astro.dart) ve Python başvuru uygulamasında birebir aynıdır.
 */
const RAD = Math.PI / 180;
const DAY_MS = 86_400_000;
const J1970 = 2440588;
const J2000 = 2451545;
const E = RAD * 23.4397;

export type AltAz = { az: number; alt: number }; // derece; azimut kuzeyden saat yönünde

const toDays = (ms: number) => ms / DAY_MS - 0.5 + J1970 - J2000;
const rightAscension = (l: number, b: number) => Math.atan2(Math.sin(l) * Math.cos(E) - Math.tan(b) * Math.sin(E), Math.cos(l));
const declination = (l: number, b: number) => Math.asin(Math.sin(b) * Math.cos(E) + Math.cos(b) * Math.sin(E) * Math.sin(l));
const sidereal = (d: number, lw: number) => RAD * (280.16 + 360.9856235 * d) - lw;
const mod360 = (x: number) => ((x % 360) + 360) % 360;

function azAlt(H: number, phi: number, dec: number): AltAz {
  const alt = Math.asin(Math.sin(phi) * Math.sin(dec) + Math.cos(phi) * Math.cos(dec) * Math.cos(H));
  const az = Math.atan2(Math.sin(H), Math.cos(H) * Math.sin(phi) - Math.tan(dec) * Math.cos(phi));
  return { az: mod360(az / RAD + 180), alt: alt / RAD };
}

function refraction(h: number) {
  const x = Math.max(h, 0);
  return 0.0002967 / Math.tan(x + 0.00312536 / (x + 0.08901179));
}

function sunCoords(d: number) {
  const M = RAD * (357.5291 + 0.98560028 * d);
  const C = RAD * (1.9148 * Math.sin(M) + 0.02 * Math.sin(2 * M) + 0.0003 * Math.sin(3 * M));
  const L = M + C + RAD * 102.9372 + Math.PI;
  return { ra: rightAscension(L, 0), dec: declination(L, 0) };
}

// Meeus tablo 47.A/47.B'nin en büyük terimleri: [D, M, M', F, katsayı]
const LON: number[][] = [[0,0,1,0,6288774],[2,0,-1,0,1274027],[2,0,0,0,658314],[0,0,2,0,213618],[0,1,0,0,-185116],[0,0,0,2,-114332],
  [2,0,-2,0,58793],[2,-1,-1,0,57066],[2,0,1,0,53322],[2,-1,0,0,45758],[0,1,-1,0,-40923],[1,0,0,0,-34720],
  [0,1,1,0,-30383],[2,0,0,-2,15327],[0,0,1,2,-12528],[0,0,1,-2,10980],[4,0,-1,0,10675],[0,0,3,0,10034],
  [4,0,-2,0,8548],[2,1,-1,0,-7888],[2,1,0,0,-6766],[1,0,-1,0,-5163],[1,1,0,0,4987],[2,-1,1,0,4036]];
const LAT: number[][] = [[0,0,0,1,5128122],[0,0,1,1,280602],[0,0,1,-1,277693],[2,0,0,-1,173237],[2,0,-1,1,55413],[2,0,-1,-1,46271],
  [2,0,0,1,32573],[0,0,2,1,17198],[2,0,1,-1,9266],[0,0,2,-1,8822],[2,-1,0,-1,8216],[2,0,-2,-1,4324]];
const DIST: number[][] = [[0,0,1,0,-20905355],[2,0,-1,0,-3699111],[2,0,0,0,-2955968],[0,0,2,0,-569925],[0,1,0,0,48888],[0,0,0,2,-3149],
  [2,0,-2,0,246158],[2,-1,0,0,-152138],[2,0,1,0,-170733],[2,-1,-1,0,-204586],[0,1,-1,0,-129620],[1,0,0,0,108743]];

function moonCoords(d: number) {
  const L = RAD * (218.3164477 + 13.17639648 * d);
  const D = RAD * (297.8501921 + 12.19074912 * d);
  const M = RAD * (357.5291092 + 0.98560028 * d);
  const Mm = RAD * (134.9633964 + 13.06499295 * d);
  const F = RAD * (93.272095 + 13.22935024 * d);
  const arg = (t: number[]) => t[0]! * D + t[1]! * M + t[2]! * Mm + t[3]! * F;
  const lon = L + (RAD * LON.reduce((s, t) => s + t[4]! * Math.sin(arg(t)), 0)) / 1e6;
  const lat = (RAD * LAT.reduce((s, t) => s + t[4]! * Math.sin(arg(t)), 0)) / 1e6;
  const dist = 385000.56 + DIST.reduce((s, t) => s + t[4]! * Math.cos(arg(t)), 0) / 1000;
  return { ra: rightAscension(lon, lat), dec: declination(lon, lat), dist };
}

export function sunPosition(ms: number, lat: number, lng: number): AltAz {
  const d = toDays(ms);
  const { ra, dec } = sunCoords(d);
  return azAlt(sidereal(d, RAD * -lng) - ra, RAD * lat, dec);
}

export function moonPosition(ms: number, lat: number, lng: number): AltAz {
  const d = toDays(ms);
  const phi = RAD * lat;
  const { ra, dec, dist } = moonCoords(d);
  const H = sidereal(d, RAD * -lng) - ra;
  let alt = Math.asin(Math.sin(phi) * Math.sin(dec) + Math.cos(phi) * Math.cos(dec) * Math.cos(H));
  alt -= Math.asin(6378.14 / dist) * Math.cos(alt); // paralaks
  const az = Math.atan2(Math.sin(H), Math.cos(H) * Math.sin(phi) - Math.tan(dec) * Math.cos(phi));
  return { az: mod360(az / RAD + 180), alt: (alt + refraction(alt)) / RAD };
}

const GC_RA = RAD * 266.4168;
const GC_DEC = RAD * -29.0078;

/** Samanyolu çekirdeği (Sagittarius A*, J2000). */
export function corePosition(ms: number, lat: number, lng: number): AltAz {
  const d = toDays(ms);
  return azAlt(sidereal(d, RAD * -lng) - GC_RA, RAD * lat, GC_DEC);
}

/** Aydınlanma oranı (0–1) ve evre (0 yeni ay → 0.5 dolunay → 1). */
export function moonIllumination(ms: number) {
  const d = toDays(ms);
  const s = sunCoords(d);
  const m = moonCoords(d);
  const sdist = 149598000;
  const phi = Math.acos(Math.sin(s.dec) * Math.sin(m.dec) + Math.cos(s.dec) * Math.cos(m.dec) * Math.cos(s.ra - m.ra));
  const inc = Math.atan2(sdist * Math.sin(phi), m.dist - sdist * Math.cos(phi));
  const angle = Math.atan2(Math.cos(s.dec) * Math.sin(s.ra - m.ra), Math.sin(s.dec) * Math.cos(m.dec) - Math.cos(s.dec) * Math.sin(m.dec) * Math.cos(s.ra - m.ra));
  return { fraction: (1 + Math.cos(inc)) / 2, phase: 0.5 + (0.5 * inc * (angle < 0 ? -1 : 1)) / Math.PI };
}

// ---------------------------------------------------------------- gece planı

export type Sample = { t: number; sun: AltAz; moon: AltAz; core: AltAz };
export type Window = { start: number; end: number };

export type NightPlan = {
  samples: Sample[];
  sunset: number | null;
  sunrise: number | null;
  duskAstro: number | null; // astronomik alacakaranlık sonu (Güneş −18°)
  dawnAstro: number | null;
  moonrise: number | null;
  moonset: number | null;
  coreRise: number | null;
  coreSet: number | null;
  coreTransit: { t: number; alt: number; az: number } | null;
  illumination: number;
  phase: number;
  /** Çekirdek ≥10°, gökyüzü tamamen karanlık ve Ay ufkun altında (ya da %25'ten az aydınlık) */
  bestWindows: Window[];
};

const STEP = 5 * 60_000;

/** Verilen tarihin öğlesinden ertesi öğleye kadar (cihazın saat diliminde) gece planı. */
export function planNight(date: Date, lat: number, lng: number): NightPlan {
  const start = new Date(date);
  start.setHours(12, 0, 0, 0);
  const samples: Sample[] = [];
  for (let t = start.getTime(); t <= start.getTime() + DAY_MS; t += STEP) {
    samples.push({ t, sun: sunPosition(t, lat, lng), moon: moonPosition(t, lat, lng), core: corePosition(t, lat, lng) });
  }
  // Eşik geçişini iki örnek arasında doğrusal olarak bul
  const cross = (get: (s: Sample) => number, level: number, rising: boolean) => {
    for (let i = 1; i < samples.length; i++) {
      const a = get(samples[i - 1]!), b = get(samples[i]!);
      if (rising ? a < level && b >= level : a >= level && b < level) {
        return samples[i - 1]!.t + ((level - a) / (b - a)) * STEP;
      }
    }
    return null;
  };
  const sunAlt = (s: Sample) => s.sun.alt, moonAlt = (s: Sample) => s.moon.alt, coreAlt = (s: Sample) => s.core.alt;
  const midnight = samples[Math.floor(samples.length / 2)]!.t;
  const illum = moonIllumination(midnight);

  const top = samples.reduce((m, s) => (s.core.alt > m.core.alt ? s : m), samples[0]!);
  const good = (s: Sample) => s.core.alt >= 10 && s.sun.alt <= -18 && (s.moon.alt < 0 || illum.fraction < 0.25);
  const bestWindows: Window[] = [];
  let open: number | null = null;
  for (const s of samples) {
    if (good(s) && open === null) open = s.t;
    if (!good(s) && open !== null) {
      bestWindows.push({ start: open, end: s.t });
      open = null;
    }
  }
  if (open !== null) bestWindows.push({ start: open, end: samples.at(-1)!.t });

  return {
    samples,
    sunset: cross(sunAlt, -0.833, false),
    sunrise: cross(sunAlt, -0.833, true),
    duskAstro: cross(sunAlt, -18, false),
    dawnAstro: cross(sunAlt, -18, true),
    moonrise: cross(moonAlt, 0.125, true),
    moonset: cross(moonAlt, 0.125, false),
    coreRise: cross(coreAlt, 0, true),
    coreSet: cross(coreAlt, 0, false),
    coreTransit: top.core.alt > 0 ? { t: top.t, alt: top.core.alt, az: top.core.az } : null,
    illumination: illum.fraction,
    phase: illum.phase,
    bestWindows: bestWindows.filter((w) => w.end - w.start >= 15 * 60_000),
  };
}

export function compassPoint(az: number, locale: string) {
  const tr = ["K", "KKD", "KD", "DKD", "D", "DGD", "GD", "GGD", "G", "GGB", "GB", "BGB", "B", "BKB", "KB", "KKB"];
  const en = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"];
  return (locale === "tr" ? tr : en)[Math.round(mod360(az) / 22.5) % 16];
}
