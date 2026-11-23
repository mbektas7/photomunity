import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import 'feed_screen.dart';
import '../widgets/design.dart';

// Göreli zaman tek yerde: widgets/design.dart
export '../widgets/design.dart' show relativeTime;

/// Akış ekranının üst çubuğundaki zil ve okunmamış rozeti.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key, this.filled = false});

  /// Ana sayfa üst çubuğu: beyaz yuvarlak zemin.
  final bool filled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final count = ref.watch(unreadCountProvider).asData?.value ?? 0;
    return IconButton(
      style: filled
          ? IconButton.styleFrom(backgroundColor: p.surface, fixedSize: const Size(44, 44), minimumSize: const Size(44, 44))
          : null,
      tooltip: L10n.of(context)('notifications.title'),
      onPressed: () => context.push('/notifications'),
      icon: Badge(
        isLabelVisible: count > 0,
        backgroundColor: p.accent,
        textColor: p.accentInk,
        label: Text(count > 99 ? '99+' : '$count'),
        child: const Icon(LucideIcons.bell),
      ),
    );
  }
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    final s = ref.watch(notificationsProvider);
    final ctrl = ref.read(notificationsProvider.notifier);
    final locale = t.locale.languageCode;

    Widget body;
    if (s.loading && s.items.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (s.error != null && s.items.isEmpty) {
      body = ErrorView(error: s.error!, onRetry: ctrl.refresh);
    } else if (s.items.isEmpty) {
      body = ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            t('notifications.empty'),
            style: font(15, height: 1.5, color: p.inkMuted),
          ),
        ],
      );
    } else {
      body = NotificationListener<ScrollNotification>(
        onNotification: (n) => loadMoreOnScroll(n, ctrl.loadMore),
        child: ListView.separated(
          itemCount: s.items.length,
          separatorBuilder: (_, _) => Divider(color: p.line, indent: 72),
          itemBuilder: (context, i) => _Tile(n: s.items[i], locale: locale),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(t('notifications.title'))),
      body: RefreshIndicator(onRefresh: ctrl.refresh, child: body),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.n, required this.locale});
  final AppNotification n;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: () => context.push(n.route),
      child: Container(
        color: n.read ? null : p.accent.withValues(alpha: 0.06),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            n.actor != null
                ? Avatar(
                    name: n.actor!.displayName,
                    url: n.actor!.avatarUrl,
                    size: 42,
                  )
                : CircleAvatar(
                    radius: 21,
                    backgroundColor: p.accent,
                    child: Icon(LucideIcons.image, size: 19, color: p.surface),
                  ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n.text, style: font(15, height: 1.35, color: p.ink)),
                  const SizedBox(height: 2),
                  Text(
                    relativeTime(n.createdAt, locale),
                    style: font(13, color: p.inkMuted),
                  ),
                ],
              ),
            ),
            if (n.type == 'message_request') ...[
              const SizedBox(width: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onPressed: () => context.push(n.route),
                child: Text(L10n.of(context)('messages.view')),
              ),
            ],
            if (n.photoThumb != null) ...[
              const SizedBox(width: 12),
              SizedBox(
                width: 48,
                height: 48,
                child: NetPhoto(url: n.photoThumb!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
