import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api_client.dart';
import '../../core/astro.dart';
import '../../core/l10n.dart';
import '../../core/models.dart';
import '../../core/sky.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/design.dart';
import '../../widgets/place_picker.dart';
import 'sky_common.dart';

const planKinds = ['milkyway', 'golden', 'blue', 'moonrise', 'meteor', 'other'];

/// Gece çekimleri: elle seçilen sabah saatleri (00:00–11:59) gecenin ertesi gününe düşer.
bool _nightKind(String kind) => kind == 'milkyway' || kind == 'meteor';

IconData planIcon(String kind) => switch (kind) {
  'milkyway' => LucideIcons.sparkles,
  'golden' => LucideIcons.sunset,
  'blue' => LucideIcons.cloudMoon,
  'moonrise' => LucideIcons.moon,
  'meteor' => LucideIcons.zap,
  _ => LucideIcons.camera,
};

List<Color> _planColors(String kind) => switch (kind) {
  'golden' => const [Color(0xFFFFB36B), Color(0xFFC2410C)],
  'blue' => const [Color(0xFF4D6FD6), Color(0xFF1B2A6B)],
  'moonrise' => const [Color(0xFF3A4270), Color(0xFF151933)],
  _ => const [Color(0xFF1A2050), Color(0xFF0B0E24)],
};

/// Yeni çekim planı ya da var olanı düzenleme.
/// Yeni plan için sorgu: kind, lat, lng, name, date (gün, ms), at (tam an, ms).
class PlanEditScreen extends ConsumerStatefulWidget {
  const PlanEditScreen({super.key, this.id, this.kind, this.lat, this.lng, this.name, this.date, this.at});
  final String? id;
  final String? kind;
  final double? lat, lng;
  final String? name;
  final DateTime? date;
  final DateTime? at;

  @override
  ConsumerState<PlanEditScreen> createState() => _PlanEditScreenState();
}

class _PlanEditScreenState extends ConsumerState<PlanEditScreen> {
  String _kind = 'milkyway';
  late double _lat, _lng;
  String? _placeName;
  late DateTime _date;

