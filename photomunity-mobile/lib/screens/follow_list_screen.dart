import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

/// Takipçiler / takip edilenler. Kendi listende takipçiyi çıkarabilir, takibi bırakabilirsin.
final followListProvider = FutureProvider.autoDispose
    .family<List<UserCard>, (String, bool, String)>((ref, arg) async {
      final (username, followers, q) = arg;
      final res = await ref.read(apiProvider).get<Map<String, dynamic>>(
        '/users/$username/${followers ? 'followers' : 'following'}',
        query: {'limit': 100, if (q.isNotEmpty) 'q': q},
      );
      return (res['items'] as List).map((e) => UserCard.fromJson(e as Map<String, dynamic>)).toList();
    });

class FollowListScreen extends ConsumerStatefulWidget {
  const FollowListScreen({super.key, required this.username, this.tab = 0});
  final String username;

  /// 0 takipçiler, 1 takip edilenler.
  final int tab;

  @override
  ConsumerState<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends ConsumerState<FollowListScreen> {
  late int _tab = widget.tab;
  final _search = TextEditingController();
  Timer? _debounce;
  String _q = '';

  // Bu ekranda yapılan değişiklikler: çıkarılan takipçiler ve takibi bırakılanlar
  final _removed = <String>{};
  final _unfollowed = <String>{};
  final _busy = <String>{};

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  bool get _isMe => ref.read(authProvider).asData?.value?.username == widget.username;

  Future<void> _run(String username, Future<void> Function() fn) async {
    setState(() => _busy.add(username));
    try {
      await fn();
      ref.invalidate(profileProvider(widget.username));
      ref.invalidate(photoPagesProvider('feed'));
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy.remove(username));
    }
  }

  Future<void> _removeFollower(UserCard u) async {
    final t = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(t('follows.remove_confirm', {'name': u.displayName})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('common.cancel'))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(t('follows.remove'))),
        ],
      ),
    );
    if (ok != true) return;
    await _run(u.username, () async {
      await ref.read(apiProvider).delete<dynamic>('/me/followers/${u.username}');
      _removed.add(u.username);
    });
  }

  Future<void> _toggleFollow(UserCard u) => _run(u.username, () async {
    final api = ref.read(apiProvider);
    if (_unfollowed.contains(u.username)) {
      await api.post<dynamic>('/users/${u.username}/follow');
      _unfollowed.remove(u.username);
    } else {
      await api.delete<dynamic>('/users/${u.username}/follow');
      _unfollowed.add(u.username);
    }
  });

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final prof = ref.watch(profileProvider(widget.username)).asData?.value;
    final followers = _tab == 0;
    final list = ref.watch(followListProvider((widget.username, followers, _q)));
    final items = list.asData?.value.where((u) => !(followers && _removed.contains(u.username))).toList();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 0,
        title: Text(widget.username, style: font(20, weight: 700, color: p.ink)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(999)),
              child: Row(
                children: [
                  for (final (i, label) in [
                    t('follows.followers_tab', {'count': prof?.followersCount ?? ''}),
                    t('follows.following_tab', {'count': prof?.followingCount ?? ''}),
                  ].indexed)
                    Expanded(
                      child: Semantics(
                        selected: _tab == i,
                        button: true,
                        child: GestureDetector(
                          onTap: () => setState(() => _tab = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _tab == i ? p.surface : Colors.transparent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(label.trim(),
                                style: font(14, weight: _tab == i ? 700 : 600, color: _tab == i ? p.ink : p.inkMuted)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () {
                  if (mounted) setState(() => _q = v.trim());
                });
              },
              style: font(15, color: p.ink),
              decoration: InputDecoration(
                hintText: t(followers ? 'follows.search_followers' : 'follows.search_following'),
                isDense: true,
                filled: true,
                fillColor: p.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                prefixIcon: Icon(LucideIcons.search, size: 18, color: p.inkMuted),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide(color: p.accent, width: 1.5),
                ),
              ),
            ),
          ),
          Expanded(
            child: switch (list) {
              AsyncValue(:final error?) when items == null => ErrorView(
                error: error,
                onRetry: () => ref.invalidate(followListProvider),
              ),
              _ when items == null => const Center(child: CircularProgressIndicator()),
              _ when items.isEmpty => Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  t(_q.isNotEmpty ? 'search.empty' : (followers ? 'follows.empty_followers' : 'follows.empty_following')),
                  style: font(15, color: p.inkMuted),
                ),
              ),
              _ => ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
                children: [
                  Material(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(22),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final (i, u) in items.indexed) ...[
                          if (i > 0) Divider(color: p.line, indent: 70, height: 1),
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                            leading: Avatar(name: u.displayName, url: u.avatarUrl, size: 44),
                            title: Text(u.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: font(15, weight: 700, color: p.ink)),
                            subtitle: Text('@${u.username}', style: font(12.5, color: p.inkMuted)),
                            onTap: () => context.push('/u/${u.username}'),
                            trailing: !_isMe
                                ? null
                                : followers
                                ? _ActionButton(
                                    label: t('follows.remove'),
                                    busy: _busy.contains(u.username),
                                    onPressed: () => _removeFollower(u),
                                  )
                                : _ActionButton(
                                    label: t(_unfollowed.contains(u.username) ? 'profile.follow' : 'profile.following_button'),
                                    primary: _unfollowed.contains(u.username),
                                    busy: _busy.contains(u.username),
                                    onPressed: () => _toggleFollow(u),
                                  ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_isMe && followers) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(t('follows.remove_hint'), style: font(13, color: p.inkMuted)),
                    ),
                  ],
                ],
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.onPressed, this.busy = false, this.primary = false});
  final String label;
  final VoidCallback onPressed;
  final bool busy;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: primary ? p.accent : p.surface2,
        foregroundColor: primary ? p.accentInk : p.ink,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        textStyle: font(13, weight: 700),
      ),
      onPressed: busy ? null : onPressed,
      child: BusyLabel(busy: busy, label: label),
    );
  }
}
