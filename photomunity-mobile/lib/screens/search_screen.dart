import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/ad_widgets.dart';
import '../widgets/common.dart';
import '../widgets/community_widgets.dart';

/// Ana sayfadaki büyüteçten açılır: üst çubuk arama kutusuna dönüşür.
/// Kişiler ve topluluklar aranır; ileride başka türler eklenebilir.
class UserSearchScreen extends ConsumerStatefulWidget {
  const UserSearchScreen({super.key, this.initialQuery = '', this.communities = false});
  final String initialQuery;

  /// Topluluk ekranından açıldıysa topluluk aramasıyla başlar.
  final bool communities;

  @override
  ConsumerState<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends ConsumerState<UserSearchScreen> {
  late final _ctrl = TextEditingController(text: widget.initialQuery);
  Timer? _debounce;
  late String _q = widget.initialQuery.trim();
  late int _kind = widget.communities ? 1 : 0; // 0 kişiler, 1 topluluklar

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() {}); // temizle düğmesi
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _q = v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        automaticallyImplyLeading: false,
        titleSpacing: Space.s5,
        title: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                autocorrect: false,
                onChanged: _onChanged,
                onSubmitted: (v) => setState(() => _q = v.trim()),
                style: font(16, color: p.ink),
                decoration: InputDecoration(
                  hintText: t('search.pill'),
                  isDense: true,
                  filled: true,
                  fillColor: p.surface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  prefixIcon: Icon(LucideIcons.search, size: 19, color: p.ink),
                  suffixIcon: _ctrl.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: t('search.clear'),
                          icon: Icon(LucideIcons.circleX, size: 18, color: p.inkMuted),
                          onPressed: () {
                            _ctrl.clear();
                            _debounce?.cancel();
                            setState(() => _q = '');
                          },
                        ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(color: p.accent, width: 1.5),
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: () => context.pop(),
              style: TextButton.styleFrom(foregroundColor: p.ink),
              child: Text(t('common.cancel'), style: font(15, weight: 600, color: p.ink)),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s5, 2, Space.s5, Space.s3),
            child: Row(
              children: [
                for (final (i, label) in [t('search.people'), t('search.communities')].indexed) ...[
                  _Chip(label: label, selected: _kind == i, onTap: () => setState(() => _kind = i)),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            child: _q.isEmpty
                ? _Hint(text: t(_kind == 0 ? 'search.prompt' : 'search.prompt_communities'))
                : _kind == 0
                ? _people(context)
                : _communities(context),
          ),
        ],
      ),
    );
  }

  Widget _people(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    return _results<UserCard>(
      ref.watch(userSearchProvider(_q)),
      onRetry: () => ref.invalidate(userSearchProvider(_q)),
      empty: t('search.empty'),
      row: (u) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.s4, vertical: 2),
        leading: Avatar(name: u.displayName, url: u.avatarUrl, size: 44),
        title: Row(
          children: [
            Flexible(
              child: Text(u.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: font(15.5, weight: 700, color: p.ink)),
            ),
            if (u.isPro) ...[const SizedBox(width: 6), const ProBadge()],
          ],
        ),
        subtitle: Text('@${u.username}', style: font(13, color: p.inkMuted)),
        onTap: () => context.push('/u/${u.username}'),
      ),
    );
  }

  Widget _communities(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    return _results<CommunityCard>(
      ref.watch(communitiesProvider((_q, false))),
      onRetry: () => ref.invalidate(communitiesProvider((_q, false))),
      empty: t('search.empty_communities'),
      row: (c) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.s4, vertical: 2),
        leading: CommunityLogo(name: c.name, url: c.logoUrl, size: 44),
        title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: font(15.5, weight: 700, color: p.ink)),
        subtitle: Text(
          [if (c.city != null) c.city!, t('community.members', {'count': c.memberCount})].join(' · '),
          style: font(13, color: p.inkMuted),
        ),
        onTap: () => context.push('/c/${c.slug}'),
      ),
    );
  }

  Widget _results<T>(
    AsyncValue<List<T>> res, {
    required VoidCallback onRetry,
    required String empty,
    required Widget Function(T) row,
  }) {
    final p = context.palette;
    return switch (res) {
      AsyncValue(:final error?) when !res.hasValue => ErrorView(error: error, onRetry: onRetry),
      AsyncValue(:final value?) when value.isEmpty => _Hint(text: empty),
      AsyncValue(:final value?) => ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
        children: [
          Material(
            color: p.surface,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (final (i, item) in value.indexed) ...[
                    if (i > 0) Divider(color: p.line, indent: 72, height: 1),
                    row(item),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? p.ink : p.surface,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Text(label, style: font(13.5, weight: 700, color: selected ? p.bg : p.inkMuted)),
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.s5, Space.s4, Space.s5, 0),
    child: Text(text, style: font(15, color: context.palette.inkMuted)),
  );
}
