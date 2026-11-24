import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/design.dart';
import 'feed_screen.dart' show loadMoreOnScroll;

const critiqueCriteria = ['composition', 'light', 'focus', 'editing'];

const _good = Color(0xFF1A7F45);
const _orangeBg = Color(0xFFFFF3E0);
const _orange = Color(0xFFB45309);

/// "Eleştiriye açık" rozeti.
class CritiqueBadge extends StatelessWidget {
  const CritiqueBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: const ShapeDecoration(color: _orangeBg, shape: StadiumBorder()),
    child: Text(L10n.of(context)('critique.open_badge'), style: font(11.5, weight: 700, color: _orange)),
  );
}

/// Ölçüt satırı: etiket, 5 bölmeli çubuk ve puan.
class _CriterionBar extends StatelessWidget {
  const _CriterionBar({required this.label, required this.value, this.text});
  final String label;
  final double value;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: '$label ${text ?? value.round()}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 108,
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: font(13.5, color: p.inkMuted)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Row(
                children: [
                  for (var i = 0; i < 5; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      child: Container(
                        height: 8,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(999)),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: (value - i).clamp(0.0, 1.0),
                          child: ColoredBox(color: p.accent),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(
              width: 30,
              child: Text(text ?? '${value.round()}', textAlign: TextAlign.right,
                  style: font(13, weight: 700, color: p.ink, tabular: true)),
            ),
          ],
        ),
      ),
    );
  }
}

String _avg(double? v, String locale) {
  if (v == null) return '—';
  final s = v.toStringAsFixed(1);
  return locale == 'tr' ? s.replaceAll('.', ',') : s;
}

/// Fotoğrafın eleştirileri: fotoğrafçının sorusu, ortalamalar, eleştiriler, yaz/düzenle.
class CritiqueScreen extends ConsumerWidget {
  const CritiqueScreen({super.key, required this.photoId});
  final String photoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    final locale = t.locale.languageCode;
    final photo = ref.watch(photoProvider(photoId)).asData?.value;
    final async = ref.watch(critiquesProvider(photoId));
    final list = async.asData?.value;
    final me = ref.watch(authProvider).asData?.value;
    final isOwner = photo != null && photo.user.id == me?.id;

    return Scaffold(
      appBar: pageBar(context, t('critique.title')),
      bottomNavigationBar: list == null || (!list.canCritique && list.myCritique == null)
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                child: Material(
                  color: p.surface,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => showCritiqueSheet(context, ref, photoId, list.myCritique),
                    child: SizedBox(
                      height: 50,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 6, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                t(list.myCritique == null ? 'critique.write_hint' : 'critique.yours_hint'),
                                style: font(14.5, color: p.inkSubtle),
                              ),
                            ),
                            Container(
                              height: 38,
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              alignment: Alignment.center,
                              decoration: ShapeDecoration(color: p.accent, shape: const StadiumBorder()),
                              child: Text(
                                t(list.myCritique == null ? 'critique.rate_write' : 'critique.edit_mine'),
                                style: font(13.5, weight: 700, color: p.accentInk),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(critiquesProvider(photoId)),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (photo != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => context.push('/p/$photoId'),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 64,
                        height: 64,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: ContainPhoto(url: photo.thumb?.url, background: p.surface),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(photo.title ?? t('critique.untitled'), maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: font(15, weight: 700, color: p.ink)),
                            Text(
                              photo.critiqueRequested
                                  ? t('critique.asks', {'name': photo.user.displayName})
                                  : photo.user.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: font(13, color: p.inkMuted),
                            ),
                            if (photo.critiqueRequested) ...[const SizedBox(height: 4), const CritiqueBadge()],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (list == null && async.hasError)
              ErrorView(error: async.error!, onRetry: () => ref.invalidate(critiquesProvider(photoId)))
            else if (list == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else ...[
              if (list.critiqueQuestion != null)
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('critique.question').toUpperCase(),
                          style: font(12, weight: 700, spacing: 0.3, color: p.inkMuted)),
                      const SizedBox(height: 4),
                      Text(list.critiqueQuestion!, style: font(14.5, height: 1.4, color: p.ink)),
                    ],
                  ),
                ),
              if (list.count > 0)
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(t('critique.averages'), style: font(15, weight: 700, color: p.ink)),
                          ),
                          Text(
                            '${_avg(list.averages['overall'], locale)} · ${t('critique.count', {'count': list.count})}',
                            style: font(13, weight: 600, color: p.inkMuted, tabular: true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      for (final c in critiqueCriteria)
                        _CriterionBar(
                          label: t('critique.c_$c'),
                          value: list.averages[c] ?? 0,
                          text: _avg(list.averages[c], locale),
                        ),
                    ],
                  ),
                ),
              if (!list.critiqueRequested && list.count == 0)
                SectionCard(
                  child: Text(
                    t(isOwner ? 'critique.closed_owner' : 'critique.closed'),
                    style: font(14, color: p.inkMuted),
                  ),
                )
              else if (list.items.isEmpty)
                SectionCard(
                  child: Text(
                    t(isOwner ? 'critique.empty_owner' : 'critique.empty'),
                    style: font(14, color: p.inkMuted),
                  ),
                ),
              for (final c in list.items) _CritiqueCard(c: c, photoId: photoId),
            ],
          ],
        ),
      ),
    );
  }
}

