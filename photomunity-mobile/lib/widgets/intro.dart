import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n.dart';
import '../core/push.dart';
import '../core/theme.dart';
import 'design.dart';

/// "Nasıl çalışır" tanıtımları: her modül ilk açılışta bir kez kısa bir sayfa dizisi gösterir;
/// uygulama çubuğundaki "?" düğmesi aynı tanıtımı yeniden açar.
///
/// Kapatmak için: `--dart-define=INTROS=false`. Testlerde depo eklentisi olmadığından tanıtımlar
/// "görülmüş" sayılır; belirli modülleri göstermek için [Intros.debugUnseen] verilir.
const introsEnabled = bool.fromEnvironment('INTROS', defaultValue: true);

class IntroStep {
  const IntroStep(this.icon);
  final IconData icon;
}

class IntroModule {
  const IntroModule(this.colors, this.steps);

  /// Görsel alanın degradesi (uygulama renkleri).
  final List<Color> colors;
  final List<IntroStep> steps;
}

const _accent = [Color(0xFF4D74FF), Color(0xFF1F3BB3)];
const _night = [Color(0xFF2B2370), Color(0xFF0E0C2A)];
const _dusk = [Color(0xFFFF9A5A), Color(0xFFC2410C)];
const _teal = [Color(0xFF1F8A82), Color(0xFF0E3533)];
const _gold = [Color(0xFFF5B83D), Color(0xFFB4690E)];
const _rose = [Color(0xFFE85D8A), Color(0xFF8E1F4B)];

/// Modül kayıt defteri. Metinler l10n'da: `intro.<modül>.title`, `intro.<modül>.<i>.t` / `.b`.
const introModules = <String, IntroModule>{
  'feed': IntroModule(_accent, [
    IntroStep(LucideIcons.users),
    IntroStep(LucideIcons.heart),
    IntroStep(LucideIcons.imagePlus),
  ]),
  'explore': IntroModule(_accent, [
    IntroStep(LucideIcons.compass),
    IntroStep(LucideIcons.messageSquareText),
    IntroStep(LucideIcons.trophy),
  ]),
  'map': IntroModule(_teal, [
    IntroStep(LucideIcons.map),
    IntroStep(LucideIcons.mapPin),
    IntroStep(LucideIcons.shieldCheck),
  ]),
  'communities': IntroModule(_accent, [
    IntroStep(LucideIcons.usersRound),
    IntroStep(LucideIcons.newspaper),
    IntroStep(LucideIcons.calendarDays),
    IntroStep(LucideIcons.trophy),
  ]),
  'contests': IntroModule(_gold, [
    IntroStep(LucideIcons.imagePlus),
    IntroStep(LucideIcons.star),
    IntroStep(LucideIcons.medal),
    IntroStep(LucideIcons.eyeOff),
  ]),
  'themes': IntroModule(_gold, [
    IntroStep(LucideIcons.image),
    IntroStep(LucideIcons.heart),
    IntroStep(LucideIcons.award),
  ]),
  'critique': IntroModule(_rose, [
    IntroStep(LucideIcons.messageSquarePlus),
    IntroStep(LucideIcons.listChecks),
    IntroStep(LucideIcons.thumbsUp),
  ]),
  'collections': IntroModule(_accent, [
    IntroStep(LucideIcons.layers),
    IntroStep(LucideIcons.listOrdered),
    IntroStep(LucideIcons.share2),
  ]),
  'events': IntroModule(_teal, [
    IntroStep(LucideIcons.footprints),
    IntroStep(LucideIcons.users),
    IntroStep(LucideIcons.moon),
  ]),
  'sky': IntroModule(_night, [
    IntroStep(LucideIcons.gauge),
    IntroStep(LucideIcons.cloudSun),
    IntroStep(LucideIcons.calendarDays),
  ]),
  'night_ar': IntroModule(_night, [
    IntroStep(LucideIcons.smartphone),
    IntroStep(LucideIcons.moon),
    IntroStep(LucideIcons.clock),
    IntroStep(LucideIcons.layers),
  ]),
  'moon': IntroModule(_night, [
    IntroStep(LucideIcons.moon),
    IntroStep(LucideIcons.calendarDays),
    IntroStep(LucideIcons.sparkles),
  ]),
  'sun_moon': IntroModule(_dusk, [
    IntroStep(LucideIcons.sunset),
    IntroStep(LucideIcons.compass),
    IntroStep(LucideIcons.calendarClock),
  ]),
  'night_tools': IntroModule(_teal, [
    IntroStep(LucideIcons.orbit),
    IntroStep(LucideIcons.timer),
    IntroStep(LucideIcons.sparkles),
  ]),
  'plans': IntroModule(_night, [
    IntroStep(LucideIcons.calendarClock),
    IntroStep(LucideIcons.cloudRain),
    IntroStep(LucideIcons.users),
  ]),
  'dark_spots': IntroModule(_night, [
    IntroStep(LucideIcons.lightbulb),
    IntroStep(LucideIcons.mapPin),
    IntroStep(LucideIcons.calendarClock),
  ]),
  'messages': IntroModule(_accent, [
    IntroStep(LucideIcons.inbox),
    IntroStep(LucideIcons.send),
    IntroStep(LucideIcons.image),
  ]),
  'gear': IntroModule(_teal, [
    IntroStep(LucideIcons.camera),
    IntroStep(LucideIcons.aperture),
    IntroStep(LucideIcons.tag),
  ]),
  'upload': IntroModule(_accent, [
    IntroStep(LucideIcons.image),
    IntroStep(LucideIcons.mapPin),
    IntroStep(LucideIcons.copyright),
    IntroStep(LucideIcons.messageSquarePlus),
  ]),
  'profile': IntroModule(_rose, [
    IntroStep(LucideIcons.layers),
    IntroStep(LucideIcons.award),
    IntroStep(LucideIcons.share2),
  ]),
};

