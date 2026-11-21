import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../core/api_client.dart';
import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/ad_widgets.dart';
import '../widgets/common.dart';

const _specialties = [
  'astro',
  'landscape',
  'street',
  'portrait',
  'wildlife',
  'sports',
  'architecture',
  'documentary',
  'wedding',
  'macro',
  'aerial',
  'travel',
];
const _equipmentTypes = [
  'body',
  'lens',
  'tripod',
  'filter',
  'flash',
  'drone',
  'other',
];

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.welcome = false});
  final bool welcome;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(authProvider.notifier).welcomePending = false;
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final me = ref.watch(authProvider).asData?.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('settings.heading')),
        // Kayıttan doğrudan gelindiyse geri gidilecek sayfa yoktur
        leading: context.canPop()
            ? null
            : IconButton(
                icon: const Icon(LucideIcons.x),
                onPressed: () => context.go('/feed'),
              ),
      ),
      body: me == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 48),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                if (widget.welcome) ...[
                  Notice(t('settings.welcome'), tone: NoticeTone.success),
                  const SizedBox(height: 12),
                ],
                if (!me.emailVerified) ...[
                  const _VerifyBanner(),
                  const SizedBox(height: 12),
                ],
                Material(
                  color: context.palette.surface,
                  child: ListTile(
                    onTap: () => context.push('/pro'),
                    leading: const ProBadge(),
                    title: Text(
                      me.isPro ? t('pro.you_are_pro') : t('pro.settings_title'),
                      style: font(
                        15.5,
                        weight: 600,
                        color: context.palette.ink,
                      ),
                    ),
                    subtitle: Text(
                      me.isPro
                          ? t('pro.settings_manage')
                          : t('pro.settings_body'),
                      style: font(13, color: context.palette.inkMuted),
                    ),
                    trailing: const Icon(LucideIcons.chevronRight),
                  ),
                ),
                const SizedBox(height: 28),
                _ProfileSection(me: me),
                const SizedBox(height: 36),
                _EquipmentSection(initial: me.equipment),
                const SizedBox(height: 36),
                const _NotificationSettings(),
                const SizedBox(height: 36),
                const _AccountSection(),
              ],
            ),
    );
  }
}

class _VerifyBanner extends ConsumerStatefulWidget {
  const _VerifyBanner();

  @override
  ConsumerState<_VerifyBanner> createState() => _VerifyBannerState();
}

class _VerifyBannerState extends ConsumerState<_VerifyBanner> {
  bool _sent = false;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    return Notice(
      _sent ? t('settings.verify_sent') : t('settings.verify_needed'),
      action: _sent
          ? null
          : TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () async {
                await ref
                    .read(apiProvider)
                    .post<dynamic>('/auth/resend-verification');
                if (mounted) setState(() => _sent = true);
              },
              child: Text(t('settings.verify_resend')),
            ),
    );
  }
}

class _ProfileSection extends ConsumerStatefulWidget {
  const _ProfileSection({required this.me});
  final Me me;

