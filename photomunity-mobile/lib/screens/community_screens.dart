import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';
import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/community_widgets.dart';
import '../widgets/photo_widgets.dart';
import 'notifications_screen.dart' show relativeTime;

void openWeb(BuildContext context, String path) {
  final locale = L10n.of(context).locale.languageCode;
  launchUrl(
    Uri.parse('${AppConfig.webUrl}/$locale$path'),
    mode: LaunchMode.externalApplication,
  );
}

class NewCommunityScreen extends ConsumerStatefulWidget {
  const NewCommunityScreen({super.key});

  @override
  ConsumerState<NewCommunityScreen> createState() => _NewCommunityScreenState();
}

class _NewCommunityScreenState extends ConsumerState<NewCommunityScreen> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _city = TextEditingController();
  final _country = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _desc, _city, _country]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().length < 3) return;
    setState(() => _busy = true);
    String? opt(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    try {
      final res = await ref.read(apiProvider).post<Map<String, dynamic>>(
        '/communities',
        {
          'name': _name.text.trim(),
          'description': opt(_desc),
          'city': opt(_city),
          'country': opt(_country)?.toUpperCase(),
        },
      );
      ref.invalidate(communitiesProvider);
      if (mounted) context.pushReplacement('/c/${res['slug']}/settings?created=1');
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(t('community.new_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          Text(
            t('community.new_lead'),
            style: font(15, height: 1.45, color: p.inkMuted),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _name,
            maxLength: 100,
            decoration: InputDecoration(
              labelText: t('community.name'),
              hintText: t('community.name_placeholder'),
            ),
          ),
          TextField(
            controller: _desc,
            maxLength: 3000,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(labelText: t('community.description')),
          ),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _city,
                  decoration: InputDecoration(labelText: t('settings.city')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _country,
                  maxLength: 2,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: t('settings.country'),
                    counterText: '',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _busy ? null : _create,
            child: BusyLabel(busy: _busy, label: t('community.create')),
          ),
        ],
      ),
    );
  }
}

