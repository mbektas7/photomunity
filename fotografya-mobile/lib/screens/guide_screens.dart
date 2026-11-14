import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/calculators.dart';
import '../core/l10n.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/ad_widgets.dart';
import '../widgets/common.dart';

final _guidesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((
  ref,
) async {
  return (await ref.read(apiProvider).get<List<dynamic>>('/guides'))
      .cast<Map<String, dynamic>>();
});

final _guideProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, slug) async {
      return ref.read(apiProvider).get<Map<String, dynamic>>('/guides/$slug');
    });

class GuideHubScreen extends ConsumerWidget {
  const GuideHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    final guides = ref.watch(_guidesProvider);
    Widget tool(
      IconData icon,
      String title,
      String body,
      String route, {
      bool accent = false,
    }) => Material(
      color: accent ? p.ink : p.mat,
      child: InkWell(
        onTap: () => context.push(route),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: accent ? p.mat : p.ink),
              const SizedBox(height: 12),
              Text(
                title,
                style: font(15.5, weight: 600, color: accent ? p.mat : p.ink),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: font(
                  13,
                  color: accent ? p.mat.withValues(alpha: 0.7) : p.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(t('guide.title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Text(t('guide.lead'), style: font(15, height: 1.45, color: p.muted)),
          const SizedBox(height: 16),
          tool(
            Icons.nightlight_outlined,
            t('guide.planner_title'),
            t('guide.planner_body'),
            '/planner',
            accent: true,
          ),
          const SizedBox(height: 1),
          Row(
            children: [
              Expanded(
                child: tool(
                  Icons.timer_outlined,
                  t('guide.npf_title'),
                  t('guide.npf_body'),
                  '/tools?c=npf',
                ),
              ),
              const SizedBox(width: 1),
              Expanded(
                child: tool(
                  Icons.camera_outlined,
                  t('guide.dof_title'),
                  t('guide.dof_body'),
                  '/tools?c=dof',
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),
          tool(
            Icons.filter_b_and_w_outlined,
            t('guide.nd_title'),
            t('guide.nd_body'),
            '/tools?c=nd',
          ),
          const SizedBox(height: 24),
          ...switch (guides) {
            AsyncData(:final value) => [
              for (final cat in ['night', 'landscape', 'action', 'people']) ...[
                if (value.any((g) => g['category'] == cat)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                    child: Text(
                      t('guide.category.$cat'),
                      style: font(17, weight: 600, color: p.ink),
                    ),
                  ),
                  for (final g in value.where((g) => g['category'] == cat))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Material(
                        color: p.mat,
                        child: ListTile(
                          onTap: () => context.push('/guide/${g['slug']}'),
                          title: Text(
                            g['title'] as String,
                            style: font(16, weight: 600, color: p.ink),
                          ),
                          subtitle: Text(
                            g['summary'] as String,
                            style: font(13.5, height: 1.4, color: p.muted),
                          ),
                          trailing: Icon(Icons.chevron_right, color: p.muted),
                        ),
                      ),
                    ),
                ],
              ],
            ],
            AsyncError(:final error) => [
              ErrorView(
                error: error,
                onRetry: () => ref.invalidate(_guidesProvider),
              ),
            ],
            _ => [
              const Padding(
                padding: EdgeInsets.all(30),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          },
          const SizedBox(height: 20),
          const InlineAd(),
        ],
      ),
    );
  }
}

class GuideScreen extends ConsumerWidget {
  const GuideScreen({super.key, required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    final g = ref.watch(_guideProvider(slug));
    return Scaffold(
      appBar: AppBar(),
      body: switch (g) {
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 40),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value['title'] as String,
                    style: font(
                      36,
                      weight: 700,
                      height: 1,
                      spacing: -1.4,
                      color: p.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    value['summary'] as String,
                    style: font(16, height: 1.45, color: p.muted),
                  ),
                ],
              ),
            ),
            // Vizör şeridi: üç temel ayar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              color: Colors.black,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final k in ['aperture', 'shutter', 'iso'])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (value['settings'] as Map)[k] as String,
                            style: font(
                              17,
                              weight: 600,
                              height: 1.3,
                              color: const Color(0xFFF2F2EE),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t('guide.setting.$k'),
                            style: font(12, color: const Color(0xFF8D8D88)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final k in ['mode', 'focus', 'white_balance', 'other'])
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: p.line)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('guide.setting.$k'),
                            style: font(12.5, color: p.muted),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            (value['settings'] as Map)[k] as String,
                            style: font(15, height: 1.4, color: p.ink),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    t('guide.tips'),
                    style: font(17, weight: 600, color: p.ink),
                  ),
                  for (final x in (value['tips'] as List).cast<String>())
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check, size: 18, color: p.accent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              x,
                              style: font(15, height: 1.45, color: p.ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    t('guide.mistakes'),
                    style: font(17, weight: 600, color: p.ink),
                  ),
                  for (final x in (value['mistakes'] as List).cast<String>())
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.close, size: 18, color: p.danger),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              x,
                              style: font(15, height: 1.45, color: p.ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (value['planner'] == true) ...[
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => context.push('/planner'),
                      icon: const Icon(Icons.nightlight_outlined),
                      label: Text(t('guide.open_planner')),
                    ),
                  ],
                ],
              ),
            ),
            if (value['calculator'] != null) ...[
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: CalculatorCard(id: value['calculator'] as String),
              ),
            ],
          ],
        ),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(_guideProvider(slug)),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key, this.focus});
  final String? focus;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final order = ['npf', 'dof', 'nd']
      ..sort((a, b) => (a == focus ? -1 : 0) - (b == focus ? -1 : 0));
    return Scaffold(
      appBar: AppBar(title: Text(t('tools.title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          for (final id in order)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: CalculatorCard(id: id),
            ),
        ],
      ),
    );
  }
}

