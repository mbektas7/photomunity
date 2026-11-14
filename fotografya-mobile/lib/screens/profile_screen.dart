import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/config.dart';
import 'package:flutter/services.dart';
import '../widgets/design.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/ad_widgets.dart';
import '../widgets/common.dart';
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
    if (me == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
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
    final t = L10n.of(context);
    final prof = async.asData?.value;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        automaticallyImplyLeading: false,
        leading: widget.isTab
            ? null
            : IconButton(
                tooltip: t('ui.back'),
                icon: const Icon(LucideIcons.chevronLeft, size: 28),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
        actions: [
          if (prof != null)
            IconButton(
              tooltip: t('ui.share'),
              icon: const Icon(LucideIcons.share2),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: '${AppConfig.webUrl}/${t.locale.languageCode}/u/${prof.username}'));
                if (context.mounted) toast(context, t('ui.link_copied'));
              },
            ),
          if (!widget.isTab && prof?.isMe == false)
            PopupMenuButton<String>(
              tooltip: t('ui.more'),
              icon: const Icon(LucideIcons.ellipsisVertical),
              onSelected: (v) => v == 'block' ? _block(prof!) : _report(prof!.id),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'report', child: Text(t('report.button'))),
                PopupMenuItem(
                  value: 'block',
                  child: Text(t('messages.block'), style: TextStyle(color: context.palette.danger)),
                ),
              ],
            ),
          if (widget.isTab)
            IconButton(
              onPressed: () => context.push('/settings'),
              icon: const Icon(LucideIcons.settings),
              tooltip: t('settings.heading'),
            ),
          const SizedBox(width: 8),
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

  int _tab = 0; // 0 fotoğraflar, 1 ekipman

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
    final body = kit.where((e) => e.type == 'body').firstOrNull;
    final nf = NumberFormat.decimalPattern(t.locale.languageCode);

    Widget stat(int n, String label) => Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: p.surface2,
          borderRadius: BorderRadius.circular(Radii.box),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(nf.format(n), style: font(24, weight: 700, spacing: -0.7, color: p.ink, tabular: true)),
            ),
            Text(label.toLowerCase(), style: font(13, color: p.inkMuted)),
          ],
        ),
      ),
    );

    Widget tabButton(int i, String label) {
      final active = _tab == i;
      return Semantics(
        selected: active,
        button: true,
        child: InkWell(
          onTap: () => setState(() => _tab = i),
          child: Container(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
            margin: const EdgeInsets.only(right: 24),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: active ? p.ink : Colors.transparent, width: 2.5)),
            ),
            child: Text(label, style: font(16.5, weight: active ? 700 : 500, color: active ? p.ink : p.inkMuted)),
          ),
        ),
      );
    }

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
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              sliver: SliverToBoxAdapter(
                child: SurfaceCard(
                  padding: const EdgeInsets.all(Space.s4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (prof.coverUrl != null) ...[
                        // Kapak bir afiş görseli; kart içinde şerit olarak durur
                        ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.photo),
                          child: AspectRatio(aspectRatio: 3, child: NetPhoto(url: prof.coverUrl!)),
                        ),
                        const SizedBox(height: Space.s4),
                      ],
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(color: p.accentTint, shape: BoxShape.circle),
                            child: Avatar(name: prof.displayName, url: prof.avatarUrl, size: 70),
                          ),
                          const SizedBox(width: Space.s4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(prof.displayName, style: font(26, weight: 700, height: 1.1, spacing: -0.9, color: p.ink)),
                                    if (prof.isPro) const ProBadge(),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 2,
                                  children: [
                                    if (!prof.isPublic) _Meta(icon: LucideIcons.lock, text: t('profile.private')),
                                    if (place.isNotEmpty) _Meta(icon: LucideIcons.mapPin, text: place),
                                    if (place.isEmpty && prof.isPublic) _Meta(icon: LucideIcons.atSign, text: prof.username),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (prof.bio != null) ...[
                        const SizedBox(height: Space.s4),
                        Text(prof.bio!, style: font(16, height: 1.5, color: p.ink)),
                      ],
                      const SizedBox(height: Space.s4),
                      Row(
                        children: [
                          stat(prof.photosCount, t('profile.photos')),
                          const SizedBox(width: Space.s2),
                          stat(prof.followersCount, t('profile.followers')),
                          const SizedBox(width: Space.s2),
                          stat(prof.followingCount, t('profile.following')),
                        ],
                      ),
                      const SizedBox(height: Space.s4),
                      Row(
                        children: [
                          if (prof.isMe)
                            Expanded(
                              child: FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: p.surface2, foregroundColor: p.ink),
                                onPressed: () => context.push('/settings'),
                                child: Text(t('profile.edit')),
                              ),
                            )
                          else ...[
                            Expanded(
                              child: FilledButton(
                                style: prof.isFollowing
                                    ? FilledButton.styleFrom(backgroundColor: p.surface2, foregroundColor: p.ink)
                                    : null,
                                onPressed: _followBusy ? null : () => _toggleFollow(prof),
                                child: BusyLabel(
                                  busy: _followBusy,
                                  label: prof.isFollowing ? t('profile.following_button') : t('profile.follow'),
                                ),
                              ),
                            ),
                            if (prof.isPublic) ...[
                              const SizedBox(width: Space.s2),
                              Expanded(
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(backgroundColor: p.surface2, foregroundColor: p.ink),
                                  onPressed: () => context.push('/messages/new/${prof.username}'),
                                  icon: const Icon(LucideIcons.messageCircle, size: 20),
                                  label: Text(t('profile.message_short')),
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                      if (prof.specialties.isNotEmpty || body != null) ...[
                        const SizedBox(height: Space.s4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final sp in prof.specialties) ExifChip(t('specialties.$sp')),
                            if (body != null) ExifChip('${body.brand} ${body.model}'),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Space.s5, Space.s4, Space.s5, Space.s3),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    tabButton(0, t('profile.tab_photos')),
                    if (kit.isNotEmpty) tabButton(1, t('profile.tab_kit')),
                  ],
                ),
              ),
            ),
            if (_tab == 1 && kit.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverToBoxAdapter(
                  child: SurfaceCard(
                    padding: const EdgeInsets.fromLTRB(Space.s4, 6, Space.s4, 6),
                    child: Column(
                      children: [
                        for (final (i, e) in kit.indexed)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              border: i == 0 ? null : Border(top: BorderSide(color: p.line)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text('${e.brand} ${e.model}', maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: font(15, weight: 600, color: p.ink)),
                                ),
                                Text(t('equipment.${e.type}'), style: AppText.caption(p.inkMuted)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              )
            else if (!prof.canViewPhotos)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverToBoxAdapter(
                  child: SurfaceCard(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(LucideIcons.lock, color: p.ink),
                        const SizedBox(height: 12),
                        Text(t('profile.private_title'), style: AppText.heading(p.ink)),
                        const SizedBox(height: 4),
                        Text(t('profile.private_body'), style: font(15, color: p.inkMuted)),
                      ],
                    ),
                  ),
                ),
              )
            else if (pages != null && pages.items.isEmpty && !pages.loading)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverToBoxAdapter(
                  child: SurfaceCard(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(prof.isMe ? t('profile.empty_me') : t('profile.empty'), style: font(15, color: p.inkMuted)),
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
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverPhotoColumns(photos: pages.items),
              ),
            SliverToBoxAdapter(child: SizedBox(height: widget.isTab ? navClearance : 32)),
          ],
        ),
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