class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key, required this.slug});
  final String slug;

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  bool _busy = false;

  Future<void> _membership(bool join) async {
    setState(() => _busy = true);
    try {
      final api = ref.read(apiProvider);
      join
          ? await api.post<dynamic>('/communities/${widget.slug}/join')
          : await api.delete<dynamic>('/communities/${widget.slug}/join');
      ref.invalidate(communityProvider(widget.slug));
      ref.invalidate(communitiesProvider);
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Galeriden yeni bir kare seçip yükler ve topluluğa paylaşır.
  void _sharePhoto() => context.push('/upload?community=${widget.slug}');

  Future<void> _writeNews() async {
    final t = L10n.of(context);
    final title = TextEditingController();
    final body = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(c).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: title,
              maxLength: 200,
              decoration: InputDecoration(labelText: t('community.news_title')),
            ),
            TextField(
              controller: body,
              maxLength: 5000,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(labelText: t('community.news_body')),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(t('community.publish')),
            ),
          ],
        ),
      ),
    );
    if (ok == true && title.text.trim().isNotEmpty) {
      try {
        await ref.read(apiProvider).post<dynamic>(
          '/communities/${widget.slug}/posts',
          {
            'kind': 'news',
            'title': title.text.trim(),
            'body': body.text.trim().isEmpty ? null : body.text.trim(),
          },
        );
        ref.invalidate(communityPostsProvider(widget.slug));
      } catch (e) {
        if (mounted) toast(context, errorText(context, e));
      }
    }
    title.dispose();
    body.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(communityProvider(widget.slug));
    return Scaffold(
      body: async.hasValue
          ? _body(context, async.requireValue)
          : async.hasError
          ? SafeArea(
              child: ErrorView(
                error: async.error!,
                onRetry: () => ref.invalidate(communityProvider(widget.slug)),
              ),
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _body(BuildContext context, Community c) {
    final t = L10n.of(context);
    final p = context.palette;
    return DefaultTabController(
      length: 3,
      child: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            pinned: true,
            expandedHeight: c.coverUrl != null ? 150 : null,
            flexibleSpace: c.coverUrl != null
                ? FlexibleSpaceBar(background: NetPhoto(url: c.coverUrl!))
                : null,
            actions: [
              if (c.isAdmin)
                IconButton(
                  tooltip: t('csettings.title'),
                  icon: const Icon(LucideIcons.settings),
                  onPressed: () => context.push('/c/${c.slug}/settings'),
                ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CommunityLogo(name: c.name, url: c.logoUrl, size: 64),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.name,
                              style: font(
                                24,
                                weight: 700,
                                height: 1.08,
                                spacing: -0.8,
                                color: p.ink,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                ?c.city,
                                t('community.members', {
                                  'count': c.memberCount,
                                }),
                                if (c.joinApproval) t('community.approval_badge'),
                              ].join('  ·  '),
                              style: font(13.5, color: p.inkMuted),
                            ),
                            if (c.openContests > 0)
                              Text(
                                t('community.active_contests', {
                                  'count': c.openContests,
                                }),
                                style: font(13.5, weight: 500, color: p.accent),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (c.description != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      c.description!,
                      style: font(15, height: 1.5, color: p.ink),
                    ),
                  ],
                  const SizedBox(height: 14),
                  if (c.myRole == null)
                    JoinButton(c: c, height: 44, expand: true)
                  else if (c.myRole == 'member')
                    OutlinedButton(
                      onPressed: _busy ? null : () => _membership(false),
                      child: BusyLabel(
                        busy: _busy,
                        label: t('community.leave'),
                      ),
                    ),
                  if (c.isAdmin && (c.pendingRequests ?? 0) > 0) ...[
                    const SizedBox(height: 18),
                    _JoinRequests(slug: c.slug, count: c.pendingRequests!),
                  ],
                ],
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabsHeader(
              TabBar(
                labelStyle: font(15, weight: 600),
                unselectedLabelColor: p.inkMuted,
                labelColor: p.ink,
                indicatorColor: p.ink,
                tabs: [
                  Tab(text: t('community.tab_feed')),
                  Tab(text: t('community.tab_contests')),
                  Tab(text: t('community.tab_members')),
                ],
              ),
              p.bg,
            ),
          ),
        ],
        body: TabBarView(children: [_feed(c), _contests(c), _members(c)]),
      ),
    );
  }

  Widget _feed(Community c) {
    final t = L10n.of(context);
    final p = context.palette;
    final posts = ref.watch(communityPostsProvider(c.slug));
    final locale = t.locale.languageCode;
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(communityPostsProvider(c.slug)),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
        children: [
          if (c.myRole != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _sharePhoto,
                    icon: const Icon(LucideIcons.plus, size: 18),
                    label: Text(t('community.share_photo')),
                  ),
                  if (c.isAdmin)
                    OutlinedButton(
                      onPressed: _writeNews,
                      child: Text(t('community.write_news')),
                    ),
                ],
              ),
            ),
          ...switch (posts) {
            AsyncData(:final value) when value.isEmpty => [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  t('community.feed_empty'),
                  style: font(15, color: p.inkMuted),
                ),
              ),
            ],
            AsyncData(:final value) => [
              for (final post in value)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: switch (post.kind) {
                    'photo' when post.photo != null => PhotoPrint(
                      photo: post.photo!,
                    ),
                    'contest' when post.contest != null => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('community.contest_announced', {
                              'time': relativeTime(post.createdAt, locale),
                            }),
                            style: font(13, color: p.inkMuted),
                          ),
                          const SizedBox(height: 6),
                          ContestTile(c: post.contest!, showCommunity: false),
                        ],
                      ),
                    ),
                    _ => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(18),
                      color: p.surface,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${post.author.displayName} · ${relativeTime(post.createdAt, locale)}',
                            style: font(13, color: p.inkMuted),
                          ),
                          if (post.title != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              post.title!,
                              style: font(
                                19,
                                weight: 600,
                                height: 1.25,
                                color: p.ink,
                              ),
                            ),
                          ],
                          if (post.body != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              post.body!,
                              style: font(15, height: 1.5, color: p.ink),
                            ),
                          ],
                        ],
                      ),
                    ),
                  },
                ),
            ],
            AsyncError(:final error) => [
              ErrorView(
                error: error,
                onRetry: () => ref.invalidate(communityPostsProvider(c.slug)),
              ),
            ],
            _ => [
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          },
        ],
      ),
    );
  }

  Widget _contests(Community c) {
    final t = L10n.of(context);
    final p = context.palette;
    final list = ref.watch(communityContestsProvider(c.slug));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (c.isAdmin)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FilledButton.icon(
              onPressed: () => context.push('/c/${c.slug}/contests/new'),
              icon: const Icon(LucideIcons.plus, size: 18),
              label: Text(t('cform.new_title')),
            ),
          ),
        ...switch (list) {
          AsyncData(:final value) when value.isEmpty => [
            Text(
              t('community.contests_empty'),
              style: font(15, color: p.inkMuted),
            ),
          ],
          AsyncData(:final value) => [
            for (final x in value)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ContestTile(c: x, showCommunity: false),
              ),
          ],
          AsyncError(:final error) => [ErrorView(error: error)],
          _ => [const Center(child: CircularProgressIndicator())],
        },
      ],
    );
  }

  Widget _members(Community c) {
    final t = L10n.of(context);
    final p = context.palette;
    final list = ref.watch(membersProvider(c.slug));
    const order = {'owner': 0, 'admin': 1, 'member': 2};
    return switch (list) {
      AsyncData(:final value) => _memberList(
        [...value]..sort((a, b) => order[a.role]!.compareTo(order[b.role]!)),
        t,
        p,
      ),
      AsyncError(:final error) => ErrorView(error: error),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Widget _memberList(List<Member> sorted, L10n t, Palette p) =>
      ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: sorted.length,
        separatorBuilder: (_, _) => Divider(color: p.line, indent: 72),
        itemBuilder: (_, i) {
          final m = sorted[i];
          return ListTile(
            onTap: () => context.push('/u/${m.user.username}'),
            leading: Avatar(
              name: m.user.displayName,
              url: m.user.avatarUrl,
              size: 40,
            ),
            title: Text(
              m.user.displayName,
              style: font(15, weight: 600, color: p.ink),
            ),
            subtitle: Text(
              '@${m.user.username}',
              style: font(13, color: p.inkMuted),
            ),
            trailing: m.role == 'member'
                ? null
                : Text(
                    t('community.role.${m.role}'),
                    style: font(12.5, color: p.inkMuted),
                  ),
          );
        },
      );
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  _TabsHeader(this.tabs, this.color);
  final TabBar tabs;
  final Color color;

  @override
  double get minExtent => tabs.preferredSize.height;
  @override
  double get maxExtent => tabs.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => ColoredBox(color: color, child: tabs);

  @override
  bool shouldRebuild(covariant _TabsHeader old) =>
      old.tabs != tabs || old.color != color;
}


