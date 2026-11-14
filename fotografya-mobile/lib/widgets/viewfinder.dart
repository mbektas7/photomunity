import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';

/// EXIF, makinenin vizöründeki bilgi şeridi gibi okunur. Temadan bağımsız olarak her zaman siyahtır.
class Viewfinder extends StatelessWidget {
  const Viewfinder({super.key, required this.exif});
  final Exif exif;

  static const _white = Color(0xFFF2F2EE);
  static const _label = Color(0xFF8D8D88);
  static const _sub = Color(0xFFC9C9C4);

  String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final readings = <(String, String)>[
      if (exif.shutter != null) (exif.shutter!, t('photo.shutter')),
      if (exif.aperture != null)
        ('f/${_num(exif.aperture!)}', t('photo.aperture')),
      if (exif.iso != null) ('${exif.iso}', 'ISO'),
      if (exif.focalLength != null)
        (
          '${exif.focalLength!.round()}mm',
          exif.focal35 != null && exif.focal35 != exif.focalLength!.round()
              ? t('photo.equivalent', {'mm': exif.focal35!})
              : t('photo.focal'),
        ),
    ];
    final camera = exif.camera;
    final meta = [
      ?camera,
      ?exif.lens,
      if (exif.takenAt != null)
        DateFormat.yMMMMd(t.locale.languageCode).format(exif.takenAt!),
    ];
    if (readings.isEmpty && meta.isEmpty) return const SizedBox.shrink();

    return Semantics(
      container: true,
      label: readings.map((r) => '${r.$2} ${r.$1}').join(', '),
      child: ExcludeSemantics(
        child: Container(
          color: Colors.black,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (readings.isNotEmpty)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (value, label) in readings)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                value,
                                style: font(
                                  23,
                                  weight: 600,
                                  height: 1,
                                  spacing: -0.4,
                                  color: _white,
                                  tabular: true,
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              label,
                              style: font(11.5, height: 1.2, color: _label),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              if (meta.isNotEmpty) ...[
                if (readings.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                  const SizedBox(height: 14),
                ],
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    for (final (i, m) in meta.indexed)
                      Text(
                        m,
                        style: font(
                          13.5,
                          color: i == 0 && camera != null ? _white : _sub,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