class Intros {
  Intros._();

  static const _key = 'pm_intros_seen';
  static FlutterSecureStorage storage = const FlutterSecureStorage();
  static Set<String>? _seen;
  static bool _showing = false;

  /// Testler / ekran görüntüleri: verilirse yalnızca bu modüller "görülmemiş" sayılır (depo okunmaz).
  static Set<String>? debugUnseen;

  static Future<Set<String>> _load() async {
    if (_seen != null) return _seen!;
    final forced = debugUnseen;
    if (forced != null) return _seen = introModules.keys.toSet().difference(forced);
    try {
      final v = await storage.read(key: _key);
      _seen = {...?v?.split(',').where((x) => x.isNotEmpty)};
    } catch (_) {
      // Depo yoksa (test ortamı) tanıtım gösterilmez
      _seen = introModules.keys.toSet();
    }
    return _seen!;
  }

  static Future<void> _markSeen(String module) async {
    final seen = await _load();
    if (!seen.add(module) || debugUnseen != null) return;
    try {
      await storage.write(key: _key, value: seen.join(','));
    } catch (_) {}
  }

  /// İlk açılışta gösterir. Ekran en üstte değilse (üstünde başka sayfa ya da pencere varsa) atlanır.
  static Future<void> maybeShow(BuildContext context, String module) async {
    if (!introsEnabled || _showing || !introModules.containsKey(module)) return;
    final seen = await _load();
    if (seen.contains(module)) return;
    // Bildirim izni penceresi açıksa kapanmasını bekle
    await PushService.permissionPrompt.timeout(const Duration(minutes: 2), onTimeout: () {});
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!context.mounted || _showing) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    await show(context, module);
  }

  /// "?" düğmesi: her zaman gösterir.
  static Future<void> show(BuildContext context, String module) async {
    final m = introModules[module];
    if (m == null || _showing) return;
    _showing = true;
    unawaited(_markSeen(module));
    try {
      await showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: context.palette.bg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (_) => IntroPager(module: module, data: m),
      );
    } finally {
      _showing = false;
    }
  }
}

