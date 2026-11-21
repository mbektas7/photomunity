import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Photomunity logosu (design/logo). Tek renk; temaya göre mürekkep rengine boyanır.
/// [stacked] false: yatay (simge + yazı), true: simgenin altında yazı.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.height = 30, this.stacked = false, this.color});

  final double height;
  final bool stacked;
  final Color? color;

  @override
  Widget build(BuildContext context) => Image.asset(
    stacked ? 'assets/brand/logo_stacked.png' : 'assets/brand/logo.png',
    height: height,
    color: color ?? context.palette.ink,
    filterQuality: FilterQuality.high,
    semanticLabel: 'Photomunity',
  );
}
