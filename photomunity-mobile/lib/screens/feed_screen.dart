import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/ad_widgets.dart';
import '../widgets/brand_logo.dart';
import '../widgets/design.dart';
import 'messages_screens.dart';
import 'notifications_screen.dart';

/// Sona yaklaşınca bir sonraki sayfayı yükler.
bool loadMoreOnScroll(ScrollNotification n, VoidCallback loadMore) {
  if (n.metrics.extentAfter < 900) loadMore();
  return false;
}

/// Alt menünün altında içerik kalmasın diye kaydırma sonu boşluğu.
const navClearance = 120.0;

class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    final pages = ref.watch(photoPagesProvider('feed'));
    final ctrl = ref.read(photoPagesProvider('feed').notifier);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: Space.s5,
        title: const BrandLogo(height: 32),
        actions: const [
          MessagesButton(),
          NotificationBell(),
          SizedBox(width: 10),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(unreadCountProvider);
          ref.invalidate(contestsProvider);
          ref.invalidate(communitiesProvider);
          await ctrl.refresh();
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) => loadMoreOnScroll(n, ctrl.loadMore),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: _Stories()),
              if (pages.initialLoading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (pages.items.isEmpty && pages.error != null)
                SliverFillRemaining(
                  child: ErrorView(error: pages.error!, onRetry: ctrl.refresh),
                )
              else if (pages.items.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  sliver: SliverToBoxAdapter(
                    child: SurfaceCard(
                      padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t('feed.empty_title'), style: AppText.title(p.ink)),
                          const SizedBox(height: 8),
                          Text(
                            t('feed.empty_body'),
                            style: font(15, height: 1.5, color: p.inkMuted),
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: () => context.go('/explore'),
                            child: Text(t('feed.go_explore')),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  sliver: SliverList.separated(
                    itemCount: pages.items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: Space.s3),
                    itemBuilder: (_, i) => (i + 1) % 8 == 0
                        ? Column(
                            children: [
                              PhotoCardView(photo: pages.items[i]),
                              const SizedBox(height: Space.s3),
                              const InlineAd(),
                            ],
                          )
                        : PhotoCardView(photo: pages.items[i]),
                  ),
                ),
              if (pages.loading && pages.items.isNotEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: navClearance)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hikâye halkaları. "Görülmemiş içerik" API'de yok: açık yarışmalar live,
/// üye olunan topluluklar accent halkayla gösterilir (README → Veri gereksinimleri).
class _Stories extends ConsumerWidget {
  const _Stories();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final judging = ref.watch(contestsProvider('judging')).asData?.value ?? const [];
    final open = ref.watch(contestsProvider('open')).asData?.value ?? const [];
    final mine = ref.watch(communitiesProvider(('', true))).asData?.value ?? const [];
    final contests = [...judging, ...open]
      ..sort((a, b) => contestNextMoment(a)!.compareTo(contestNextMoment(b)!));
    if (contests.isEmpty && mine.isEmpty) return const SizedBox(height: 4);
    return Semantics(
      label: t('feed.stories'),
      container: true,
      child: SizedBox(
        height: 124,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          children: [
            for (final c in contests.take(6))
              Builder(
                builder: (_) {
                  final left = shortRemaining(t, contestNextMoment(c)!);
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: StoryRing(
                      label: c.title,
                      image: c.community.logoUrl,
                      state: RingState.live,
                      badge: left?.$1,
                      semanticLabel: left == null ? c.title : '${c.title}, ${left.$2}',
                      onTap: () => context.push('/contests/${c.id}'),
                    ),
                  );
                },
              ),
            for (final c in mine)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: StoryRing(
                  label: c.name,
                  image: c.logoUrl,
                  state: RingState.accent,
                  onTap: () => context.push('/c/${c.slug}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
