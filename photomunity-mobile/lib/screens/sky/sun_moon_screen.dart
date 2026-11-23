import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/astro.dart';
import '../../core/config.dart';
import '../../core/l10n.dart';
import '../../core/sky.dart';
import '../../core/theme.dart';
import 'sky_common.dart';

const _sunriseColor = Color(0xFFF5B82E);
const _sunsetColor = Color(0xFFF07F1F);
const _moonriseColor = Color(0xFF7F96FF);
const _moonsetColor = Color(0xFF4A58B8);
const _blue = Color(0xFF5B6BD6);
const _gold = Color(0xFFFFB35A);
const _night = Color(0xFF1C2250);
const _day = Color(0xFFCFE3FF);

/// Güneş & Ay planlayıcı: haritada seçilen noktadan doğuş/batış yönleri, altın ve mavi saat.
class SunMoonPlannerScreen extends ConsumerStatefulWidget {
  const SunMoonPlannerScreen({super.key, this.date});
  final DateTime? date;

  @override
  ConsumerState<SunMoonPlannerScreen> createState() => _SunMoonPlannerScreenState();
}

class _SunMoonPlannerScreenState extends ConsumerState<SunMoonPlannerScreen> {
  late DateTime _date = DateUtils.dateOnly(widget.date ?? DateTime.now());
  final _map = MapController();

