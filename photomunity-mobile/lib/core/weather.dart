// Open-Meteo saatlik tahmini (ücretsiz, anahtarsız): bulut (toplam/alçak/orta/yüksek), nem, rüzgâr.
// Gökyüzü ekranı, etkinlik detayı ve "tekrar çek" kartı kullanır. Yer ve saat başına önbelleklenir.
import 'package:dio/dio.dart';

class HourWeather {
  HourWeather(this.t, this.cloud, this.low, this.mid, this.high, this.humidity, this.wind);

  /// Saatin başlangıcı (gerçek an; cihaz saat dilimine çevrilmiş).
  final DateTime t;
  final int cloud, low, mid, high, humidity;

  /// km/s
  final double wind;
}

class Forecast {
  Forecast(this.hours, this.utcOffset);
  final List<HourWeather> hours;

  /// Yerin (tahmin anındaki) UTC farkı; EXIF'teki yerel çekim saatini gerçek ana çevirmek için.
  final Duration utcOffset;

  bool covers(DateTime t) =>
      hours.isNotEmpty && !t.isBefore(hours.first.t) && t.isBefore(hours.last.t.add(const Duration(hours: 1)));

  /// [a, b) aralığındaki saatlerin ortalaması; tahmin aralığı kapsamıyorsa null.
  ({double cloud, double humidity, double wind})? average(DateTime a, DateTime b) {
    final xs = [
      for (final h in hours)
        if (h.t.add(const Duration(hours: 1)).isAfter(a) && h.t.isBefore(b)) h,
    ];
    if (xs.isEmpty) return null;
    double mean(num Function(HourWeather) f) => xs.fold<double>(0, (s, h) => s + f(h)) / xs.length;
    return (cloud: mean((h) => h.cloud), humidity: mean((h) => h.humidity), wind: mean((h) => h.wind));
  }

  /// Verilen ana en yakın saat.
  HourWeather? at(DateTime t) {
    for (final h in hours) {
      if (!t.isBefore(h.t) && t.isBefore(h.t.add(const Duration(hours: 1)))) return h;
    }
    return null;
  }
}

const openMeteoUrl = 'https://api.open-meteo.com/v1/forecast';

final _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 8)));
final _cache = <String, ({int hour, Future<Forecast> f})>{};

/// Yer (≈1 km'ye yuvarlanmış) ve saat başına tek istek.
Future<Forecast> fetchForecast(double lat, double lng) {
  final key = '${lat.toStringAsFixed(2)},${lng.toStringAsFixed(2)}';
  final hour = DateTime.now().millisecondsSinceEpoch ~/ 3600000;
  final hit = _cache[key];
  if (hit != null && hit.hour == hour) return hit.f;
  final f = _load(lat, lng);
  _cache[key] = (hour: hour, f: f);
  f.catchError((_) {
    if (identical(_cache[key]?.f, f)) _cache.remove(key); // hata önbelleğe alınmaz
    return Forecast(const [], Duration.zero);
  });
  return f;
}

Future<Forecast> _load(double lat, double lng) async {
  final res = await _dio.get<Map<String, dynamic>>(
    openMeteoUrl,
    queryParameters: {
      'latitude': lat.toStringAsFixed(3),
      'longitude': lng.toStringAsFixed(3),
      'hourly': 'cloud_cover,cloud_cover_low,cloud_cover_mid,cloud_cover_high,relative_humidity_2m,wind_speed_10m',
      'timezone': 'auto',
      'forecast_days': 7,
    },
  );
  final j = res.data!;
  final offset = Duration(seconds: (j['utc_offset_seconds'] as num?)?.toInt() ?? 0);
  final h = j['hourly'] as Map<String, dynamic>;
  final times = (h['time'] as List).cast<String>();
  int n(String k, int i) => ((h[k] as List)[i] as num?)?.round() ?? 0;
  return Forecast([
    for (var i = 0; i < times.length; i++)
      HourWeather(
        // Yerel saat (ofsetsiz) → gerçek an
        DateTime.parse('${times[i]}Z').subtract(offset).toLocal(),
        n('cloud_cover', i),
        n('cloud_cover_low', i),
        n('cloud_cover_mid', i),
        n('cloud_cover_high', i),
        n('relative_humidity_2m', i),
        ((h['wind_speed_10m'] as List)[i] as num?)?.toDouble() ?? 0,
      ),
  ], offset);
}
