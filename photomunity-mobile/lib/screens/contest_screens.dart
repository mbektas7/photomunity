import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/community_widgets.dart';
import '../widgets/design.dart';

class ContestScreen extends ConsumerStatefulWidget {
  const ContestScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<ContestScreen> createState() => _ContestScreenState();
}

class _ContestScreenState extends ConsumerState<ContestScreen> {
  bool _busy = false;
  final _scroll = ScrollController();
  final _resultsKey = GlobalKey();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// "Tüm sonuçlar": sonuç listesine kaydır. Liste tembel kurulduğu için henüz
  /// çizilmemişse önce aşağı ilerleyip yeniden dener.
  Future<void> _scrollToResults([int attempt = 0]) async {
    final ctx = _resultsKey.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    if (!_scroll.hasClients || attempt > 4) return;
    final pos = _scroll.position;
    _scroll.jumpTo((pos.pixels + pos.viewportDimension).clamp(0, pos.maxScrollExtent));
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) await _scrollToResults(attempt + 1);
  }

  Future<void> _enter() async {
    final t = L10n.of(context);
    final photo = await pickMyPhoto(context, ref, t('contest.pick_entry'));
    if (photo == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).post<dynamic>(
        '/contests/${widget.id}/entries',
        {'photo_id': photo.id},
      );
      ref.invalidate(contestProvider(widget.id));
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdraw() async {
    final t = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(t('contest.withdraw_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(t('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(t('contest.withdraw')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(apiProvider)
          .delete<dynamic>('/contests/${widget.id}/entries/me');
      ref.invalidate(contestProvider(widget.id));
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    }
  }

  Future<void> _share(Contest c) async {
    await Clipboard.setData(ClipboardData(text: c.shareUrl));
    if (mounted) toast(context, L10n.of(context)('contest.link_copied'));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(contestProvider(widget.id));
    final c = async.asData?.value;
    final t = L10n.of(context);
    final publicVoting = c != null && c.status == 'judging' && c.judgingMode == 'public';
    final p = context.palette;
    // Çizimde yarışma içeriği beyaz (surface) bir yaprak üzerinde; kutular surface-2.
    return Scaffold(
      backgroundColor: p.surface,
      appBar: AppBar(
        backgroundColor: p.surface,
        toolbarHeight: 72,
        leadingWidth: 76,
        leading: Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Center(
            child: RoundIconButton(
              icon: LucideIcons.chevronLeft,
              label: t('ui.back'),
              color: p.surface2,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
        actions: [
          if (c?.myRole == 'admin')
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: RoundIconButton(
                icon: LucideIcons.slidersHorizontal,
                label: t('manage.title'),
                color: p.surface2,
                onPressed: () => context.push('/contests/${widget.id}/manage'),
              ),
            ),
          if (c != null)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: RoundIconButton(
                icon: LucideIcons.share2,
                label: t('contest.share'),
                color: p.surface2,
                onPressed: () => _share(c),
              ),
            ),
        ],
      ),
      body: async.hasValue
          ? _body(context, async.requireValue)
          : async.hasError
          ? ErrorView(
              error: async.error!,
              onRetry: () => ref.invalidate(contestProvider(widget.id)),
            )
          : const Center(child: CircularProgressIndicator()),
      bottomNavigationBar: publicVoting
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: LargeButton(
                label: t('contest.start_voting'),
                icon: LucideIcons.star,
                onPressed: () => _startVoting(c),
              ),
            )
          : null,
    );
  }

  void _startVoting(Contest c) {
    final list = ref.read(entriesProvider(c.id)).asData?.value ?? const <Entry>[];
    final votable = list.where((e) => !e.mine).toList();
    if (votable.isEmpty) return;
    final first = votable.firstWhere((e) => e.myStars == null, orElse: () => votable.first);
    showVoteSheet(context, c.id, list.indexOf(first));
  }

  Widget _body(BuildContext context, Contest c) {
    final t = L10n.of(context);
    final p = context.palette;
    final locale = t.locale.languageCode;
    final next = contestNextMoment(c);
    final countdownLabel = switch (c.status) {
      'judging' => t('contest.countdown_voting'),
      'closed' => t('contest.countdown_results'),
      _ => t('contest.countdown_deadline'),
    };
    Widget section(String title, Widget child) => SurfaceCard(
      color: p.surface2,
      padding: const EdgeInsets.all(Space.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.heading(p.ink)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(contestProvider(widget.id));
        ref.invalidate(entriesProvider(widget.id));
      },
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(Space.s5, 4, Space.s5, 32),
        children: [
          if (c.status == 'finished')
            _Winners(contest: c, onAllResults: _scrollToResults),
          // Yarışma kapak görseli API'de yok; başlık bölümü görselsiz.
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusBadge(status: c.status, mode: c.judgingMode),
              InkWell(
                borderRadius: BorderRadius.circular(Radii.box),
                onTap: () => context.push('/c/${c.community.slug}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    c.community.name,
                    style: font(15, color: p.inkMuted),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(c.title, style: AppText.display(p.ink).copyWith(fontSize: 40, height: 1.05)),
          const SizedBox(height: Space.s5),
          if (next != null && next.isAfter(DateTime.now())) ...[
            Countdown(until: next, srLabel: countdownLabel),
            const SizedBox(height: Space.s6),
          ],
          _phase(context, c, locale),
          const SizedBox(height: Space.s6),
          SurfaceCard(
            color: p.surface2,
            padding: const EdgeInsets.all(Space.s5),
            child: ContestTimeline(c: c),
          ),
          const SizedBox(height: Space.s3),
          if (c.prizes.isNotEmpty) ...[
            section(
              t('contest.prizes'),
              Column(
                children: [
                  for (final pr in c.prizes)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: p.ringIdle.withValues(alpha: 0.5))),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: p.surface, shape: BoxShape.circle),
                            child: Text('${pr.rank}', style: font(13, weight: 700, color: p.ink, tabular: true)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: Text(pr.title, style: AppText.body(p.ink))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.s3),
          ],
          section(
            t('contest.about'),
            Text(c.description, style: font(15, height: 1.55, color: p.inkMuted)),
          ),
          if (c.rules != null) ...[
            const SizedBox(height: Space.s3),
            section(
              t('contest.rules'),
              Text(c.rules!, style: font(15, height: 1.55, color: p.inkMuted)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _panel(Palette p, List<Widget> children) => Container(
    padding: const EdgeInsets.all(Space.s5),
    decoration: BoxDecoration(
      color: p.surface2,
      borderRadius: BorderRadius.circular(Radii.card),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );

  Widget _phase(BuildContext context, Contest c, String locale) {
    final t = L10n.of(context);
    final p = context.palette;
    switch (c.status) {
      case 'open' || 'draft':
        if (c.myEntry != null) {
          final img = c.myEntry!.feed;
          return _panel(p, [
            if (img != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.photo),
                child: AspectRatio(
                  aspectRatio: img.ratio,
                  child: NetPhoto(url: img.url),
                ),
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(LucideIcons.check, color: p.accent, size: 20),
                const SizedBox(width: 6),
                Text(
                  t('contest.you_entered'),
                  style: font(16, weight: 600, color: p.ink),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              t('contest.entered_body'),
              style: font(14.5, height: 1.45, color: p.inkMuted),
            ),
            TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: _withdraw,
              child: Text(t('contest.withdraw')),
            ),
          ]);
        }
        return _panel(p, [
          Text(t('contest.enter_title'), style: AppText.title(p.ink)),
          const SizedBox(height: 6),
          Text(
            t('contest.enter_body'),
            style: font(15, height: 1.45, color: p.inkMuted),
          ),
          const SizedBox(height: 16),
          LargeButton(
            label: t('contest.enter_cta'),
            busy: _busy,
            onPressed: c.status == 'draft' ? null : _enter,
          ),
        ]);
      case 'judging' when c.judgingMode == 'public':
        return _Voting(contestId: c.id);
      case 'judging':
        return _panel(p, [
          Text(
            t('contest.jury_title'),
            style: font(17, weight: 600, color: p.ink),
          ),
          const SizedBox(height: 4),
          Text(
            t('contest.jury_body'),
            style: font(15, height: 1.45, color: p.inkMuted),
          ),
          if (c.isJudge) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.push('/contests/${c.id}/jury'),
              child: Text(t('contest.start_judging')),
            ),
          ],
        ]);
      case 'closed':
        return _panel(p, [
          Text(
            t('contest.closed_title'),
            style: font(17, weight: 600, color: p.ink),
          ),
          const SizedBox(height: 4),
          Text(
            t('contest.closed_body', {
              'date': DateFormat.yMMMMd(locale).add_Hm().format(c.resultsAt),
            }),
            style: font(15, color: p.inkMuted),
          ),
        ]);
      default:
        return KeyedSubtree(key: _resultsKey, child: _Results(contestId: c.id));
    }
  }
}

class _Voting extends ConsumerWidget {
  const _Voting({required this.contestId});
  final String contestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    final entries = ref.watch(entriesProvider(contestId));
    return switch (entries) {
      AsyncData(:final value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(t('contest.entries_title'), style: AppText.title(p.ink)),
              const Spacer(),
              Text(
                [
                  t('contest.entries_n', {'count': value.length}),
                  t('contest.my_votes', {
                    'count': value.where((e) => !e.mine && e.myStars != null).length,
                  }),
                ].join(', '),
                style: font(15, color: p.inkMuted, tabular: true),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (value.isEmpty)
            Text(t('contest.no_entries'), style: font(15, color: p.inkMuted))
          else
            _EntryColumns(
              entries: value,
              onOpen: (i) => showVoteSheet(context, contestId, i),
            ),
        ],
      ),
      AsyncError(:final error) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(entriesProvider(contestId)),
      ),
      _ => const Padding(
        padding: EdgeInsets.all(30),
        child: Center(child: CircularProgressIndicator()),
      ),
    };
  }
}

/// İki sütunlu duvar: her kare kendi oranında (kırpma yok), sol altta oy hapı.
class _EntryColumns extends StatelessWidget {
  const _EntryColumns({required this.entries, required this.onOpen});
  final List<Entry> entries;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final cols = [<int>[], <int>[]];
    final h = [0.0, 0.0];
    for (var i = 0; i < entries.length; i++) {
      final r = entries[i].feed?.ratio ?? 1.5;
      final c = h[0] <= h[1] ? 0 : 1;
      cols[c].add(i);
      h[c] += 1 / r;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (ci, col) in cols.indexed) ...[
          if (ci > 0) const SizedBox(width: Space.s3),
          Expanded(
            child: Column(
              children: [
                for (final i in col)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.s3),
                    child: _EntryTile(entry: entries[i], onTap: () => onOpen(i)),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});
  final Entry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = L10n.of(context);
    final img = entry.feed;
    final Widget pill = entry.mine
        ? _ScrimPill(text: t('contest.your_entry'))
        : entry.myStars != null
        ? Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: ShapeDecoration(color: p.accent, shape: const StadiumBorder()),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star_rounded, size: 18, color: p.accentInk),
                const SizedBox(width: 4),
                Text('${entry.myStars}', style: font(15, weight: 700, color: p.accentInk, tabular: true)),
              ],
            ),
          )
        : _ScrimPill(text: t('contest.vote_cta'));
    return Semantics(
      button: true,
      label: [
        entry.title,
        entry.mine
            ? t('contest.your_entry')
            : entry.myStars != null
            ? t('contest.stars', {'count': entry.myStars!})
            : t('contest.vote_cta'),
      ].whereType<String>().join(', '),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.photo),
          child: Stack(
            children: [
              AspectRatio(
                aspectRatio: img?.ratio ?? 1.5,
                child: img == null ? ColoredBox(color: p.surface2) : NetPhoto(url: img.url),
              ),
              Positioned(left: 8, bottom: 8, child: pill),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScrimPill extends StatelessWidget {
  const _ScrimPill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      alignment: Alignment.center,
      decoration: ShapeDecoration(color: p.scrim, shape: const StadiumBorder()),
      child: Text(text, style: font(14.5, weight: 700, color: p.ink)),
    );
  }
}

/// Oylama: kare kendi oranında, altında 1–5 yıldız; puanlayınca sıradakine geçer.
Future<void> showVoteSheet(BuildContext context, String contestId, int start) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _VoteSheet(contestId: contestId, start: start),
    );

class _VoteSheet extends ConsumerStatefulWidget {
  const _VoteSheet({required this.contestId, required this.start});
  final String contestId;
  final int start;

  @override
  ConsumerState<_VoteSheet> createState() => _VoteSheetState();
}

class _VoteSheetState extends ConsumerState<_VoteSheet> {
  late int _i = widget.start;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final list = ref.watch(entriesProvider(widget.contestId)).asData?.value ?? const <Entry>[];
    if (list.isEmpty) return const SizedBox(height: 200);
    final i = _i.clamp(0, list.length - 1);
    final e = list[i];
    final votable = list.where((x) => !x.mine).toList();
    final done = votable.where((x) => x.myStars != null).length;
    final img = e.full ?? e.feed;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t('contest.rated_progress', {'done': done, 'total': votable.length}),
            textAlign: TextAlign.center,
            style: font(14, weight: 600, color: p.inkMuted, tabular: true),
          ),
          const SizedBox(height: Space.s3),
          if (img != null)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.55),
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.photo),
                  child: AspectRatio(aspectRatio: img.ratio, child: NetPhoto(url: img.url, fit: BoxFit.contain)),
                ),
              ),
            ),
          const SizedBox(height: Space.s4),
          Row(
            children: [
              RoundIconButton(
                icon: LucideIcons.chevronLeft,
                label: t('contest.prev_entry'),
                onPressed: i == 0 ? null : () => setState(() => _i = i - 1),
              ),
              Expanded(
                child: Center(
                  child: e.mine
                      ? Text(t('contest.your_entry'), style: AppText.bodyStrong(p.ink))
                      : StarRating(
                          value: e.myStars,
                          onChanged: (stars) {
                            ref
                                .read(entriesProvider(widget.contestId).notifier)
                                .vote(e.id, stars)
                                .catchError((Object err) {
                                  if (context.mounted) toast(context, errorText(context, err));
                                });
                            if (i < list.length - 1) {
                              Future.delayed(const Duration(milliseconds: 250), () {
                                if (mounted) setState(() => _i = i + 1);
                              });
                            }
                          },
                        ),
                ),
              ),
              RoundIconButton(
                icon: LucideIcons.chevronRight,
                label: t('contest.next_entry'),
                onPressed: i == list.length - 1 ? null : () => setState(() => _i = i + 1),
              ),
            ],
          ),
          const SizedBox(height: Space.s2),
          Text(t('contest.vote_hint'), textAlign: TextAlign.center, style: AppText.caption(p.inkMuted)),
        ],
      ),
    );
  }
}

