// Güneş, Ay ve Samanyolu çekirdeğinin gökyüzündeki konumu (düşük hassasiyetli efemeris).
//
// Web'deki src/lib/astro.ts ile birebir aynı formüller. Doğruluk (ephem'e karşı, ufuk üstü):
// Güneş ≤0.22°, Ay ≤0.57°, Samanyolu çekirdeği ≤0.11°.
import 'dart:math' as math;

const _rad = math.pi / 180;
const _dayMs = 86400000;
const _j1970 = 2440588;
const _j2000 = 2451545;
const _e = _rad * 23.4397;

class AltAz {
  const AltAz(this.az, this.alt);
  final double az; // derece, kuzeyden saat yönünde
  final double alt; // derece
}

double _toDays(int ms) => ms / _dayMs - 0.5 + _j1970 - _j2000;
double _rightAscension(double l, double b) => math.atan2(
  math.sin(l) * math.cos(_e) - math.tan(b) * math.sin(_e),
  math.cos(l),
);
double _declination(double l, double b) => math.asin(
  math.sin(b) * math.cos(_e) + math.cos(b) * math.sin(_e) * math.sin(l),
);
double _sidereal(double d, double lw) => _rad * (280.16 + 360.9856235 * d) - lw;
double _mod360(double x) => (x % 360 + 360) % 360;

AltAz _azAlt(double h, double phi, double dec) {
  final alt = math.asin(
    math.sin(phi) * math.sin(dec) + math.cos(phi) * math.cos(dec) * math.cos(h),
  );
  final az = math.atan2(
    math.sin(h),
    math.cos(h) * math.sin(phi) - math.tan(dec) * math.cos(phi),
  );
  return AltAz(_mod360(az / _rad + 180), alt / _rad);
}

double _refraction(double h) {
  final x = math.max(h, 0.0);
  return 0.0002967 / math.tan(x + 0.00312536 / (x + 0.08901179));
}

({double ra, double dec}) _sunCoords(double d) {
  final m = _rad * (357.5291 + 0.98560028 * d);
  final c =
      _rad *
      (1.9148 * math.sin(m) +
          0.02 * math.sin(2 * m) +
          0.0003 * math.sin(3 * m));
  final l = m + c + _rad * 102.9372 + math.pi;
  return (ra: _rightAscension(l, 0), dec: _declination(l, 0));
}

// Meeus tablo 47.A/47.B: [D, M, M', F, katsayı]
const _lon = [
  [0, 0, 1, 0, 6288774],
  [2, 0, -1, 0, 1274027],
  [2, 0, 0, 0, 658314],
  [0, 0, 2, 0, 213618],
  [0, 1, 0, 0, -185116],
  [0, 0, 0, 2, -114332],
  [2, 0, -2, 0, 58793],
  [2, -1, -1, 0, 57066],
  [2, 0, 1, 0, 53322],
  [2, -1, 0, 0, 45758],
  [0, 1, -1, 0, -40923],
  [1, 0, 0, 0, -34720],
  [0, 1, 1, 0, -30383],
  [2, 0, 0, -2, 15327],
  [0, 0, 1, 2, -12528],
  [0, 0, 1, -2, 10980],
  [4, 0, -1, 0, 10675],
  [0, 0, 3, 0, 10034],
  [4, 0, -2, 0, 8548],
  [2, 1, -1, 0, -7888],
  [2, 1, 0, 0, -6766],
  [1, 0, -1, 0, -5163],
  [1, 1, 0, 0, 4987],
  [2, -1, 1, 0, 4036],
];
const _lat = [
  [0, 0, 0, 1, 5128122],
  [0, 0, 1, 1, 280602],
  [0, 0, 1, -1, 277693],
  [2, 0, 0, -1, 173237],
  [2, 0, -1, 1, 55413],
  [2, 0, -1, -1, 46271],
  [2, 0, 0, 1, 32573],
  [0, 0, 2, 1, 17198],
  [2, 0, 1, -1, 9266],
  [0, 0, 2, -1, 8822],
  [2, -1, 0, -1, 8216],
  [2, 0, -2, -1, 4324],
];
const _dist = [
  [0, 0, 1, 0, -20905355],
  [2, 0, -1, 0, -3699111],
  [2, 0, 0, 0, -2955968],
  [0, 0, 2, 0, -569925],
  [0, 1, 0, 0, 48888],
  [0, 0, 0, 2, -3149],
  [2, 0, -2, 0, 246158],
  [2, -1, 0, 0, -152138],
  [2, 0, 1, 0, -170733],
  [2, -1, -1, 0, -204586],
  [0, 1, -1, 0, -129620],
  [1, 0, 0, 0, 108743],
];

