import 'package:flutter_test/flutter_test.dart';
import 'package:photomunity/core/astro.dart';
import 'package:photomunity/core/sky.dart';

void main() {
  // Trabzon
  const lat = 41.0, lng = 39.72;

  test('gün planı: gün doğumu/batımı ve altın saat sıralı', () {
    final d = planDay(DateTime(2026, 6, 21), lat, lng);
    expect(d.sunrise, isNotNull);
    expect(d.sunset, isNotNull);
    expect(d.sunrise!.az, inInclusiveRange(55, 65)); // yaz gündönümünde KD
    expect(d.sunset!.az, inInclusiveRange(295, 305));
    expect(d.blueMorning!.end.isAfter(d.blueMorning!.start), isTrue);
    expect(d.goldenMorning!.start.isAtSameMomentAs(d.blueMorning!.end), isTrue);
    expect(d.goldenEvening!.end.isBefore(d.blueEvening!.end), isTrue);
  });

  test('Ay takvimi ve sonraki yeni ay', () {
    final m = moonMonth(2026, 12);
    expect(m.length, 31);
    final nm = nextPhase(DateTime(2026, 12, 1));
    // 2026-12-09 yeni ay (UTC 00:52); bir gün tolerans
    expect(nm.difference(DateTime.utc(2026, 12, 9, 0, 52)).inHours.abs(), lessThan(24));
    expect(moonIllumination(nm.millisecondsSinceEpoch).fraction, lessThan(0.02));
    final fm = nextPhase(DateTime(2026, 12, 1), full: true);
    expect(moonIllumination(fm.millisecondsSinceEpoch).fraction, greaterThan(0.98));
  });

  test('galaktik bant l=0 çekirdekle aynı yerde', () {
    final t = DateTime.utc(2026, 7, 12, 21).millisecondsSinceEpoch;
    final band = galacticBand(t, lat, lng);
    final core = corePosition(t, lat, lng);
    expect((band.first.pos.az - core.az).abs(), lessThan(0.6));
    expect((band.first.pos.alt - core.alt).abs(), lessThan(0.6));
  });

  test('yıldız izi: 30° ≈ 2 saat', () {
    final r = starTrails(arcDeg: 30, exposureSec: 30, gapSec: 1);
    expect(r.total.inMinutes, inInclusiveRange(118, 121));
    expect(r.frames, 232);
  });
}
