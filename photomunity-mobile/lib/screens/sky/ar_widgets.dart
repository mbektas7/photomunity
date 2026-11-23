import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/astro.dart';
import '../../core/l10n.dart';
import '../../core/sky.dart';
import '../../core/theme.dart';

/// Night AR'ın yarı saydam kapsülü.
class ArGlass extends StatelessWidget {
  const ArGlass({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(999)),
    child: child,
  );
}

class ArGlassButton extends StatelessWidget {
  const ArGlassButton({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Tooltip(
      message: label,
      child: Material(
        color: Colors.black.withValues(alpha: 0.5),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 44, height: 44, child: Icon(icon, color: Colors.white, size: 20)),
        ),
      ),
    ),
  );
}

/// Zaman paneli: seçili saat, "Şimdi", gece çubuğu (alacakaranlık + çekim penceresi) ve kaydırıcı.
class ArTimePanel extends StatelessWidget {
  const ArTimePanel({
    super.key,
    required this.plan,
    required this.time,
    required this.locale,
    required this.onChanged,
    required this.onNow,
  });
  final NightPlan plan;
  final DateTime time;
  final String locale;
  final ValueChanged<DateTime> onChanged;
  final VoidCallback onNow;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final hm = DateFormat.Hm(locale);
    final start = plan.samples.first.t.toDouble(), end = plan.samples.last.t.toDouble();
    double f(DateTime? d) => d == null ? 0 : ((d.millisecondsSinceEpoch - start) / (end - start)).clamp(0.0, 1.0);
    final transit = nightCoreHighest(plan);
    final isTransit = transit != null && time.difference(transit.t).inMinutes.abs() <= 10;
    final inWindow = plan.bestWindows.any((w) => !time.isBefore(w.start) && !time.isAfter(w.end));
    final caption = isTransit
        ? t('ar.core_highest')
        : inWindow
        ? t('ar.in_window')
        : t('ar.out_window');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(hm.format(time), style: font(22, weight: 700, color: Colors.white, tabular: true)),
                  Text(
                    '${DateFormat.MMMEd(locale).format(time)} · $caption',
                    style: font(12.5, color: inWindow || isTransit ? const Color(0xFF7FE0C0) : Colors.white70),
                  ),
                ],
              ),
            ),
            if (transit != null)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: () => onChanged(transit.t),
                child: Text(t('ar.jump_core')),
              ),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.14),
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: onNow,
              child: Text(t('ar.now')),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            Widget seg(DateTime? a, DateTime? b, Color color) => Positioned(
              left: f(a) * w,
              width: ((f(b) - f(a)).clamp(0.0, 1.0)) * w,
              top: 0,
              bottom: 0,
              child: ColoredBox(color: color),
            );
            return SizedBox(
              height: 6,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Stack(
                  children: [
                    const Positioned.fill(child: ColoredBox(color: Color(0xFFFF9A5A))),
                    if (plan.sunset != null && plan.sunrise != null) seg(plan.sunset, plan.sunrise, const Color(0xFF5B6BD6)),
                    if (plan.duskAstro != null && plan.dawnAstro != null)
                      seg(plan.duskAstro, plan.dawnAstro, const Color(0xFF1C2250)),
                    for (final win in plan.bestWindows) seg(win.start, win.end, const Color(0xFF7FE0C0)),
                  ],
                ),
              ),
            );
          },
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            activeTrackColor: Colors.white24,
            inactiveTrackColor: Colors.white10,
            thumbColor: Colors.white,
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Slider(
            value: time.millisecondsSinceEpoch.toDouble().clamp(start, end),
            min: start,
            max: end,
            onChanged: (v) => onChanged(DateTime.fromMillisecondsSinceEpoch(v.round())),
          ),
        ),
        Row(
          children: [
            Text(
              '${t('sky.sunset')} ${plan.sunset == null ? '—' : hm.format(plan.sunset!)}',
              style: font(11, color: Colors.white60),
            ),
            const Spacer(),
            Text(t('ar.window_legend'), style: font(11, color: const Color(0xFF7FE0C0))),
            const Spacer(),
            Text(
              '${t('sky.sunrise')} ${plan.sunrise == null ? '—' : hm.format(plan.sunrise!)}',
              style: font(11, color: Colors.white60),
            ),
          ],
        ),
      ],
    );
  }
}
