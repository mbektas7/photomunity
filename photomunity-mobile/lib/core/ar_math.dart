// AR yansıtma matematiği (Flutter'dan bağımsız, test edilebilir).
//
// Cihaz koordinatları (Android sözleşmesi): x sağ, y yukarı, z ekrandan dışarı.
// Arka kamera −z yönüne bakar. Dünya koordinatları: Doğu, Kuzey, Yukarı.
import 'dart:math' as math;

class Vec3 {
  const Vec3(this.x, this.y, this.z);
  final double x, y, z;
  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator *(double k) => Vec3(x * k, y * k, z * k);
  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 cross(Vec3 o) =>
      Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(dot(this));
  Vec3 get unit => this * (1 / length);
}

/// Cihazın dünyadaki yönelimi: kameranın ileri, sağ ve yukarı eksenleri (dünya koordinatlarında).
class DeviceAttitude {
  const DeviceAttitude(this.forward, this.right, this.up);
  final Vec3 forward, right, up;

  /// Kameranın baktığı yön: azimut (kuzeyden saat yönünde) ve yükseklik, derece.
  ({double az, double alt}) get pointing => (
    az: (math.atan2(forward.x, forward.y) * 180 / math.pi + 360) % 360,
    alt: math.asin(forward.z.clamp(-1.0, 1.0)) * 180 / math.pi,
  );
}

/// Yerçekimi (ivmeölçer) ve manyetik alan vektörlerinden yönelim. [headingOffset] derece:
/// manyetik sapma ve pusula hatası için kullanıcı kalibrasyonu (pozitif = doğuya döndür).
DeviceAttitude? orientationFrom(
  Vec3 gravity,
  Vec3 magnetic, {
  double headingOffset = 0,
}) {
  if (gravity.length < 1e-3 || magnetic.length < 1e-3) return null;
  final up = gravity.unit; // dinlenmede ivmeölçer yukarıyı gösterir
  final eastRaw = magnetic.cross(up);
  if (eastRaw.length < 1e-3) return null; // telefon manyetik alana paralel
  final east = eastRaw.unit;
  final north = up.cross(east);
  // Cihaz ekseni → dünya: satırlar Doğu, Kuzey, Yukarı bileşenleri
  Vec3 toWorld(Vec3 d) => Vec3(
    east.x * d.x + east.y * d.y + east.z * d.z,
    north.x * d.x + north.y * d.y + north.z * d.z,
    up.x * d.x + up.y * d.y + up.z * d.z,
  );
  var f = toWorld(const Vec3(0, 0, -1)),
      r = toWorld(const Vec3(1, 0, 0)),
      u = toWorld(const Vec3(0, 1, 0));
  if (headingOffset != 0) {
    final a = headingOffset * math.pi / 180;
    Vec3 rot(Vec3 v) => Vec3(
      v.x * math.cos(a) + v.y * math.sin(a),
      -v.x * math.sin(a) + v.y * math.cos(a),
      v.z,
    );
    f = rot(f);
    r = rot(r);
    u = rot(u);
  }
  return DeviceAttitude(f, r, u);
}

Vec3 directionOf(double azDeg, double altDeg) {
  final az = azDeg * math.pi / 180, alt = altDeg * math.pi / 180;
  return Vec3(
    math.cos(alt) * math.sin(az),
    math.cos(alt) * math.cos(az),
    math.sin(alt),
  );
}

/// Gök cismini ekran noktasına yansıtır; kameranın arkasındaysa null. [vfovDeg] dikey görüş açısı.
({double x, double y})? project(
  DeviceAttitude o,
  double azDeg,
  double altDeg,
  double width,
  double height,
  double vfovDeg,
) {
  final v = directionOf(azDeg, altDeg);
  final z = v.dot(o.forward);
  if (z <= 0.05) return null;
  final focal = (height / 2) / math.tan(vfovDeg * math.pi / 360);
  return (
    x: width / 2 + v.dot(o.right) / z * focal,
    y: height / 2 - v.dot(o.up) / z * focal,
  );
}

/// Basit alçak geçiren süzgeç: sensör titremesini yumuşatır.
Vec3 lowPass(Vec3? previous, Vec3 next, [double alpha = 0.15]) =>
    previous == null
    ? next
    : previous +
          (Vec3(next.x - previous.x, next.y - previous.y, next.z - previous.z) *
              alpha);