({double ra, double dec, double dist}) _moonCoords(double d) {
  final l0 = _rad * (218.3164477 + 13.17639648 * d);
  final dd = _rad * (297.8501921 + 12.19074912 * d);
  final m = _rad * (357.5291092 + 0.98560028 * d);
  final mm = _rad * (134.9633964 + 13.06499295 * d);
  final f = _rad * (93.272095 + 13.22935024 * d);
  double arg(List<int> t) => t[0] * dd + t[1] * m + t[2] * mm + t[3] * f;
  var lonSum = 0.0, latSum = 0.0, distSum = 0.0;
  for (final t in _lon) {
    lonSum += t[4] * math.sin(arg(t));
  }
  for (final t in _lat) {
    latSum += t[4] * math.sin(arg(t));
  }
  for (final t in _dist) {
    distSum += t[4] * math.cos(arg(t));
  }
  final lon = l0 + _rad * lonSum / 1e6;
  final lat = _rad * latSum / 1e6;
  return (
    ra: _rightAscension(lon, lat),
    dec: _declination(lon, lat),
    dist: 385000.56 + distSum / 1000,
  );
}

AltAz sunPosition(int ms, double lat, double lng) {
  final d = _toDays(ms);
  final s = _sunCoords(d);
  return _azAlt(_sidereal(d, _rad * -lng) - s.ra, _rad * lat, s.dec);
}

AltAz moonPosition(int ms, double lat, double lng) {
  final d = _toDays(ms);
  final phi = _rad * lat;
  final c = _moonCoords(d);
  final h = _sidereal(d, _rad * -lng) - c.ra;
  var alt = math.asin(
    math.sin(phi) * math.sin(c.dec) +
        math.cos(phi) * math.cos(c.dec) * math.cos(h),
  );
  alt -= math.asin(6378.14 / c.dist) * math.cos(alt); // paralaks
  final az = math.atan2(
    math.sin(h),
    math.cos(h) * math.sin(phi) - math.tan(c.dec) * math.cos(phi),
  );
  return AltAz(_mod360(az / _rad + 180), (alt + _refraction(alt)) / _rad);
}

const _gcRa = _rad * 266.4168;
const _gcDec = _rad * -29.0078;

/// Samanyolu çekirdeği (Sagittarius A*, J2000).
AltAz corePosition(int ms, double lat, double lng) {
  final d = _toDays(ms);
  return _azAlt(_sidereal(d, _rad * -lng) - _gcRa, _rad * lat, _gcDec);
}

/// Aydınlanma oranı (0–1) ve evre (0 yeni ay → 0.5 dolunay → 1).
({double fraction, double phase}) moonIllumination(int ms) {
  final d = _toDays(ms);
  final s = _sunCoords(d);
  final m = _moonCoords(d);
  const sdist = 149598000.0;
  final phi = math.acos(
    math.sin(s.dec) * math.sin(m.dec) +
        math.cos(s.dec) * math.cos(m.dec) * math.cos(s.ra - m.ra),
  );
  final inc = math.atan2(sdist * math.sin(phi), m.dist - sdist * math.cos(phi));
  final angle = math.atan2(
    math.cos(s.dec) * math.sin(s.ra - m.ra),
    math.sin(s.dec) * math.cos(m.dec) -
        math.cos(s.dec) * math.sin(m.dec) * math.cos(s.ra - m.ra),
  );
  return (
    fraction: (1 + math.cos(inc)) / 2,
    phase: 0.5 + 0.5 * inc * (angle < 0 ? -1 : 1) / math.pi,
  );
}

class Sample {
  Sample(this.t, this.sun, this.moon, this.core);
  final int t;
  final AltAz sun;
  final AltAz moon;
  final AltAz core;
}

