import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/l10n.dart';
import '../../state/providers.dart';

/// Gökyüzü modülünün ortak konumu: profildeki şehir, yoksa Kaçkarlar; "Konumum" ile cihaz konumu.
class SkyPlace {
  const SkyPlace(this.lat, this.lng, this.label, {this.fromDevice = false});
  final double lat, lng;
  final String label;
  final bool fromDevice;
}

final skyPlaceProvider = NotifierProvider<SkyPlaceController, SkyPlace>(SkyPlaceController.new);

class SkyPlaceController extends Notifier<SkyPlace> {
  @override
  SkyPlace build() {
    final me = ref.read(authProvider).asData?.value;
    if (me?.latitude != null && me?.longitude != null) {
      return SkyPlace(me!.latitude!, me.longitude!, me.city ?? '');
    }
    return const SkyPlace(40.83, 41.16, 'Kaçkar Dağları');
  }

  void set(double lat, double lng, String label) => state = SkyPlace(lat, lng, label);

  /// Cihaz konumu; izin yoksa false döner.
  Future<bool> locate(String label) async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return false;
    final pos = await Geolocator.getCurrentPosition();
    state = SkyPlace(pos.latitude, pos.longitude, label, fromDevice: true);
    return true;
  }
}

/// Ay'ın o günkü şekli: aydınlık yarım daire + terminatör elipsi (kuzey yarımküreden bakış).
class MoonGlyph extends StatelessWidget {
  const MoonGlyph({
    super.key,
    required this.phase,
    required this.fraction,
    this.size = 28,
    this.lit = const Color(0xFFF4F0DE),
    this.dark = const Color(0xFF2A2F45),
  });
  final double phase, fraction, size;
  final Color lit, dark;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '%${(fraction * 100).round()}',
    child: CustomPaint(size: Size.square(size), painter: _MoonPainter(phase, fraction, lit, dark)),
  );
}

class _MoonPainter extends CustomPainter {
  _MoonPainter(this.phase, this.fraction, this.lit, this.dark);
  final double phase, fraction;
  final Color lit, dark;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    canvas.drawCircle(c, r, Paint()..color = dark);
    if (fraction < 0.01) return;
    if (fraction > 0.99) {
      canvas.drawCircle(c, r, Paint()..color = lit);
      return;
    }
    final waxing = phase % 1 < 0.5;
    final k = 1 - 2 * fraction; // >0 hilal, <0 şişkin
    final path = Path()..moveTo(r, 0);
    path.arcToPoint(Offset(r, size.height), radius: Radius.circular(r), clockwise: waxing);
    path.arcToPoint(
      Offset(r, 0),
      radius: Radius.elliptical((k.abs() * r).clamp(0.01, r), r),
      clockwise: (k > 0) != waxing,
    );
    canvas.drawPath(path, Paint()..color = lit);
  }

  @override
  bool shouldRepaint(covariant _MoonPainter old) => old.phase != phase || old.fraction != fraction;
}

/// "Konumum" düğmesi ve konum etiketi (AppBar alt satırı).
class SkyPlaceLine extends ConsumerWidget {
  const SkyPlaceLine({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final place = ref.watch(skyPlaceProvider);
    final c = color ?? DefaultTextStyle.of(context).style.color;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final ok = await ref.read(skyPlaceProvider.notifier).locate(t('planner.my_location'));
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('sky.location_denied'))));
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(place.fromDevice ? Icons.my_location : Icons.location_on_outlined, size: 14, color: c),
            const SizedBox(width: 4),
            Text(
              place.label.isEmpty
                  ? '${place.lat.toStringAsFixed(2)}, ${place.lng.toStringAsFixed(2)}'
                  : place.label,
              style: TextStyle(fontSize: 13, color: c),
            ),
          ],
        ),
      ),
    );
  }
}
