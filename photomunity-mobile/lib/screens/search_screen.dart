import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/ad_widgets.dart';
import '../widgets/common.dart';

/// Ana sayfadaki arama alanından açılır: kayıtlı kullanıcıları arar.
class UserSearchScreen extends ConsumerStatefulWidget {
  const UserSearchScreen({super.key, this.initialQuery = ''});
  final String initialQuery;

  @override
  ConsumerState<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends ConsumerState<UserSearchScreen> {
  late final _ctrl = TextEditingController(text: widget.initialQuery);
  Timer? _debounce;
  late String _q = widget.initialQuery.trim();

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _q = v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final results = _q.isEmpty ? null : ref.watch(userSearchProvider(_q));

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 0,
        leading: IconButton(
          tooltip: t('ui.back'),
          icon: const Icon(LucideIcons.chevronLeft, size: 28),
          onPressed: () => context.pop(),
        ),
        title: Padding(
          padding: const EdgeInsets.only(right: Space.s4),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.search,
            autocorrect: false,
            onChanged: _onChanged,
            onSubmitted: (v) => setState(() => _q = v.trim()),
            style: font(16, color: p.ink),
            decoration: InputDecoration(
              hintText: t('search.hint'),
              prefixIcon: const Icon(LucideIcons.search, size: 20),
              suffixIcon: _ctrl.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: t('search.clear'),
                      icon: const Icon(LucideIcons.x, size: 18),
                      onPressed: () {
                        _ctrl.clear();
                        _debounce?.cancel();
                        setState(() => _q = '');
                      },
                    ),
              isDense: true,
            ),
          ),
        ),
      ),
      body: switch (results) {
        null => _Hint(text: t('search.prompt')),
        AsyncValue(:final error?) when !results.hasValue => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(userSearchProvider(_q)),
        ),
        AsyncValue(:final value?) when value.isEmpty => _Hint(text: t('search.empty')),
        AsyncValue(:final value?) => ListView.separated(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(vertical: Space.s2),
          itemCount: value.length,
          separatorBuilder: (_, _) => Divider(color: p.line, indent: 76, height: 1),
          itemBuilder: (_, i) {
            final u = value[i];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: Space.s5, vertical: 4),
              leading: Avatar(name: u.displayName, url: u.avatarUrl, size: 44),
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      u.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: font(15.5, weight: 600, color: p.ink),
                    ),
                  ),
                  if (u.isPro) ...[const SizedBox(width: 6), const ProBadge()],
                ],
              ),
              subtitle: Text('@${u.username}', style: font(13.5, color: p.inkMuted)),
              onTap: () => context.push('/u/${u.username}'),
            );
          },
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.s5, Space.s6, Space.s5, 0),
    child: Text(text, style: font(15, color: context.palette.inkMuted)),
  );
}

/// Ana sayfa üst çubuğundaki arama alanı; dokununca arama ekranı açılır.
class SearchPill extends StatelessWidget {
  const SearchPill({super.key});

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    return Semantics(
      button: true,
      label: t('search.hint'),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => context.push('/search'),
        borderRadius: BorderRadius.circular(Radii.pill),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.search, size: 18, color: p.inkMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t('search.pill'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: font(14.5, color: p.inkMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