/// Yönetici görünümü: bekleyen katılma istekleri, onayla / reddet.
class _JoinRequests extends ConsumerStatefulWidget {
  const _JoinRequests({required this.slug, required this.count});
  final String slug;
  final int count;

  @override
  ConsumerState<_JoinRequests> createState() => _JoinRequestsState();
}

class _JoinRequestsState extends ConsumerState<_JoinRequests> {
  final _busy = <String>{};

  Future<void> _decide(String username, bool approve) async {
    setState(() => _busy.add(username));
    try {
      await ref.read(apiProvider).post<dynamic>(
        '/communities/${widget.slug}/join-requests/$username/${approve ? 'approve' : 'decline'}',
      );
      ref.invalidate(joinRequestsProvider(widget.slug));
      ref.invalidate(communityProvider(widget.slug));
      ref.invalidate(communitiesProvider);
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy.remove(username));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final list = ref.watch(joinRequestsProvider(widget.slug)).asData?.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(text: '${t('community.join_requests')}  '),
            TextSpan(text: '${list?.length ?? widget.count}', style: TextStyle(color: p.accentText)),
          ]),
          style: font(18, weight: 700, color: p.ink),
        ),
        const SizedBox(height: 10),
        if (list == null)
          const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
        else
          DecoratedBox(
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(22)),
            child: Column(
              children: [
                for (final (i, r) in list.indexed) ...[
                  if (i > 0) Divider(color: p.line, indent: 70, height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => context.push('/u/${r.user.username}'),
                          child: Avatar(name: r.user.displayName, url: r.user.avatarUrl, size: 44),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.user.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: font(15, weight: 700, color: p.ink)),
                              Text('@${r.user.username} · ${relativeTime(r.createdAt, t.locale.languageCode)}',
                                  maxLines: 1, overflow: TextOverflow.ellipsis, style: font(12.5, color: p.inkMuted)),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: t('community.decline'),
                          style: IconButton.styleFrom(backgroundColor: p.surface2),
                          onPressed: _busy.contains(r.user.username) ? null : () => _decide(r.user.username, false),
                          icon: Icon(LucideIcons.x, size: 18, color: p.inkMuted),
                        ),
                        const SizedBox(width: 6),
                        FilledButton(
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 14)),
                          onPressed: _busy.contains(r.user.username) ? null : () => _decide(r.user.username, true),
                          child: Text(t('community.approve')),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
