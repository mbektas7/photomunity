import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n.dart';
import '../core/models.dart';
import '../core/profile_images.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import 'settings_screen.dart' show equipmentTypeKeys, specialtyKeys;

/// Tanıtımı bitirir ya da kapatır (sunucuda işaretlenir; bir daha gösterilmez).
Future<void> finishOnboarding(WidgetRef ref) async {
  try {
    final res = await ref.read(apiProvider).patch<Map<String, dynamic>>('/me', {'onboarding_done': true});
    ref.read(authProvider.notifier).setMe(Me.fromJson(res));
  } catch (_) {
    // Ağ hatası olursa kart bir sonraki açılışta yeniden görünür; akışı engellemeyiz
  }
}

/// Kayıt sonrası 4 adımlı tanıtım: profil fotoğrafı, hakkında, ekipman, ilk fotoğraf. Her adım atlanabilir.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.step = 0});
  final int step;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late int _step = widget.step.clamp(0, 3);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(authProvider.notifier).welcomePending = false;
    final me = ref.read(authProvider).asData?.value;
    _bio = TextEditingController(text: me?.bio ?? '');
    _city = TextEditingController(text: me?.city ?? '');
    _specs = [...?me?.specialties];
    _gear = [...?me?.equipment];
  }

  // 2. ve 3. adımın alanları açılışta doldurulur (dispose sırasında ref okunmasın)
  late final TextEditingController _bio;
  late final TextEditingController _city;
  late final List<String> _specs;
  late final List<Equipment> _gear;

  @override
  void dispose() {
    _bio.dispose();
    _city.dispose();
    super.dispose();
  }

  void _next() {
    if (_step < 3) {
      setState(() => _step++);
    } else {
      _done('/feed');
    }
  }

  Future<void> _done(String to) async {
    setState(() => _busy = true);
    await finishOnboarding(ref);
    if (mounted) context.go(to);
  }

  Future<void> _primary() async {
    switch (_step) {
      case 0:
        setState(() => _busy = true);
        final ok = await uploadProfileImage(context, ref, 'avatar');
        if (!mounted) return;
        setState(() => _busy = false);
        if (ok) _next();
      case 1:
        await _save(() => ref.read(apiProvider).patch<Map<String, dynamic>>('/me', {
          'bio': _bio.text.trim(),
          'specialties': _specs,
          'city': _city.text.trim().isEmpty ? null : _city.text.trim(),
        }).then((res) => ref.read(authProvider.notifier).setMe(Me.fromJson(res))));
      case 2:
        await _save(() async {
          await ref.read(apiProvider).put<List<dynamic>>('/me/equipment', [for (final e in _gear) e.toJson()]);
          await ref.read(authProvider.notifier).refreshMe();
        });
      case 3:
        await _done('/feed');
        if (mounted) context.push('/upload');
    }
  }

  Future<void> _save(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(profileProvider);
      if (mounted) _next();
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addGear() async {
    final item = await showModalBottomSheet<Equipment>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _GearSheet(),
    );
    if (item != null) setState(() => _gear.add(item));
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final me = ref.watch(authProvider).asData?.value;
    final titles = ['onb.avatar', 'onb.about', 'onb.gear', 'onb.photo'];
    final primary = [
      me?.avatarUrl != null ? t('onb.change_photo') : t('onb.pick_photo'),
      t('onb.continue'),
      t('onb.continue'),
      t('onb.to_upload'),
    ][_step];
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step--);
      },
      child: Scaffold(
        backgroundColor: p.bg,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(
                  children: [
                    for (var i = 0; i < 4; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          height: 4,
                          decoration: BoxDecoration(
                            color: i <= _step ? p.accent : p.line,
                            borderRadius: BorderRadius.circular(Radii.pill),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 8, 0),
                child: Row(
                  children: [
                    Text(t('onb.step', {'n': _step + 1}), style: font(13, color: p.inkMuted)),
                    const Spacer(),
                    TextButton(
                      onPressed: _busy ? null : (_step == 3 ? () => _done('/feed') : _next),
                      child: Text(
                        t(_step == 3 ? 'onb.finish' : 'onb.skip'),
                        style: font(14, weight: 600, color: p.inkMuted),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
                  children: [
                    Text(t('${titles[_step]}_title'), style: font(28, weight: 700, spacing: -0.5)),
                    const SizedBox(height: 8),
                    Text(t('${titles[_step]}_lead'), style: font(15, color: p.inkMuted)),
                    const SizedBox(height: 26),
                    switch (_step) {
                      0 => _avatarStep(me, p, t),
                      1 => _aboutStep(p, t),
                      2 => _gearStep(p, t),
                      _ => _photoStep(p, t),
                    },
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  onPressed: _busy ? null : _primary,
                  child: BusyLabel(busy: _busy, label: primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatarStep(Me? me, Palette p, L10n t) => Column(
    children: [
      const SizedBox(height: 10),
      GestureDetector(
        onTap: _busy ? null : _primary,
        child: SizedBox(
          width: 156,
          height: 156,
          child: Stack(
            children: [
              Positioned.fill(
                child: me?.avatarUrl != null
                    ? ClipOval(child: NetPhoto(url: me!.avatarUrl!))
                    : DecoratedBox(
                        decoration: BoxDecoration(color: p.accentTint, shape: BoxShape.circle),
                        child: Icon(LucideIcons.camera, size: 52, color: p.accentText),
                      ),
              ),
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: p.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: p.bg, width: 4),
                  ),
                  child: Icon(me?.avatarUrl != null ? LucideIcons.pencil : LucideIcons.plus, size: 18, color: p.accentInk),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 18),
      Text(t('onb.avatar_hint'), textAlign: TextAlign.center, style: font(14, color: p.inkMuted)),
    ],
  );

  Widget _aboutStep(Palette p, L10n t) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _label(t('settings.bio'), p),
      TextField(
        controller: _bio,
        maxLines: 4,
        minLines: 3,
        maxLength: 500,
        decoration: InputDecoration(hintText: t('onb.bio_hint')),
      ),
      const SizedBox(height: 8),
      _label(t('onb.what_you_shoot'), p),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final s in specialtyKeys)
            FilterChip(
              label: Text(t('specialties.$s')),
              selected: _specs.contains(s),
              onSelected: (on) => setState(() => on ? _specs.add(s) : _specs.remove(s)),
            ),
        ],
      ),
      const SizedBox(height: 18),
      _label(t('settings.city'), p),
      TextField(controller: _city, textCapitalization: TextCapitalization.words),
    ],
  );

  Widget _gearStep(Palette p, L10n t) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, e) in _gear.indexed)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(18)),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(12)),
                child: Icon(LucideIcons.camera, size: 20, color: p.ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${e.brand} ${e.model}', style: font(15, weight: 700)),
                    Text(t('equipment.${e.type}'), style: font(13, color: p.inkMuted)),
                  ],
                ),
              ),
              IconButton(
                tooltip: t('settings.remove'),
                icon: Icon(LucideIcons.x, size: 18, color: p.inkMuted),
                onPressed: () => setState(() => _gear.removeAt(i)),
              ),
            ],
          ),
        ),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        onPressed: _addGear,
        icon: const Icon(LucideIcons.plus, size: 18),
        label: Text(t('settings.add_equipment')),
      ),
    ],
  );

  Widget _photoStep(Palette p, L10n t) => GestureDetector(
    onTap: _busy ? null : _primary,
    child: Container(
      height: 300,
      decoration: BoxDecoration(
        color: p.accentTint,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: p.accent.withValues(alpha: 0.35), width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
            child: Icon(LucideIcons.plus, size: 28, color: p.accentInk),
          ),
          const SizedBox(height: 12),
          Text(t('onb.pick_photo'), style: font(16, weight: 700, color: p.accentText)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(t('onb.photo_hint'), textAlign: TextAlign.center, style: font(13, color: p.inkMuted)),
          ),
        ],
      ),
    ),
  );

  Widget _label(String text, Palette p) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
    child: Text(text, style: font(13, weight: 700, color: p.inkMuted)),
  );
}

