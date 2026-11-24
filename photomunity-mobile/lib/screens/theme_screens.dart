import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/community_widgets.dart';
import '../widgets/design.dart';
import '../widgets/justified_wall.dart';
import 'feed_screen.dart' show loadMoreOnScroll;

/// "23–30 Kasım" / "28 Kas – 5 Ara"
String themeRange(WeeklyTheme th, String locale) {
  final a = th.startsAt, b = th.endsAt;
  if (a.month == b.month && a.year == b.year) return '${a.day}–${DateFormat.MMMMd(locale).format(b)}';
  return '${DateFormat.MMMd(locale).format(a)} – ${DateFormat.MMMd(locale).format(b)}';
}

/// Haftanın teması: süren tema (id yoksa) ya da belirli bir tema.
class WeeklyThemeScreen extends ConsumerStatefulWidget {
  const WeeklyThemeScreen({super.key, this.id});
  final String? id;

  @override
  ConsumerState<WeeklyThemeScreen> createState() => _WeeklyThemeScreenState();
}

class _WeeklyThemeScreenState extends ConsumerState<WeeklyThemeScreen> {
  String _sort = 'top';
  bool _busy = false;

  void _refreshTheme(WeeklyTheme th) {
    widget.id == null ? ref.invalidate(currentThemeProvider) : ref.invalidate(themeProvider(th.id));
    ref.invalidate(themeEntriesProvider);
  }