  /// Elle seçilen saat; null iken plan türüne göre önerilen saat kullanılır.
  TimeOfDay? _time;
  bool _remind = true;
  bool _weather = true;
  bool _shared = false;
  bool _busy = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    final place = ref.read(skyPlaceProvider);
    _kind = planKinds.contains(widget.kind) ? widget.kind! : 'milkyway';
    _lat = widget.lat ?? place.lat;
    _lng = widget.lng ?? place.lng;
    _placeName = widget.name ?? (widget.lat == null && place.label.isNotEmpty ? place.label : null);
    final at = widget.at;
    final base = widget.date ?? at ?? DateTime.now();
    _date = DateUtils.dateOnly(at != null && _nightKind(_kind) && at.hour < 12 ? at.subtract(const Duration(days: 1)) : base);
    if (at != null) _adoptTime(at);
    _ready = widget.id == null;
  }

  /// Verilen an önerilen saatten farklıysa elle seçilmiş sayılır.
  void _adoptTime(DateTime at) {
    final s = suggestedPlanTime(_kind, _date, _lat, _lng);
    _time = s != null && s.t.difference(at).inMinutes.abs() <= 2 ? null : TimeOfDay.fromDateTime(at);
  }

  void _load(ShootPlan plan) {
    _kind = plan.kind;
    _lat = plan.latitude;
    _lng = plan.longitude;
    _placeName = plan.placeName;
    final at = plan.targetAt;
    _date = DateUtils.dateOnly(_nightKind(_kind) && at.hour < 12 ? at.subtract(const Duration(days: 1)) : at);
    _remind = plan.remind;
    _weather = plan.weatherAlert;
    _shared = plan.shared;
    _adoptTime(at);
    _ready = true;
  }

  ({DateTime t, double? az, double? alt})? get _suggested => suggestedPlanTime(_kind, _date, _lat, _lng);

  DateTime? get _target {
    final time = _time;
    if (time == null) return _suggested?.t;
    final next = _nightKind(_kind) && time.hour < 12 ? 1 : 0;
    return DateTime(_date.year, _date.month, _date.day + next, time.hour, time.minute);
  }

  Future<void> _pickPlace() async {
    final picked = await pickPlace(context, lat: _lat, lng: _lng, name: _placeName);
    if (picked == null) return;
    setState(() {
      _lat = picked.lat;
      _lng = picked.lng;
      _placeName = picked.name;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(DateUtils.dateOnly(now)) ? now : _date,
      firstDate: DateUtils.dateOnly(now).subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = L10n.of(context);
    final target = _target;
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? (target == null ? const TimeOfDay(hour: 21, minute: 0) : TimeOfDay.fromDateTime(target)),
      helpText: _suggested == null ? null : t('plan.time_hint'),
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    final t = L10n.of(context);
    final target = _target;
    if (target == null) {
      toast(context, t('plan.pick_time'));
      return;
    }
    setState(() => _busy = true);
    final body = {
      'kind': _kind,
      'latitude': _lat,
      'longitude': _lng,
      'place_name': _placeName,
      'target_at': target.toUtc().toIso8601String(),
      'remind': _remind,
      'weather_alert': _weather,
      'shared': _shared,
    };
    try {
      final api = ref.read(apiProvider);
      widget.id == null ? await api.post<dynamic>('/me/plans', body) : await api.patch<dynamic>('/me/plans/${widget.id}', body);
      ref.invalidate(plansProvider);
      if (widget.id != null) ref.invalidate(planProvider(widget.id!));
      ref.invalidate(sharedPlansProvider);
      if (!mounted) return;
      toast(context, t('plan.saved'));
      context.canPop() ? context.pop() : context.go('/sky/plans');
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmPlanDelete(context);
    if (!ok || !mounted) return;
    try {
      await ref.read(apiProvider).delete<dynamic>('/me/plans/${widget.id}');
      ref.invalidate(plansProvider);
      if (mounted) context.canPop() ? context.pop() : context.go('/sky/plans');
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    if (!_ready) {
      final async = ref.watch(planProvider(widget.id!));
      if (async.hasValue) {
        _load(async.requireValue);
      } else if (async.hasError && const {403, 404}.contains(ApiException.from(async.error!).status)) {
        // Bildirimden gelen, takip ettiğim birinin planı (katıldığım plan hatırlatması gibi)
        return SharedPlanScreen(id: widget.id!);
      } else {
        return Scaffold(
          appBar: pageBar(context, t('plan.edit_title')),
          body: async.hasError
              ? ErrorView(error: async.error!, onRetry: () => ref.invalidate(planProvider(widget.id!)))
              : const Center(child: CircularProgressIndicator()),
        );
      }
    }
    final locale = t.locale.languageCode;
    final hm = DateFormat.Hm(locale);
    final s = _suggested;
    final target = _target;
    final night = planNight(_date, _lat, _lng);
    final moonEvent = night.moonset ?? night.moonrise;
    final moonSub = night.moonset != null
        ? t('sky.moon_sets_at', {'time': hm.format(night.moonset!)})
        : night.moonrise != null
        ? t('plan.moon_rises_at', {'time': hm.format(night.moonrise!)})
        : null;
    final timeSub = _time != null
        ? t('plan.time_manual')
        : s == null
        ? t('plan.no_suggestion_$_kind')
        : switch (_kind) {
            'milkyway' => '${t('sky.core_highest')} · ${s.alt!.round()}° ${compassPoint(s.az!, locale)}',
            'golden' => t('plan.golden_start'),
            'blue' => t('plan.blue_start'),
            'moonrise' => '${t('sky.moonrise')} · ${s.az!.round()}° ${compassPoint(s.az!, locale)}',
            'meteor' => t('plan.dark_middle'),
            _ => '',
          };
    final preview = switch (_kind) {
      'milkyway' when s != null && _time == null =>
        t('plan.preview_core', {'dir': compassPoint(s.az!, locale), 'alt': s.alt!.round()}),
      'golden' || 'blue' when s?.az != null => t('plan.preview_sun', {'az': s!.az!.round(), 'dir': compassPoint(s.az!, locale)}),
      'moonrise' when s != null => t('plan.preview_moon', {'az': s.az!.round(), 'dir': compassPoint(s.az!, locale)}),
      'meteor' => t('plan.preview_meteor'),
      _ => null,
    };

    Widget row(String label, String value, {String? sub, VoidCallback? onTap, bool last = false}) => InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: p.line))),
        child: Row(
          children: [
            Text(label, style: font(14.5, color: p.inkMuted)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(value, textAlign: TextAlign.right, style: font(14.5, weight: 700, color: p.ink, tabular: true)),
                  if (sub != null && sub.isNotEmpty)
                    Text(sub, textAlign: TextAlign.right, style: font(12, color: p.inkMuted)),
                ],
              ),
            ),
            if (onTap != null) ...[const SizedBox(width: 6), Icon(LucideIcons.chevronRight, size: 18, color: p.inkSubtle)],
          ],
        ),
      ),
    );

    return Scaffold(
      appBar: pageBar(
        context,
        t(widget.id == null ? 'plan.new_title' : 'plan.edit_title'),
        actions: [
          if (widget.id != null)
            IconButton(
              tooltip: t('plan.delete'),
              icon: Icon(LucideIcons.trash2, color: p.danger),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 32),
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final k in planKinds)
                      PillChip(
                        label: t('plan.kind_$k'),
                        selected: _kind == k,
                        color: p.surface2,
                        onTap: () => setState(() {
                          _kind = k;
                          if (k != 'other') _time = null;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                row(
                  t('plan.place'),
                  _placeName ?? '${_lat.toStringAsFixed(3)}, ${_lng.toStringAsFixed(3)}',
                  sub: _placeName == null ? null : '${_lat.toStringAsFixed(3)}, ${_lng.toStringAsFixed(3)}',
                  onTap: _pickPlace,
                ),
                row(t('plan.date'), DateFormat.MMMMEEEEd(locale).format(_date), onTap: _pickDate),
                row(t('plan.time'), target == null ? '—' : hm.format(target), sub: timeSub, onTap: _pickTime),
                row(
                  t('plan.moon'),
                  '${t('planner.phase.${moonPhaseKey(night.phase)}')} %${(night.illumination * 100).round()}',
                  sub: moonEvent == null ? null : moonSub,
                  last: true,
                ),
                if (preview != null) ...[
                  const SizedBox(height: 12),
                  _PreviewStrip(kind: _kind, text: '${t('plan.preview')} · $preview'),
                ],
              ],
            ),
          ),
          SectionCard(
            child: Column(
              children: [
                ToggleRow(
                  title: t('plan.remind'),
                  sub: t('plan.remind_sub'),
                  value: _remind,
                  onChanged: (v) => setState(() => _remind = v),
                ),
                ToggleRow(
                  title: t('plan.weather_alert'),
                  sub: t('plan.weather_alert_sub'),
                  value: _weather,
                  onChanged: (v) => setState(() => _weather = v),
                ),
                ToggleRow(
                  title: t('plan.share_friends'),
                  sub: t('plan.share_friends_sub'),
                  value: _shared,
                  onChanged: (v) => setState(() => _shared = v),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: SizedBox(
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(shape: const StadiumBorder(), textStyle: font(15, weight: 700)),
                onPressed: _busy || target == null ? null : _save,
                child: BusyLabel(busy: _busy, label: t('plan.save')),
              ),
            ),
          ),
          if (target == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
              child: Text(t('plan.pick_time'), textAlign: TextAlign.center, style: font(13, color: p.inkMuted)),
            ),
        ],
      ),
    );
  }
}

