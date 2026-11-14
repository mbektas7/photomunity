// Fotoğraf hesaplayıcıları — web'deki src/lib/calculators.ts ile birebir aynı.
import 'dart:math' as math;

const sensors = <String, ({double w, double h})>{
  'ff': (w: 36, h: 24),
  'apsc': (w: 23.5, h: 15.6),
  'apsc_canon': (w: 22.3, h: 14.9),
  'mft': (w: 17.3, h: 13),
  'one_inch': (w: 13.2, h: 8.8),
  'mf': (w: 43.8, h: 32.9),
};

final _ffDiag = math.sqrt(36 * 36 + 24 * 24);
double _diag(String s) =>
    math.sqrt(sensors[s]!.w * sensors[s]!.w + sensors[s]!.h * sensors[s]!.h);

double cropFactor(String s) => _ffDiag / _diag(s);

double pixelPitch(String s, double megapixels) {
  final sz = sensors[s]!;
  return sz.w / math.sqrt(megapixels * 1e6 * sz.w / sz.h) * 1000;
}

/// NPF kuralı (Michaud): yıldızların nokta kalacağı en uzun pozlama (sn).
double npfSeconds(
  String s,
  double megapixels,
  double focal,
  double aperture, [
  double declinationDeg = 0,
]) {
  final p = pixelPitch(s, megapixels);
  return (16.856 * aperture + 0.0997 * focal + 13.713 * p) /
      (focal * math.cos(declinationDeg * math.pi / 180));
}

double rule500Seconds(String s, double focal) => 500 / (focal * cropFactor(s));

double circleOfConfusion(String s) => _diag(s) / 1442;

/// Alan derinliği; metre. Arka sınır hiperfokalin ötesinde sonsuzdur (null).
({double hyperfocal, double near, double? far}) depthOfField(
  String s,
  double focal,
  double aperture,
  double distanceM,
) {
  final c = circleOfConfusion(s);
  final h = focal * focal / (aperture * c) + focal;
  final x = distanceM * 1000;
  final near = x * (h - focal) / (h + x - 2 * focal);
  final far = x < h ? x * (h - focal) / (h - x) : null;
  return (
    hyperfocal: h / 1000,
    near: near / 1000,
    far: far == null ? null : far / 1000,
  );
}

double ndSeconds(double base, int stops) => base * math.pow(2, stops);

const ndFilters = [
  (label: 'ND8', stops: 3),
  (label: 'ND64', stops: 6),
  (label: 'ND1000', stops: 10),
  (label: 'ND32000', stops: 15),
];

const shutterSpeeds = <double>[
  1 / 8000,
  1 / 4000,
  1 / 2000,
  1 / 1000,
  1 / 500,
  1 / 250,
  1 / 125,
  1 / 60,
  1 / 30,
  1 / 15,
  1 / 8,
  1 / 4,
  1 / 2,
  1,
  2,
  4,
  8,
  15,
  30,
];

String formatShutter(double seconds, String locale) {
  final tr = locale == 'tr';
  if (seconds < 0.5) return '1/${(1 / seconds).round()}';
  if (seconds < 60) {
    final n = seconds < 10
        ? double.parse(seconds.toStringAsFixed(1)).toString().replaceAll(RegExp(r'\.0$'), '')
        : seconds.round().toString();
    return tr ? '${n.replaceAll('.', ',')} sn' : '$n s';
  }
  final m = seconds ~/ 60, s = (seconds % 60).round();
  if (seconds < 3600) return tr ? '$m dk $s sn' : '$m min $s s';
  final h = seconds ~/ 3600, mm = ((seconds % 3600) / 60).round();
  return tr ? '$h sa $mm dk' : '$h h $mm min';
}

String formatDistance(double? m, String locale) {
  if (m == null) return '∞';
  if (m < 1) return '${(m * 100).round()} cm';
  final v = m < 10 ? m.toStringAsFixed(2) : m.toStringAsFixed(1);
  return '${locale == 'tr' ? v.replaceAll('.', ',') : v} m';
}