  @override
  ConsumerState<_ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends ConsumerState<_ProfileSection> {
  late final _name = TextEditingController(text: widget.me.displayName);
  late final _username = TextEditingController(text: widget.me.username);
  late final _bio = TextEditingController(text: widget.me.bio);
  late final _website = TextEditingController(text: widget.me.website);
  late final _city = TextEditingController(text: widget.me.city);
  late final _country = TextEditingController(text: widget.me.country);
  late bool _public = widget.me.isPublic;
  late String _locale = widget.me.locale;
  late List<String> _specs = [...widget.me.specialties];
  late double? _lat = widget.me.latitude;
  late double? _lng = widget.me.longitude;
  bool _busy = false;
  ApiException? _error;

  @override
  void dispose() {
    for (final c in [_name, _username, _bio, _website, _city, _country]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _locate() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
    );
    setState(() {
      _lat = pos.latitude;
      _lng = pos.longitude;
    });
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    String? opt(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    var website = opt(_website);
    if (website != null && !website.startsWith(RegExp('https?://'))) {
      website = 'https://$website';
    }
    try {
      final res = await ref.read(apiProvider).patch<Map<String, dynamic>>(
        '/me',
        {
          'display_name': _name.text.trim(),
          'username': _username.text.trim().toLowerCase(),
          'bio': opt(_bio),
          'website': website,
          'city': opt(_city),
          'country': opt(_country)?.toUpperCase(),
          'is_public': _public,
          'locale': _locale,
          'specialties': _specs,
          'latitude': _lat,
          'longitude': _lng,
        },
      );
      ref.read(authProvider.notifier).setMe(Me.fromJson(res));
      ref.invalidate(profileProvider);
      if (mounted) toast(context, L10n.of(context)('common.saved'));
    } catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    const gap = SizedBox(height: 14);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(t('settings.profile')),
        const SizedBox(height: 18),
        TextField(
          controller: _name,
          maxLength: 80,
          decoration: InputDecoration(
            labelText: t('settings.display_name'),
            counterText: '',
          ),
        ),
        gap,
        TextField(
          controller: _username,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: t('settings.username'),
            prefixText: '@',
            errorText: _error?.code == 'username_taken'
                ? _error!.message
                : null,
          ),
        ),
        gap,
        TextField(
          controller: _bio,
          maxLength: 500,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(labelText: t('settings.bio')),
        ),
        TextField(
          controller: _website,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(labelText: t('settings.website')),
        ),
        gap,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _city,
                decoration: InputDecoration(labelText: t('settings.city')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _country,
                maxLength: 2,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: t('settings.country'),
                  helperText: t('settings.country_hint'),
                  counterText: '',
                ),
              ),
            ),
          ],
        ),
        gap,
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          decoration: BoxDecoration(
            border: Border.all(color: p.line),
            borderRadius: BorderRadius.circular(Radii.box),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('settings.map_location'),
                      style: font(15, weight: 500, color: p.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _lat != null
                          ? t('settings.map_location_set')
                          : t('settings.map_location_hint'),
                      style: font(13, height: 1.4, color: p.inkMuted),
                    ),
                  ],
                ),
              ),
              if (_lat != null)
                TextButton(
                  onPressed: () => setState(() {
                    _lat = null;
                    _lng = null;
                  }),
                  child: Text(t('settings.remove')),
                )
              else
                TextButton(
                  onPressed: _locate,
                  child: Text(t('settings.use_my_location')),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          t('settings.specialties'),
          style: font(14, weight: 500, color: p.ink),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in _specialties)
              FilterChip(
                label: Text(t('specialties.$s')),
                selected: _specs.contains(s),
                labelStyle: font(14, color: _specs.contains(s) ? p.surface : p.ink),
                side: BorderSide(color: _specs.contains(s) ? p.ink : p.line),
                onSelected: (on) => setState(
                  () => _specs = on
                      ? ([..._specs, s].take(10).toList())
                      : (_specs..remove(s)).toList(),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            t('settings.public'),
            style: font(15, weight: 500, color: p.ink),
          ),
          subtitle: Text(
            _public ? t('settings.public_on') : t('settings.public_off'),
            style: font(13, height: 1.4, color: p.inkMuted),
          ),
          value: _public,
          onChanged: (v) => setState(() => _public = v),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _locale,
          decoration: InputDecoration(labelText: t('settings.language')),
          items: const [
            DropdownMenuItem(value: 'tr', child: Text('Türkçe')),
            DropdownMenuItem(value: 'en', child: Text('English')),
          ],
          onChanged: (v) => setState(() => _locale = v ?? _locale),
        ),
        if (_error != null && _error!.code != 'username_taken') ...[
          const SizedBox(height: 14),
          Notice(errorText(context, _error!), tone: NoticeTone.error),
        ],
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: BusyLabel(busy: _busy, label: t('settings.save')),
          ),
        ),
      ],
    );
  }
}

class _EquipmentSection extends ConsumerStatefulWidget {
  const _EquipmentSection({required this.initial});
  final List<Equipment> initial;

  @override
  ConsumerState<_EquipmentSection> createState() => _EquipmentSectionState();
}

class _EquipmentRow {
  _EquipmentRow(this.type, String brand, String model)
    : brand = TextEditingController(text: brand),
      model = TextEditingController(text: model);
  String type;
  final TextEditingController brand;
  final TextEditingController model;
}

class _EquipmentSectionState extends ConsumerState<_EquipmentSection> {
  late final List<_EquipmentRow> _rows = [
    for (final e in widget.initial) _EquipmentRow(e.type, e.brand, e.model),
  ];
  bool _busy = false;

