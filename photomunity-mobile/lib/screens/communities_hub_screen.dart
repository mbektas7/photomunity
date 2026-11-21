import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/community_widgets.dart';
import '../widgets/design.dart';
import 'feed_screen.dart' show navClearance;

/// Alt menüdeki "Topluluk": topluluklar (yönettiklerin, üyeliklerin, keşfet) ve yarışmalar.
class CommunitiesScreen extends ConsumerStatefulWidget {
  const CommunitiesScreen({super.key, this.segment});

  /// 0 topluluklar, 1 yarışmalar.
  final int? segment;

  @override
  ConsumerState<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends ConsumerState<CommunitiesScreen> {
  late int _segment = widget.segment ?? 0;
  String _status = 'open';

  @override
  void didUpdateWidget(covariant CommunitiesScreen old) {
    super.didUpdateWidget(old);
    if (widget.segment != null && widget.segment != old.segment) _segment = widget.segment!;
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(communitiesProvider);
            ref.invalidate(contestsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: navClearance),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.s5, 10, Space.s5, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(t('nav.community'), style: font(34, weight: 700, spacing: -1.2, color: p.ink)),
                    ),
                    RoundIconButton(
                      icon: LucideIcons.search,
                      label: t('search.hint'),
                      color: p.surface,
                      onPressed: () => context.push('/search?k=${_segment == 0 ? 'c' : 'p'}'),
                    ),
                    if (_segment == 0) ...[
                      const SizedBox(width: 8),
                      Semantics(
                        button: true,
                        label: t('community.create'),
                        excludeSemantics: true,
                        child: Material(
                          color: p.ink,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => context.push('/communities/new'),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Icon(LucideIcons.plus, size: 22, color: p.bg, weight: IconStroke.active),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.s5),
                child: _Segment(
                  labels: [t('nav.communities'), t('nav.contests')],
                  value: _segment,
                  onChanged: (v) => setState(() => _segment = v),
                ),
              ),
              if (_segment == 0) ..._communities(context) else ..._contests(context),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- Topluluklar

  List<Widget> _communities(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final mine = ref.watch(communitiesProvider(('', true)));
    final all = ref.watch(communitiesProvider(('', false)));
    final managed = mine.asData?.value.where((c) => c.isAdmin).toList() ?? const <CommunityCard>[];
    final member = mine.asData?.value.where((c) => !c.isAdmin).toList() ?? const <CommunityCard>[];
    final discover = all.asData?.value.where((c) => c.myRole == null).toList();

    return [
      if (managed.isNotEmpty) ...[
        _Heading(t('community.managed')),
        SizedBox(
          height: 160,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.s5),
            itemCount: managed.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _ManagedCard(c: managed[i]),
          ),
        ),
      ],
      if (member.isNotEmpty) ...[
        _Heading(t('community.member_of')),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.s5),
            itemCount: member.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final c = member[i];
              return Semantics(
                button: true,
                label: c.name,
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.box),
                  onTap: () => context.push('/c/${c.slug}'),
                  child: SizedBox(
                    width: 66,
                    child: Column(
                      children: [
                        CommunityLogo(name: c.name, url: c.logoUrl, size: 58),
                        const SizedBox(height: 6),
                        Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: font(12, weight: 600, color: p.ink)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
      _Heading(t('community.discover')),
      switch (all) {
        AsyncError(:final error) when discover == null => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(communitiesProvider),
        ),
        _ when discover == null => const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        ),
        _ when discover.isEmpty => Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.s5),
          child: Text(t('community.discover_empty'), style: font(15, color: p.inkMuted)),
        ),
        _ => _ListCard(
          children: [
            for (final c in discover)
              _Row(
                leading: CommunityLogo(name: c.name, url: c.logoUrl, size: 48),
                title: c.name,
                subtitle: [
                  if (c.city != null) c.city!,
                  t('community.members', {'count': c.memberCount}),
                  if (c.joinApproval) t('community.approval_badge'),
                ].join(' · '),
                trailing: JoinButton(c: c),
                onTap: () => context.push('/c/${c.slug}'),
              ),
          ],
        ),
      },
    ];
  }

  // ---------------------------------------------------------------- Yarışmalar

  List<Widget> _contests(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final list = ref.watch(contestsProvider(_status));
    final items = list.asData?.value;
    // Katılıma açık yarışmalarda en yakın son tarihli olan öne çıkar
    final featured = _status == 'open' && items != null && items.isNotEmpty ? items.first : null;
    final rest = featured == null ? items : items!.skip(1).toList();

    return [
      SizedBox(
        height: 64,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(Space.s5, 16, Space.s5, 10),
          children: [
            for (final s in ['open', 'judging', 'finished']) ...[
              _Pill(label: t('contest.tab_$s'), selected: _status == s, onTap: () => setState(() => _status = s)),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
      if (list case AsyncError(:final error) when items == null)
        ErrorView(error: error, onRetry: () => ref.invalidate(contestsProvider))
      else if (items == null)
        const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
      else if (items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.s5),
          child: Text(t('contest.empty_$_status'), style: font(15, color: p.inkMuted)),
        )
      else ...[
        if (featured != null) _FeaturedContest(c: featured),
        if (rest!.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ListCard(
            children: [
              for (final c in rest)
                _Row(
                  leading: CommunityLogo(name: c.community.name, url: c.community.logoUrl, size: 48),
                  title: c.title,
                  subtitle: [
                    c.community.name,
                    t(c.judgingMode == 'jury' ? 'cform.mode_jury' : 'cform.mode_public'),
                    t('contest.entries', {'count': c.entryCount}),
                  ].join(' · '),
                  trailing: _RemainingBadge(c: c),
                  onTap: () => context.push('/contests/${c.id}'),
                ),
            ],
          ),
        ],
      ],
    ];
  }
}

// ---------------------------------------------------------------- parçalar

class _Segment extends StatelessWidget {
  const _Segment({required this.labels, required this.value, required this.onChanged});
  final List<String> labels;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(999)),
      child: Row(
        children: [
          for (final (i, label) in labels.indexed)
            Expanded(
              child: Semantics(
                selected: value == i,
                button: true,
                child: GestureDetector(
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: value == i ? p.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(label,
                        style: font(14.5, weight: value == i ? 700 : 600, color: value == i ? p.ink : p.inkMuted)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? p.ink : p.surface,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Text(label, style: font(13.5, weight: 700, color: selected ? p.bg : p.inkMuted)),
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.s5, 22, Space.s5, 10),
    child: Text(text, style: font(18, weight: 700, spacing: -0.2, color: context.palette.ink)),
  );
}

class _ListCard extends StatelessWidget {
  const _ListCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(22)),
      child: Column(
        children: [
          for (final (i, w) in children.indexed) ...[
            if (i > 0) Divider(color: p.line, indent: 74, height: 1),
            w,
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.leading, required this.title, required this.subtitle, required this.trailing, required this.onTap});
  final Widget leading;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: font(15.5, weight: 700, color: p.ink)),
                  const SizedBox(height: 1),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: font(12.5, color: p.inkMuted)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _ManagedCard extends StatelessWidget {
  const _ManagedCard({required this.c});
  final CommunityCard c;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final pending = c.pendingRequests ?? 0;
    return Semantics(
      button: true,
      label: c.name,
      excludeSemantics: true,
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/c/${c.slug}'),
          child: SizedBox(
            width: 168,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(
                          height: 78,
                          width: double.infinity,
                          child: c.logoUrl != null
                              ? NetPhoto(url: c.logoUrl!)
                              : ColoredBox(
                                  color: p.accentTint,
                                  child: Center(
                                    child: Text(
                                      c.name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join(),
                                      style: font(26, weight: 700, color: p.accentText),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      if (pending > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(999)),
                            child: Text(t('community.requests_badge', {'count': pending}),
                                style: font(11, weight: 700, color: p.accentInk)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: font(15, weight: 700, color: p.ink)),
                  Text(
                    '${t(c.myRole == 'owner' ? 'community.role_owner' : 'community.role_admin')} · ${t('community.members', {'count': c.memberCount})}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: font(12, color: p.inkMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Katılıma açık yarışmalardan en yakın son tarihlisi: koyu kart, geri sayım ve katılım sayısı.
class _FeaturedContest extends StatelessWidget {
  const _FeaturedContest({required this.c});
  final ContestCard c;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    const ink = Color(0xFFF3F4F7);
    const muted = Color(0xFFA3A8B5);
    const tile = Color(0xFF232730);
    final left = shortRemaining(t, c.submissionDeadline);
    Widget stat(String value, String label, {Color color = ink}) => Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: tile, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: font(22, weight: 700, color: color)),
            Text(label, style: font(12, color: muted)),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: const Color(0xFF14161B),
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/contests/${c.id}'),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CommunityLogo(name: c.community.name, url: c.community.logoUrl, size: 40),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${c.community.name} · ${t(c.judgingMode == 'jury' ? 'cform.mode_jury' : 'cform.mode_public')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: font(13, color: muted),
                          ),
                          Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: font(20, weight: 700, spacing: -0.4, color: ink)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    stat(left?.$1 ?? '–', t('contest.until_deadline'), color: p.live),
                    const SizedBox(width: 8),
                    stat('${c.entryCount}', t('contest.entries_label')),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => context.push('/contests/${c.id}'),
                    child: Text(t('contest.enter_title')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RemainingBadge extends StatelessWidget {
  const _RemainingBadge({required this.c});
  final ContestCard c;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final at = contestNextMoment(c);
    final left = at == null ? null : shortRemaining(t, at);
    if (left == null) {
      return Icon(LucideIcons.chevronRight, size: 20, color: p.inkSubtle);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: p.live.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(999)),
      child: Text(left.$1, style: font(12, weight: 700, color: p.ink)),
    );
  }
}
