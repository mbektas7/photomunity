import 'package:flutter/material.dart';
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
import 'community_screens.dart' show openWeb;

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
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (c != null)
            IconButton(
              tooltip: t('contest.share'),
              icon: const Icon(Icons.link),
              onPressed: () => _share(c),
            ),
          if (c?.myRole == 'admin')
            IconButton(
              tooltip: t('contest.manage_web'),
              icon: const Icon(Icons.tune),
              onPressed: () =>
                  openWeb(context, '/contests/${widget.id}/manage'),
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
    );
  }

  Widget _body(BuildContext context, Contest c) {
    final t = L10n.of(context);
    final p = context.palette;
    final locale = t.locale.languageCode;
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(contestProvider(widget.id));
        ref.invalidate(entriesProvider(widget.id));
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => context.push('/c/${c.community.slug}'),
                  child: Row(
                    children: [
                      CommunityLogo(
                        name: c.community.name,
                        url: c.community.logoUrl,
                        size: 26,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          c.community.name,
                          style: font(14.5, weight: 500, color: p.ink),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    StatusBadge(status: c.status),
                    const SizedBox(width: 8),
                    Text(
                      '${t('contest.mode.${c.judgingMode}')} · ${t('contest.entries', {'count': c.entryCount})}',
                      style: font(12.5, color: p.inkMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  c.title,
                  style: font(
                    36,
                    weight: 700,
                    height: 1.0,
                    spacing: -1.4,
                    color: p.ink,
                  ),
                ),
                const SizedBox(height: 18),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ContestTimeline(c: c),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _phase(context, c, locale),
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (c.prizes.isNotEmpty) ...[
                  Text(
                    t('contest.prizes'),
                    style: font(15, weight: 600, color: p.ink),
                  ),
                  const SizedBox(height: 6),
                  for (final pr in c.prizes)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: p.line)),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 30,
                            child: Text(
                              '${pr.rank}.',
                              style: font(17, weight: 600, color: p.ink),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              pr.title,
                              style: font(15, color: p.ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 22),
                ],
                Text(
                  t('contest.about'),
                  style: font(15, weight: 600, color: p.ink),
                ),
                const SizedBox(height: 6),
                Text(c.description, style: font(15, height: 1.5, color: p.ink)),
                if (c.rules != null) ...[
                  const SizedBox(height: 18),
                  Text(
                    t('contest.rules'),
                    style: font(15, weight: 600, color: p.ink),
                  ),
                  const SizedBox(height: 6),
                  Text(c.rules!, style: font(15, height: 1.5, color: p.inkMuted)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel(Palette p, List<Widget> children) => Container(
    color: p.surface,
    padding: const EdgeInsets.all(20),
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
              AspectRatio(
                aspectRatio: img.ratio,
                child: NetPhoto(url: img.url),
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.check, color: p.accent, size: 20),
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
          Text(
            t('contest.enter_title'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            t('contest.enter_body'),
            style: font(15, height: 1.45, color: p.inkMuted),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy || c.status == 'draft' ? null : _enter,
            child: BusyLabel(busy: _busy, label: t('contest.enter_cta')),
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
          Builder(
            builder: (_) {
              final votable = value.where((e) => !e.mine).toList();
              final done = votable.where((e) => e.myStars != null).length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t('contest.rated_progress', {
                      'done': done,
                      'total': votable.length,
                    }),
                    style: font(13.5, weight: 500, color: p.ink),
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: votable.isEmpty ? 0 : done / votable.length,
                  ),
                  const SizedBox(height: 14),
                ],
              );
            },
          ),
          for (final e in value)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(10),
              color: p.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (e.feed != null)
                    GestureDetector(
                      onTap: () => _fullscreen(context, e),
                      child: AspectRatio(
                        aspectRatio: e.feed!.ratio,
                        child: NetPhoto(url: e.feed!.url),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          e.user?.displayName ?? e.title ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: font(13.5, color: p.inkMuted),
                        ),
                      ),
                      if (e.mine)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: ShapeDecoration(
                            color: p.ink.withValues(alpha: 0.06),
                            shape: const StadiumBorder(),
                          ),
                          child: Text(
                            t('contest.your_entry'),
                            style: font(13.5, weight: 500, color: p.ink),
                          ),
                        )
                      else
                        StarRating(
                          value: e.myStars,
                          onChanged: (stars) => ref
                              .read(entriesProvider(contestId).notifier)
                              .vote(e.id, stars)
                              .catchError((Object err) {
                                if (context.mounted)
                                  toast(context, errorText(context, err));
                              }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          if (value.isEmpty)
            Text(t('contest.no_entries'), style: font(15, color: p.inkMuted)),
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
              Icon(Icons.emoji_events_outlined, color: p.accent),
              const SizedBox(width: 8),
              Text(
                t('contest.results'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final e in value)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: p.surface,
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
                              style: font(14, weight: 600, color: p.accent),
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