class _CritiqueCard extends ConsumerWidget {
  const _CritiqueCard({required this.c, required this.photoId});
  final Critique c;
  final String photoId;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final t = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        content: Text(t('critique.delete_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(t('common.cancel'))),
          TextButton(onPressed: () => Navigator.pop(d, true), child: Text(t('common.delete'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(critiquesProvider(photoId).notifier).remove(c);
    } catch (e) {
      if (context.mounted) toast(context, errorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    final specialties = c.authorSpecialties.take(2).map((s) => t('specialties.$s')).join(', ');
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => context.push('/u/${c.user.username}'),
                child: Avatar(name: c.user.displayName, url: c.user.avatarUrl, size: 34),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: c.user.displayName, style: font(14.5, weight: 700, color: p.ink)),
                    if (specialties.isNotEmpty)
                      TextSpan(text: ' · $specialties', style: font(12, color: p.inkMuted)),
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (c.mine)
                Text(t('critique.helpful_n', {'count': c.helpfulCount}), style: font(12, weight: 700, color: p.inkMuted))
              else
                Semantics(
                  button: true,
                  toggled: c.helpfulByMe,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () async {
                      try {
                        await ref.read(critiquesProvider(photoId).notifier).toggleHelpful(c);
                      } catch (e) {
                        if (context.mounted) toast(context, errorText(context, e));
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: ShapeDecoration(
                        color: c.helpfulByMe ? const Color(0x1F1A7F45) : Colors.transparent,
                        shape: const StadiumBorder(),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.thumbsUp, size: 14, color: c.helpfulByMe ? _good : p.inkMuted),
                          const SizedBox(width: 4),
                          Text(
                            t('critique.helpful_n', {'count': c.helpfulCount}),
                            style: font(12, weight: 700, color: c.helpfulByMe ? _good : p.inkMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (c.canDelete)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: t('common.delete'),
                  icon: Icon(LucideIcons.trash2, size: 17, color: p.inkMuted),
                  onPressed: () => _delete(context, ref),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (final e in c.scores.entries) _CriterionBar(label: t('critique.c_${e.key}'), value: e.value.toDouble()),
          if (c.good != null || c.improve != null) ...[
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                style: font(14, height: 1.45, color: p.ink),
                children: [
                  if (c.good != null) ...[
                    TextSpan(text: '${t('critique.good')}: ', style: font(14, weight: 700, height: 1.45, color: p.ink)),
                    TextSpan(text: c.good),
                  ],
                  if (c.good != null && c.improve != null) const TextSpan(text: '\n'),
                  if (c.improve != null) ...[
                    TextSpan(text: '${t('critique.improve')}: ', style: font(14, weight: 700, height: 1.45, color: p.ink)),
                    TextSpan(text: c.improve),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Eleştiri yazma / düzenleme: her ölçüt için 1–5, iyi yanlar ve öneri.
Future<void> showCritiqueSheet(BuildContext context, WidgetRef ref, String photoId, Critique? mine) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CritiqueSheet(photoId: photoId, mine: mine),
  );
}

class _CritiqueSheet extends ConsumerStatefulWidget {
  const _CritiqueSheet({required this.photoId, this.mine});
  final String photoId;
  final Critique? mine;

  @override
  ConsumerState<_CritiqueSheet> createState() => _CritiqueSheetState();
}

class _CritiqueSheetState extends ConsumerState<_CritiqueSheet> {
  late final Map<String, int> _scores = {...?widget.mine?.scores};
  late final _good = TextEditingController(text: widget.mine?.good);
  late final _improve = TextEditingController(text: widget.mine?.improve);
  bool _busy = false;

  @override
  void dispose() {
    _good.dispose();
    _improve.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() call) async {
    setState(() => _busy = true);
    try {
      await call();
      if (mounted) Navigator.pop(context);
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
    final ctrl = ref.read(critiquesProvider(widget.photoId).notifier);
    final complete = critiqueCriteria.every(_scores.containsKey);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t(widget.mine == null ? 'critique.write_title' : 'critique.edit_title'),
                style: font(18, weight: 700, color: p.ink)),
            const SizedBox(height: 4),
            Text(t('critique.scale_hint'), style: font(13, color: p.inkMuted)),
            const SizedBox(height: 12),
            for (final c in critiqueCriteria)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(width: 112, child: Text(t('critique.c_$c'), style: font(14, color: p.ink))),
                    Expanded(
                      child: Row(
                        children: [
                          for (var v = 1; v <= 5; v++) ...[
                            if (v > 1) const SizedBox(width: 5),
                            Expanded(
                              child: Semantics(
                                button: true,
                                selected: _scores[c] == v,
                                label: '${t('critique.c_$c')} $v',
                                excludeSemantics: true,
                                child: Material(
                                  color: (_scores[c] ?? 0) >= v ? p.accent : p.surface2,
                                  borderRadius: BorderRadius.circular(10),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () => setState(() => _scores[c] = v),
                                    child: SizedBox(
                                      height: 36,
                                      child: Center(
                                        child: Text(
                                          '$v',
                                          style: font(14, weight: 700, color: (_scores[c] ?? 0) >= v ? p.accentInk : p.inkMuted),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            TextField(
              controller: _good,
              maxLength: 1000,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(labelText: t('critique.good'), hintText: t('critique.good_hint')),
            ),
            TextField(
              controller: _improve,
              maxLength: 1000,
              minLines: 2,
              maxLines: 6,
              decoration: InputDecoration(labelText: t('critique.improve'), hintText: t('critique.improve_hint')),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: !complete || _busy
                  ? null
                  : () => _run(() => ctrl.save({
                        ..._scores,
                        'good': _good.text.trim().isEmpty ? null : _good.text.trim(),
                        'improve': _improve.text.trim().isEmpty ? null : _improve.text.trim(),
                      })),
              child: BusyLabel(busy: _busy, label: t('critique.send')),
            ),
            if (widget.mine != null)
              TextButton(
                onPressed: _busy ? null : () => _run(ctrl.deleteMine),
                child: Text(t('critique.delete_mine'), style: TextStyle(color: p.danger)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Eleştiri bekleyen kareler.
class CritiqueRequestsScreen extends ConsumerWidget {
  const CritiqueRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    const key = 'critiques/requests';
    final pages = ref.watch(cursorPhotosProvider(key));
    final ctrl = ref.read(cursorPhotosProvider(key).notifier);
    return Scaffold(
      appBar: pageBar(context, t('critique.requests_title'), sub: t('critique.requests_sub')),
      body: RefreshIndicator(
        onRefresh: ctrl.refresh,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) => loadMoreOnScroll(n, ctrl.loadMore),
          child: ListView(
            padding: const EdgeInsets.only(top: 4, bottom: 32),
            children: [
              if (pages.initialLoading)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
              else if (pages.items.isEmpty && pages.error != null)
                ErrorView(error: pages.error!, onRetry: ctrl.refresh)
              else if (pages.items.isEmpty)
                SectionCard(child: Text(t('critique.requests_empty'), style: font(15, color: p.inkMuted)))
              else
                for (final ph in pages.items) _RequestCard(photo: ph),
              if (pages.loading && pages.items.isNotEmpty)
                const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.photo});
  final PhotoCard photo;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final img = photo.feed ?? photo.thumb;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: SurfaceCard(
        radius: 22,
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: () => context.push('/p/${photo.id}/critiques'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (img != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: AspectRatio(
                    aspectRatio: img.ratio,
                    child: ContainPhoto(url: img.url, semanticLabel: photo.title),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Avatar(name: photo.user.displayName, url: photo.user.avatarUrl, size: 28),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(photo.user.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: font(14, weight: 700, color: p.ink)),
                        ),
                        Text(t('critique.count', {'count': photo.critiqueCount}), style: font(12.5, color: p.inkMuted)),
                      ],
                    ),
                    if (photo.title != null) ...[
                      const SizedBox(height: 6),
                      Text(photo.title!, style: font(15, weight: 700, color: p.ink)),
                    ],
                    if (photo.critiqueQuestion != null) ...[
                      const SizedBox(height: 4),
                      Text('“${photo.critiqueQuestion!}”', style: font(14, height: 1.4, color: p.ink)),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const CritiqueBadge(),
                        const Spacer(),
                        Text(t('critique.give'), style: font(14, weight: 700, color: p.accentText)),
                        Icon(LucideIcons.chevronRight, size: 18, color: p.accentText),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Yükleme ve düzenlemede "Eleştiriye açık" anahtarı ve fotoğrafçının sorusu.
class CritiqueToggle extends StatelessWidget {
  const CritiqueToggle({super.key, required this.value, required this.question, required this.onChanged});
  final bool value;
  final TextEditingController question;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ToggleRow(title: t('critique.open_toggle'), sub: t('critique.open_toggle_hint'), value: value, onChanged: onChanged),
        if (value)
          TextField(
            controller: question,
            maxLength: 300,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(labelText: t('critique.question_label'), hintText: t('critique.question_hint')),
          ),
      ],
    );
  }
}
