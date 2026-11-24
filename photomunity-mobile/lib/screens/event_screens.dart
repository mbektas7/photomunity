import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/astro.dart';
import '../core/config.dart';
import '../core/l10n.dart';
import '../core/models.dart';
import '../core/sky.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/design.dart';
import '../widgets/place_picker.dart';
import 'sky/sky_common.dart';

const _red = Color(0xFFB42318);
const _green = Color(0xFF1A7F45);

/// Takvim yaprağı: ay kısaltması ve gün.
class _DateLeaf extends StatelessWidget {
  const _DateLeaf({required this.at, this.size = 1});
  final DateTime at;
  final double size;

  @override
  Widget build(BuildContext context) {
    final locale = L10n.of(context).locale.languageCode;
    return Container(
      width: 48 * size,
      padding: EdgeInsets.symmetric(vertical: 6 * size),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(DateFormat.MMM(locale).format(at).toUpperCase(),
              style: font(11 * size, weight: 700, height: 1.1, color: _red)),
          Text('${at.day}', style: font(20 * size, weight: 700, height: 1.1, color: const Color(0xFF14161B))),
        ],
      ),
    );
  }
}

String _timeRange(EventCard e, String locale) {
  final hm = DateFormat.Hm(locale);
  final day = DateFormat.EEEE(locale).format(e.startsAt);
  return e.endsAt == null ? '$day ${hm.format(e.startsAt)}' : '$day ${hm.format(e.startsAt)} – ${hm.format(e.endsAt!)}';
}

/// Topluluk sayfasındaki "Etkinlikler" sekmesi.
class CommunityEventsTab extends ConsumerWidget {
  const CommunityEventsTab({super.key, required this.c});
  final Community c;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    final async = ref.watch(communityEventsProvider(c.slug));
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(communityEventsProvider(c.slug)),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (c.isAdmin)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FilledButton.icon(
                onPressed: () => context.push('/c/${c.slug}/events/new'),
                icon: const Icon(LucideIcons.plus, size: 18),
                label: Text(t('event.create')),
              ),
            ),
          ...switch (async) {
            AsyncData(:final value) when value.upcoming.isEmpty && value.past.isEmpty => [
              Text(t('event.empty'), style: font(15, color: p.inkMuted)),
            ],
            AsyncData(:final value) => [
              if (value.upcoming.isNotEmpty) ...[
                Text(t('event.upcoming'), style: font(15, weight: 700, color: p.ink)),
                const SizedBox(height: 8),
                for (final e in value.upcoming) EventTile(e: e),
              ],
              if (value.past.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(t('event.past'), style: font(15, weight: 700, color: p.inkMuted)),
                const SizedBox(height: 8),
                for (final e in value.past) EventTile(e: e),
              ],
            ],
            AsyncError(:final error) => [
              ErrorView(error: error, onRetry: () => ref.invalidate(communityEventsProvider(c.slug))),
            ],
            _ => [const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))],
          },
        ],
      ),
    );
  }
}