/// Hesaplayıcı kartı (npf | dof | nd). Sonuçlar vizör şeridi tarzında.
class CalculatorCard extends StatefulWidget {
  const CalculatorCard({super.key, required this.id});
  final String id;

  @override
  State<CalculatorCard> createState() => _CalculatorCardState();
}

class _CalculatorCardState extends State<CalculatorCard> {
  String _sensor = 'ff';
  double _mp = 24, _focal = 14, _aperture = 1.8, _distance = 3, _base = 1 / 125;
  int _stops = 10;
  static const _apertures = [
    1.2,
    1.4,
    1.8,
    2.0,
    2.8,
    4.0,
    5.6,
    8.0,
    11.0,
    16.0,
    22.0,
  ];

  @override
  void initState() {
    super.initState();
    if (widget.id == 'dof') {
      _focal = 24;
      _aperture = 8;
    }
  }

  Widget _readout(List<(String, String, bool)> items) {
    return Container(
      color: Colors.black,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      child: Wrap(
        spacing: 24,
        runSpacing: 12,
        children: [
          for (final (value, label, strong) in items)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: font(
                    strong ? 28 : 20,
                    weight: 600,
                    height: 1,
                    color: const Color(0xFFF2F2EE),
                  ),
                ),
                const SizedBox(height: 4),
                Text(label, style: font(12, color: const Color(0xFF8D8D88))),
              ],
            ),
        ],
      ),
    );
  }

  Widget _dropdown<T>(
    String label,
    T value,
    List<(T, String)> items,
    ValueChanged<T> onChanged,
  ) => DropdownButtonFormField<T>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label, isDense: true),
    items: [
      for (final (v, l) in items) DropdownMenuItem(value: v, child: Text(l)),
    ],
    onChanged: (v) {
      if (v != null) setState(() => onChanged(v));
    },
  );

  Widget _number(String label, double value, ValueChanged<double> onChanged) =>
      TextFormField(
        initialValue: value % 1 == 0
            ? value.toInt().toString()
            : value.toString(),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, isDense: true),
        onChanged: (v) {
          final n = double.tryParse(v.replaceAll(',', '.'));
          if (n != null && n > 0) setState(() => onChanged(n));
        },
      );

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final locale = t.locale.languageCode;
    final sensorItems = [
      for (final s in sensors.keys)
        (s, '${t('tools.sensor.$s')} (×${cropFactor(s).toStringAsFixed(2)})'),
    ];
    final apertureItems = [
      for (final a in _apertures) (a, 'f/${a % 1 == 0 ? a.toInt() : a}'),
    ];

    final (title, lead, body) = switch (widget.id) {
      'npf' => (
        t('tools.npf_title'),
        t('tools.npf_lead'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dropdown(
              t('tools.sensor_label'),
              _sensor,
              sensorItems,
              (v) => _sensor = v,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _number(t('tools.megapixels'), _mp, (v) => _mp = v),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _number(t('tools.focal'), _focal, (v) => _focal = v),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _dropdown(
              t('tools.aperture'),
              _aperture,
              apertureItems,
              (v) => _aperture = v,
            ),
            _readout([
              (
                formatShutter(
                  npfSeconds(_sensor, _mp, _focal, _aperture),
                  locale,
                ),
                t('tools.npf_result'),
                true,
              ),
              (
                formatShutter(
                  npfSeconds(_sensor, _mp, _focal, _aperture, -29.0078),
                  locale,
                ),
                t('tools.npf_core'),
                false,
              ),
              (
                formatShutter(rule500Seconds(_sensor, _focal), locale),
                t('tools.rule500'),
                false,
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              t('tools.npf_note', {
                'pitch': pixelPitch(_sensor, _mp).toStringAsFixed(1),
              }),
              style: font(12.5, height: 1.4, color: p.muted),
            ),
          ],
        ),
      ),
      'dof' => (
        t('tools.dof_title'),
        t('tools.dof_lead'),
        Builder(
          builder: (_) {
            final r = depthOfField(_sensor, _focal, _aperture, _distance);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _dropdown(
                  t('tools.sensor_label'),
                  _sensor,
                  sensorItems,
                  (v) => _sensor = v,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _number(
                        t('tools.focal'),
                        _focal,
                        (v) => _focal = v,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _number(
                        t('tools.distance'),
                        _distance,
                        (v) => _distance = v,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _dropdown(
                  t('tools.aperture'),
                  _aperture,
                  apertureItems,
                  (v) => _aperture = v,
                ),
                _readout([
                  (
                    formatDistance(r.hyperfocal, locale),
                    t('tools.hyperfocal'),
                    true,
                  ),
                  (formatDistance(r.near, locale), t('tools.near'), false),
                  (formatDistance(r.far, locale), t('tools.far'), false),
                ]),
                const SizedBox(height: 8),
                Text(
                  t('tools.dof_hyperfocal_tip', {
                    'h': formatDistance(r.hyperfocal, locale),
                    'half': formatDistance(r.hyperfocal / 2, locale),
                  }),
                  style: font(12.5, height: 1.4, color: p.muted),
                ),
              ],
            );
          },
        ),
      ),
      _ => (
        t('tools.nd_title'),
        t('tools.nd_lead'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dropdown(t('tools.nd_base'), _base, [
              for (final s in shutterSpeeds) (s, formatShutter(s, locale)),
            ], (v) => _base = v),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in ndFilters)
                  ChoiceChip(
                    label: Text(
                      '${f.label} · ${t('tools.stops', {'n': f.stops})}',
                    ),
                    selected: _stops == f.stops,
                    onSelected: (_) => setState(() => _stops = f.stops),
                  ),
              ],
            ),
            _readout([
              (
                formatShutter(ndSeconds(_base, _stops), locale),
                t('tools.nd_result'),
                true,
              ),
            ]),
            if (ndSeconds(_base, _stops) > 30) ...[
              const SizedBox(height: 8),
              Text(t('tools.nd_bulb'), style: font(12.5, color: p.muted)),
            ],
          ],
        ),
      ),
    };

    return Container(
      color: p.mat,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: font(18, weight: 600, color: p.ink)),
          const SizedBox(height: 4),
          Text(lead, style: font(13.5, height: 1.4, color: p.muted)),
          const SizedBox(height: 14),
          body,
        ],
      ),
    );
  }
}