/// Ekranı sarar: ilk açılışta modülün tanıtımını gösterir.
class ModuleIntro extends StatefulWidget {
  const ModuleIntro({super.key, required this.module, required this.child});
  final String module;
  final Widget child;

  @override
  State<ModuleIntro> createState() => _ModuleIntroState();
}

class _ModuleIntroState extends State<ModuleIntro> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Intros.maybeShow(context, widget.module);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Uygulama çubuğundaki "Nasıl çalışır" düğmesi.
class IntroButton extends StatelessWidget {
  const IntroButton({super.key, required this.module, this.size = 40, this.color, this.scrim = false});
  final String module;
  final double size;
  final Color? color;
  final bool scrim;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    return RoundIconButton(
      icon: LucideIcons.circleQuestionMark,
      label: t('intro.how_it_works'),
      size: size,
      scrim: scrim,
      color: color ?? (scrim ? null : context.palette.surface),
      onPressed: () => Intros.show(context, module),
    );
  }
}

/// Sayfalı tanıtım: görsel, başlık, açıklama, sayfa noktaları; "Geç" ve "İleri / Başla".
class IntroPager extends StatefulWidget {
  const IntroPager({super.key, required this.module, required this.data});
  final String module;
  final IntroModule data;

  @override
  State<IntroPager> createState() => _IntroPagerState();
}

class _IntroPagerState extends State<IntroPager> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_index >= widget.data.steps.length - 1) {
      Navigator.of(context).pop();
    } else {
      _pages.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final steps = widget.data.steps;
    final last = _index == steps.length - 1;
    final height = (MediaQuery.sizeOf(context).height * 0.66).clamp(460.0, 600.0);
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${t('intro.how_it_works').toUpperCase()} · ${t('intro.${widget.module}.title')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: font(12, weight: 700, color: p.inkMuted, spacing: 0.6),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(t('intro.skip'), style: font(14, weight: 600, color: p.inkMuted)),
                ),
              ],
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: steps.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => _IntroPage(
                icon: steps[i].icon,
                colors: widget.data.colors,
                index: i,
                title: t('intro.${widget.module}.$i.t'),
                body: t('intro.${widget.module}.$i.b'),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 16 + MediaQuery.paddingOf(context).bottom),
            child: Row(
              children: [
                Semantics(
                  label: '${_index + 1} / ${steps.length}',
                  child: Row(
                    children: [
                      for (var i = 0; i < steps.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          margin: const EdgeInsets.only(right: 6),
                          width: i == _index ? 22 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _index ? p.accent : p.line,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                    ],
                  ),
                ),
                const Spacer(),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 26),
                      textStyle: font(15, weight: 700),
                    ),
                    onPressed: _next,
                    child: Text(t(last ? 'intro.start' : 'intro.next')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroPage extends StatelessWidget {
  const _IntroPage({required this.icon, required this.colors, required this.index, required this.title, required this.body});
  final IconData icon;
  final List<Color> colors;
  final int index;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 176,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
            ),
            child: Stack(
              children: [
                // Hafif halkalar: her sayfada biraz kayar
                Positioned(
                  right: -40 + index * 18.0,
                  top: -50,
                  child: _Ring(size: 180, color: Colors.white.withValues(alpha: 0.10)),
                ),
                Positioned(
                  left: -30 - index * 10.0,
                  bottom: -60,
                  child: _Ring(size: 150, color: Colors.white.withValues(alpha: 0.07)),
                ),
                Center(
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.28), width: 1.5),
                    ),
                    child: Icon(icon, size: 44, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(title, style: font(22, weight: 700, color: p.ink)),
          const SizedBox(height: 8),
          Text(body, style: font(15.5, color: p.inkMuted, height: 1.45)),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 18)),
  );
}
