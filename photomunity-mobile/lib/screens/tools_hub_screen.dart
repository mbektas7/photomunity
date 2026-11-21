import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/design.dart';
import 'feed_screen.dart' show navClearance;

/// Alt menünün ortasındaki logo: fotoğrafçılık araçları. Yeni modüller buraya eklenir.
class ToolsHubScreen extends ConsumerWidget {
  const ToolsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    final me = ref.watch(authProvider).asData?.value;
    final tiles = <(IconData, String, String, String)>[
      (LucideIcons.scan, t('hub.ar'), t('hub.ar_sub'), arRoute(me?.latitude, me?.longitude)),
      (LucideIcons.calculator, t('tools.title'), t('hub.tools_sub'), '/tools'),
      (LucideIcons.bookOpen, t('guide.title'), t('hub.guide_sub'), '/guide'),
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
              label: t('planner.title'),
              excludeSemantics: true,
              child: Material(
                color: const Color(0xFF0E1224),
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => context.push('/planner'),
                  child: SizedBox(
                    height: 200,
                    child: Stack(
                      children: [
                        for (final (x, y, r) in const [(0.86, 0.32, 2.0), (0.72, 0.48, 1.5), (0.58, 0.26, 1.2), (0.93, 0.6, 1.2)])
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment(x * 2 - 1, y * 2 - 1),
                              child: Container(
                                width: r * 2,
                                height: r * 2,
                                decoration: const BoxDecoration(color: Color(0xFFDDE2FF), shape: BoxShape.circle),
                              ),
                            ),
                          ),
                        const Positioned(
                          top: 18,
                          right: 18,
                          child: Icon(LucideIcons.moonStar, size: 30, color: Color(0xFFFFD58A)),
                        ),
                        Positioned(
                          left: 20,
                          right: 20,
                          bottom: 20,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t('planner.title'),
                                  style: font(24, weight: 700, spacing: -0.6, color: const Color(0xFFF3F4F7))),
                              const SizedBox(height: 2),
                              Text(t('hub.planner_sub'), style: font(14, color: const Color(0xFFA9B1D6))),
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
              childAspectRatio: 1.32,
              children: [
                for (final (icon, title, sub, route) in tiles)
                  _Tile(icon: icon, title: title, subtitle: sub, onTap: () => context.push(route)),
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
  const _Tile({required this.icon, required this.title, required this.subtitle, this.onTap, this.dashed = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
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
        child: InkWell(onTap: onTap, child: body),
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