/// Plan önizleme şeridi: türüne göre gökyüzü rengi, Samanyolu için parlak bant.
class _PreviewStrip extends StatelessWidget {
  const _PreviewStrip({required this.kind, required this.text});
  final String kind;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = _planColors(kind);
    return Container(
      height: 90,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors[1], colors[0], const Color(0xFF0B0B12)],
          stops: const [0, 0.7, 0.7],
        ),
      ),
      child: Stack(
        children: [
          if (kind == 'milkyway')
            Positioned(
              left: 140,
              top: -30,
              child: Transform.rotate(
                angle: 0.45,
                child: Container(
                  width: 70,
                  height: 160,
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(colors: [Color(0x88D9C3FF), Color(0x00D9C3FF)]),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 6,
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: font(11.5, color: Colors.white.withValues(alpha: 0.85)),
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> confirmPlanDelete(BuildContext context) async {
  final t = L10n.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      content: Text(t('plan.delete_confirm')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('common.cancel'))),
        TextButton(onPressed: () => Navigator.pop(c, true), child: Text(t('common.delete'))),
      ],
    ),
  );
  return ok == true;
}

/// Planlarım: yaklaşan / geçmiş / arkadaşların planları; kaydırarak silme, son bulut tahmini.
class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({super.key, this.scope});

  /// upcoming | past | friends
  final String? scope;

  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends ConsumerState<PlansScreen> {
  late String _scope = const {'upcoming', 'past', 'friends'}.contains(widget.scope) ? widget.scope! : 'upcoming';
  final _removed = <String>{};

  Future<void> _remove(ShootPlan plan) async {
    setState(() => _removed.add(plan.id));
    try {
      await ref.read(apiProvider).delete<dynamic>('/me/plans/${plan.id}');
      ref.invalidate(plansProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _removed.remove(plan.id));
      toast(context, errorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final friends = _scope == 'friends';
    final async = ref.watch(plansProvider(friends ? 'upcoming' : _scope));
    final items = async.asData?.value.where((x) => !_removed.contains(x.id)).toList();
    return Scaffold(
      appBar: pageBar(
        context,
        t('plan.my_plans'),
        intro: 'plans',
        actions: [
          RoundIconButton(
            icon: LucideIcons.plus,
            label: t('plan.new_title'),
            size: 40,
            color: p.surface,
            onPressed: () => context.push('/sky/plans/new'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(plansProvider);
          if (_scope == 'friends') await ref.read(sharedPlansProvider.notifier).refresh();
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Wrap(
                spacing: 6,
                children: [
                  PillChip(label: t('plan.upcoming'), selected: _scope == 'upcoming', onTap: () => setState(() => _scope = 'upcoming')),
                  PillChip(label: t('plan.past'), selected: _scope == 'past', onTap: () => setState(() => _scope = 'past')),
                  PillChip(label: t('plan.friends'), selected: friends, onTap: () => setState(() => _scope = 'friends')),
                ],
              ),
            ),
            if (friends)
              const _FriendPlans()
            else if (items == null && async.hasError)
              ErrorView(error: async.error!, onRetry: () => ref.invalidate(plansProvider))
            else if (items == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (items.isEmpty)
              SectionCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(LucideIcons.calendarClock, color: p.ink),
                    const SizedBox(height: 10),
                    Text(t(_scope == 'upcoming' ? 'plan.empty' : 'plan.empty_past'), style: font(15, color: p.inkMuted)),
                    if (_scope == 'upcoming') ...[
                      const SizedBox(height: 14),
                      FilledButton(onPressed: () => context.push('/sky/plans/new'), child: Text(t('plan.new_title'))),
                    ],
                  ],
                ),
              )
            else ...[
              for (final plan in items)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Dismissible(
                    key: ValueKey(plan.id),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) => confirmPlanDelete(context),
                    onDismissed: (_) => _remove(plan),
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 22),
                      decoration: BoxDecoration(color: p.danger, borderRadius: BorderRadius.circular(20)),
                      child: const Icon(LucideIcons.trash2, color: Colors.white),
                    ),
                    child: _PlanTile(plan: plan),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Text(t('plan.swipe_hint'), style: font(12.5, color: p.inkMuted)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.plan});
  final ShootPlan plan;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final locale = t.locale.languageCode;
    final cloud = plan.lastCloudCover;
    final colors = _planColors(plan.kind);
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push('/sky/plans/${plan.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
                ),
                child: Icon(planIcon(plan.kind), color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.title ?? t('plan.kind_${plan.kind}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: font(15.5, weight: 700, color: p.ink),
                    ),
                    Text(
                      '${DateFormat.MMMEd(locale).format(plan.targetAt)} · ${DateFormat.Hm(locale).format(plan.targetAt)}',
                      style: font(13, color: p.ink, tabular: true),
                    ),
                    Text(
                      plan.placeName ?? '${plan.latitude.toStringAsFixed(3)}, ${plan.longitude.toStringAsFixed(3)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: font(12.5, color: p.inkMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (cloud != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: ShapeDecoration(
                        color: cloud > 40 ? const Color(0xFFFFE9E5) : p.surface2,
                        shape: const StadiumBorder(),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.cloud, size: 13, color: cloud > 40 ? const Color(0xFFB42318) : p.inkMuted),
                          const SizedBox(width: 4),
                          Text(
                            '%$cloud',
                            style: font(12, weight: 700, color: cloud > 40 ? const Color(0xFFB42318) : p.inkMuted, tabular: true),
                          ),
                        ],
                      ),
                    ),
                  if (plan.shared && plan.joiners.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Semantics(
                      label: t('plan.joined_count', {'count': plan.joinCount}),
                      child: AvatarStack(users: plan.joiners, size: 20, max: 3),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (plan.shared) ...[
                        Icon(LucideIcons.users, size: 15, color: p.inkMuted),
                        if (plan.joinCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(left: 3),
                            child: Text('${plan.joinCount}', style: font(12, weight: 700, color: p.inkMuted, tabular: true)),
                          ),
                        const SizedBox(width: 6),
                      ],
                      if (plan.remind) Icon(LucideIcons.bellRing, size: 15, color: p.inkMuted),
                      if (plan.weatherAlert) ...[
                        const SizedBox(width: 6),
                        Icon(LucideIcons.cloudRain, size: 15, color: p.inkMuted),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// Katıl / ayrıl; güncel planı döndürür.
Future<SharedPlan> togglePlanJoin(WidgetRef ref, SharedPlan plan) async {
  final api = ref.read(apiProvider);
  late SharedPlan next;
  if (plan.joined) {
    await api.delete<dynamic>('/plans/${plan.id}/join');
    next = SharedPlan.fromJson(await api.get<Map<String, dynamic>>('/plans/${plan.id}'));
  } else {
    next = SharedPlan.fromJson(await api.post<Map<String, dynamic>>('/plans/${plan.id}/join'));
  }
  ref.invalidate(sharedPlanProvider(plan.id));
  return next;
}

/// Takip ettiklerimin paylaştığı yaklaşan planlar.
class _FriendPlans extends ConsumerStatefulWidget {
  const _FriendPlans();

  @override
  ConsumerState<_FriendPlans> createState() => _FriendPlansState();
}

class _FriendPlansState extends ConsumerState<_FriendPlans> {
  final _updated = <String, SharedPlan>{};
  final _busy = <String>{};

  Future<void> _toggle(SharedPlan plan) async {
    final t = L10n.of(context);
    setState(() => _busy.add(plan.id));
    try {
      final next = await togglePlanJoin(ref, plan);
      if (!mounted) return;
      setState(() => _updated[plan.id] = next);
      toast(context, t(next.joined ? 'plan.joined_toast' : 'plan.left_toast'));
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy.remove(plan.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final state = ref.watch(sharedPlansProvider);
    final ctrl = ref.read(sharedPlansProvider.notifier);
    if (state.initialLoading) {
      return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    }
    if (state.items.isEmpty && state.error != null) return ErrorView(error: state.error!, onRetry: ctrl.refresh);
    if (state.items.isEmpty) {
      return SectionCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.usersRound, color: p.ink),
            const SizedBox(height: 10),
            Text(t('plan.friends_empty'), style: font(15, color: p.inkMuted)),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final raw in state.items)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SharedPlanTile(
              plan: _updated[raw.id] ?? raw,
              busy: _busy.contains(raw.id),
              onToggle: () => _toggle(_updated[raw.id] ?? raw),
            ),
          ),
        if (!state.done)
          TextButton(onPressed: state.loading ? null : ctrl.loadMore, child: Text(t('plan.load_more'))),
      ],
    );
  }
}

/// Arkadaşın plan satırı: sahibi, zaman, yer, katılanlar ve katıl / ayrıl.
class SharedPlanTile extends StatelessWidget {
  const SharedPlanTile({super.key, required this.plan, required this.onToggle, this.busy = false});
  final SharedPlan plan;
  final VoidCallback onToggle;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final locale = t.locale.languageCode;
    final colors = _planColors(plan.kind);
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push('/sky/plans/shared/${plan.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
                    ),
                    child: Icon(planIcon(plan.kind), color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan.title ?? t('plan.kind_${plan.kind}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: font(15.5, weight: 700, color: p.ink),
                        ),
                        Text(
                          '${DateFormat.MMMEd(locale).format(plan.targetAt)} · ${DateFormat.Hm(locale).format(plan.targetAt)}',
                          style: font(13, color: p.ink, tabular: true),
                        ),
                        Text(
                          plan.placeName ?? '${plan.latitude.toStringAsFixed(3)}, ${plan.longitude.toStringAsFixed(3)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: font(12.5, color: p.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Avatar(name: plan.owner.displayName, url: plan.owner.avatarUrl, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      plan.joinCount > 0
                          ? '${plan.owner.displayName} · ${t('plan.joined_count', {'count': plan.joinCount})}'
                          : plan.owner.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: font(13, color: p.inkMuted),
                    ),
                  ),
                  if (plan.joiners.isNotEmpty) ...[
                    AvatarStack(users: plan.joiners, size: 20, max: 3),
                    const SizedBox(width: 8),
                  ],
                  SizedBox(
                    height: 36,
                    child: plan.joined
                        ? OutlinedButton(
                            style: OutlinedButton.styleFrom(shape: const StadiumBorder(), foregroundColor: p.ink),
                            onPressed: busy ? null : onToggle,
                            child: BusyLabel(busy: busy, label: t('plan.leave')),
                          )
                        : FilledButton(
                            style: FilledButton.styleFrom(shape: const StadiumBorder()),
                            onPressed: busy ? null : onToggle,
                            child: BusyLabel(busy: busy, label: t('plan.join')),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paylaşılan planın salt okunur ayrıntısı: sahibi, gece bilgisi, katılanlar; katıl ve kısayollar.
class SharedPlanScreen extends ConsumerStatefulWidget {
  const SharedPlanScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<SharedPlanScreen> createState() => _SharedPlanScreenState();
}

class _SharedPlanScreenState extends ConsumerState<SharedPlanScreen> {
  bool _busy = false;

  Future<void> _toggle(SharedPlan plan) async {
    final t = L10n.of(context);
    setState(() => _busy = true);
    try {
      final next = await togglePlanJoin(ref, plan);
      ref.invalidate(sharedPlansProvider);
      if (mounted) toast(context, t(next.joined ? 'plan.joined_toast' : 'plan.left_toast'));
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _usePlace(SharedPlan plan) => ref.read(skyPlaceProvider.notifier).set(
    plan.latitude,
    plan.longitude,
    plan.placeName ?? '${plan.latitude.toStringAsFixed(3)}, ${plan.longitude.toStringAsFixed(3)}',
  );

  /// Gece çekimlerinde gece yarısından sonrası önceki gecedir (Night AR ve planlayıcı öğleden başlar).
  DateTime _night(SharedPlan plan) =>
      plan.targetAt.hour < 12 ? plan.targetAt.subtract(const Duration(days: 1)) : plan.targetAt;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final async = ref.watch(sharedPlanProvider(widget.id));
    final plan = async.asData?.value;
    if (plan == null) {
      return Scaffold(
        appBar: pageBar(context, t('plan.shared_title')),
        body: async.hasError
            ? ErrorView(error: async.error!, onRetry: () => ref.invalidate(sharedPlanProvider(widget.id)))
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final me = ref.watch(authProvider).asData?.value;
    final mine = me != null && me.id == plan.owner.id;
    final locale = t.locale.languageCode;
    final hm = DateFormat.Hm(locale);
    final night = planNight(DateUtils.dateOnly(_night(plan)), plan.latitude, plan.longitude);
    final past = plan.status == 'past';

    Widget row(String label, String value, {String? sub, bool last = false}) => Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: p.line))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: font(14.5, color: p.inkMuted)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value, textAlign: TextAlign.right, style: font(14.5, weight: 700, color: p.ink, tabular: true)),
                if (sub != null && sub.isNotEmpty) Text(sub, textAlign: TextAlign.right, style: font(12, color: p.inkMuted)),
              ],
            ),
          ),
        ],
      ),
    );

    final secondary = FilledButton.styleFrom(
      backgroundColor: p.surface,
      foregroundColor: p.ink,
      minimumSize: const Size.fromHeight(48),
      shape: const StadiumBorder(),
      textStyle: font(14.5, weight: 700),
    );

    return Scaffold(
      appBar: pageBar(context, plan.title ?? t('plan.kind_${plan.kind}'), sub: t('plan.shared_title')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(sharedPlanProvider(widget.id)),
        child: ListView(
          padding: const EdgeInsets.only(top: 4, bottom: 32),
          children: [
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => context.push('/u/${plan.owner.username}'),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Avatar(name: plan.owner.displayName, url: plan.owner.avatarUrl, size: 40),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(plan.owner.displayName, style: font(15, weight: 700, color: p.ink)),
                                Text(t('plan.shared_by'), style: font(12.5, color: p.inkMuted)),
                              ],
                            ),
                          ),
                          Icon(LucideIcons.chevronRight, size: 18, color: p.inkSubtle),
                        ],
                      ),
                    ),
                  ),
                  _PreviewStrip(kind: plan.kind, text: t('plan.kind_${plan.kind}')),
                  const SizedBox(height: 6),
                  row(t('plan.date'), DateFormat.MMMMEEEEd(locale).format(plan.targetAt)),
                  row(t('plan.time'), hm.format(plan.targetAt)),
                  row(
                    t('plan.place'),
                    plan.placeName ?? '${plan.latitude.toStringAsFixed(3)}, ${plan.longitude.toStringAsFixed(3)}',
                    sub: plan.placeName == null ? null : '${plan.latitude.toStringAsFixed(3)}, ${plan.longitude.toStringAsFixed(3)}',
                  ),
                  row(
                    t('plan.moon'),
                    '${t('planner.phase.${moonPhaseKey(night.phase)}')} %${(night.illumination * 100).round()}',
                    last: plan.notes == null,
                  ),
                  if (plan.notes != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(plan.notes!, style: font(14, color: p.ink)),
                    ),
                ],
              ),
            ),
            SectionCard(
              child: Row(
                children: [
                  Icon(LucideIcons.users, size: 20, color: p.accentText),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      plan.joinCount == 0 ? t('plan.no_joiners') : t('plan.joined_count', {'count': plan.joinCount}),
                      style: font(14, color: p.ink),
                    ),
                  ),
                  AvatarStack(users: plan.joiners, size: 26, max: 6),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (mine)
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: const StadiumBorder()),
                      onPressed: () => context.push('/sky/plans/${plan.id}'),
                      child: Text(t('plan.edit_mine')),
                    )
                  else if (!past)
                    FilledButton(
                      style: plan.joined
                          ? secondary.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(50)))
                          : FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: const StadiumBorder()),
                      onPressed: _busy ? null : () => _toggle(plan),
                      child: BusyLabel(busy: _busy, label: t(plan.joined ? 'plan.leave' : 'plan.join')),
                    ),
                  if (!mine && plan.joined && !past)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(t('plan.joined_hint'), textAlign: TextAlign.center, style: font(12.5, color: p.inkMuted)),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: secondary,
                          icon: const Icon(LucideIcons.scanLine, size: 18),
                          label: Text(t('plan.open_ar'), maxLines: 1, overflow: TextOverflow.ellipsis),
                          onPressed: () {
                            _usePlace(plan);
                            context.push('/sky/ar?date=${_night(plan).millisecondsSinceEpoch}');
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          style: secondary,
                          icon: const Icon(LucideIcons.sunMoon, size: 18),
                          label: Text(t('plan.open_planner'), maxLines: 1, overflow: TextOverflow.ellipsis),
                          onPressed: () {
                            _usePlace(plan);
                            context.push('/sky/planner?date=${DateUtils.dateOnly(_night(plan)).millisecondsSinceEpoch}');
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
