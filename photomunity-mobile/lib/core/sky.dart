// Gökyüzü modülü için astro.dart üzerine kurulu hesaplar: gün planı (altın/mavi saat, doğuş-batış
// yönleri), Ay takvimi, Samanyolu bandı, gece hesaplayıcıları ve meteor yağmurları.
// Web'deki src/lib/sky.ts ile aynı kurallar.
import 'dart:math' as math;

import 'astro.dart';

const _rad = math.pi / 180;
const _minute = 60000;

/// Bir olayın zamanı ve o anki yönü (azimut, derece).
typedef SkyEvent = ({DateTime t, double az});

/// Zaman aralığı.
typedef Span = ({DateTime start, DateTime end});

/// Takvim günü (yerel 00:00–24:00) için Güneş ve Ay planı.
class DayPlan {
  DayPlan({
    required this.date,
    this.sunrise,
    this.sunset,
    this.moonrise,
    this.moonset,
    this.moonTransit,
    this.blueMorning,
    this.goldenMorning,
    this.goldenEvening,
    this.blueEvening,
    this.civilDawn,
    this.civilDusk,
    this.astroDawn,
    this.astroDusk,
    required this.sunNoonAlt,
  });

  final DateTime date;
  final SkyEvent? sunrise, sunset, moonrise, moonset;
  final ({DateTime t, double alt, double az})? moonTransit;
  final Span? blueMorning, goldenMorning, goldenEvening, blueEvening;
  final DateTime? civilDawn, civilDusk, astroDawn, astroDusk;
  final double sunNoonAlt;
}

/// Altın saat: Güneş −4°…+6°; mavi saat: −6°…−4° (PhotoPills ve yaygın tanım).
DayPlan planDay(DateTime date, double lat, double lng) {
  final start = DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
  final end = DateTime(date.year, date.month, date.day + 1).millisecondsSinceEpoch;
  const step = 2 * _minute;
  final ts = <int>[for (var t = start; t <= end; t += step) t];
  final sun = [for (final t in ts) sunPosition(t, lat, lng)];
  final moon = [for (final t in ts) moonPosition(t, lat, lng)];

  // Seviye geçişi: yükselirken ya da alçalırken; doğrusal ara değer
  int? cross(List<AltAz> xs, double level, bool rising, {int from = 0}) {
    for (var i = math.max(1, from); i < xs.length; i++) {
      final a = xs[i - 1].alt, b = xs[i].alt;
      if (rising ? a < level && b >= level : a >= level && b < level) {
        return (ts[i - 1] + (level - a) / (b - a) * step).round();
      }
    }
    return null;
  }

  DateTime? at(int? ms) => ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  SkyEvent? event(List<AltAz> xs, double level, bool rising, AltAz Function(int) pos) {
    final ms = cross(xs, level, rising);
    return ms == null ? null : (t: DateTime.fromMillisecondsSinceEpoch(ms), az: pos(ms).az);
  }

  Span? span(double lo, double hi, bool morning) {
    // sabah: lo'dan hi'ye yükselir; akşam: hi'den lo'ya alçalır
    final a = morning ? cross(sun, lo, true) : cross(sun, hi, false);
    final b = morning ? cross(sun, hi, true) : cross(sun, lo, false);
    if (a == null || b == null || b <= a) return null;
    return (start: DateTime.fromMillisecondsSinceEpoch(a), end: DateTime.fromMillisecondsSinceEpoch(b));
  }

  var top = 0;
  for (var i = 1; i < moon.length; i++) {
    if (moon[i].alt > moon[top].alt) top = i;
  }
  return DayPlan(
    date: DateTime(date.year, date.month, date.day),
    sunrise: event(sun, -0.833, true, (t) => sunPosition(t, lat, lng)),
    sunset: event(sun, -0.833, false, (t) => sunPosition(t, lat, lng)),
    moonrise: event(moon, 0.125, true, (t) => moonPosition(t, lat, lng)),
    moonset: event(moon, 0.125, false, (t) => moonPosition(t, lat, lng)),
    moonTransit: moon[top].alt > 0
        ? (t: DateTime.fromMillisecondsSinceEpoch(ts[top]), alt: moon[top].alt, az: moon[top].az)
        : null,
    blueMorning: span(-6, -4, true),
    goldenMorning: span(-4, 6, true),
    goldenEvening: span(-4, 6, false),
    blueEvening: span(-6, -4, false),
    civilDawn: at(cross(sun, -6, true)),
    civilDusk: at(cross(sun, -6, false)),
    astroDawn: at(cross(sun, -18, true)),
    astroDusk: at(cross(sun, -18, false)),
    sunNoonAlt: sun.map((s) => s.alt).reduce(math.max),
  );
}