void _fullscreen(BuildContext context, Entry e) {
  final img = e.full;
  if (img == null) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: NetPhoto(url: img.url, fit: BoxFit.contain),
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------- kazananlar sunumu

const _gold = Color(0xFFE2B33C);
const _silver = Color(0xFFB9C0CC);
const _bronze = Color(0xFFC98B5A);
const _medalInk = Color(0xFF14161B);

Color _medalColor(int? rank) => switch (rank) {
  1 => _gold,
  2 => _silver,
  _ => _bronze,
};

String _medalLabel(L10n t, int? rank) => switch (rank) {
  1 => '🥇 ${t('winners.first')}',
  2 => '🥈 ${t('winners.second')}',
  3 => '🥉 ${t('winners.third')}',
  _ => '$rank.',
};

/// Sonuçlanan yarışmanın üstünde gece gökyüzü zeminli duyuru: birinci büyük
/// (kırpılmadan, bulanık kopyası üzerinde), ikinci ve üçüncü yan yana.
class _Winners extends ConsumerWidget {
  const _Winners({required this.contest, required this.onAllResults});
  final Contest contest;
  final VoidCallback onAllResults;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    final list = ref.watch(entriesProvider(contest.id)).asData?.value;
    if (list == null) return const SizedBox.shrink();
    final ranked = list.where((e) => !e.disqualified && e.rank != null && e.rank! <= 3).toList();
    final first = ranked.where((e) => e.rank == 1).firstOrNull;
    if (first == null) return const SizedBox.shrink();
    final rest = ranked.where((e) => e != first).take(2).toList();
    final c = contest;
    final stats = [
      if (c.entryCount > 0) t('winners.stat_entries', {'count': c.entryCount}),
      if (c.judgeCount > 0) t('winners.stat_judges', {'count': c.judgeCount}),
      if (c.voteCount > 0) t('winners.stat_votes', {'count': c.voteCount}),
    ];
    final locale = t.locale.toLanguageTag();
    final muted = Colors.white.withValues(alpha: 0.65);

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.card),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topCenter,
              radius: 1.4,
              colors: [Color(0xFF2B2370), Color(0xFF0D0F1A), Color(0xFF07080D)],
              stops: [0, 0.6, 1],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 22, 14, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t('winners.announced'),
                  textAlign: TextAlign.center,
                  style: font(12, weight: 700, spacing: 0.5, color: _gold),
                ),
                const SizedBox(height: 2),
                Text(
                  c.title,
                  textAlign: TextAlign.center,
                  style: font(26, weight: 700, spacing: -0.6, height: 1.15, color: Colors.white),
                ),
                if (stats.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    stats.join(' · '),
                    textAlign: TextAlign.center,
                    style: font(13, color: muted, tabular: true),
                  ),
                ],
                const SizedBox(height: 14),
                _FirstPhoto(entry: first, badge: _medalLabel(t, first.rank)),
                _WinnerLine(entry: first, locale: locale),
                if (rest.isNotEmpty)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < 2; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(
                          child: i < rest.length
                              ? _RunnerUp(entry: rest[i], badge: _medalLabel(t, rest[i].rank))
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Builder(
                        builder: (bctx) => FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            backgroundColor: p.accent,
                            foregroundColor: p.accentInk,
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            textStyle: font(15, weight: 700),
                          ),
                          onPressed: () => _shareWinner(bctx, first),
                          child: Text(t('winners.share'), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                          foregroundColor: Colors.white,
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          textStyle: font(15, weight: 700),
                        ),
                        onPressed: onAllResults,
                        child: Text(t('winners.all_results'), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _shareWinner(BuildContext context, Entry first) async {
    final t = L10n.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    final winner = first.user?.displayName ?? first.title ?? '';
    final text = '${t('winners.share_text', {'contest': contest.title, 'winner': winner})} · ${contest.shareUrl}';
    try {
      await SharePlus.instance.share(ShareParams(text: text, sharePositionOrigin: origin));
    } catch (e) {
      if (context.mounted) toast(context, errorText(context, e));
    }
  }
}

class _MedalBadge extends StatelessWidget {
  const _MedalBadge({required this.label, required this.color, this.small = false});
  final String label;
  final Color color;
  final bool small;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: small ? 8 : 11, vertical: small ? 3 : 5),
    decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
    child: Text(label, style: font(small ? 11 : 12, weight: 700, color: _medalInk)),
  );
}