class NightPlan {
  NightPlan({
    required this.samples,
    this.sunset,
    this.sunrise,
    this.duskAstro,
    this.dawnAstro,
    this.moonrise,
    this.moonset,
    this.coreRise,
    this.coreSet,
    this.coreTransit,
    required this.illumination,
    required this.phase,
    required this.bestWindows,
  });

  final List<Sample> samples;
  final DateTime? sunset,
      sunrise,
      duskAstro,
      dawnAstro,
      moonrise,
      moonset,
      coreRise,
      coreSet;
  final ({DateTime t, double alt, double az})? coreTransit;
  final double illumination;
  final double phase;
  final List<({DateTime start, DateTime end})> bestWindows;
}

const _step = 5 * 60000;

/// Verilen günün öğlesinden ertesi öğleye kadar gece planı (web ile aynı kurallar).
NightPlan planNight(DateTime date, double lat, double lng) {
  final start = DateTime(
    date.year,
    date.month,
    date.day,
    12,
  ).millisecondsSinceEpoch;
  final samples = <Sample>[];
  for (var t = start; t <= start + _dayMs; t += _step) {
    samples.add(
      Sample(
        t,
        sunPosition(t, lat, lng),
        moonPosition(t, lat, lng),
        corePosition(t, lat, lng),
      ),
    );
  }
  DateTime? cross(double Function(Sample) get, double level, bool rising) {
    for (var i = 1; i < samples.length; i++) {
      final a = get(samples[i - 1]), b = get(samples[i]);
      if (rising ? a < level && b >= level : a >= level && b < level) {
        return DateTime.fromMillisecondsSinceEpoch(
          (samples[i - 1].t + (level - a) / (b - a) * _step).round(),
        );
      }
    }
    return null;
  }

  final illum = moonIllumination(samples[samples.length ~/ 2].t);
  final top = samples.reduce((m, s) => s.core.alt > m.core.alt ? s : m);
  bool good(Sample s) =>
      s.core.alt >= 10 &&
      s.sun.alt <= -18 &&
      (s.moon.alt < 0 || illum.fraction < 0.25);
  final windows = <({DateTime start, DateTime end})>[];
  int? open;
  for (final s in samples) {
    if (good(s) && open == null) open = s.t;
    if (!good(s) && open != null) {
      windows.add((
        start: DateTime.fromMillisecondsSinceEpoch(open),
        end: DateTime.fromMillisecondsSinceEpoch(s.t),
      ));
      open = null;
    }
  }
  if (open != null)
    windows.add((
      start: DateTime.fromMillisecondsSinceEpoch(open),
      end: DateTime.fromMillisecondsSinceEpoch(samples.last.t),
    ));

  return NightPlan(
    samples: samples,
    sunset: cross((s) => s.sun.alt, -0.833, false),
    sunrise: cross((s) => s.sun.alt, -0.833, true),
    duskAstro: cross((s) => s.sun.alt, -18, false),
    dawnAstro: cross((s) => s.sun.alt, -18, true),
    moonrise: cross((s) => s.moon.alt, 0.125, true),
    moonset: cross((s) => s.moon.alt, 0.125, false),
    coreRise: cross((s) => s.core.alt, 0, true),
    coreSet: cross((s) => s.core.alt, 0, false),
    coreTransit: top.core.alt > 0
        ? (
            t: DateTime.fromMillisecondsSinceEpoch(top.t),
            alt: top.core.alt,
            az: top.core.az,
          )
        : null,
    illumination: illum.fraction,
    phase: illum.phase,
    bestWindows: windows
        .where((w) => w.end.difference(w.start).inMinutes >= 15)
        .toList(),
  );
}

String compassPoint(double az, String locale) {
  const tr = [
    'K',
    'KKD',
    'KD',
    'DKD',
    'D',
    'DGD',
    'GD',
    'GGD',
    'G',
    'GGB',
    'GB',
    'BGB',
    'B',
    'BKB',
    'KB',
    'KKB',
  ];
  const en = [
    'N',
    'NNE',
    'NE',
    'ENE',
    'E',
    'ESE',
    'SE',
    'SSE',
    'S',
    'SSW',
    'SW',
    'WSW',
    'W',
    'WNW',
    'NW',
    'NNW',
  ];
  return (locale == 'tr' ? tr : en)[(_mod360(az) / 22.5).round() % 16];
}
