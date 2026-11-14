import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../core/astro.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/design.dart';

class PlannerScreen extends ConsumerStatefulWidget {
  const PlannerScreen({super.key});

  @override
  ConsumerState<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends ConsumerState<PlannerScreen> {
  DateTime _date = DateTime.now();
  double? _lat, _lng;
  String _label = '';
  DateTime? _selected;

  @override
  void initState() {
    super.initState();
    final me = ref.read(authProvider).asData?.value;
    if (me?.latitude != null && me?.longitude != null) {
      _lat = me!.latitude;
      _lng = me.longitude;
      _label = me.city ?? '';
    } else {
      _lat = 40.83;
      _lng = 41.16;
      _label = 'Kaçkar Dağları';
    }
  }

  Future<void> _locate() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied)
      perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever)
      return;
    final pos = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    setState(() {
      _lat = pos.latitude;
      _lng = pos.longitude;
      _label = L10n.of(context)('planner.my_location');
      _selected = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final locale = t.locale.languageCode;
    final plan = planNight(_date, _lat!, _lng!);
    final hm = DateFormat.Hm(locale);
    String tm(DateTime? d) => d == null ? '—' : hm.format(d);
    final at =
        _selected ??
        plan.coreTransit?.t ??
        DateTime.fromMillisecondsSinceEpoch(
          plan.samples[plan.samples.length ~/ 2].t,
        );
    final best = plan.bestWindows.isEmpty ? null : plan.bestWindows.first;
    const phases = [
      'new',
      'waxing_crescent',
      'first_quarter',
      'waxing_gibbous',
      'full',
      'waning_gibbous',
      'last_quarter',
      'waning_crescent',
    ];
    final phaseName = t(
      'planner.phase.${phases[(plan.phase * 8).round() % 8]}',
    );
    final core = corePosition(at.millisecondsSinceEpoch, _lat!, _lng!);
    final moon = moonPosition(at.millisecondsSinceEpoch, _lat!, _lng!);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('planner.title'), style: font(24, weight: 700, spacing: -0.7, color: p.ink)),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: LargeButton(
          label: t('planner.open_ar'),
          icon: LucideIcons.scan,
          onPressed: () => context.push(
            '/planner/ar?lat=$_lat&lng=$_lng&date=${_date.millisecondsSinceEpoch}',
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: p.surface,
                  foregroundColor: p.ink,
                  minimumSize: const Size(0, 48),
                  textStyle: font(16, weight: 600),
                ),
                icon: const Icon(LucideIcons.calendar, size: 20),
                label: Text(DateFormat.yMMMd(locale).format(_date)),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (d != null) setState(() {
                    _date = d;
                    _selected = null;
                  });
                },
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: p.surface,
                  foregroundColor: p.ink,
                  minimumSize: const Size(0, 48),
                  textStyle: font(16, weight: 600),
                ),
                icon: const Icon(LucideIcons.mapPin, size: 20),
                label: Text(_label.isNotEmpty ? _label : t('planner.use_location')),
                onPressed: _locate,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_label.isEmpty ? '' : '$_label · '}${_lat!.toStringAsFixed(2)}, ${_lng!.toStringAsFixed(2)}',
            style: font(13, color: p.inkMuted),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
            decoration: BoxDecoration(
              color: best != null ? p.accent : p.surface,
              borderRadius: BorderRadius.circular(Radii.card),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('planner.best_window'),
                  style: font(
                    15,
                    weight: 600,
                    color: best != null
                        ? p.accentInk.withValues(alpha: 0.85)
                        : p.inkMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  best != null
                      ? '${tm(best.start)} – ${tm(best.end)}'
                      : t('planner.no_window'),
                  style: font(
                    best != null ? 40 : 24,
                    weight: 700,
                    spacing: best != null ? -1.4 : -0.4,
                    color: best != null ? p.accentInk : p.ink,
                    tabular: true,
                  ),
                ),
                if (plan.coreTransit != null)
                  Text(
                    t('planner.core_peak', {
                      'time': tm(plan.coreTransit!.t),
                      'alt': plan.coreTransit!.alt.round(),
                      'dir': compassPoint(plan.coreTransit!.az, locale),
                    }),
                    style: font(
                      13,
                      color: best != null
                          ? p.accentInk.withValues(alpha: 0.85)
                          : p.inkMuted,
                    ),
                  ),
              ],
            ),
          ),
          if (best == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                plan.illumination >= 0.25 && plan.coreTransit != null
                    ? t('planner.why_moon')
                    : plan.coreTransit == null
                    ? t('planner.why_core')
                    : t('planner.why_dark'),
                style: font(13, height: 1.4, color: p.inkMuted),
              ),
            ),
          const SizedBox(height: Space.s2),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(Space.s4),
                  decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(Radii.card)),
                  child: Row(
                    children: [
                      CustomPaint(
                        size: const Size(44, 44),
                        painter: _MoonPainter(
                          plan.phase,
                          plan.illumination,
                          p.inkSubtle,
                          p.line,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              phaseName,
                              style: font(14, weight: 600, color: p.ink),
                            ),
                            Text(
                              t('planner.illuminated', {
                                'pct': (plan.illumination * 100).round(),
                              }),
                              style: font(12.5, color: p.inkMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: Space.s2),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(Space.s4),
                  decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(Radii.card)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('planner.dark_window'),
                        style: font(12.5, color: p.inkMuted),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        plan.duskAstro != null
                            ? '${tm(plan.duskAstro)} – ${tm(plan.dawnAstro)}'
                            : t('planner.no_darkness'),
                        style: font(16, weight: 600, color: p.ink),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(Radii.card)),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                  child: Wrap(
                    spacing: 16,
                    children: [
                      for (final (name, color) in [
                        (t('planner.core'), p.accent),
                        (t('planner.moon'), p.inkMuted),
                        (t('planner.sun'), p.inkSubtle),
                      ])
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 18, height: 3, decoration: ShapeDecoration(color: color, shape: const StadiumBorder())),
                            const SizedBox(width: 6),
                            Text(name, style: font(14, color: p.inkMuted)),
                          ],
                        ),
                    ],
                  ),
                ),
                GestureDetector(
                  onPanDown: (d) => _pick(d.localPosition.dx, context, plan),
                  onPanUpdate: (d) => _pick(d.localPosition.dx, context, plan),
                  child: CustomPaint(
                    size: const Size(double.infinity, 200),
                    painter: _ChartPainter(plan, at, p, locale),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    t('planner.chart_hint'),
                    style: font(11.5, color: p.inkMuted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(Space.s4),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(Radii.card)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('planner.at_time', {'time': tm(at)}),
                  style: font(14.5, weight: 600, color: p.ink),
                ),
                const SizedBox(height: 8),
                for (final (name, pos, color) in [
                  (t('planner.core'), core, p.accent),
                  (t('planner.moon'), moon, p.inkMuted),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(name, style: font(14.5, color: p.ink)),
                        ),
                        Text(
                          pos.alt < 0
                              ? t('planner.below_horizon')
                              : '${compassPoint(pos.az, locale)} ${pos.az.round()}° · ${pos.alt.round()}°',
                          style: font(14, color: pos.alt < 0 ? p.inkMuted : p.ink),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const SizedBox(height: 14),
          Wrap(
            spacing: Space.s2,
            runSpacing: Space.s2,
            children: [
              for (final (k, v) in [
                ('sunset', plan.sunset),
                ('sunrise', plan.sunrise),
                ('moonrise', plan.moonrise),
                ('moonset', plan.moonset),
                ('core_rise', plan.coreRise),
                ('core_set', plan.coreSet),
                ('dusk', plan.duskAstro),
                ('dawn', plan.dawnAstro),
              ])
                SizedBox(
                  width: (MediaQuery.sizeOf(context).width - 24 - Space.s2) / 2,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(Radii.box)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tm(v), style: font(17, weight: 600, color: p.ink)),
                        Text(
                          t('planner.event.$k'),
                          style: font(12.5, color: p.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            t('planner.accuracy'),
            style: font(11.5, height: 1.4, color: p.inkMuted),
          ),
        ],
      ),
    );
  }

  void _pick(double dx, BuildContext context, NightPlan plan) {
    final w = context.size?.width ?? 1;
    final frac = (dx / (w - 32)).clamp(0.0, 1.0);
    final t0 = plan.samples.first.t, t1 = plan.samples.last.t;
    setState(
      () => _selected = DateTime.fromMillisecondsSinceEpoch(
        (t0 + frac * (t1 - t0)).round(),
      ),
    );
  }
}

class _MoonPainter extends CustomPainter {
  _MoonPainter(this.phase, this.fraction, this.color, this.base);
  final double phase, fraction;
  final Color color, base;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    canvas.drawCircle(c, r, Paint()..color = base);
    final waxing = phase < 0.5;
    final k = 1 - 2 * fraction;
    final path = Path()..moveTo(r, 0);
    path.arcToPoint(
      Offset(r, size.height),
      radius: Radius.circular(r),
      clockwise: waxing,
    );
    path.arcToPoint(
      Offset(r, 0),
      radius: Radius.elliptical(math.max(0.01, k.abs() * r), r),
      clockwise: (k > 0) != waxing,
    );
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _MoonPainter old) =>
      old.phase != phase || old.fraction != fraction;
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.plan, this.at, this.p, this.locale);
  final NightPlan plan;
  final DateTime at;
  final Palette p;
  final String locale;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 6.0, bottom = 20.0;
    final s = plan.samples;
    final t0 = s.first.t.toDouble(), t1 = s.last.t.toDouble();
    double x(num t) => (t - t0) / (t1 - t0) * size.width;
    double y(double alt) =>
        top +
        (90 - alt.clamp(-20.0, 90.0)) / 110 * (size.height - top - bottom);
    final h = size.height - top - bottom;

    // Astronomik karanlık ve en iyi pencere
    int? open;
    for (final smp in s) {
      if (smp.sun.alt < -18 && open == null) open = smp.t;
      if ((smp.sun.alt >= -18 || smp == s.last) && open != null) {
        canvas.drawRect(
          Rect.fromLTWH(x(open), top, x(smp.t) - x(open), h),
          Paint()..color = p.ink.withValues(alpha: 0.08),
        );
        open = null;
      }
    }
    for (final w in plan.bestWindows) {
      canvas.drawRect(
        Rect.fromLTWH(
          x(w.start.millisecondsSinceEpoch),
          top,
          x(w.end.millisecondsSinceEpoch) - x(w.start.millisecondsSinceEpoch),
          h,
        ),
        Paint()..color = p.accent.withValues(alpha: 0.18),
      );
    }
    final grid = Paint()
      ..color = p.line
      ..strokeWidth = 1;
    for (final a in [30.0, 60.0]) {
      canvas.drawLine(Offset(0, y(a)), Offset(size.width, y(a)), grid);
    }
    canvas.drawLine(
      Offset(0, y(0)),
      Offset(size.width, y(0)),
      Paint()
        ..color = p.inkMuted
        ..strokeWidth = 1,
    );

    void curve(double Function(Sample) get, Color color, double width) {
      final path = Path();
      for (var i = 0; i < s.length; i++) {
        final pt = Offset(x(s[i].t), y(get(s[i])));
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..style = PaintingStyle.stroke,
      );
    }

    curve((v) => v.sun.alt, p.inkSubtle, 2);
    curve((v) => v.moon.alt, p.inkMuted, 2);
    curve((v) => v.core.alt, p.accent, 3);
    final ax = x(at.millisecondsSinceEpoch);
    canvas.drawLine(
      Offset(ax, top),
      Offset(ax, top + h),
      Paint()
        ..color = p.ink
        ..strokeWidth = 1.5,
    );

    final fmt = DateFormat.Hm(locale);
    for (var i = 0; i <= 24; i += 4) {
      final t = t0 + i * 3600000;
      final tp = TextPainter(
        text: TextSpan(
          text: fmt.format(DateTime.fromMillisecondsSinceEpoch(t.round())),
          style: font(10, color: p.inkMuted),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          (x(t) - tp.width / 2).clamp(0.0, size.width - tp.width),
          size.height - 14,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.plan != plan || old.at != at;
}
