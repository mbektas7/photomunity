import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/astro.dart';
import '../core/l10n.dart';
import '../core/models.dart';
import '../core/sky.dart';
import '../core/theme.dart';
import '../screens/sky/sky_common.dart';
import '../state/providers.dart';

final _cache = <String, ({RedoTarget target, List<RedoMatch> matches})>{};

/// "Bu kareyi tekrar çek": çekim anındaki Güneş / Samanyolu çekirdeği konumu ve 12 ay içinde benzer anlar.
/// Yalnızca sahibi konum eklediyse ve EXIF'te çekim zamanı varsa görünür.
class RedoCard extends ConsumerWidget {
  const RedoCard({super.key, required this.photo});
  final PhotoDetail photo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = photo.location;
    final taken = photo.exif?.takenAt;
    if (loc == null || taken == null) return const SizedBox.shrink();
    final t = L10n.of(context);
    final locale = t.locale.languageCode;

    // EXIF saati kameranın yerel saati (saat dilimi yok): yerin UTC farkı Open-Meteo'dan, yoksa cihazınki.
    final forecast = ref.watch(forecastProvider((loc.latitude, loc.longitude)));
    if (forecast.isLoading) return const SizedBox.shrink();
    final offset = forecast.asData?.value?.utcOffset ??
        DateTime(taken.year, taken.month, taken.day, taken.hour, taken.minute).timeZoneOffset;
    final key = '${photo.id}:${offset.inMinutes}';
    final r = _cache[key] ??= () {
      final at = DateTime.utc(taken.year, taken.month, taken.day, taken.hour, taken.minute, taken.second).subtract(offset);
      final target = redoTarget(at.toLocal(), loc.latitude, loc.longitude);
      return (target: target, matches: findRedoDates(target, loc.latitude, loc.longitude, DateTime.now()));
    }();
    final core = r.target.kind == 'core';
    final dir = compassPoint(r.target.az, locale);
    final first = r.matches.firstOrNull;
    final kind = core
        ? 'milkyway'
        : r.target.alt >= -4 && r.target.alt <= 6
        ? 'golden'
        : r.target.alt < -4 && r.target.alt >= -6
        ? 'blue'
        : 'other';

    final buttonText = font(14, weight: 700);
    return Container(
      margin: const EdgeInsets.only(top: Space.s4),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A2050), Color(0xFF0D1130)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.repeat, size: 15, color: Colors.white70),
              const SizedBox(width: 8),
              Text(t('redo.title').toUpperCase(), style: font(12, weight: 700, spacing: 0.3, color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              style: font(15, height: 1.4, color: Colors.white),
              children: [
                TextSpan(text: t(core ? 'redo.core_was' : 'redo.sun_was')),
                TextSpan(
                  text: ' ${r.target.az.round()}° $dir, ${r.target.alt.round()}° ',
                  style: font(15, weight: 700, height: 1.4, color: Colors.white),
                ),
                TextSpan(text: t(core ? 'redo.core_tail' : 'redo.sun_tail')),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (r.matches.isEmpty)
            Text(t('redo.none'), style: font(13.5, color: Colors.white70))
          else
            Row(
              children: [
                for (final (i, m) in r.matches.indexed) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        children: [
                          Text(DateFormat.MMMd(locale).format(m.t), style: font(12, color: Colors.white70)),
                          Text(DateFormat.Hm(locale).format(m.t), style: font(14, weight: 700, color: Colors.white, tabular: true)),
                          Text(
                            core ? t('redo.moon', {'pct': (m.moon * 100).round()}) : '${m.az.round()}° · ${m.alt.round()}°',
                            style: font(11, color: const Color(0xFF7FE0C0)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF14161B),
                      shape: const StadiumBorder(),
                      textStyle: buttonText,
                    ),
                    onPressed: () => context.push(Uri(path: '/sky/plans/new', queryParameters: {
                      'kind': kind,
                      'lat': '${loc.latitude}',
                      'lng': '${loc.longitude}',
                      'name': ?loc.name,
                      if (first != null) 'at': '${first.t.millisecondsSinceEpoch}',
                    }).toString()),
                    child: Text(t('redo.plan'), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.14),
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                      textStyle: buttonText,
                    ),
                    onPressed: () {
                      ref.read(skyPlaceProvider.notifier).set(
                            loc.latitude,
                            loc.longitude,
                            loc.name ?? '${loc.latitude.toStringAsFixed(3)}, ${loc.longitude.toStringAsFixed(3)}',
                          );
                      // Night AR gece planını verilen günün öğlesinden başlatır; gece yarısından sonrası önceki gecedir
                      final when = first?.t ?? DateTime.now();
                      final night = when.hour < 12 ? when.subtract(const Duration(days: 1)) : when;
                      context.push('/sky/ar?date=${night.millisecondsSinceEpoch}');
                    },
                    child: Text(t('redo.open_ar'), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