class _GearSheet extends StatefulWidget {
  const _GearSheet();

  @override
  State<_GearSheet> createState() => _GearSheetState();
}

class _GearSheetState extends State<_GearSheet> {
  String _type = 'body';
  final _brand = TextEditingController();
  final _model = TextEditingController();

  @override
  void dispose() {
    _brand.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final ok = _brand.text.trim().isNotEmpty && _model.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t('settings.add_equipment'), style: font(19, weight: 700)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final ty in equipmentTypeKeys)
                ChoiceChip(
                  label: Text(t('equipment.$ty')),
                  selected: _type == ty,
                  onSelected: (_) => setState(() => _type = ty),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _brand,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: t('settings.brand')),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _model,
            decoration: InputDecoration(labelText: t('settings.model')),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: ok
                ? () => Navigator.pop(
                    context,
                    Equipment(type: _type, brand: _brand.text.trim(), model: _model.text.trim()),
                  )
                : null,
            child: Text(t('onb.add')),
          ),
        ],
      ),
    );
  }
}

/// Ana sayfadaki "Profilini tamamla" kartı: tanıtım bitmemiş yeni hesaplarda görünür.
class OnboardingCard extends ConsumerWidget {
  const OnboardingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authProvider).asData?.value;
    if (me == null || me.onboardingDone) return const SizedBox.shrink();
    final steps = me.onboardingSteps;
    final done = steps.where((s) => s).length;
    if (done == steps.length) {
      // Hepsi tamam: kartı kalıcı olarak kapat
      WidgetsBinding.instance.addPostFrameCallback((_) => finishOnboarding(ref));
      return const SizedBox.shrink();
    }
    final t = L10n.of(context);
    final p = context.palette;
    const labels = ['onb.step_avatar', 'onb.step_about', 'onb.step_gear', 'onb.step_photo'];
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(Radii.card)),
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
                    Text(t('onb.card_title'), style: font(17, weight: 700)),
                    const SizedBox(height: 2),
                    Text(
                      t('onb.card_lead', {'done': done, 'total': steps.length}),
                      style: font(13, color: p.inkMuted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: t('onb.dismiss'),
                visualDensity: VisualDensity.compact,
                icon: Icon(LucideIcons.x, size: 18, color: p.inkSubtle),
                onPressed: () => finishOnboarding(ref),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 10, 8, 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.pill),
              child: LinearProgressIndicator(
                value: done / steps.length,
                minHeight: 6,
                backgroundColor: p.surface2,
                color: p.accent,
              ),
            ),
          ),
          for (final (i, ok) in steps.indexed)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: ok ? null : () => i == 3 ? context.push('/upload') : context.push('/onboarding?step=$i'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ok ? p.accent : null,
                        border: ok ? null : Border.all(color: p.ringIdle, width: 2),
                      ),
                      child: ok ? Icon(LucideIcons.check, size: 14, color: p.accentInk) : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t(labels[i]),
                        style: ok
                            ? font(14.5, color: p.inkSubtle).copyWith(decoration: TextDecoration.lineThrough)
                            : font(14.5, weight: 600),
                      ),
                    ),
                    if (!ok) Icon(LucideIcons.chevronRight, size: 18, color: p.inkSubtle),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
