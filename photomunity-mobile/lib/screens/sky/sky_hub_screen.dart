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
import '../../core/weather.dart';
import '../../state/providers.dart';
import '../../widgets/design.dart';
import '../../widgets/intro.dart';
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
    final hm = DateFormat.Hm(locale);
    final best = plan.bestWindows.isEmpty ? null : plan.bestWindows.first;
    final core = nightCoreHighest(plan);
    final shower = upcomingShowers(now, count: 1).first;
    final moonSet = plan.moonset;

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

    final forecast = ref.watch(forecastProvider((place.lat, place.lng))).asData?.value;
    final span = darkSpan(plan);
    final tonightWx = span == null ? null : forecast?.average(span.start, span.end);
    final score = nightScore(plan, cloud: tonightWx?.cloud);
    final plans = ref.watch(plansProvider('upcoming')).asData?.value;
    final verdict = t('sky.score_${score.score >= 80 ? 'great' : score.verdict}');
    final moonText = '${t('planner.phase.${moonPhaseKey(plan.phase)}')} %${(plan.illumination * 100).round()}';
    final moonLine = [
      if (tonightWx != null) t(tonightWx.cloud < 20 ? 'sky.clear' : (tonightWx.cloud < 60 ? 'sky.partly' : 'sky.cloudy')),
      moonText,
      if (tonightWx == null && moonSet != null) t('sky.moon_sets_at', {'time': hm.format(moonSet)}),
    ].join(' · ');
    final ringColor = switch (score.verdict) {
      'good' => const Color(0xFF7FE0C0),
      'fair' => const Color(0xFFFFD27A),
      _ => const Color(0xFFFF9C8F),
    };

    Widget wxStat(IconData icon, String label, String value) => Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: Colors.white70),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: font(11.5, color: Colors.white70)),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: font(15, weight: 700, color: Colors.white)),
          ],
        ),
      ),
    );

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
        actions: const [IntroButton(module: 'sky'), SizedBox(width: 12)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // Bu gece: çekim puanı, hava ve pencere
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => context.push('/planner'),
            child: Ink(
              padding: const EdgeInsets.all(16),
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
                      MoonGlyph(phase: plan.phase, fraction: plan.illumination, size: 48, dark: const Color(0xFF2A3060)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t('sky.tonight').toUpperCase(),
                              style: font(12, weight: 700, spacing: 0.4, color: Colors.white60),
                            ),
                            Text(verdict, style: font(20, weight: 700, color: Colors.white)),
                            Text(moonLine, style: font(13, color: Colors.white70)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Semantics(
                        label: t('sky.score_label', {'score': score.score}),
                        excludeSemantics: true,
                        child: Container(
                          width: 54,
                          height: 54,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ringColor, width: 4)),
                          child: Text('${score.score}', style: font(17, weight: 700, color: Colors.white, tabular: true)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      wxStat(LucideIcons.cloud, t('sky.cloud'), tonightWx == null ? '—' : '%${tonightWx.cloud.round()}'),
                      const SizedBox(width: 6),
                      wxStat(LucideIcons.droplet, t('sky.humidity'), tonightWx == null ? '—' : '%${tonightWx.humidity.round()}'),
                      const SizedBox(width: 6),
                      wxStat(LucideIcons.wind, t('sky.wind'),
                          tonightWx == null ? '—' : t('sky.kmh', {'v': tonightWx.wind.round()})),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      wxStat(
                        LucideIcons.clock,
                        t('sky.window'),
                        best == null ? '—' : '${hm.format(best.start)}–${hm.format(best.end)}',
                      ),
                      const SizedBox(width: 6),
                      wxStat(
                        LucideIcons.orbit,
                        t('sky.core_highest'),
                        core == null
                            ? t('sky.below_horizon')
                            : '${hm.format(core.t)} · ${core.alt.round()}° ${compassPoint(core.az, locale)}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          _NightsCard(base: night, lat: place.lat, lng: place.lng, forecast: forecast),
          const SizedBox(height: 10),
          Material(
            color: p.surface,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => context.push('/sky/plans'),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(color: p.accentTint, borderRadius: BorderRadius.circular(12)),
                      child: Icon(LucideIcons.calendarClock, color: p.accentText),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t('plan.my_plans'), style: font(15.5, weight: 700, color: p.ink)),
                          Text(
                            plans == null
                                ? t('plan.my_plans_sub')
                                : plans.isEmpty
                                ? t('plan.none_upcoming')
                                : t('plan.upcoming_count', {'count': plans.length}),
                            style: font(12.5, color: p.inkMuted),
                          ),
                        ],
                      ),
                    ),
                    if (plans != null && plans.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: ShapeDecoration(color: p.accent, shape: const StadiumBorder()),
                        child: Text('${plans.length}', style: font(11, weight: 700, color: p.accentInk, tabular: true)),
                      ),
                    const SizedBox(width: 6),
                    Icon(LucideIcons.chevronRight, color: p.inkSubtle),
                  ],
                ),
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
              onTap: () => context.push('/sky/dark'),
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: const Color(0xFF151933), borderRadius: BorderRadius.circular(12)),
                child: const Icon(LucideIcons.mapPinned, color: Color(0xFFFFD27A)),
              ),
              title: Text(t('dark.title'), style: font(15, weight: 700, color: p.ink)),
              subtitle: Text(t('dark.hub_sub'), style: font(13, color: p.inkMuted)),
              trailing: Icon(LucideIcons.chevronRight, color: p.inkSubtle),
            ),
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

