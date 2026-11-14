import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/justified_wall.dart';
import 'feed_screen.dart';

class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    final pages = ref.watch(photoPagesProvider('explore'));
    final ctrl = ref.read(photoPagesProvider('explore').notifier);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: ctrl.refresh,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) => loadMoreOnScroll(n, ctrl.loadMore),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverSafeArea(
                bottom: false,
                sliver: SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                t('explore.title'),
                                style: font(
                                  36,
                                  weight: 700,
                                  height: 1,
                                  spacing: -1.4,
                                  color: p.ink,
                                ),
                              ),
                            ),
                            IconButton.outlined(
                              tooltip: t('guide.title'),
                              onPressed: () => context.push('/guide'),
                              icon: const Icon(
                                Icons.menu_book_outlined,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 6),
                            OutlinedButton.icon(
                              onPressed: () => context.push('/map'),
                              icon: const Icon(Icons.map_outlined, size: 18),
                              label: Text(t('explore.map')),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t('explore.lead'),
                          style: font(15, color: p.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
                  padding: const EdgeInsets.all(20),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      t('explore.empty'),
                      style: font(15, color: p.inkMuted),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  sliver: SliverJustifiedWall(photos: pages.items),
                ),
              if (pages.loading && pages.items.isNotEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }
}