// ------------------------------------------------------------------ Ay

/// Evre adı anahtarı (l10n: moon.phase_*). phase: 0 yeni ay → 0.5 dolunay → 1.
String moonPhaseKey(double phase) {
  final p = phase % 1;
  if (p < 0.03 || p > 0.97) return 'new';
  if (p < 0.22) return 'waxing_crescent';
  if (p < 0.28) return 'first_quarter';
  if (p < 0.47) return 'waxing_gibbous';
  if (p < 0.53) return 'full';
  if (p < 0.72) return 'waning_gibbous';
  if (p < 0.78) return 'last_quarter';
  return 'waning_crescent';
}

/// Ay'ın yaşı (gün, yeni aydan bu yana).
double moonAgeDays(double phase) => (phase % 1) * 29.530588;

/// Takvimdeki bir gün: gece yarısından önceki akşam (22:00) için Ay durumu.
class MoonDay {
  MoonDay(this.date, this.fraction, this.phase);
  final DateTime date;
  final double fraction;
  final double phase;

  /// Samanyolu ve yıldız çekimi için karanlık gece (Ay %35 altı).
  bool get dark => fraction < 0.35;
}

List<MoonDay> moonMonth(int year, int month) {
  final days = DateTime(year, month + 1, 0).day;
  return [
    for (var d = 1; d <= days; d++)
      () {
        final t = DateTime(year, month, d, 22);
        final i = moonIllumination(t.millisecondsSinceEpoch);
        return MoonDay(DateTime(year, month, d), i.fraction, i.phase);
      }(),
  ];
}

/// Verilen andan sonraki ilk yeni ay ya da dolunay (saat hassasiyetinde).
DateTime nextPhase(DateTime from, {bool full = false}) {
  final target = full ? 0.5 : 0.0;
  double diff(DateTime t) {
    final p = moonIllumination(t.millisecondsSinceEpoch).phase;
    return ((p - target + 1.5) % 1) - 0.5; // −0.5…0.5, hedefte 0'dan geçer (− → +)
  }

  var t = from;
  var prev = diff(t);
  for (var i = 0; i < 24 * 32; i++) {
    final n = t.add(const Duration(hours: 1));
    final d = diff(n);
    if (prev < 0 && d >= 0 && (d - prev).abs() < 0.5) return n;
    prev = d;
    t = n;
  }
  return t;
}

// ------------------------------------------------------------------ Samanyolu bandı

// Galaktik → ekvatoral (J2000): kuzey galaktik kutup ve gök kutbunun galaktik boylamı
const _ngpRa = 192.85948 * _rad;
const _ngpDec = 27.12825 * _rad;
const _lNcp = 122.93192 * _rad;

/// Galaktik düzlemdeki (b = enlem) noktaları ufuk koordinatına çevirir.
/// l = 0 galaktik merkez (çekirdek). AR'da bandın çizimi için.
List<({double l, AltAz pos})> galacticBand(int ms, double lat, double lng, {double b = 0, double stepDeg = 5}) {
  final out = <({double l, AltAz pos})>[];
  final bb = b * _rad;
  for (var l = 0.0; l < 360; l += stepDeg) {
    final ll = l * _rad;
    final sinDec = math.sin(bb) * math.sin(_ngpDec) + math.cos(bb) * math.cos(_ngpDec) * math.cos(_lNcp - ll);
    final dec = math.asin(sinDec);
    final y = math.cos(bb) * math.sin(_lNcp - ll);
    final x = math.sin(bb) * math.cos(_ngpDec) - math.cos(bb) * math.sin(_ngpDec) * math.cos(_lNcp - ll);
    final ra = _ngpRa + math.atan2(y, x);
    out.add((l: l, pos: equatorialToHorizontal(ms, lat, lng, ra, dec)));
  }
  return out;
}

