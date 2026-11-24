import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'theme_screens.dart' show ThemeBanner;
import '../core/l10n.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import 'onboarding_screen.dart';
import '../widgets/common.dart';
import '../widgets/ad_widgets.dart';
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
        // Solda yükle; sağda arama (dokununca açılır), mesajlar ve bildirimler
        title: Semantics(
          button: true,
          label: t('nav.upload'),
          excludeSemantics: true,
          child: Material(
            color: p.accent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => context.push('/upload'),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(LucideIcons.plus, size: 24, color: p.accentInk, weight: IconStroke.active),
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            style: IconButton.styleFrom(backgroundColor: p.surface, fixedSize: const Size(44, 44), minimumSize: const Size(44, 44)),
            tooltip: t('search.hint'),
            onPressed: () => context.push('/search'),
            icon: const Icon(LucideIcons.search),
          ),
          const SizedBox(width: 8),
          const MessagesButton(filled: true),
          const SizedBox(width: 8),
          const NotificationBell(filled: true),
          const SizedBox(width: Space.s5),
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
              const SliverToBoxAdapter(child: _HomeBanner()),
              const SliverToBoxAdapter(child: ThemeBanner()),
              const SliverToBoxAdapter(child: OnboardingCard()),
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
                            onPressed: () => context.push('/explore'),
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


/// Yönetimin ana sayfa duyurusu; kapatılınca bu oturumda gizlenir.
class _HomeBanner extends ConsumerWidget {
  const _HomeBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    final b = ref.watch(homeBannerProvider(t.locale.languageCode)).asData?.value;
    if (b == null || ref.watch(closedBannerProvider) == b.id) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Material(
        color: p.accentTint,
        borderRadius: BorderRadius.circular(Radii.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.card),
          onTap: b.link == null ? null : () => context.push(b.link!),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.megaphone, size: 20, color: p.accentText),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.title, style: font(15, weight: 700, color: p.ink)),
                      const SizedBox(height: 2),
                      Text(b.body, style: font(14, height: 1.4, color: p.inkMuted)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: t('ui.close'),
                  icon: Icon(LucideIcons.x, size: 18, color: p.ink),
                  onPressed: () => ref.read(closedBannerProvider.notifier).close(b.id),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