class _FirstPhoto extends StatelessWidget {
  const _FirstPhoto({required this.entry, required this.badge});
  final Entry entry;
  final String badge;

  @override
  Widget build(BuildContext context) {
    final img = entry.feed;
    return Semantics(
      image: true,
      label: [badge, entry.title, entry.user?.displayName].whereType<String>().join(', '),
      child: GestureDetector(
        onTap: () => _fullscreen(context, entry),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: AspectRatio(
            aspectRatio: 358 / 236,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Colors.black),
                if (img != null) ...[
                  // Arka planda aynı karenin bulanık, karartılmış kopyası; kare kendisi kırpılmaz.
                  ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24, tileMode: TileMode.decal),
                    child: NetPhoto(url: img.url, fit: BoxFit.cover),
                  ),
                  const ColoredBox(color: Color(0x80000000)),
                  NetPhoto(url: img.url, fit: BoxFit.contain),
                ],
                Positioned(left: 12, top: 12, child: _MedalBadge(label: badge, color: _medalColor(entry.rank))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WinnerLine extends StatelessWidget {
  const _WinnerLine({required this.entry, required this.locale});
  final Entry entry;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final u = entry.user;
    final muted = Colors.white.withValues(alpha: 0.65);
    final gear = entry.exif?.lens ?? entry.exif?.camera;
    final sub = [if (u != null) '@${u.username}', ?gear].join(' · ');
    final name = u?.displayName ?? '';
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.box),
      onTap: u == null ? null : () => context.push('/u/${u.username}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            if (u != null) ...[
              u.avatarUrl != null
                  ? Avatar(name: name, url: u.avatarUrl, size: 36)
                  : Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: _gold, shape: BoxShape.circle),
                      child: Text(initials, style: font(13, weight: 700, color: _medalInk)),
                    ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title ?? name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: font(15, weight: 700, color: Colors.white),
                  ),
                  if (sub.isNotEmpty)
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: font(12.5, color: muted),
                    ),
                  if (entry.prize != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.trophy, size: 13, color: _gold),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              entry.prize!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: font(12.5, weight: 600, color: _gold),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (entry.score != null) ...[
              const SizedBox(width: 10),
              Semantics(
                label: t('contest.score', {'score': NumberFormat('0.00', locale).format(entry.score)}),
                excludeSemantics: true,
                child: Text(
                  NumberFormat('0.00', locale).format(entry.score),
                  style: font(16, weight: 700, color: Colors.white, tabular: true),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RunnerUp extends StatelessWidget {
  const _RunnerUp({required this.entry, required this.badge});
  final Entry entry;
  final String badge;

  @override
  Widget build(BuildContext context) {
    final img = entry.feed;
    final u = entry.user;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _fullscreen(context, entry),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.photo),
            child: SizedBox(
              height: 110,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Colors.black),
                  if (img != null) NetPhoto(url: img.url, fit: BoxFit.contain),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: _MedalBadge(label: badge, color: _medalColor(entry.rank), small: true),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: u == null ? null : () => context.push('/u/${u.username}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.title ?? u?.displayName ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: font(13, weight: 700, color: Colors.white),
              ),
              if (u != null)
                Text(
                  '@${u.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: font(12, color: Colors.white.withValues(alpha: 0.6)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.contestId});
  final String contestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    final entries = ref.watch(entriesProvider(contestId));
    return switch (entries) {
      AsyncData(:final value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.trophy, color: p.accent),
              const SizedBox(width: 8),
              Text(t('contest.results'), style: AppText.title(p.ink)),
            ],
          ),
          const SizedBox(height: 14),
          for (final e in value)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(Radii.card),
                border: e.rank == 1
                    ? Border.all(color: p.accent, width: 2)
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (e.feed != null)
                    GestureDetector(
                      onTap: () => _fullscreen(context, e),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
                        ),
                        child: AspectRatio(
                          aspectRatio: e.feed!.ratio,
                          child: NetPhoto(
                            url: e.feed!.url,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      SizedBox(
                        width: e.rank != null && e.rank! <= 3 ? 52 : 36,
                        child: Text(
                          e.rank != null ? '${e.rank}.' : '–',
                          style: font(
                            e.rank != null && e.rank! <= 3 ? 34 : 18,
                            weight: 700,
                            height: 1,
                            spacing: -1,
                            color: p.ink,
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: e.user == null
                              ? null
                              : () => context.push('/u/${e.user!.username}'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.user?.displayName ?? '',
                                style: font(15, weight: 600, color: p.ink),
                              ),
                              if (e.title != null)
                                Text(e.title!, style: font(13, color: p.inkMuted)),
                            ],
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (e.prize != null)
                            Text(
                              e.prize!,
                              style: font(14, weight: 600, color: p.accentText),
                            ),
                          if (e.score != null)
                            Text(
                              t('contest.score', {
                                'score': e.score!.toStringAsFixed(2),
                              }),
                              style: font(12.5, color: p.inkMuted),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
      AsyncError(:final error) => ErrorView(error: error),
      _ => const Padding(
        padding: EdgeInsets.all(30),
        child: Center(child: CircularProgressIndicator()),
      ),
    };
  }
}

/// Jüri ekranı: kareler tek tek, anonim, 1–10 puan; puanlayınca sıradaki puanlanmamış kareye geçer.
class JuryScreen extends ConsumerStatefulWidget {
  const JuryScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<JuryScreen> createState() => _JuryScreenState();
}

class _JuryScreenState extends ConsumerState<JuryScreen> {
  final _pages = PageController();
  final _note = TextEditingController();
  String? _noteEntryId; // _note hangi karenin notunu tutuyor
  bool _savingNote = false;
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Sayfa değişince özel not alanını o karenin kayıtlı notuyla doldur.
  void _syncNote(Entry e) {
    if (_noteEntryId == e.id) return;
    _noteEntryId = e.id;
    _note.text = e.myNote ?? '';
  }

  /// Not alanı bu kareye aitse metni (boşsa notu siler), değilse null (not korunur).
  String? _noteFor(Entry e) => _noteEntryId == e.id ? _note.text : null;

  Future<void> _saveNote(Entry e) async {
    final score = e.myScore;
    if (score == null || _savingNote) return;
    final t = L10n.of(context);
    setState(() => _savingNote = true);
    try {
      await ref
          .read(entriesProvider(widget.id).notifier)
          .score(e.id, score, note: _note.text);
      if (mounted) {
        FocusScope.of(context).unfocus();
        toast(context, t('jury.note_saved'));
      }
    } catch (err) {
      if (mounted) toast(context, errorText(context, err));
    } finally {
      if (mounted) setState(() => _savingNote = false);
    }
  }

  Future<void> _give(List<Entry> list, int value) async {
    final e = list[_index];
    if (e.mine) return;
    try {
      await ref
          .read(entriesProvider(widget.id).notifier)
          .score(e.id, value, note: _noteFor(e));
      final next = list.indexWhere(
        (x) => list.indexOf(x) > _index && x.myScore == null && !x.mine,
      );
      if (next >= 0 && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 180));
        _pages.animateToPage(
          next,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    } catch (err) {
      if (mounted) toast(context, errorText(context, err));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final entries = ref.watch(entriesProvider(widget.id));
    final list = entries.asData?.value ?? const <Entry>[];
    final scorable = list.where((e) => !e.mine).toList();
    final done = scorable.where((e) => e.myScore != null).length;
    if (list.isNotEmpty) {
      final current = list[_index.clamp(0, list.length - 1)];
      if (_noteEntryId != current.id) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _syncNote(current));
        });
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          t('jury.progress', {'done': done, 'total': scorable.length}),
          style: font(15, weight: 600, color: Colors.white),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: LinearProgressIndicator(
            value: scorable.isEmpty ? 0 : done / scorable.length,
            minHeight: 3,
          ),
        ),
      ),
      body: entries.hasError
          ? ErrorView(error: entries.error!)
          : list.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: list.length,
                    onPageChanged: (i) => setState(() {
                      _index = i;
                      _syncNote(list[i]);
                    }),
                    itemBuilder: (_, i) {
                      final img = list[i].full;
                      return img == null
                          ? const SizedBox.shrink()
                          : InteractiveViewer(
                              maxScale: 4,
                              child: Center(
                                child: NetPhoto(
                                  url: img.url,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            );
                    },
                  ),
                ),
                Container(
                  color: p.bg,
                  padding: EdgeInsets.fromLTRB(
                    12,
                    14,
                    12,
                    14 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Column(
                    children: [
                      Text(
                        t('jury.position', {
                          'n': _index + 1,
                          'total': list.length,
                        }),
                        style: font(13, color: p.inkMuted),
                      ),
                      if (_exifLine(list[_index].exif) case final exif?) ...[
                        const SizedBox(height: 4),
                        Text(
                          exif,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: font(12.5, color: p.inkMuted, tabular: true),
                        ),
                      ],
                      const SizedBox(height: 10),
                      if (list[_index].mine)
                        Text(
                          t('jury.own_entry'),
                          style: font(14.5, weight: 500, color: p.ink),
                        )
                      else
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          alignment: WrapAlignment.center,
                          children: [
                            for (var v = 1; v <= 10; v++)
                              SizedBox(
                                width: 54,
                                height: 48,
                                child: list[_index].myScore == v
                                    ? FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: p.accent,
                                          foregroundColor: p.accentInk,
                                          padding: EdgeInsets.zero,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                        ),
                                        onPressed: () => _give(list, v),
                                        child: Text('$v'),
                                      )
                                    : OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                        ),
                                        onPressed: () => _give(list, v),
                                        child: Text('$v'),
                                      ),
                              ),
                          ],
                        ),
                      if (!list[_index].mine) ...[
                        const SizedBox(height: 12),
                        _JuryNoteField(
                          controller: _note,
                          entry: list[_index],
                          saving: _savingNote,
                          onSave: () => _saveNote(list[_index]),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

String _fmtNum(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Jüri için kısa çekim bilgisi: makine/objektif · odak · diyafram · enstantane · ISO.
String? _exifLine(Exif? x) {
  if (x == null) return null;
  final parts = [
    ?x.camera,
    ?x.lens,
    if (x.focalLength != null) '${x.focalLength!.round()}mm',
    if (x.aperture != null) 'f/${_fmtNum(x.aperture!)}',
    ?x.shutter,
    if (x.iso != null) 'ISO ${x.iso}',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Jürinin karelere düştüğü özel not; yalnızca kendisi görür. Puan vermeden kaydedilemez.
class _JuryNoteField extends StatelessWidget {
  const _JuryNoteField({
    required this.controller,
    required this.entry,
    required this.saving,
    required this.onSave,
  });
  final TextEditingController controller;
  final Entry entry;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final dirty = value.text.trim() != (entry.myNote ?? '');
        final canSave = dirty && entry.myScore != null && !saving;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              minLines: 1,
              maxLines: 3,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              style: font(14.5, color: p.ink),
              decoration: InputDecoration(
                labelText: t('jury.note_label'),
                hintText: t('jury.note_hint'),
                counterText: '',
                isDense: true,
                prefixIcon: Icon(LucideIcons.lock, size: 16, color: p.inkMuted),
                suffixIcon: dirty
                    ? IconButton(
                        tooltip: t('jury.note_save'),
                        onPressed: canSave ? onSave : null,
                        icon: saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(LucideIcons.check, color: canSave ? p.accent : p.inkMuted),
                      )
                    : null,
              ),
            ),
            if (dirty && entry.myScore == null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  t('jury.note_needs_score'),
                  textAlign: TextAlign.center,
                  style: font(12.5, color: p.inkMuted),
                ),
              ),
          ],
        );
      },
    );
  }
}