/// Önümüzdeki beş gece: bulut çubuğu, Ay şekli ve İyi/Orta/Kötü (gece puanından).
class _NightsCard extends StatelessWidget {
  const _NightsCard({required this.base, required this.lat, required this.lng, required this.forecast});
  final DateTime base;
  final double lat, lng;
  final Forecast? forecast;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final locale = t.locale.languageCode;
    final nights = [
      for (var i = 0; i < 5; i++)
        () {
          final date = DateTime(base.year, base.month, base.day + i);
          final plan = planNight(date, lat, lng);
          final span = darkSpan(plan);
          final wx = span == null ? null : forecast?.average(span.start, span.end);
          return (date: date, plan: plan, cloud: wx?.cloud, score: nightScore(plan, cloud: wx?.cloud));
        }(),
    ];
    const verdictColor = {'good': Color(0xFF1A7F45), 'fair': Color(0xFFB45309), 'poor': Color(0xFFB42318)};
    const verdictDark = {'good': Color(0xFF6FD69A), 'fair': Color(0xFFF2B866), 'poor': Color(0xFFFF8A7A)};
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SurfaceCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(t('sky.next_nights'), style: font(16, weight: 700, color: p.ink))),
              Text(t('sky.cloud_moon'), style: font(12.5, color: p.inkMuted)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final (i, n) in nights.indexed)
                Expanded(
                  child: Semantics(
                    label: t('sky.night_sr', {
                      'day': i == 0 ? t('sky.tonight') : DateFormat.EEEE(locale).format(n.date),
                      'cloud': n.cloud == null ? '—' : '%${n.cloud!.round()}',
                      'verdict': t('sky.verdict_${n.score.verdict}'),
                    }),
                    excludeSemantics: true,
                    child: Column(
                      children: [
                        Text(
                          i == 0 ? t('sky.tonight') : DateFormat.E(locale).format(n.date),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: font(12, weight: 700, color: p.ink),
                        ),
                        const SizedBox(height: 5),
                        MoonGlyph(phase: n.plan.phase, fraction: n.plan.illumination, size: 22),
                        const SizedBox(height: 5),
                        Container(
                          width: 10,
                          height: 44,
                          alignment: Alignment.bottomCenter,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(999)),
                          child: FractionallySizedBox(
                            heightFactor: ((n.cloud ?? 0) / 100).clamp(0.0, 1.0),
                            widthFactor: 1,
                            child: const ColoredBox(color: Color(0xFF9AA3B5)),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(n.cloud == null ? '—' : '%${n.cloud!.round()}',
                            style: font(11, color: p.inkMuted, tabular: true)),
                        Text(
                          t('sky.verdict_${n.score.verdict}'),
                          style: font(11, weight: 700, color: (dark ? verdictDark : verdictColor)[n.score.verdict]),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (forecast == null) ...[
            const SizedBox(height: 10),
            Text(t('sky.no_forecast'), style: font(12, color: p.inkMuted)),
          ],
        ],
      ),
    );
  }
}
