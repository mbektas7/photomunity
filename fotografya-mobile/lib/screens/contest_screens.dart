import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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
        padding: const EdgeInsets.fromLTRB(Space.s5, 4, Space.s5, 32),
        children: [
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
        return _Results(contestId: c.id);
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
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _give(List<Entry> list, int value) async {
    final e = list[_index];
    if (e.mine) return;
    try {
      await ref.read(entriesProvider(widget.id).notifier).score(e.id, value);
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
                    onPageChanged: (i) => setState(() => _index = i),
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
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