class EventTile extends StatelessWidget {
  const EventTile({super.key, required this.e});
  final EventCard e;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final locale = t.locale.languageCode;
    final cancelled = e.status == 'cancelled';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('/events/${e.id}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(14)),
                  child: _DateLeaf(at: e.startsAt, size: 0.9),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: font(15.5, weight: 700, color: p.ink).copyWith(
                            decoration: cancelled ? TextDecoration.lineThrough : null,
                          )),
                      Text(_timeRange(e, locale), style: font(13, color: p.ink)),
                      Text(
                        [
                          e.locationName,
                          if (cancelled) t('event.cancelled') else t('event.going_n', {'count': e.attendeeCount}),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: font(12.5, color: cancelled ? _red : p.inkMuted),
                      ),
                    ],
                  ),
                ),
                if (e.attending) ...[
                  const SizedBox(width: 8),
                  Icon(LucideIcons.circleCheck, size: 20, color: p.accentText),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Etkinlik detayı: tarih, yer (+ küçük harita), o gecenin Ay/karanlık penceresi ve 7 gün içindeyse bulut tahmini.
class EventScreen extends ConsumerStatefulWidget {
  const EventScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends ConsumerState<EventScreen> {
  bool _busy = false;

  Future<void> _attend(CommunityEvent e, bool on) async {
    setState(() => _busy = true);
    try {
      final api = ref.read(apiProvider);
      on ? await api.post<dynamic>('/events/${e.id}/attend') : await api.delete<dynamic>('/events/${e.id}/attend');
      ref.invalidate(eventProvider(e.id));
      ref.invalidate(eventAttendeesProvider(e.id));
      ref.invalidate(communityEventsProvider(e.community.slug));
    } catch (err) {
      if (mounted) toast(context, errorText(context, err));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(CommunityEvent e) async {
    final t = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(t('event.cancel_title')),
        content: Text(t('event.cancel_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(t('common.cancel'))),
          TextButton(onPressed: () => Navigator.pop(d, true), child: Text(t('event.cancel_confirm'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(apiProvider).post<dynamic>('/events/${e.id}/cancel');
      ref.invalidate(eventProvider(e.id));
      ref.invalidate(communityEventsProvider(e.community.slug));
    } catch (err) {
      if (mounted) toast(context, errorText(context, err));
    }
  }

  void _attendees(CommunityEvent e) {
    final t = L10n.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (s) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(s).height * 0.6,
          child: Consumer(
            builder: (s, ref, _) {
              final async = ref.watch(eventAttendeesProvider(e.id));
              final p = s.palette;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(t('event.attendees'), style: font(18, weight: 700, color: p.ink)),
                  ),
                  Expanded(
                    child: switch (async) {
                      AsyncData(:final value) => ListView(
                        children: [
                          for (final u in value)
                            ListTile(
                              onTap: () {
                                Navigator.pop(s);
                                context.push('/u/${u.username}');
                              },
                              leading: Avatar(name: u.displayName, url: u.avatarUrl, size: 40),
                              title: Text(u.displayName, style: font(15, weight: 600, color: p.ink)),
                              subtitle: Text('@${u.username}', style: font(13, color: p.inkMuted)),
                            ),
                        ],
                      ),
                      AsyncError(:final error) => ErrorView(error: error),
                      _ => const Center(child: CircularProgressIndicator()),
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final async = ref.watch(eventProvider(widget.id));
    final e = async.asData?.value;
    return Scaffold(
      appBar: pageBar(
        context,
        t('event.title'),
        sub: e?.community.name,
        intro: 'events',
        actions: [
          if (e != null && e.canManage && e.open)
            PopupMenuButton<String>(
              tooltip: t('ui.more'),
              icon: const Icon(LucideIcons.ellipsisVertical),
              onSelected: (v) => v == 'edit' ? context.push('/events/${e.id}/edit') : _cancel(e),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text(t('event.edit'))),
                PopupMenuItem(value: 'cancel', child: Text(t('event.cancel_title'), style: TextStyle(color: context.palette.danger))),
              ],
            ),
        ],
      ),
      body: e != null
          ? _body(context, e)
          : async.hasError
          ? ErrorView(error: async.error!, onRetry: () => ref.invalidate(eventProvider(widget.id)))
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _body(BuildContext context, CommunityEvent e) {
    final t = L10n.of(context);
    final p = context.palette;
    final locale = t.locale.languageCode;
    final hm = DateFormat.Hm(locale);
    final dark = Theme.of(context).brightness == Brightness.dark;

    // O gecenin gökyüzü: Ay, karanlık pencere; koordinat ve 7 gün içindeyse bulut
    final night = e.startsAt.hour < 12 ? e.startsAt.subtract(const Duration(days: 1)) : e.startsAt;
    final plan = e.hasPoint ? planNight(night, e.latitude!, e.longitude!) : null;
    final illum = plan?.illumination ?? moonIllumination(e.startsAt.millisecondsSinceEpoch).fraction;
    final phase = plan?.phase ?? moonIllumination(e.startsAt.millisecondsSinceEpoch).phase;
    final win = plan == null || plan.bestWindows.isEmpty ? null : plan.bestWindows.first;
    final forecast = e.hasPoint && e.startsAt.difference(DateTime.now()).inDays < 7 && e.open
        ? ref.watch(forecastProvider((e.latitude!, e.longitude!))).asData?.value
        : null;
    final until = e.endsAt ?? e.startsAt.add(const Duration(hours: 3));
    final cloud = forecast != null && forecast.covers(e.startsAt) ? forecast.average(e.startsAt, until)?.cloud : null;
    final skyGood = illum < 0.35 && (cloud == null || cloud < 40);
    final skyLine = [
      '${t('planner.phase.${moonPhaseKey(phase)}')} %${(illum * 100).round()}',
      if (cloud != null) t('event.cloud_forecast', {'pct': cloud.round()}),
      if (win != null) t('event.window', {'range': '${hm.format(win.start)}–${hm.format(win.end)}'}),
    ].join(' · ');

    Widget line(IconData icon, String text, {Color? color, bool bold = false, VoidCallback? onTap, Widget? lead}) => InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            lead ?? Icon(icon, size: 17, color: color ?? p.inkMuted),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: font(14, weight: bold ? 600 : 400, color: color ?? p.ink))),
          ],
        ),
      ),
    );

    final member = e.myRole != null;
    final primary = FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: const StadiumBorder());
    final secondary = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(50),
      shape: const StadiumBorder(),
      backgroundColor: p.surface,
      foregroundColor: p.ink,
    );

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(eventProvider(widget.id)),
      child: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 32),
        children: [
          if (e.status == 'cancelled')
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Notice(t('event.cancelled_notice'), tone: NoticeTone.error),
            ),
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(22)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 140,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (e.hasPoint)
                        IgnorePointer(
                          child: FlutterMap(
                            options: MapOptions(
                              initialCenter: LatLng(e.latitude!, e.longitude!),
                              initialZoom: 12,
                              interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: dark ? AppConfig.mapTilesDark : AppConfig.mapTilesLight,
                                subdomains: const ['a', 'b', 'c', 'd'],
                                retinaMode: RetinaMode.isHighDensity(context),
                                userAgentPackageName: 'app.photomunity.photomunity',
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: LatLng(e.latitude!, e.longitude!),
                                    width: 34,
                                    height: 34,
                                    alignment: Alignment.topCenter,
                                    child: Icon(Icons.location_on, size: 34, color: p.accent),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                      else
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF2B2370), Color(0xFF0D0B24)],
                            ),
                          ),
                        ),
                      Positioned(left: 14, top: 12, child: _DateLeaf(at: e.startsAt)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.title, style: font(20, weight: 700, color: p.ink)),
                      const SizedBox(height: 8),
                      line(LucideIcons.clock, '${DateFormat.MMMMd(locale).format(e.startsAt)} · ${_timeRange(e, locale)}'),
                      line(
                        LucideIcons.mapPin,
                        e.locationName,
                        onTap: e.hasPoint ? () => context.push('/map?lat=${e.latitude}&lng=${e.longitude}') : null,
                      ),
                      line(
                        LucideIcons.moon,
                        skyLine,
                        bold: true,
                        color: skyGood ? (dark ? const Color(0xFF6FD69A) : _green) : null,
                        lead: Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: MoonGlyph(phase: phase, fraction: illum, size: 16),
                        ),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: e.attendeeCount > 0 ? () => _attendees(e) : null,
                        child: Row(
                          children: [
                            AvatarStack(users: e.attendeesPreview, size: 30),
                            if (e.attendeesPreview.isNotEmpty) const SizedBox(width: 8),
                            Expanded(
                              child: Text.rich(
                                TextSpan(children: [
                                  TextSpan(
                                    text: t('event.people', {'count': e.attendeeCount}),
                                    style: font(13, weight: 700, color: p.ink),
                                  ),
                                  TextSpan(
                                    text: ' ${t('event.going')}${e.capacity == null ? '' : ' · ${t('event.capacity_n', {'count': e.capacity!})}'}',
                                    style: font(13, color: p.inkMuted),
                                  ),
                                ]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (e.description != null)
            SectionCard(child: Text(e.description!, style: font(14.5, height: 1.5, color: p.ink))),
          if (e.bring != null)
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('event.bring'), style: font(15, weight: 700, color: p.ink)),
                  const SizedBox(height: 4),
                  Text(e.bring!, style: font(13.5, height: 1.5, color: p.inkMuted)),
                ],
              ),
            ),
          if (e.open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              child: !member
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(t('event.members_only'), textAlign: TextAlign.center, style: font(13.5, color: p.inkMuted)),
                        const SizedBox(height: 8),
                        FilledButton(
                          style: primary,
                          onPressed: () => context.push('/c/${e.community.slug}'),
                          child: Text(t('event.open_community')),
                        ),
                      ],
                    )
                  : e.attending
                  ? FilledButton(
                      style: secondary,
                      onPressed: _busy ? null : () => _attend(e, false),
                      child: BusyLabel(busy: _busy, label: t('event.leave')),
                    )
                  : FilledButton(
                      style: primary,
                      onPressed: _busy || e.full ? null : () => _attend(e, true),
                      child: BusyLabel(busy: _busy, label: t(e.full ? 'event.full' : 'event.attend')),
                    ),
            ),
          if (e.attending && e.open)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
              child: Text(t('event.you_are_going'), textAlign: TextAlign.center, style: font(13, color: p.inkMuted)),
            ),
        ],
      ),
    );
  }
}