  /// Başlangıç noktasından azimut yönünde [km] uzaklıktaki nokta (büyük daire).
  LatLng _dest(LatLng from, double az, double km) {
    const r = 6371.0;
    final d = km / r;
    final b = az * math.pi / 180;
    final la1 = from.latitude * math.pi / 180, lo1 = from.longitude * math.pi / 180;
    final la2 = math.asin(math.sin(la1) * math.cos(d) + math.cos(la1) * math.sin(d) * math.cos(b));
    final lo2 = lo1 + math.atan2(math.sin(b) * math.sin(d) * math.cos(la1), math.cos(d) - math.sin(la1) * math.sin(la2));
    return LatLng(la2 * 180 / math.pi, lo2 * 180 / math.pi);
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final locale = t.locale.languageCode;
    final place = ref.watch(skyPlaceProvider);
    final here = LatLng(place.lat, place.lng);
    final day = planDay(_date, place.lat, place.lng);
    final hm = DateFormat.Hm(locale);
    final dark = Theme.of(context).brightness == Brightness.dark;
    String span(Span? s) => s == null ? '—' : '${hm.format(s.start)} – ${hm.format(s.end)}';

    final lines = <(SkyEvent?, Color, String, bool)>[
      (day.sunrise, _sunriseColor, t('sky.sunrise'), false),
      (day.sunset, _sunsetColor, t('sky.sunset'), false),
      (day.moonrise, _moonriseColor, t('sky.moonrise'), true),
      (day.moonset, _moonsetColor, t('sky.moonset'), true),
    ];

    Widget legend((SkyEvent?, Color, String, bool) l) {
      final (e, c, label, _) = l;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(width: 18, height: 4, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: font(14.5, color: p.ink))),
            Text(
              e == null ? '—' : '${hm.format(e.t)} · ${e.az.round()}° ${compassPoint(e.az, locale)}',
              style: font(14.5, weight: 700, color: p.ink, tabular: true),
            ),
          ],
        ),
      );
    }

    Widget seg(String label, String value, Color c) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: font(14.5, color: p.ink))),
          Text(value, style: font(14.5, weight: 700, color: p.ink, tabular: true)),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('sky.sun_moon'), style: font(21, weight: 700, color: p.ink)),
            SkyPlaceLine(color: p.inkMuted),
          ],
        ),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 300,
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: here,
                initialZoom: 11,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                onTap: (_, ll) => ref
                    .read(skyPlaceProvider.notifier)
                    .set(ll.latitude, ll.longitude, '${ll.latitude.toStringAsFixed(3)}, ${ll.longitude.toStringAsFixed(3)}'),
              ),
              children: [
                TileLayer(
                  urlTemplate: dark ? AppConfig.mapTilesDark : AppConfig.mapTilesLight,
                  subdomains: const ['a', 'b', 'c', 'd'],
                  retinaMode: RetinaMode.isHighDensity(context),
                  userAgentPackageName: 'app.photomunity.photomunity',
                ),
                PolylineLayer(
                  polylines: [
                    for (final (e, c, _, moon) in lines)
                      if (e != null)
                        Polyline(
                          points: [here, _dest(here, e.az, 12)],
                          color: c,
                          strokeWidth: 4,
                          pattern: moon ? StrokePattern.dashed(segments: const [10, 7]) : const StrokePattern.solid(),
                        ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: here,
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          color: p.accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                      ),
                    ),
                  ],
                ),
                const RichAttributionWidget(attributions: [TextSourceAttribution(AppConfig.mapAttribution)]),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        DateFormat.MMMMEEEEd(locale).format(_date),
                        style: font(18, weight: 700, color: p.ink),
                      ),
                    ),
                    IconButton(
                      tooltip: t('sky.prev_day'),
                      onPressed: () => setState(() => _date = _date.subtract(const Duration(days: 1))),
                      icon: const Icon(LucideIcons.chevronLeft),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _date = DateUtils.dateOnly(DateTime.now())),
                      child: Text(t('sky.today')),
                    ),
                    IconButton(
                      tooltip: t('sky.next_day'),
                      onPressed: () => setState(() => _date = _date.add(const Duration(days: 1))),
                      icon: const Icon(LucideIcons.chevronRight),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _DayBar(day: day),
                const SizedBox(height: 10),
                seg(t('sky.blue_morning'), span(day.blueMorning), _blue),
                seg(t('sky.golden_morning'), span(day.goldenMorning), _gold),
                seg(t('sky.golden_evening'), span(day.goldenEvening), _gold),
                seg(t('sky.blue_evening'), span(day.blueEvening), _blue),
                Divider(color: p.line, height: 24),
                for (final l in lines) legend(l),
                const SizedBox(height: 8),
                Text(t('sky.planner_hint'), style: font(12.5, color: p.inkMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Günün 24 saatlik çubuğu: gece, mavi saat, altın saat, gündüz.
class _DayBar extends StatelessWidget {
  const _DayBar({required this.day});
  final DayPlan day;

  @override
  Widget build(BuildContext context) {
    final start = day.date;
    double f(DateTime? t) => t == null ? 0 : (t.difference(start).inMinutes / 1440).clamp(0.0, 1.0);
    final stops = <(double, double, Color)>[
      if (day.blueMorning != null) (f(day.blueMorning!.start), f(day.blueMorning!.end), _blue),
      if (day.goldenMorning != null) (f(day.goldenMorning!.start), f(day.goldenMorning!.end), _gold),
      if (day.goldenMorning != null && day.goldenEvening != null)
        (f(day.goldenMorning!.end), f(day.goldenEvening!.start), _day),
      if (day.goldenEvening != null) (f(day.goldenEvening!.start), f(day.goldenEvening!.end), _gold),
      if (day.blueEvening != null) (f(day.blueEvening!.start), f(day.blueEvening!.end), _blue),
    ];
    return LayoutBuilder(
      builder: (context, c) => ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 12,
          child: Stack(
            children: [
              Container(color: _night),
              for (final (a, b, color) in stops)
                Positioned(left: a * c.maxWidth, width: (b - a) * c.maxWidth, top: 0, bottom: 0, child: ColoredBox(color: color)),
              // Şu an
              if (DateUtils.isSameDay(start, DateTime.now()))
                Positioned(
                  left: f(DateTime.now()) * c.maxWidth - 1,
                  width: 2,
                  top: 0,
                  bottom: 0,
                  child: const ColoredBox(color: Colors.redAccent),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
