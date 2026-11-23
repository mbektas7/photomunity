import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/astro.dart';
import '../../core/calculators.dart';
import '../../core/l10n.dart';
import '../../core/sky.dart';
import '../../core/theme.dart';
import 'sky_common.dart';

/// Gece hesapları: yıldız izi, timelapse, nokta yıldız (NPF) ve meteor yağmurları.
class NightToolsScreen extends StatelessWidget {
  const NightToolsScreen({super.key, this.tab});
  final String? tab;

  static const _tabs = ['trails', 'timelapse', 'npf', 'meteors'];

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    return DefaultTabController(
      length: _tabs.length,
      initialIndex: math.max(0, _tabs.indexOf(tab ?? '')),
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('sky.night_tools'), style: font(21, weight: 700, color: p.ink)),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelStyle: font(14.5, weight: 700),
            labelColor: p.ink,
            unselectedLabelColor: p.inkMuted,
            indicatorColor: p.ink,
            tabs: [for (final k in _tabs) Tab(text: t('sky.tab_$k'))],
          ),
        ),
        body: const TabBarView(children: [_Trails(), _Timelapse(), _Npf(), _Meteors()]),
      ),
    );
  }
}

/// Sayı girişi: etiket + değer + birim, − / + ile adım adım.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.unit,
    required this.onChanged,
    required this.step,
    required this.min,
    required this.max,
    this.decimals = 0,
  });
  final String label, unit;
  final double value, step, min, max;
  final int decimals;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: font(12, color: p.inkMuted)),
                Text.rich(
                  maxLines: 1,
                  TextSpan(
                    children: [
                      TextSpan(text: value.toStringAsFixed(decimals), style: font(18, weight: 700, color: p.ink)),
                      TextSpan(text: ' $unit', style: font(13, color: p.inkMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 38, height: 38),
            padding: EdgeInsets.zero,
            onPressed: value - step >= min ? () => onChanged(value - step) : null,
            icon: const Icon(Icons.remove),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 38, height: 38),
            padding: EdgeInsets.zero,
            onPressed: value + step <= max ? () => onChanged(value + step) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.left, required this.leftLabel, required this.right, required this.rightLabel, this.note});
  final String left, leftLabel, right, rightLabel;
  final String? note;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: const Color(0xFF14161B), borderRadius: BorderRadius.circular(Radii.card)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(leftLabel, style: font(12, color: Colors.white60)),
                  Text(left, style: font(26, weight: 700, color: Colors.white)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(rightLabel, style: font(12, color: Colors.white60)),
                Text(right, style: font(26, weight: 700, color: Colors.white)),
              ],
            ),
          ],
        ),
        if (note != null) ...[
          const SizedBox(height: 6),
          Text(note!, style: font(12.5, color: Colors.white70)),
        ],
      ],
    ),
  );
}

String _dur(Duration d, L10n t) {
  final h = d.inHours, m = d.inMinutes % 60;
  return h > 0 ? t('sky.dur_hm', {'h': h, 'm': m}) : t('sky.dur_m', {'m': m});
}

Widget _grid(List<Widget> children) => GridView.count(
  crossAxisCount: 2,
  shrinkWrap: true,
  physics: const NeverScrollableScrollPhysics(),
  mainAxisSpacing: 8,
  crossAxisSpacing: 8,
  childAspectRatio: 2.05,
  children: children,
);

class _Trails extends StatefulWidget {
  const _Trails();

  @override
  State<_Trails> createState() => _TrailsState();
}

class _TrailsState extends State<_Trails> {
  double _arc = 30, _exp = 30, _gap = 1, _mb = 30;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final r = starTrails(arcDeg: _arc, exposureSec: _exp, gapSec: _gap);
    final gb = r.frames * _mb / 1000;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.card),
          child: SizedBox(height: 160, child: CustomPaint(painter: _TrailsPainter(_arc))),
        ),
        const SizedBox(height: 6),
        Text(t('sky.trails_lead'), style: font(13, color: p.inkMuted)),
        const SizedBox(height: 12),
        _grid([
          _Stepper(label: t('sky.trail_arc'), value: _arc, unit: '°', step: 5, min: 5, max: 180, onChanged: (v) => setState(() => _arc = v)),
          _Stepper(label: t('sky.frame_exposure'), value: _exp, unit: t('sky.sec'), step: 5, min: 5, max: 240, onChanged: (v) => setState(() => _exp = v)),
          _Stepper(label: t('sky.frame_gap'), value: _gap, unit: t('sky.sec'), step: 1, min: 0, max: 30, onChanged: (v) => setState(() => _gap = v)),
          _Stepper(label: t('sky.raw_size'), value: _mb, unit: 'MB', step: 5, min: 5, max: 150, onChanged: (v) => setState(() => _mb = v)),
        ]),
        const SizedBox(height: 12),
        _Result(
          leftLabel: t('sky.total_time'),
          left: _dur(r.total, t),
          rightLabel: t('sky.frames'),
          right: '${r.frames}',
          note: t('sky.trails_note', {'gb': gb.toStringAsFixed(1)}),
        ),
      ],
    );
  }
}