/// RA/Dec (radyan) → ufuk koordinatı (kırılmasız; yıldızlar ve bant için yeterli).
AltAz equatorialToHorizontal(int ms, double lat, double lng, double ra, double dec) {
  final d = ms / 86400000 - 0.5 + 2440588 - 2451545;
  final lst = _rad * (280.16 + 360.9856235 * d) + _rad * lng;
  final h = lst - ra;
  final phi = lat * _rad;
  final alt = math.asin(math.sin(phi) * math.sin(dec) + math.cos(phi) * math.cos(dec) * math.cos(h));
  final az = math.atan2(math.sin(h), math.cos(h) * math.sin(phi) - math.tan(dec) * math.cos(phi));
  return AltAz(((az / _rad + 180) % 360 + 360) % 360, alt / _rad);
}

// ------------------------------------------------------------------ Gece hesaplayıcıları

/// Yıldız izi: gök saatte ~15,04° döner. İstenen yay için toplam süre ve kare sayısı.
({Duration total, int frames}) starTrails({required double arcDeg, required double exposureSec, required double gapSec}) {
  final seconds = arcDeg / 15.041 * 3600;
  final frames = (seconds / (exposureSec + gapSec)).ceil();
  return (total: Duration(seconds: seconds.round()), frames: frames);
}

/// Timelapse: çekim süresi ve video süresi → aralık ve kare sayısı.
({int frames, double intervalSec}) timelapse({required Duration shoot, required double clipSec, required int fps}) {
  final frames = (clipSec * fps).round();
  return (frames: frames, intervalSec: frames <= 1 ? 0 : shoot.inSeconds / (frames - 1));
}

// ------------------------------------------------------------------ Meteor yağmurları

/// IMO takvimi: zirve (ay, gün), ZHR, radyantın RA/Dec (derece).
class MeteorShower {
  const MeteorShower(this.key, this.month, this.day, this.zhr, this.ra, this.dec, this.activeFrom, this.activeTo);
  final String key; // l10n: meteor.<key>
  final int month, day, zhr;
  final double ra, dec;
  final (int, int) activeFrom, activeTo; // (ay, gün)

  DateTime peakIn(int year) => DateTime(year, month, day, 2);
}

const meteorShowers = [
  MeteorShower('quadrantids', 1, 3, 80, 230, 49, (12, 28), (1, 12)),
  MeteorShower('lyrids', 4, 22, 18, 271, 34, (4, 14), (4, 30)),
  MeteorShower('eta_aquariids', 5, 6, 50, 338, -1, (4, 19), (5, 28)),
  MeteorShower('delta_aquariids', 7, 30, 25, 340, -16, (7, 12), (8, 23)),
  MeteorShower('perseids', 8, 12, 100, 48, 58, (7, 17), (8, 24)),
  MeteorShower('draconids', 10, 8, 10, 262, 54, (10, 6), (10, 10)),
  MeteorShower('orionids', 10, 21, 20, 95, 16, (10, 2), (11, 7)),
  MeteorShower('leonids', 11, 17, 15, 152, 22, (11, 6), (11, 30)),
  MeteorShower('geminids', 12, 14, 150, 112, 33, (12, 4), (12, 20)),
  MeteorShower('ursids', 12, 22, 10, 217, 76, (12, 17), (12, 26)),
];

/// Bugünden itibaren sıradaki yağmurlar (en yakın zirve önce).
List<({MeteorShower s, DateTime peak, double moon})> upcomingShowers(DateTime now, {int count = 10}) {
  final today = DateTime(now.year, now.month, now.day);
  final list = [
    for (final s in meteorShowers)
      () {
        var peak = s.peakIn(now.year);
        if (peak.isBefore(today)) peak = s.peakIn(now.year + 1);
        return (s: s, peak: peak, moon: moonIllumination(peak.millisecondsSinceEpoch).fraction);
      }(),
  ]..sort((a, b) => a.peak.compareTo(b.peak));
  return list.take(count).toList();
}

/// Çekirdeğin karanlıkta (Güneş −12° altında) ulaştığı en yüksek konum; görünmüyorsa null.
/// planNight'ın coreTransit'i gündüzü de sayar (Kasım'da öğlen gibi); gece için bu kullanılır.
({DateTime t, double alt, double az})? nightCoreHighest(NightPlan plan) {
  Sample? best;
  for (final s in plan.samples) {
    if (s.sun.alt > -12 || s.core.alt <= 0) continue;
    if (best == null || s.core.alt > best.core.alt) best = s;
  }
  return best == null ? null : (t: DateTime.fromMillisecondsSinceEpoch(best.t), alt: best.core.alt, az: best.core.az);
}