  @override
  void dispose() {
    for (final r in _rows) {
      r.brand.dispose();
      r.model.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).put<List<dynamic>>('/me/equipment', [
        for (final r in _rows)
          if (r.brand.text.trim().isNotEmpty && r.model.text.trim().isNotEmpty)
            Equipment(
              type: r.type,
              brand: r.brand.text.trim(),
              model: r.model.text.trim(),
            ).toJson(),
      ]);
      await ref.read(authProvider.notifier).refreshMe();
      ref.invalidate(profileProvider);
      if (mounted) toast(context, L10n.of(context)('common.saved'));
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          t('settings.equipment'),
          lead: t('settings.equipment_lead'),
        ),
        const SizedBox(height: 16),
        for (final (i, r) in _rows.indexed)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 12),
            color: p.surface,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButton<String>(
                        value: r.type,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        style: font(15, weight: 600, color: p.ink),
                        items: [
                          for (final ty in _equipmentTypes)
                            DropdownMenuItem(
                              value: ty,
                              child: Text(t('equipment.$ty')),
                            ),
                        ],
                        onChanged: (v) => setState(() => r.type = v ?? r.type),
                      ),
                    ),
                    IconButton(
                      tooltip: t('settings.remove'),
                      icon: Icon(LucideIcons.trash2, color: p.inkMuted),
                      onPressed: () => setState(() => _rows.removeAt(i)),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: r.brand,
                          decoration: InputDecoration(
                            labelText: t('settings.brand'),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: r.model,
                          decoration: InputDecoration(
                            labelText: t('settings.model'),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: () => setState(
                () => _rows.add(
                  _EquipmentRow(_rows.isEmpty ? 'body' : 'lens', '', ''),
                ),
              ),
              icon: const Icon(LucideIcons.plus, size: 18),
              label: Text(t('settings.add_equipment')),
            ),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: BusyLabel(
                busy: _busy,
                label: t('settings.save_equipment'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AccountSection extends ConsumerStatefulWidget {
  const _AccountSection();

  @override
  ConsumerState<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<_AccountSection> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    final t = L10n.of(context);
    if (_next.text.length < 8) {
      toast(context, t('auth.short_password'));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(authProvider.notifier)
          .changePassword(
            _current.text.isEmpty ? null : _current.text,
            _next.text,
          );
      _current.clear();
      _next.clear();
      if (mounted) toast(context, t('settings.password_changed'));
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAccount() async {
    final t = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t('settings.delete_account')),
        content: Text(t('settings.delete_account_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(t('common.cancel')),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: context.palette.danger,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: Text(t('settings.delete_account')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(authProvider.notifier).deleteAccount();
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(t('settings.account')),
        const SizedBox(height: 18),
        Text(
          t('settings.change_password'),
          style: font(15, weight: 600, color: p.ink),
        ),
        const SizedBox(height: 2),
        Text(
          t('settings.change_password_hint'),
          style: font(13, color: p.inkMuted),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _current,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: t('settings.current_password'),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _next,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(labelText: t('settings.new_password')),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: _busy ? null : _changePassword,
            child: BusyLabel(busy: _busy, label: t('settings.change_password')),
          ),
        ),
        const SizedBox(height: 28),
        OutlinedButton(
          onPressed: () => ref.read(authProvider.notifier).logout(),
          child: Text(t('settings.logout')),
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: p.danger.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(Radii.box),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('settings.delete_account'),
                style: font(15, weight: 600, color: p.ink),
              ),
              const SizedBox(height: 4),
              Text(
                t('settings.delete_account_body'),
                style: font(13.5, height: 1.45, color: p.inkMuted),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.danger,
                  side: BorderSide(color: p.danger),
                ),
                onPressed: _deleteAccount,
                child: Text(t('settings.delete_account')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}


const _pushTypes = [
  'new_follower',
  'photo_liked',
  'photo_published',
  'photo_rejected',
  'contest_new',
  'contest_deadline',
  'contest_results',
];

final _notificationSettingsProvider =
    FutureProvider.autoDispose<Map<String, bool>>((ref) async {
      final res = await ref
          .read(apiProvider)
          .get<Map<String, dynamic>>('/me/notification-settings');
      return (res['push'] as Map).map((k, v) => MapEntry('$k', v == true));
    });

class _NotificationSettings extends ConsumerStatefulWidget {
  const _NotificationSettings();

  @override
  ConsumerState<_NotificationSettings> createState() =>
      _NotificationSettingsState();
}

class _NotificationSettingsState extends ConsumerState<_NotificationSettings> {
  final _local = <String, bool>{};

  Future<void> _set(String type, bool value) async {
    setState(() => _local[type] = value);
    try {
      await ref.read(apiProvider).patch<dynamic>('/me/notification-settings', {
        'push': {type: value},
      });
    } catch (e) {
      if (mounted) {
        setState(() => _local[type] = !value);
        toast(context, errorText(context, e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final saved = ref.watch(_notificationSettingsProvider).asData?.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          t('settings.notifications'),
          lead: t('settings.notifications_lead'),
        ),
        const SizedBox(height: 8),
        if (saved == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          for (final type in _pushTypes)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                t('settings.push.$type'),
                style: font(15, color: p.ink),
              ),
              value: _local[type] ?? saved[type] ?? false,
              onChanged: (v) => _set(type, v),
            ),
      ],
    );
  }
}