/// Etkinlik oluşturma / düzenleme (topluluk sahibi ve yöneticileri).
class EventFormScreen extends ConsumerStatefulWidget {
  const EventFormScreen({super.key, this.slug, this.id});
  final String? slug;
  final String? id;

  @override
  ConsumerState<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends ConsumerState<EventFormScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _place = TextEditingController();
  final _capacity = TextEditingController();
  final _bring = TextEditingController();
  late DateTime _date = DateUtils.dateOnly(DateTime.now().add(const Duration(days: 7)));
  TimeOfDay _start = const TimeOfDay(hour: 21, minute: 0);
  TimeOfDay? _end;
  double? _lat, _lng;
  bool _busy = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loaded = widget.id == null;
  }

  @override
  void dispose() {
    for (final c in [_title, _desc, _place, _capacity, _bring]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(CommunityEvent e) {
    _title.text = e.title;
    _desc.text = e.description ?? '';
    _place.text = e.locationName;
    _capacity.text = e.capacity?.toString() ?? '';
    _bring.text = e.bring ?? '';
    _date = DateUtils.dateOnly(e.startsAt);
    _start = TimeOfDay.fromDateTime(e.startsAt);
    _end = e.endsAt == null ? null : TimeOfDay.fromDateTime(e.endsAt!);
    _lat = e.latitude;
    _lng = e.longitude;
    _loaded = true;
  }

  DateTime get _startsAt => DateTime(_date.year, _date.month, _date.day, _start.hour, _start.minute);

  /// Bitiş başlangıçtan önceyse ertesi gün (gece etkinlikleri).
  DateTime? get _endsAt {
    final end = _end;
    if (end == null) return null;
    var d = DateTime(_date.year, _date.month, _date.day, end.hour, end.minute);
    if (!d.isAfter(_startsAt)) d = d.add(const Duration(days: 1));
    return d;
  }

  Future<void> _save() async {
    final t = L10n.of(context);
    if (_title.text.trim().isEmpty || _place.text.trim().isEmpty) {
      toast(context, t('event.form_required'));
      return;
    }
    setState(() => _busy = true);
    final body = {
      'title': _title.text.trim(),
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'starts_at': _startsAt.toUtc().toIso8601String(),
      'ends_at': _endsAt?.toUtc().toIso8601String(),
      'location_name': _place.text.trim(),
      'latitude': _lat,
      'longitude': _lng,
      'capacity': int.tryParse(_capacity.text.trim()),
      'bring': _bring.text.trim().isEmpty ? null : _bring.text.trim(),
    };
    try {
      final api = ref.read(apiProvider);
      final res = widget.id == null
          ? await api.post<Map<String, dynamic>>('/communities/${widget.slug}/events', body)
          : await api.patch<Map<String, dynamic>>('/events/${widget.id}', body);
      final e = CommunityEvent.fromJson(res);
      ref.invalidate(communityEventsProvider(e.community.slug));
      ref.invalidate(eventProvider(e.id));
      if (!mounted) return;
      widget.id == null ? context.pushReplacement('/events/${e.id}') : context.pop();
    } catch (err) {
      if (mounted) toast(context, errorText(context, err));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final locale = t.locale.languageCode;
    if (!_loaded) {
      final async = ref.watch(eventProvider(widget.id!));
      if (async.hasValue) {
        _fill(async.requireValue);
      } else {
        return Scaffold(
          appBar: pageBar(context, t('event.edit')),
          body: async.hasError ? ErrorView(error: async.error!) : const Center(child: CircularProgressIndicator()),
        );
      }
    }
    Widget pickRow(String label, String value, VoidCallback onTap, {Widget? trailing}) => InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Text(label, style: font(14.5, color: p.inkMuted)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(value, textAlign: TextAlign.right, style: font(14.5, weight: 700, color: p.ink, tabular: true)),
            ),
            trailing ?? Icon(LucideIcons.chevronRight, size: 18, color: p.inkSubtle),
          ],
        ),
      ),
    );
    return Scaffold(
      appBar: pageBar(context, t(widget.id == null ? 'event.create' : 'event.edit')),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 32),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          SectionCard(
            child: Column(
              children: [
                TextField(
                  controller: _title,
                  maxLength: 150,
                  decoration: InputDecoration(labelText: t('event.f_title'), hintText: t('event.f_title_hint')),
                ),
                TextField(
                  controller: _desc,
                  maxLength: 3000,
                  minLines: 2,
                  maxLines: 6,
                  decoration: InputDecoration(labelText: t('event.f_description')),
                ),
              ],
            ),
          ),
          SectionCard(
            child: Column(
              children: [
                pickRow(t('plan.date'), DateFormat.MMMMEEEEd(locale).format(_date), () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _date.isBefore(DateUtils.dateOnly(now)) ? now : _date,
                    firstDate: DateUtils.dateOnly(now),
                    lastDate: now.add(const Duration(days: 730)),
                  );
                  if (d != null) setState(() => _date = d);
                }),
                Divider(height: 1, color: p.line),
                pickRow(t('event.f_start'), _start.format(context), () async {
                  final v = await showTimePicker(context: context, initialTime: _start);
                  if (v != null) setState(() => _start = v);
                }),
                Divider(height: 1, color: p.line),
                pickRow(
                  t('event.f_end'),
                  _end == null ? t('event.f_end_none') : _end!.format(context),
                  () async {
                    final v = await showTimePicker(context: context, initialTime: _end ?? _start);
                    if (v != null) setState(() => _end = v);
                  },
                  trailing: _end == null
                      ? null
                      : IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: t('event.f_end_clear'),
                          icon: Icon(LucideIcons.x, size: 18, color: p.inkMuted),
                          onPressed: () => setState(() => _end = null),
                        ),
                ),
              ],
            ),
          ),
          SectionCard(
            child: Column(
              children: [
                TextField(
                  controller: _place,
                  maxLength: 200,
                  decoration: InputDecoration(labelText: t('event.f_place'), hintText: t('event.f_place_hint')),
                ),
                pickRow(
                  t('event.f_point'),
                  _lat == null ? t('event.f_point_none') : '${_lat!.toStringAsFixed(3)}, ${_lng!.toStringAsFixed(3)}',
                  () async {
                    final picked = await pickPlace(context, lat: _lat, lng: _lng, name: _place.text.trim().isEmpty ? null : _place.text.trim());
                    if (picked == null) return;
                    setState(() {
                      _lat = picked.lat;
                      _lng = picked.lng;
                      if (picked.name != null) _place.text = picked.name!;
                    });
                  },
                  trailing: _lat == null
                      ? null
                      : IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: t('event.f_point_clear'),
                          icon: Icon(LucideIcons.x, size: 18, color: p.inkMuted),
                          onPressed: () => setState(() => _lat = _lng = null),
                        ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(t('event.f_point_hint'), style: font(12.5, color: p.inkMuted)),
                ),
              ],
            ),
          ),
          SectionCard(
            child: Column(
              children: [
                TextField(
                  controller: _capacity,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: t('event.f_capacity'), hintText: t('event.f_capacity_hint')),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _bring,
                  maxLength: 500,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(labelText: t('event.bring'), hintText: t('event.f_bring_hint')),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: const StadiumBorder()),
              onPressed: _busy ? null : _save,
              child: BusyLabel(busy: _busy, label: t(widget.id == null ? 'event.publish' : 'common.save')),
            ),
          ),
          if (widget.id == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
              child: Text(t('event.publish_note'), textAlign: TextAlign.center, style: font(12.5, color: p.inkMuted)),
            ),
        ],
      ),
    );
  }
}