  Future<void> _enter(WeeklyTheme th) async {
    final t = L10n.of(context);
    final photo = await pickMyPhoto(context, ref, t('theme.pick_photo'));
    if (photo == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).post<dynamic>('/themes/${th.id}/entries', {'photo_id': photo.id});
      _refreshTheme(th);
      if (mounted) toast(context, t('theme.entered'));
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdraw(WeeklyTheme th) async {
    final t = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(t('theme.withdraw_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('common.cancel'))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(t('theme.withdraw'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).delete<dynamic>('/themes/${th.id}/entries/me');
      _refreshTheme(th);
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _rules() {
    final t = L10n.of(context);
    final p = context.palette;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t('theme.rules'), style: font(18, weight: 700, color: p.ink)),
              const SizedBox(height: 10),
              for (final k in ['one', 'own', 'likes', 'withdraw', 'badge'])
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Icon(LucideIcons.check, size: 16, color: p.accentText),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(t('theme.rule_$k'), style: font(14.5, height: 1.4, color: p.ink))),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final async = widget.id == null
        ? ref.watch(currentThemeProvider)
        : ref.watch(themeProvider(widget.id!)).whenData<WeeklyTheme?>((v) => v);
    return Scaffold(
      appBar: pageBar(context, t('theme.title'), sub: t('theme.sub'), intro: 'themes'),
      body: async.hasValue
          ? _body(context, async.requireValue)
          : async.hasError
          ? ErrorView(
              error: async.error!,
              onRetry: () => widget.id == null ? ref.invalidate(currentThemeProvider) : ref.invalidate(themeProvider(widget.id!)),
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _body(BuildContext context, WeeklyTheme? th) {
    final t = L10n.of(context);
    final p = context.palette;
    final past = ref.watch(pastThemesProvider).asData?.value ?? const <WeeklyTheme>[];
    final last = past.where((x) => x.winner != null && x.id != th?.id).firstOrNull;
    final entries = th == null ? null : ref.watch(themeEntriesProvider((th.id, _sort)));
    return RefreshIndicator(
      onRefresh: () async {
        if (th != null) _refreshTheme(th);
        if (th == null) ref.invalidate(currentThemeProvider);
        ref.invalidate(pastThemesProvider);
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) =>
            th == null ? false : loadMoreOnScroll(n, ref.read(themeEntriesProvider((th.id, _sort)).notifier).loadMore),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (th == null)
              SliverToBoxAdapter(
                child: SectionCard(
                  margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(LucideIcons.calendarClock, color: p.ink),
                      const SizedBox(height: 10),
                      Text(t('theme.none'), style: font(16, weight: 700, color: p.ink)),
                      const SizedBox(height: 4),
                      Text(t('theme.none_body'), style: font(14, color: p.inkMuted)),
                    ],
                  ),
                ),
              )
            else ...[
              SliverToBoxAdapter(child: _hero(context, th)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                sliver: SliverToBoxAdapter(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in ['top', 'new', 'following'])
                        PillChip(label: t('theme.sort_$s'), selected: _sort == s, onTap: () => setState(() => _sort = s)),
                    ],
                  ),
                ),
              ),
              if (entries == null || entries.initialLoading)
                const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
                )
              else if (entries.items.isEmpty && entries.error != null)
                SliverToBoxAdapter(
                  child: ErrorView(
                    error: entries.error!,
                    onRetry: () => ref.read(themeEntriesProvider((th.id, _sort)).notifier).refresh(),
                  ),
                )
              else if (entries.items.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    child: Text(t(_sort == 'following' ? 'theme.empty_following' : 'theme.empty'),
                        style: font(15, color: p.inkMuted)),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: _EntryWall(entries: entries.items, showRank: _sort == 'top'),
                ),
            ],
            if (last != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Material(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => context.push('/themes/${last.id}'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            const Text('🏆', style: TextStyle(fontSize: 20)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(t('theme.last_week', {'title': last.title}),
                                      style: font(13.5, weight: 700, color: p.ink)),
                                  Text(
                                    t('theme.last_winner', {'user': last.winner!.photo.user.username}),
                                    style: font(13.5, color: p.inkMuted),
                                  ),
                                ],
                              ),
                            ),
                            Icon(LucideIcons.chevronRight, size: 20, color: p.inkSubtle),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  Widget _hero(BuildContext context, WeeklyTheme th) {
    final t = L10n.of(context);
    final locale = t.locale.languageCode;
    final left = remainingText(th.endsAt, locale);
    final cover = th.winner?.photo ?? th.myEntry?.photo;
    final status = switch (th.status) {
      'active' => t('theme.left', {'time': left}),
      'scheduled' => t('theme.starts', {'date': DateFormat.MMMMd(locale).format(th.startsAt)}),
      'ended' => t('theme.ending'),
      _ => t('theme.finished'),
    };
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: const Color(0xFF14161B), borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 150,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF2B2370), Color(0xFF0D0B24)],
                    ),
                  ),
                ),
                // Kazanan (ya da kendi katılımın) kırpılmadan
                if (cover?.feed != null) NetPhoto(url: cover!.feed!.url, fit: BoxFit.contain),
                Positioned(
                  left: 14,
                  top: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(999)),
                    child: Text('#${th.number} · ${themeRange(th, locale)}',
                        style: font(12, weight: 700, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(th.title, style: font(22, weight: 700, color: Colors.white)),
                if (th.description != null) ...[
                  const SizedBox(height: 2),
                  Text(th.description!, style: font(13.5, height: 1.4, color: Colors.white.withValues(alpha: 0.75))),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${th.entryCount}', style: font(13, weight: 700, color: Colors.white)),
                        TextSpan(text: ' ${t('theme.entries')}', style: font(13, color: Colors.white)),
                      ]),
                    ),
                    Text(status, style: font(13, weight: 700, color: Colors.white)),
                  ],
                ),
                if (th.winner != null) ...[
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () => context.push('/p/${th.winner!.photo.id}'),
                    child: Text(
                      t('theme.winner', {'user': th.winner!.photo.user.username}),
                      style: font(13.5, weight: 700, color: const Color(0xFFFFD27A)),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (th.active)
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: th.myEntry == null
                              ? FilledButton(
                                  style: FilledButton.styleFrom(shape: const StadiumBorder()),
                                  onPressed: _busy ? null : () => _enter(th),
                                  child: BusyLabel(busy: _busy, label: t('theme.submit')),
                                )
                              : FilledButton(
                                  style: FilledButton.styleFrom(
                                    shape: const StadiumBorder(),
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF14161B),
                                  ),
                                  onPressed: _busy ? null : () => _withdraw(th),
                                  child: BusyLabel(busy: _busy, label: t('theme.entered_withdraw')),
                                ),
                        ),
                      )
                    else
                      const Spacer(),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 46,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          shape: const StadiumBorder(),
                          backgroundColor: Colors.white.withValues(alpha: 0.12),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _rules,
                        child: Text(t('theme.rules')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Katılımlar: kırpılmadan, gerçek oranlarla satırlar; "En beğenilen"de ilk üç sıra rozeti.
class _EntryWall extends StatelessWidget {
  const _EntryWall({required this.entries, required this.showRank});
  final List<ThemeEntry> entries;
  final bool showRank;

  @override
  Widget build(BuildContext context) {
    final rank = {for (final e in entries) e.photo.id: e.rank};
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final rows = buildRows([for (final e in entries) e.photo], constraints.crossAxisExtent, 150);
        return SliverList.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 4),
          itemBuilder: (context, i) {
            final row = rows[i];
            return SizedBox(
              height: row.height,
              child: Row(
                children: [
                  for (final (index, (photo, w)) in row.items.indexed) ...[
                    if (index > 0) const SizedBox(width: 4),
                    SizedBox(
                      width: w,
                      child: GestureDetector(
                        onTap: () => context.push('/p/${photo.id}'),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              NetPhoto(url: (photo.thumb ?? photo.feed)!.url, semanticLabel: photo.title ?? photo.user.displayName),
                              if (showRank && (rank[photo.id] ?? 99) <= 3)
                                Positioned(
                                  left: 6,
                                  top: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.55),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text('#${rank[photo.id]}', style: font(11, weight: 700, color: Colors.white)),
                                  ),
                                ),
                              Positioned(
                                right: 6,
                                bottom: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(LucideIcons.heart, size: 11, color: Colors.white),
                                      const SizedBox(width: 3),
                                      Text('${photo.likeCount}', style: font(10.5, weight: 700, color: Colors.white, tabular: true)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Akış ve Keşfet'te süren temaya kısayol; tema yoksa görünmez.
class ThemeBanner extends ConsumerWidget {
  const ThemeBanner({super.key, this.padding = const EdgeInsets.fromLTRB(12, 0, 12, 14)});
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final th = ref.watch(currentThemeProvider).asData?.value;
    if (th == null) return const SizedBox.shrink();
    final t = L10n.of(context);
    final left = remainingText(th.endsAt, t.locale.languageCode);
    return Padding(
      padding: padding,
      child: Material(
        borderRadius: BorderRadius.circular(Radii.card),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF2B2370), Color(0xFF0D0B24)]),
          ),
          child: InkWell(
            onTap: () => context.push('/themes'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(LucideIcons.trophy, color: Color(0xFFFFD27A), size: 21),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${t('theme.title').toUpperCase()} · #${th.number}',
                            style: font(11.5, weight: 700, spacing: 0.3, color: Colors.white70)),
                        Text(th.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: font(17, weight: 700, color: Colors.white)),
                        Text(
                          [
                            '${th.entryCount} ${t('theme.entries')}',
                            if (th.active && left.isNotEmpty) t('theme.left', {'time': left}),
                          ].join(' · '),
                          style: font(12.5, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  const Icon(LucideIcons.chevronRight, color: Colors.white70),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Profilde tema rozeti: kazanılan tema sayısı; dokununca kazanılan temalar.
class ThemeWinBadge extends StatelessWidget {
  const ThemeWinBadge({super.key, required this.username, required this.count});
  final String username;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    return Semantics(
      button: true,
      label: t('theme.wins_badge', {'count': count}),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => _ThemeWins(username: username),
        ),
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: const ShapeDecoration(color: Color(0xFFFFF3E0), shape: StadiumBorder()),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.trophy, size: 13, color: Color(0xFFB45309)),
              const SizedBox(width: 4),
              Text(
                count > 1 ? t('theme.wins_short', {'count': count}) : t('theme.win_short'),
                style: font(12, weight: 700, color: const Color(0xFFB45309)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeWins extends ConsumerWidget {
  const _ThemeWins({required this.username});
  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    final async = ref.watch(themeWinsProvider(username));
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(t('theme.wins_title'), style: font(18, weight: 700, color: p.ink)),
            ),
            Expanded(
              child: switch (async) {
                AsyncData(:final value) => ListView(
                  children: [
                    for (final w in value)
                      ListTile(
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/themes/${w.themeId}');
                        },
                        leading: SizedBox(
                          width: 56,
                          height: 56,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: ContainPhoto(url: w.photo.thumb?.url),
                          ),
                        ),
                        title: Text('#${w.number} · ${w.title}', style: font(15, weight: 700, color: p.ink)),
                        subtitle: Text(t('theme.win_likes', {'count': w.likeCount}), style: font(13, color: p.inkMuted)),
                      ),
                  ],
                ),
                AsyncError(:final error) => ErrorView(error: error),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
          ],
        ),
      ),
    );
  }
}
