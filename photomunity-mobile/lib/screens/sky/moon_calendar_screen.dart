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

/// Ay takvimi: her günün Ay şekli ve yüzdesi, karanlık geceler vurgulu; güne dokununca detay.
class MoonCalendarScreen extends ConsumerStatefulWidget {
  const MoonCalendarScreen({super.key});

  @override
  ConsumerState<MoonCalendarScreen> createState() => _MoonCalendarScreenState();
}

class _MoonCalendarScreenState extends ConsumerState<MoonCalendarScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _selected = DateUtils.dateOnly(DateTime.now());

  void _shift(int by) => setState(() {
    _month = DateTime(_month.year, _month.month + by);
    final today = DateUtils.dateOnly(DateTime.now());
    _selected = today.year == _month.year && today.month == _month.month ? today : _month;
  });

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final locale = t.locale.languageCode;
    final days = moonMonth(_month.year, _month.month);
    final lead = DateTime(_month.year, _month.month).weekday - 1; // pazartesi başlangıçlı
    final today = DateUtils.dateOnly(DateTime.now());
    final weekdays = List.generate(
      7,
      (i) => DateFormat.E(locale).format(DateTime(2024, 1, 1 + i)), // 1 Ocak 2024 pazartesi
    );
    final sel = days.firstWhere((d) => d.date == _selected, orElse: () => days.first);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('sky.moon_calendar'), style: font(21, weight: 700, color: p.ink)),
            SkyPlaceLine(color: p.inkMuted),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: t('sky.prev_month'),
                onPressed: () => _shift(-1),
                icon: const Icon(LucideIcons.chevronLeft),
              ),
              Expanded(
                child: Text(
                  DateFormat.yMMMM(locale).format(_month),
                  textAlign: TextAlign.center,
                  style: font(18, weight: 700, color: p.ink),
                ),
              ),
              IconButton.filledTonal(
                tooltip: t('sky.next_month'),
                onPressed: () => _shift(1),
                icon: const Icon(LucideIcons.chevronRight),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(Radii.card)),
            child: Column(
              children: [
                Row(
                  children: [
                    for (final w in weekdays)
                      Expanded(
                        child: Text(
                          w,
                          textAlign: TextAlign.center,
                          style: font(11.5, weight: 700, color: p.inkSubtle),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 0.62,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                  children: [
                    for (var i = 0; i < lead; i++) const SizedBox.shrink(),
                    for (final d in days)
                      _DayCell(
                        day: d,
                        selected: d.date == _selected,
                        today: d.date == today,
                        onTap: () {
                          setState(() => _selected = d.date);
                          _openDay(d);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(color: p.accentTint, borderRadius: BorderRadius.circular(5)),
                ),
                const SizedBox(width: 8),
                Text(t('sky.dark_night_legend'), style: font(12.5, color: p.inkMuted)),
              ],
            ),
          ),
          Material(
            color: p.surface,
            borderRadius: BorderRadius.circular(Radii.card),
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.card),
              onTap: () => _openDay(sel),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    MoonGlyph(phase: sel.phase, fraction: sel.fraction, size: 54),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${DateFormat.MMMd(locale).format(sel.date)} · ${t('planner.phase.${moonPhaseKey(sel.phase)}')}',
                            style: font(16, weight: 700, color: p.ink),
                          ),
                          Text(
                            t('sky.illum_age', {
                              'pct': (sel.fraction * 100).round(),
                              'age': moonAgeDays(sel.phase).toStringAsFixed(1),
                            }),
                            style: font(13, color: p.inkMuted),
                          ),
                          if (sel.dark)
                            Text(
                              t('sky.dark_night'),
                              style: font(13, weight: 600, color: const Color(0xFF1A7F45)),
                            ),
                        ],
                      ),
                    ),
                    Icon(LucideIcons.chevronRight, color: p.inkSubtle),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openDay(MoonDay d) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => MoonDaySheet(date: d.date),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.selected, required this.today, required this.onTap});
  final MoonDay day;
  final bool selected, today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: day.dark && !selected ? p.accentTint : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: selected ? BorderSide(color: p.accent, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.date.day}',
              style: font(
                12.5,
                weight: today || selected ? 800 : 600,
                color: today || selected ? p.accentText : p.ink,
              ),
            ),
            const SizedBox(height: 4),
            MoonGlyph(phase: day.phase, fraction: day.fraction, size: 26),
            const SizedBox(height: 3),
            Text('%${(day.fraction * 100).round()}', style: font(10, color: p.inkMuted)),
          ],
        ),
      ),
    );
  }
}

/// Gün detayı: evre, Ay doğuş/batış ve yönleri, en yüksek an, Güneş, karanlık, sonraki yeni ay.
class MoonDaySheet extends ConsumerWidget {
  const MoonDaySheet({super.key, required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    final locale = t.locale.languageCode;
    final place = ref.watch(skyPlaceProvider);
    final day = planDay(date, place.lat, place.lng);
    final night = planNight(date, place.lat, place.lng);
    final illum = moonIllumination(DateTime(date.year, date.month, date.day, 22).millisecondsSinceEpoch);
    final hm = DateFormat.Hm(locale);
    final nextNew = nextPhase(date);
    final nextFull = nextPhase(date, full: true);
    String ev(SkyEvent? e) => e == null ? '—' : '${hm.format(e.t)} · ${e.az.round()}° ${compassPoint(e.az, locale)}';

    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(k, style: font(14.5, color: p.inkMuted))),
          Text(v, style: font(14.5, weight: 700, color: p.ink, tabular: true)),
        ],
      ),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                MoonGlyph(phase: illum.phase, fraction: illum.fraction, size: 84),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat.MMMMEEEEd(locale).format(date).toUpperCase(),
                        style: font(12.5, weight: 700, color: p.inkMuted),
                      ),
                      Text(
                        t('planner.phase.${moonPhaseKey(illum.phase)}'),
                        style: font(23, weight: 700, spacing: -0.4, color: p.ink),
                      ),
                      Text(
                        t('sky.illum_age', {
                          'pct': (illum.fraction * 100).round(),
                          'age': moonAgeDays(illum.phase).toStringAsFixed(1),
                        }),
                        style: font(14, color: p.inkMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Divider(color: p.line),
            row(t('sky.moonrise'), ev(day.moonrise)),
            row(t('sky.moonset'), ev(day.moonset)),
            row(
              t('sky.moon_highest'),
              day.moonTransit == null ? '—' : '${hm.format(day.moonTransit!.t)} · ${day.moonTransit!.alt.round()}°',
            ),
            row(
              t('sky.sunset_sunrise'),
              '${day.sunset == null ? '—' : hm.format(day.sunset!.t)} / ${night.sunrise == null ? '—' : hm.format(night.sunrise!)}',
            ),
            row(
              t('sky.astro_dark'),
              night.duskAstro == null || night.dawnAstro == null
                  ? '—'
                  : '${hm.format(night.duskAstro!)} – ${hm.format(night.dawnAstro!)}',
            ),
            row(
              t('sky.next_new_full'),
              '${DateFormat.MMMd(locale).format(nextNew)} / ${DateFormat.MMMd(locale).format(nextFull)}',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    onPressed: () {
                      Navigator.pop(context);
                      context.push('/sky/ar?date=${date.millisecondsSinceEpoch}');
                    },
                    child: Text(t('sky.open_in_ar')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    onPressed: () {
                      Navigator.pop(context);
                      context.push('/sky/planner?date=${date.millisecondsSinceEpoch}');
                    },
                    child: Text(t('sky.sun_moon')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
