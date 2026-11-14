import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/ad_widgets.dart';
import '../widgets/photo_widgets.dart';
import 'messages_screens.dart';
import 'notifications_screen.dart';

/// Sona yaklaşınca bir sonraki sayfayı yükler.
bool loadMoreOnScroll(ScrollNotification n, VoidCallback loadMore) {
  if (n.metrics.extentAfter < 900) loadMore();
  return false;
}

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
        title: const Text('Fotografya'),
        actions: const [
          MessagesButton(),
          NotificationBell(),
          SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(unreadCountProvider);
          await ctrl.refresh();
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) => loadMoreOnScroll(n, ctrl.loadMore),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
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
                  padding: const EdgeInsets.all(16),
                  sliver: SliverToBoxAdapter(
                    child: Container(
                      color: p.mat,
                      padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('feed.empty_title'),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            t('feed.empty_body'),
                            style: font(15, height: 1.5, color: p.muted),
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
                SliverList.separated(
                  itemCount: pages.items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (_, i) => (i + 1) % 8 == 0
                      ? Column(
                          children: [
                            PhotoPrint(photo: pages.items[i]),
                            const SizedBox(height: 14),
                            const InlineAd(),
                          ],
                        )
                      : PhotoPrint(photo: pages.items[i]),
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
