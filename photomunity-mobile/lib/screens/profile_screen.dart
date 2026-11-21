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
import '../core/profile_images.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/ad_widgets.dart';
import '../widgets/common.dart';
import 'feed_screen.dart';

const _kitOrder = ['body', 'lens', 'drone', 'flash', 'tripod', 'filter', 'other'];

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
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('common.cancel'))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(t('messages.block'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiProvider).post<dynamic>('/users/${prof.username}/block');
      ref.invalidate(photoPagesProvider);
      ref.invalidate(conversationsProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    }
  }

  Future<void> _share(Profile prof) async {
    final t = L10n.of(context);
    await Clipboard.setData(ClipboardData(text: '${AppConfig.webUrl}/${t.locale.languageCode}/u/${prof.username}'));
    if (mounted) toast(context, t('ui.link_copied'));
  }

  String? _imgBusy; // avatar | cover

  Future<void> _changeImage(String kind) async {
    setState(() => _imgBusy = kind);
    await uploadProfileImage(context, ref, kind);
    if (mounted) setState(() => _imgBusy = null);
  }

  /// Kendi profilinde fotoğrafa / kapağa dokununca: değiştir ya da kaldır.
  Future<void> _imageMenu(String kind, bool hasImage) async {
    final t = L10n.of(context);
    if (!hasImage) return _changeImage(kind);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.image),
              title: Text(t(kind == 'avatar' ? 'profile.change_avatar' : 'settings.change_cover')),
              onTap: () => Navigator.pop(c, 'change'),
            ),
            ListTile(
              leading: Icon(LucideIcons.trash2, color: context.palette.danger),
              title: Text(
                t(kind == 'avatar' ? 'settings.remove_avatar' : 'settings.remove_cover'),
                style: TextStyle(color: context.palette.danger),
              ),
              onTap: () => Navigator.pop(c, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'change') {
      await _changeImage(kind);
    } else {
      setState(() => _imgBusy = kind);
      await removeProfileImage(context, ref, kind);
      if (mounted) setState(() => _imgBusy = null);
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(profileProvider(widget.username));
    ref.invalidate(awardsProvider(widget.username));
    await ref.read(photoPagesProvider(_photosPath).notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(profileProvider(widget.username));
    return Scaffold(
      // Yenileme sırasında önceki veri gösterilmeye devam eder (titreme olmaz)
      body: async.hasValue
          ? _body(context, async.requireValue)
          : async.hasError
          ? SafeArea(
              child: ErrorView(error: async.error!, onRetry: () => ref.invalidate(profileProvider(widget.username))),
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  /// Kapağın üzerindeki yarı saydam yuvarlak düğme.
  Widget _glassButton(IconData icon, String label, VoidCallback onTap) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: Material(
      color: const Color(0x7314161B),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 21, color: Colors.white)),
      ),
    ),
  );

  Widget _header(BuildContext context, Profile prof, String place, Equipment? body) {
    final t = L10n.of(context);
    final p = context.palette;
    final nf = NumberFormat.decimalPattern(t.locale.languageCode);
    final top = MediaQuery.paddingOf(context).top;
    final coverH = 150 + top;
    final secondary = FilledButton.styleFrom(
      backgroundColor: p.surface2,
      foregroundColor: p.ink,
      minimumSize: const Size.fromHeight(44),
    );

    Widget stat(int n, String label, {VoidCallback? onTap}) => Expanded(
      child: Semantics(
        button: onTap != null,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.box),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(nf.format(n), style: font(19, weight: 700, spacing: -0.5, color: p.ink, tabular: true)),
                ),
                Text(
                  label.toLowerCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: font(12.5, color: p.inkMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final follows = prof.canViewPhotos || prof.isMe;
    // Yığın: kapak üstte, bilgi kartı kapağın alt kenarına 44 px biner (boşluk bırakmadan)
    return Stack(
      children: [
        // Kapak: tam genişlik; kendi profilinde "Kapağı değiştir"
        SizedBox(
          height: coverH,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (prof.coverUrl != null) NetPhoto(url: prof.coverUrl!) else ColoredBox(color: p.accentTint),
              Positioned(
                left: 16,
                right: 16,
                top: top + 8,
                child: Row(
                  children: [
                    if (!widget.isTab) ...[
                      _glassButton(LucideIcons.chevronLeft, t('ui.back'), () => Navigator.of(context).maybePop()),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: const Color(0x7314161B),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!prof.isPublic) ...[
                                const Icon(LucideIcons.lock, size: 14, color: Colors.white),
                                const SizedBox(width: 6),
                              ],
                              Flexible(
                                child: Text(
                                  prof.username,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: font(15, weight: 700, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!widget.isTab) _glassButton(LucideIcons.share2, t('ui.share'), () => _share(prof)),
                    if (!widget.isTab && !prof.isMe) ...[
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        tooltip: t('ui.more'),
                        onSelected: (v) => v == 'block' ? _block(prof) : _report(prof.id),
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'report', child: Text(t('report.button'))),
                          PopupMenuItem(
                            value: 'block',
                            child: Text(t('messages.block'), style: TextStyle(color: p.danger)),
                          ),
                        ],
                        child: const IgnorePointer(child: _GlassIcon(icon: LucideIcons.ellipsisVertical)),
                      ),
                    ],
                    if (widget.isTab)
                      _glassButton(LucideIcons.settings, t('settings.heading'), () => context.push('/settings')),
                  ],
                ),
              ),
              if (prof.isMe)
                Positioned(
                  right: 16,
                  bottom: 56,
                  child: Material(
                    color: const Color(0x8C14161B),
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: _imgBusy != null ? null : () => _imageMenu('cover', prof.coverUrl != null),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _imgBusy == 'cover'
                                ? const SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(LucideIcons.camera, size: 15, color: Colors.white),
                            const SizedBox(width: 6),
                            Text(
                              t(prof.coverUrl != null ? 'settings.change_cover' : 'settings.add_cover'),
                              style: font(13, weight: 600, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Bilgi kartı kapağın üstüne biner
        Padding(
          padding: EdgeInsets.only(top: coverH - 44),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(26)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Fotoğraf kartın üst kenarından taşar; yer kaplamasın diye taşan kısım yığının dışında
                    SizedBox(
                      width: 94,
                      height: 56,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            top: -38,
                            left: 0,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(color: p.surface, shape: BoxShape.circle),
                                  child: Opacity(
                                    opacity: _imgBusy == 'avatar' ? 0.5 : 1,
                                    child: Avatar(name: prof.displayName, url: prof.avatarUrl, size: 86),
                                  ),
                                ),
                                if (prof.isMe)
                                  Positioned(
                                    right: 0,
                                    bottom: 4,
                                    child: Semantics(
                                      button: true,
                                      label: t('profile.change_avatar'),
                                      excludeSemantics: true,
                                      child: GestureDetector(
                                        onTap: _imgBusy != null
                                            ? null
                                            : () => _imageMenu('avatar', prof.avatarUrl != null),
                                        child: Container(
                                          width: 30,
                                          height: 30,
                                          decoration: BoxDecoration(
                                            color: p.accent,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: p.surface, width: 3),
                                          ),
                                          child: Icon(
                                            LucideIcons.plus,
                                            size: 15,
                                            color: p.accentInk,
                                            weight: IconStroke.active,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Space.s3),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          children: [
                            stat(prof.photosCount, t('profile.posts')),
                            stat(
                              prof.followersCount,
                              t('profile.followers'),
                              onTap: follows ? () => context.push('/u/${prof.username}/follows?tab=0') : null,
                            ),
                            stat(
                              prof.followingCount,
                              t('profile.following'),
                              onTap: follows ? () => context.push('/u/${prof.username}/follows?tab=1') : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(prof.displayName, style: font(20, weight: 700, height: 1.15, spacing: -0.4, color: p.ink)),
                        if (prof.isPro) const ProBadge(),
                      ],
                    ),
                    if (place.isNotEmpty) ...[const SizedBox(height: 3), _Meta(icon: LucideIcons.mapPin, text: place)],
                    if (prof.bio != null) ...[
                      const SizedBox(height: 8),
                      Text(prof.bio!, style: font(15, height: 1.45, color: p.ink)),
                    ],
                    // Çektiği alanlar ve kullandığı makine
                    if (prof.specialties.isNotEmpty || body != null) ...[
                      const SizedBox(height: Space.s3),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final sp in prof.specialties) ExifChip(t('specialties.$sp')),
                          if (body != null) ExifChip('${body.brand} ${body.model}'),
                        ],
                      ),
                    ],
                    const SizedBox(height: Space.s4),
                    Row(
                      children: [
                        if (prof.isMe) ...[
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: p.ink,
                                foregroundColor: p.bg,
                                minimumSize: const Size.fromHeight(44),
                              ),
                              onPressed: () => context.push('/settings'),
                              child: Text(t('profile.edit')),
                            ),
                          ),
                          const SizedBox(width: Space.s2),
                          Expanded(
                            child: FilledButton(
                              style: secondary,
                              onPressed: () => _share(prof),
                              child: Text(t('ui.share')),
                            ),
                          ),
                        ] else ...[
                          Expanded(
                            child: FilledButton(
                              style: prof.isFollowing
                                  ? secondary
                                  : FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
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
                              child: FilledButton(
                                style: secondary,
                                onPressed: () => context.push('/messages/new/${prof.username}'),
                                child: Text(t('profile.message_short')),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  int _tab = 0; // 0 fotoğraflar, 1 ekipman

  Widget _body(BuildContext context, Profile prof) {
    final t = L10n.of(context);
    final p = context.palette;
    final pages = prof.canViewPhotos ? ref.watch(photoPagesProvider(_photosPath)) : null;
    final kit = [...prof.equipment]..sort((a, b) => _kitOrder.indexOf(a.type).compareTo(_kitOrder.indexOf(b.type)));
    final place = [prof.city, prof.country].whereType<String>().join(', ');
    final body = kit.where((e) => e.type == 'body').firstOrNull;
    final awards = prof.canViewPhotos
        ? ref.watch(awardsProvider(widget.username)).asData?.value ?? const <Award>[]
        : const <Award>[];
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
            child: Text(
              label,
              style: font(16.5, weight: active ? 700 : 500, color: active ? p.ink : p.inkMuted),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) =>
            pages == null ? false : loadMoreOnScroll(n, ref.read(photoPagesProvider(_photosPath).notifier).loadMore),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _header(context, prof, place, body)),
            // Instagram'daki "öne çıkanlar" yerine: yarışmalarda ilk üçe giren kareler
            if (awards.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: Space.s5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.s5),
                        child: Text(t('profile.awards'), style: font(15, weight: 700, color: p.ink)),
                      ),
                      const SizedBox(height: Space.s2),
                      SizedBox(
                        height: 112,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          children: [
                            for (final a in awards)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: StoryRing(
                                  label: '${a.rank}. ${a.contestTitle}',
                                  image: a.photo.thumb?.url,
                                  state: RingState.accent,
                                  semanticLabel: t('profile.award_label', {'rank': a.rank, 'contest': a.contestTitle}),
                                  size: 68,
                                  onTap: () => context.push('/p/${a.photo.id}'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Space.s5, Space.s3, Space.s5, Space.s3),
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
                                  child: Text(
                                    '${e.brand} ${e.model}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: font(15, weight: 600, color: p.ink),
                                  ),
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
                        Text(
                          prof.isMe ? t('profile.empty_me') : t('profile.empty'),
                          style: font(15, color: p.inkMuted),
                        ),
                        if (prof.isMe) ...[
                          const SizedBox(height: 14),
                          FilledButton(
                            onPressed: () => context.push('/upload'),
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

class _GlassIcon extends StatelessWidget {
  const _GlassIcon({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    decoration: const BoxDecoration(color: Color(0x7314161B), shape: BoxShape.circle),
    child: Icon(icon, size: 21, color: Colors.white),
  );
}
