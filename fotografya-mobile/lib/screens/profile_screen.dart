import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/ad_widgets.dart';
import '../widgets/common.dart';
import '../widgets/justified_wall.dart';
import 'feed_screen.dart';

const _kitOrder = [
  'body',
  'lens',
  'drone',
  'flash',
  'tripod',
  'filter',
  'other',
];

/// Alt sekmedeki "Profil": oturumdaki kullanıcının profili.
class MyProfileScreen extends ConsumerWidget {
  const MyProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authProvider).asData?.value;
    if (me == null)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return ProfileScreen(username: me.username, isTab: true);
  }
}

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, required this.username, this.isTab = false});
  final String username;
  final bool isTab;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _followBusy = false;

  String get _photosPath => 'users/${widget.username}/photos';

  Future<void> _toggleFollow(Profile p) async {
    setState(() => _followBusy = true);
    try {
      final api = ref.read(apiProvider);
      p.isFollowing
          ? await api.delete<dynamic>('/users/${p.username}/follow')
          : await api.post<dynamic>('/users/${p.username}/follow');
      ref.invalidate(profileProvider(widget.username));
      ref.invalidate(photoPagesProvider(_photosPath));
      ref.invalidate(photoPagesProvider('feed'));
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _report(String userId) async {
    final t = L10n.of(context);
    final reason = await pickReportReason(context);
    if (reason == null || !mounted) return;
    try {
      await ref.read(apiProvider).post<dynamic>('/reports', {
        'target_type': 'user',
        'target_id': userId,
        'reason': reason,
      });
      if (mounted) toast(context, t('report.thanks'));
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    }
  }

  Future<void> _block(Profile prof) async {
    final t = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(t('messages.block_confirm', {'name': prof.displayName})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(t('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(t('messages.block')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(apiProvider)
          .post<dynamic>('/users/${prof.username}/block');
      ref.invalidate(photoPagesProvider);
      ref.invalidate(conversationsProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(profileProvider(widget.username));
    await ref.read(photoPagesProvider(_photosPath).notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(profileProvider(widget.username));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '@${widget.username}',
          style: font(16, weight: 600, color: context.palette.ink),
        ),
        actions: [
          if (!widget.isTab && async.asData?.value.isMe == false)
            IconButton(
              tooltip: L10n.of(context)('report.button'),
              icon: const Icon(Icons.flag_outlined),
              onPressed: () => _report(async.asData!.value.id),
            ),
          if (!widget.isTab && async.asData?.value.isMe == false)
            PopupMenuButton<String>(
              onSelected: (_) => _block(async.asData!.value),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'block',
                  child: Text(L10n.of(context)('messages.block')),
                ),
              ],
            ),
          if (widget.isTab)
            IconButton(
              onPressed: () => context.push('/settings'),
              icon: const Icon(Icons.settings_outlined),
              tooltip: L10n.of(context)('settings.heading'),
            ),
        ],
      ),
      // Yenileme sırasında önceki veri gösterilmeye devam eder (titreme olmaz)
      body: async.hasValue
          ? _body(context, async.requireValue)
          : async.hasError
          ? ErrorView(
              error: async.error!,
              onRetry: () => ref.invalidate(profileProvider(widget.username)),
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _body(BuildContext context, Profile prof) {
    final t = L10n.of(context);
    final p = context.palette;
    final pages = prof.canViewPhotos
        ? ref.watch(photoPagesProvider(_photosPath))
        : null;
    final kit = [...prof.equipment]
      ..sort(
        (a, b) =>
            _kitOrder.indexOf(a.type).compareTo(_kitOrder.indexOf(b.type)),
      );
    final place = [prof.city, prof.country].whereType<String>().join(', ');

    return RefreshIndicator(
      onRefresh: _refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => pages == null
            ? false
            : loadMoreOnScroll(
                n,
                ref.read(photoPagesProvider(_photosPath).notifier).loadMore,
              ),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (prof.coverUrl != null)
              SliverToBoxAdapter(
                child: AspectRatio(
                  aspectRatio: 3,
                  child: NetPhoto(url: prof.coverUrl!),
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                20,
                prof.coverUrl != null ? 18 : 8,
                20,
                24,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Avatar(
                          name: prof.displayName,
                          url: prof.avatarUrl,
                          size: 72,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    prof.displayName,
                                    style: font(
                                      28,
                                      weight: 700,
                                      height: 1.05,
                                      spacing: -1,
                                      color: p.ink,
                                    ),
                                  ),
                                  if (prof.isPro) const ProBadge(),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 10,
                                runSpacing: 2,
                                children: [
                                  if (!prof.isPublic)
                                    _Meta(
                                      icon: Icons.lock_outline,
                                      text: t('profile.private'),
                                    ),
                                  if (place.isNotEmpty)
                                    _Meta(
                                      icon: Icons.place_outlined,
                                      text: place,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (prof.bio != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        prof.bio!,
                        style: font(15.5, height: 1.5, color: p.ink),
                      ),
                    ],
                    if (prof.specialties.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final s in prof.specialties)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 5,
                              ),
                              decoration: ShapeDecoration(
                                color: p.ink.withValues(alpha: 0.06),
                                shape: const StadiumBorder(),
                              ),
                              child: Text(
                                t('specialties.$s'),
                                style: font(13.5, color: p.ink),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        _Stat(n: prof.photosCount, label: t('profile.photos')),
                        _Stat(
                          n: prof.followersCount,
                          label: t('profile.followers'),
                        ),
                        _Stat(
                          n: prof.followingCount,
                          label: t('profile.following'),
                        ),
                        const Spacer(),
                        if (!prof.isMe && prof.isPublic)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: IconButton.outlined(
                              tooltip: t('profile.message'),
                              onPressed: () => context.push(
                                '/messages/new/${prof.username}',
                              ),
                              icon: const Icon(
                                Icons.chat_bubble_outline,
                                size: 20,
                              ),
                            ),
                          ),
                        if (prof.isMe)
                          OutlinedButton(
                            onPressed: () => context.push('/settings'),
                            child: Text(t('profile.edit')),
                          )
                        else if (prof.isFollowing)
                          OutlinedButton(
                            onPressed: _followBusy
                                ? null
                                : () => _toggleFollow(prof),
                            child: BusyLabel(
                              busy: _followBusy,
                              label: t('profile.following_button'),
                            ),
                          )
                        else
                          FilledButton(
                            onPressed: _followBusy
                                ? null
                                : () => _toggleFollow(prof),
                            child: BusyLabel(
                              busy: _followBusy,
                              label: t('profile.follow'),
                            ),
                          ),
                      ],
                    ),
                    if (kit.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      Container(
                        color: p.surface,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t('profile.kit'),
                              style: font(15, weight: 600, color: p.ink),
                            ),
                            const SizedBox(height: 4),
                            for (final (i, e) in kit.indexed)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  border: i == 0
                                      ? null
                                      : Border(top: BorderSide(color: p.line)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${e.brand} ${e.model}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: font(15, color: p.ink),
                                      ),
                                    ),
                                    Text(
                                      t('equipment.${e.type}'),
                                      style: font(13, color: p.inkMuted),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (!prof.canViewPhotos)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: Container(
                    color: p.surface,
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lock_outline, color: p.ink),
                        const SizedBox(height: 12),
                        Text(
                          t('profile.private_title'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t('profile.private_body'),
                          style: font(15, color: p.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (pages != null && pages.items.isEmpty && !pages.loading)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: Container(
                    color: p.surface,
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          prof.isMe
                              ? t('profile.empty_me')
                              : t('profile.empty'),
                          style: font(15, color: p.inkMuted),
                        ),
                        if (prof.isMe) ...[
                          const SizedBox(height: 14),
                          FilledButton(
                            onPressed: () => context.go('/upload'),
                            child: Text(t('profile.upload_first')),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              )
            else if (pages != null)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                sliver: SliverJustifiedWall(photos: pages.items, target: 170),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.n, required this.label});
  final int n;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$n', style: font(19, weight: 600, color: p.ink, tabular: true)),
          Text(label, style: font(12.5, color: p.inkMuted)),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: p.inkMuted),
        const SizedBox(width: 4),
        Text(text, style: font(13.5, color: p.inkMuted)),
      ],
    );
  }
}
