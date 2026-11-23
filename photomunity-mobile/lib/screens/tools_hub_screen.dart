import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import 'feed_screen.dart' show navClearance;

/// Alt menünün ortasındaki logo: fotoğrafçılık araçları. Yeni modüller buraya eklenir.
class ToolsHubScreen extends ConsumerWidget {
  const ToolsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    // Her araç kendi konusunu anlatan bir fotoğrafın üzerinde
    final tiles = <(String, String, String, String)>[
      ('sunset', t('sky.night_ar'), t('sky.night_ar_sub'), '/sky/ar'),
      ('fog', t('tools.title'), t('hub.tools_sub'), '/tools'),
      ('forest', t('guide.title'), t('hub.guide_sub'), '/guide'),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, navClearance),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('nav.tools'), style: font(34, weight: 700, spacing: -1.2, color: p.ink)),
                  const SizedBox(height: 4),
                  Text(t('hub.lead'), style: font(15, color: p.inkMuted)),
                ],
              ),
            ),
            // Öne çıkan modül: gökyüzü planlayıcı (her iki temada gece rengi)
            Semantics(
              button: true,
              label: t('sky.title'),
              excludeSemantics: true,
              child: Material(
                color: const Color(0xFF0E1224),
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => context.push('/sky'),
                  child: SizedBox(
                    height: 210,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset('assets/tools/milkyway.jpg', fit: BoxFit.cover),
                        // Yazının okunması için alt şerit (gradyan yok, düz yarı saydam)
                        const Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 104,
                          child: ColoredBox(color: Color(0x8C080A14)),
                        ),
                        Positioned(
                          left: 20,
                          right: 20,
                          bottom: 20,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t('sky.title'),
                                  style: font(24, weight: 700, spacing: -0.6, color: const Color(0xFFF3F4F7))),
                              const SizedBox(height: 2),
                              Text(t('sky.hub_sub'), style: font(14, color: const Color(0xFFD6DBF0))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.15,
              children: [
                for (final (image, title, sub, route) in tiles)
                  _PhotoTile(image: image, title: title, subtitle: sub, onTap: () => context.push(route)),
                _Tile(icon: LucideIcons.plus, title: t('hub.soon'), subtitle: t('hub.soon_sub'), dashed: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, required this.subtitle, this.dashed = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final body = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: dashed ? p.line : p.accentTint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 22, color: dashed ? p.inkMuted : p.accentText),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: font(16, weight: 700, color: dashed ? p.inkMuted : p.ink)),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: font(13, color: p.inkMuted)),
            ],
          ),
        ],
      ),
    );
    if (dashed) {
      return Semantics(
        label: '$title. $subtitle',
        child: CustomPaint(painter: _DashedBorder(p.ringIdle), child: body),
      );
    }
    return Semantics(
      button: true,
      label: title,
      excludeSemantics: true,
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: body,
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(22)));
    for (final m in path.computeMetrics()) {
      for (double d = 0; d < m.length; d += 10) {
        canvas.drawPath(m.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

/// Arka planında konuyla ilgili fotoğraf olan araç kartı.
class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.image, required this.title, required this.subtitle, required this.onTap});
  final String image;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      excludeSemantics: true,
      child: Material(
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset('assets/tools/$image.jpg', fit: BoxFit.cover),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ColoredBox(
                  color: const Color(0x8C080A14),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: font(16, weight: 700, color: Colors.white)),
                        Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: font(12.5, color: const Color(0xFFE3E6F2))),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
