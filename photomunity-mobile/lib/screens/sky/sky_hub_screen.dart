import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/astro.dart';
import '../../core/l10n.dart';
import '../../core/sky.dart';
import '../../core/theme.dart';
import 'sky_common.dart';

/// Gökyüzü modülü: bu gecenin özeti ve dört bölüm (Night AR, Ay takvimi, Güneş & Ay, gece hesapları).
class SkyHubScreen extends ConsumerWidget {
  const SkyHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    final locale = t.locale.languageCode;
    final place = ref.watch(skyPlaceProvider);
    final now = DateTime.now();
    // Gece planı öğleden öğleye; sabahın erken saatlerinde dünkü gece hâlâ sürüyor
    final night = now.hour < 12 ? now.subtract(const Duration(days: 1)) : now;
    final plan = planNight(night, place.lat, place.lng);
    final day = planDay(now, place.lat, place.lng);
    final hm = DateFormat.Hm(locale);
    final best = plan.bestWindows.isEmpty ? null : plan.bestWindows.first;
    final core = nightCoreHighest(plan);
    final shower = upcomingShowers(now, count: 1).first;
    final moonSet = plan.moonset;

    Widget stat(String label, String value) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: font(11.5, color: Colors.white60)),
            const SizedBox(height: 2),
            Text(value, style: font(15, weight: 700, color: Colors.white)),
          ],
        ),
      ),
    );

    Widget tile(String title, String sub, List<Color> colors, Widget art, String route) => Material(
      borderRadius: BorderRadius.circular(Radii.card),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        ),
        child: InkWell(
          onTap: () => context.push(route),
          child: SizedBox(
            height: 124,
            child: Stack(
              children: [
                Positioned(right: 0, bottom: 0, child: art),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: font(16, weight: 700, color: Colors.white)),
                      const SizedBox(height: 2),
                      SizedBox(
                        width: 120,
                        child: Text(sub, style: font(12.5, color: Colors.white.withValues(alpha: 0.78))),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final verdict = best != null
        ? t('sky.tonight_good')
        : (core == null ? t('sky.tonight_no_core') : t('sky.tonight_bright'));
    final moonLine = [
      '${t('planner.phase.${moonPhaseKey(plan.phase)}')} %${(plan.illumination * 100).round()}',
      if (moonSet != null) t('sky.moon_sets_at', {'time': hm.format(moonSet)}),
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('sky.title'), style: font(21, weight: 700, color: p.ink)),
            SkyPlaceLine(color: p.inkMuted),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // Bu gece
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => context.push('/planner'),
            child: Ink(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A2050), Color(0xFF0D1130)],
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      MoonGlyph(phase: plan.phase, fraction: plan.illumination, size: 56, dark: const Color(0xFF2A3060)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t('sky.tonight').toUpperCase(),
                              style: font(12, weight: 700, spacing: 0.4, color: Colors.white60),
                            ),
                            Text(verdict, style: font(20, weight: 700, color: Colors.white)),
                            Text(moonLine, style: font(13.5, color: Colors.white70)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      stat(
                        t('sky.window'),
                        best == null ? '—' : '${hm.format(best.start)} – ${hm.format(best.end)}',
                      ),
                      const SizedBox(width: 8),
                      stat(
                        t('sky.core_highest'),
                        core == null
                            ? t('sky.below_horizon')
                            : '${hm.format(core.t)} · ${core.alt.round()}° ${compassPoint(core.az, locale)}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      stat(
                        t('sky.golden_evening'),
                        day.goldenEvening == null
                            ? '—'
                            : '${hm.format(day.goldenEvening!.start)} – ${hm.format(day.goldenEvening!.end)}',
                      ),
                      const SizedBox(width: 8),
                      stat(t('sky.sunset'), day.sunset == null ? '—' : hm.format(day.sunset!.t)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.32,
            children: [
              tile(
                t('sky.night_ar'),
                t('sky.night_ar_sub'),
                const [Color(0xFF2B2370), Color(0xFF120F33)],
                const _BandArt(),
                '/sky/ar',
              ),
              tile(
                t('sky.moon_calendar'),
                t('sky.moon_calendar_sub'),
                const [Color(0xFF263049), Color(0xFF121726)],
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 14, 14),
                  child: Row(
                    children: [
                      for (final ph in [0.15, 0.3, 0.5, 0.7])
                        Padding(
                          padding: const EdgeInsets.only(left: 2),
                          child: MoonGlyph(phase: ph, fraction: (1 - math.cos(2 * math.pi * ph)) / 2, size: 24),
                        ),
                    ],
                  ),
                ),
                '/sky/moon',
              ),
              tile(
                t('sky.sun_moon'),
                t('sky.sun_moon_sub'),
                const [Color(0xFFFF9A5A), Color(0xFFC2410C)],
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 18, 0),
                  child: Container(
                    width: 52,
                    height: 26,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFD27A),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                    ),
                  ),
                ),
                '/sky/planner',
              ),
              tile(
                t('sky.night_tools'),
                t('sky.night_tools_sub'),
                const [Color(0xFF1F6F6A), Color(0xFF0E3533)],
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(LucideIcons.orbit, size: 54, color: Colors.white38),
                ),
                '/sky/tools',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Material(
            color: p.surface,
            borderRadius: BorderRadius.circular(20),
            child: ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              onTap: () => context.push('/sky/tools?tab=meteors'),
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(12)),
                child: const Icon(LucideIcons.sparkles, color: Color(0xFFC2560C)),
              ),
              title: Text(
                '${t('meteor.${shower.s.key}')} · ${DateFormat.MMMd(locale).format(shower.peak)}',
                style: font(15, weight: 700, color: p.ink),
              ),
              subtitle: Text(
                t('sky.meteor_line', {'zhr': shower.s.zhr, 'moon': (shower.moon * 100).round()}),
                style: font(13, color: p.inkMuted),
              ),
              trailing: Icon(LucideIcons.chevronRight, color: p.inkSubtle),
            ),
          ),
        ],
      ),
    );
  }
}

class _BandArt extends StatelessWidget {
  const _BandArt();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 130,
    height: 96,
    child: CustomPaint(painter: _BandPainter()),
  );
}

class _BandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final band = Path()
      ..moveTo(0, size.height + 10)
      ..cubicTo(size.width * 0.3, size.height * 0.5, size.width * 0.6, size.height * 0.3, size.width + 10, -10);
    canvas.drawPath(
      band,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 40
        ..color = const Color(0xFFC9B8FF).withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    final c = Offset(size.width * 0.6, size.height * 0.45);
    canvas.drawCircle(
      c,
      18,
      Paint()
        ..shader = const RadialGradient(colors: [Color(0xEEFFF6D8), Color(0x00FFF6D8)])
            .createShader(Rect.fromCircle(center: c, radius: 18)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