class _TrailsPainter extends CustomPainter {
  _TrailsPainter(this.arc);
  final double arc;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const RadialGradient(center: Alignment(0.4, -0.6), radius: 1.2, colors: [Color(0xFF1A2050), Color(0xFF05070F)])
            .createShader(Offset.zero & size),
    );
    final c = Offset(size.width * 0.72, size.height * 0.15);
    final rnd = math.Random(7);
    for (var i = 0; i < 26; i++) {
      final r = 12.0 + i * 11;
      final start = rnd.nextDouble() * 2 * math.pi;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        start,
        arc * math.pi / 180,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..color = const Color(0xFFCFD8FF).withValues(alpha: 0.25 + rnd.nextDouble() * 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrailsPainter old) => old.arc != arc;
}

class _Timelapse extends StatefulWidget {
  const _Timelapse();

  @override
  State<_Timelapse> createState() => _TimelapseState();
}

class _TimelapseState extends State<_Timelapse> {
  double _hours = 3, _clip = 15, _fps = 25, _exp = 20;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final r = timelapse(shoot: Duration(minutes: (_hours * 60).round()), clipSec: _clip, fps: _fps.round());
    final tooShort = r.intervalSec < _exp;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(t('sky.timelapse_lead'), style: font(13, color: p.inkMuted)),
        const SizedBox(height: 12),
        _grid([
          _Stepper(label: t('sky.shoot_length'), value: _hours, unit: t('sky.hours'), step: 0.5, min: 0.5, max: 12, decimals: 1, onChanged: (v) => setState(() => _hours = v)),
          _Stepper(label: t('sky.clip_length'), value: _clip, unit: t('sky.sec'), step: 5, min: 5, max: 120, onChanged: (v) => setState(() => _clip = v)),
          _Stepper(label: 'FPS', value: _fps, unit: '', step: 1, min: 12, max: 60, onChanged: (v) => setState(() => _fps = v)),
          _Stepper(label: t('sky.frame_exposure'), value: _exp, unit: t('sky.sec'), step: 5, min: 1, max: 60, onChanged: (v) => setState(() => _exp = v)),
        ]),
        const SizedBox(height: 12),
        _Result(
          leftLabel: t('sky.interval'),
          left: '${r.intervalSec.toStringAsFixed(1)} ${t('sky.sec')}',
          rightLabel: t('sky.frames'),
          right: '${r.frames}',
          note: tooShort ? t('sky.timelapse_too_short', {'exp': _exp.round()}) : t('sky.timelapse_ok'),
        ),
      ],
    );
  }
}

class _Npf extends StatefulWidget {
  const _Npf();

  @override
  State<_Npf> createState() => _NpfState();
}

class _NpfState extends State<_Npf> {
  String _sensor = 'ff';
  double _mp = 33, _focal = 20, _ap = 2.8;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final npf = npfSeconds(_sensor, _mp, _focal, _ap);
    final core = npfSeconds(_sensor, _mp, _focal, _ap, -29);
    final r500 = rule500Seconds(_sensor, _focal);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(t('tools.npf_lead'), style: font(13, color: p.inkMuted)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in sensors.keys)
              ChoiceChip(
                label: Text(t('tools.sensor.$s')),
                selected: _sensor == s,
                onSelected: (_) => setState(() => _sensor = s),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _grid([
          _Stepper(label: t('tools.megapixels'), value: _mp, unit: 'MP', step: 1, min: 8, max: 120, onChanged: (v) => setState(() => _mp = v)),
          _Stepper(label: t('tools.focal'), value: _focal, unit: 'mm', step: 1, min: 8, max: 200, onChanged: (v) => setState(() => _focal = v)),
          _Stepper(label: t('tools.aperture'), value: _ap, unit: 'f/', step: 0.1, min: 1, max: 8, decimals: 1, onChanged: (v) => setState(() => _ap = (v * 10).round() / 10)),
          const SizedBox.shrink(),
        ]),
        const SizedBox(height: 12),
        _Result(
          leftLabel: t('tools.npf_result'),
          left: '${npf.toStringAsFixed(1)} ${t('sky.sec')}',
          rightLabel: t('tools.npf_core'),
          right: '${core.toStringAsFixed(1)} ${t('sky.sec')}',
          note: t('sky.npf_vs_500', {'s': r500.toStringAsFixed(1)}),
        ),
      ],
    );
  }
}

class _Meteors extends StatelessWidget {
  const _Meteors();

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final locale = t.locale.languageCode;
    final list = upcomingShowers(DateTime.now());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(Radii.card)),
          child: Column(
            children: [
              for (final (i, m) in list.indexed) ...[
                if (i > 0) Divider(height: 1, color: p.line, indent: 16, endIndent: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t('meteor.${m.s.key}'), style: font(15.5, weight: 700, color: p.ink)),
                            Text(
                              t('sky.meteor_row', {
                                'date': DateFormat.MMMd(locale).format(m.peak),
                                'zhr': m.s.zhr,
                              }),
                              style: font(13, color: p.inkMuted),
                            ),
                          ],
                        ),
                      ),
                      MoonGlyph(
                        phase: moonIllumination(m.peak.millisecondsSinceEpoch).phase,
                        fraction: m.moon,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        m.moon < 0.35 ? t('sky.meteor_good') : t('sky.meteor_bright'),
                        style: font(12.5, weight: 700, color: m.moon < 0.35 ? const Color(0xFF1A7F45) : const Color(0xFFB45309)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 12, 6, 0),
          child: Text(t('sky.meteor_hint'), style: font(12.5, color: p.inkMuted)),
        ),
      ],
    );
  }
}
