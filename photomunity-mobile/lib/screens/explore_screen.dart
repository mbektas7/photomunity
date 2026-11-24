import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'theme_screens.dart' show ThemeBanner;
import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/community_widgets.dart';
import '../widgets/design.dart';
import 'feed_screen.dart';

class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    final pages = ref.watch(photoPagesProvider('explore'));
    final ctrl = ref.read(photoPagesProvider('explore').notifier);
    final judging = ref.watch(contestsProvider('judging')).asData?.value ?? const <ContestCard>[];
    final open = ref.watch(contestsProvider('open')).asData?.value ?? const <ContestCard>[];
    final live = [...judging, ...open]
      ..sort((a, b) => contestNextMoment(a)!.compareTo(contestNextMoment(b)!));

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(contestsProvider);
          await ctrl.refresh();
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) => loadMoreOnScroll(n, ctrl.loadMore),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverSafeArea(
                bottom: false,
                sliver: SliverPadding(
                  padding: const EdgeInsets.fromLTRB(Space.s5, 14, 14, Space.s5),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            t('explore.title'),
                            style: font(34, weight: 700, height: 1, spacing: -1.2, color: p.ink),
                          ),
                        ),

                      ],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, 10),
                sliver: SliverToBoxAdapter(
                  child: Text(t('explore.tools'), style: font(21, weight: 700, spacing: -0.3, color: p.ink)),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 118,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final (i, (icon, label, route)) in [
                        (LucideIcons.moon, t('sky.title'), '/sky'),
                        (LucideIcons.trophy, t('theme.title'), '/themes'),
                        (LucideIcons.messageSquareText, t('critique.requests_short'), '/critiques'),
                        (LucideIcons.scan, t('explore.tool_ar'), '/sky/ar'),
                        (LucideIcons.map, t('map.title'), '/map'),
                        (LucideIcons.calculator, t('tools.title'), '/tools'),
                        (LucideIcons.bookOpen, t('guide.title'), '/guide'),
                        (LucideIcons.users, t('nav.communities'), '/communities?s=0'),
                      ].indexed) ...[
                        if (i > 0) const SizedBox(width: Space.s2),
                        ToolTile(
                          icon: icon,
                          label: label,
                          featured: i == 0,
                          onTap: () => route.startsWith('/communities') ? context.go(route) : context.push(route),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: Space.s6)),
              const SliverToBoxAdapter(child: ThemeBanner(padding: EdgeInsets.fromLTRB(12, 0, 12, Space.s6))),
              if (live.isNotEmpty) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(Space.s5, 0, 8, 6),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Expanded(child: Text(t('feed.live_contests'), style: font(21, weight: 700, spacing: -0.3, color: p.ink))),
                        TextButton(
                          onPressed: () => context.go('/communities'),
                          child: Text(t('feed.all')),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 116,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: live.length,
                      separatorBuilder: (_, _) => const SizedBox(width: Space.s3),
                      itemBuilder: (_, i) => SizedBox(width: 300, child: _LiveContestCard(c: live[i])),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: Space.s6)),
              ],
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, 12),
                sliver: SliverToBoxAdapter(
                  child: Text(t('explore.for_you'), style: font(21, weight: 700, spacing: -0.3, color: p.ink)),
                ),
              ),
              if (pages.initialLoading)
                const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
                )
              else if (pages.items.isEmpty && pages.error != null)
                SliverToBoxAdapter(child: ErrorView(error: pages.error!, onRetry: ctrl.refresh))
              else if (pages.items.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.all(Space.s5),
                  sliver: SliverToBoxAdapter(child: Text(t('explore.empty'), style: font(15, color: p.inkMuted))),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverPhotoColumns(photos: pages.items),
                ),
              if (pages.loading && pages.items.isNotEmpty)
                const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: navClearance)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Canlı yarışma kartı; yarışma kapak görseli API'de olmadığından topluluk logosuyla.
class _LiveContestCard extends StatelessWidget {
  const _LiveContestCard({required this.c});
  final ContestCard c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = L10n.of(context);
    final left = shortRemaining(t, contestNextMoment(c)!);
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(Radii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.card),
        onTap: () => context.push('/contests/${c.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CommunityLogo(name: c.community.name, url: c.community.logoUrl, size: 76),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        LiveBadge(c.status == 'open' ? t('contest.live_open') : t('contest.live_voting')),
                        if (left != null) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(left.$2, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: font(14, color: p.inkMuted, tabular: true)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: font(18, weight: 700, spacing: -0.3, color: p.ink)),
                    Text(c.community.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: font(14, color: p.inkMuted)),
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
