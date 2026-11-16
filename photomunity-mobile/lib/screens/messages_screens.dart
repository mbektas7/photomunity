import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/design.dart';
import '../widgets/community_widgets.dart' show pickMyPhoto;

/// Akış ekranının üst çubuğundaki mesaj simgesi ve okunmamış rozeti.
class MessagesButton extends ConsumerWidget {
  const MessagesButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final u = ref.watch(messageUnreadProvider).asData?.value;
    final count = (u?.inbox ?? 0) + (u?.requests ?? 0);
    return IconButton(
      tooltip: L10n.of(context)('messages.title'),
      onPressed: () => context.push('/messages'),
      icon: Badge(
        isLabelVisible: count > 0,
        backgroundColor: p.accent,
        textColor: p.accentInk,
        label: Text(count > 99 ? '99+' : '$count'),
        child: const Icon(LucideIcons.messageCircle),
      ),
    );
  }
}

class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    final requests =
        ref.watch(messageUnreadProvider).asData?.value.requests ?? 0;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('messages.title')),
          bottom: TabBar(
            labelStyle: font(15, weight: 600),
            labelColor: p.ink,
            unselectedLabelColor: p.inkMuted,
            indicatorColor: p.ink,
            tabs: [
              Tab(text: t('messages.inbox')),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t('messages.requests')),
                    if (requests > 0) ...[
                      const SizedBox(width: 6),
                      Badge(
                        backgroundColor: p.accent,
                        textColor: p.accentInk,
                        label: Text('$requests'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _List(folder: 'inbox'),
            _List(folder: 'requests'),
          ],
        ),
      ),
    );
  }
}

class _List extends ConsumerWidget {
  const _List({required this.folder});
  final String folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    final me = ref.watch(authProvider).asData?.value;
    final list = ref.watch(conversationsProvider(folder));
    final locale = t.locale.languageCode;
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(conversationsProvider(folder)),
      child: switch (list) {
        AsyncData(:final value) when value.isEmpty => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              folder == 'requests'
                  ? t('messages.no_requests')
                  : t('messages.empty'),
              style: font(15, height: 1.5, color: p.inkMuted),
            ),
          ],
        ),
        AsyncData(:final value) => ListView.separated(
          itemCount: value.length,
          separatorBuilder: (_, _) => Divider(color: p.line, indent: 76),
          itemBuilder: (context, i) {
            final c = value[i];
            final m = c.lastMessage;
            final preview = m == null
                ? ''
                : '${m.senderId == me?.id ? '${t('messages.you')}: ' : ''}${m.body ?? (m.photo != null ? '📷 ${t('messages.photo')}' : '📍 ${t('messages.location')}')}';
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              onTap: () => context.push('/messages/${c.id}'),
              leading: Avatar(
                name: c.other.displayName,
                url: c.other.avatarUrl,
                size: 48,
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      c.other.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: font(
                        15.5,
                        weight: c.unread > 0 ? 700 : 500,
                        color: p.ink,
                      ),
                    ),
                  ),
                  Text(
                    relativeTime(c.lastMessageAt, locale),
                    style: font(12, color: p.inkMuted),
                  ),
                ],
              ),
              subtitle: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${c.status == 'request' && !c.isRequestToMe ? '${t('messages.pending')} · ' : ''}$preview',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: font(13.5, color: c.unread > 0 ? p.ink : p.inkMuted),
                    ),
                  ),
                  if (c.unread > 0)
                    Badge(
                      backgroundColor: p.accent,
                      textColor: p.accentInk,
                      label: Text('${c.unread}'),
                    ),
                ],
              ),
            );
          },
        ),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(conversationsProvider(folder)),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

/// Sohbet ekranı. [conversationId] yoksa [username] ile yeni sohbet: ilk mesaj gönderilince oluşturulur.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, this.conversationId, this.username});
  final String? conversationId;
  final String? username;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  String? _lastReadFor;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      // Liste ters çevrili: en üste yaklaşınca eski mesajları yükle
      final cid = widget.conversationId;
      if (cid != null &&
          _scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        ref.read(messagesProvider(cid).notifier).loadOlder();
      }
    });
    _maybeRedirectToExisting();
  }

  Future<void> _maybeRedirectToExisting() async {
    final u = widget.username;
    if (widget.conversationId != null || u == null) return;
    try {
      final res = await ref
          .read(apiProvider)
          .get<Map<String, dynamic>?>('/conversations/with/$u');
      if (res != null && mounted) {
        context.pushReplacement('/messages/${res['id']}');
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(Map<String, dynamic> payload) async {
    setState(() => _sending = true);
    final api = ref.read(apiProvider);
    try {
      final cid = widget.conversationId;
      if (cid == null) {
        final c = await api.post<Map<String, dynamic>>('/conversations', {
          'username': widget.username,
          ...payload,
        });
        ref.invalidate(conversationsProvider);
        if (mounted) context.pushReplacement('/messages/${c['id']}');
        return;
      }
      final m = await api.post<Map<String, dynamic>>(
        '/conversations/$cid/messages',
        payload,
      );
      ref.read(messagesProvider(cid).notifier).receive(ChatMessage.fromJson(m));
      ref.invalidate(conversationsProvider);
      ref.invalidate(conversationProvider(cid));
      _text.clear();
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sharePhoto() async {
    final photo = await pickMyPhoto(
      context,
      ref,
      L10n.of(context)('messages.attach_photo'),
    );
    if (photo != null) await _send({'photo_id': photo.id});
  }

  Future<void> _shareLocation() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }
    final pos = await Geolocator.getCurrentPosition();
    await _send({
      'location': {
        'latitude': double.parse(pos.latitude.toStringAsFixed(4)),
        'longitude': double.parse(pos.longitude.toStringAsFixed(4)),
        'name': null,
      },
    });
  }

  Future<void> _act(String action, UserCard other) async {
    final t = L10n.of(context);
    final api = ref.read(apiProvider);
    final cid = widget.conversationId!;
    if (action == 'block') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          content: Text(
            t('messages.block_confirm', {'name': other.displayName}),
          ),
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
    }
    try {
      action == 'block'
          ? await api.post<dynamic>('/users/${other.username}/block')
          : await api.post<dynamic>('/conversations/$cid/$action');
      ref.invalidate(conversationsProvider);
      ref.invalidate(messageUnreadProvider);
      if (action == 'accept') {
        ref.invalidate(conversationProvider(cid));
      } else if (mounted) {
        context.pop();
      }
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    }
  }

  void _markRead(String cid, List<ChatMessage> items, String? meId) {
    if (items.isEmpty ||
        items.last.senderId == meId ||
        _lastReadFor == items.last.id) {
      return;
    }
    _lastReadFor = items.last.id;
    ref
        .read(apiProvider)
        .post<dynamic>('/conversations/$cid/read')
        .then((_) => ref.invalidate(messageUnreadProvider))
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final cid = widget.conversationId;
    if (cid == null) {
      final profile = ref.watch(profileProvider(widget.username!));
      return switch (profile) {
        AsyncData(:final value) => _scaffold(context, null, value, const []),
        AsyncError(:final error) => Scaffold(
          appBar: AppBar(),
          body: ErrorView(error: error),
        ),
        _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
      };
    }
    final conv = ref.watch(conversationProvider(cid));
    final msgs = ref.watch(messagesProvider(cid));
    final me = ref.watch(authProvider).asData?.value;
    if (conv.hasError) {
      return Scaffold(
        appBar: AppBar(),
        body: ErrorView(error: conv.error!),
      );
    }
    final c = conv.asData?.value;
    if (c == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _markRead(cid, msgs.items, me?.id),
    );
    return _scaffold(context, c, c.other, msgs.items);
  }

  Widget _scaffold(
    BuildContext context,
    Conversation? c,
    UserCard other,
    List<ChatMessage> items,
  ) {
    final t = L10n.of(context);
    final p = context.palette;
    final me = ref.watch(authProvider).asData?.value;
    final locale = t.locale.languageCode;
    final last = items.isEmpty ? null : items.last;
    final seen =
        last != null &&
        last.senderId == me?.id &&
        c?.otherLastReadAt != null &&
        !c!.otherLastReadAt!.isBefore(last.createdAt);
    final requestToMe = c != null && c.status == 'request' && c.isRequestToMe;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.palette.surface,
        toolbarHeight: 66,
        titleSpacing: 0,
        title: InkWell(
          onTap: () => context.push('/u/${other.username}'),
          child: Row(
            children: [
              Avatar(name: other.displayName, url: other.avatarUrl, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      other.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: font(17, weight: 700, color: p.ink),
                    ),
                    Text('@${other.username}', style: font(13.5, color: p.inkMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (c != null)
            PopupMenuButton<String>(
              onSelected: (v) => _act(v, other),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'block',
                  child: Text(
                    t('messages.block'),
                    style: font(15, color: p.danger),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: items.isEmpty && c == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        t('messages.new_hint', {'name': other.displayName}),
                        textAlign: TextAlign.center,
                        style: font(14.5, height: 1.5, color: p.inkMuted),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    reverse: true, // en yeni mesaj altta; klavye açılınca liste doğal olarak yukarı kayar
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: items.length + (seen ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (seen && i == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 4, top: 2),
                          child: Text(
                            t('messages.seen'),
                            textAlign: TextAlign.right,
                            style: font(11, color: p.inkMuted),
                          ),
                        );
                      }
                      final idx = items.length - 1 - (i - (seen ? 1 : 0));
                      final m = items[idx];
                      final prev = idx > 0 ? items[idx - 1] : null;
                      final newDay =
                          prev == null ||
                          !DateUtils.isSameDay(prev.createdAt, m.createdAt);
                      return Column(
                        children: [
                          if (newDay)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Text(
                                _day(m.createdAt, locale),
                                style: font(13, weight: 600, color: p.inkMuted),
                              ),
                            ),
                          _Bubble(m: m, mine: m.senderId == me?.id),
                        ],
                      );
                    },
                  ),
          ),
          if (requestToMe)
            Container(
              margin: EdgeInsets.fromLTRB(12, 0, 12, 12 + MediaQuery.paddingOf(context).bottom),
              padding: const EdgeInsets.all(Space.s4),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(Radii.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t('messages.request_from', {'name': other.displayName}),
                    style: font(15, color: p.ink),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t('messages.request_hint'),
                    style: font(13, height: 1.4, color: p.inkMuted),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: () => _act('accept', other),
                          child: Text(t('messages.accept')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: p.surface2, foregroundColor: p.ink),
                          onPressed: () => _act('decline', other),
                          child: Text(t('messages.decline')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (c != null && c.status == 'request' && !c.isRequestToMe)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 0, 6),
                        child: Text(
                          t('messages.pending_hint'),
                          style: font(12, color: p.inkMuted),
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        RoundIconButton(
                          icon: LucideIcons.imagePlus,
                          label: t('messages.attach_photo'),
                          color: p.surface,
                          onPressed: _sending ? null : _sharePhoto,
                        ),
                        const SizedBox(width: 6),
                        RoundIconButton(
                          icon: LucideIcons.locateFixed,
                          label: t('messages.attach_location'),
                          color: p.surface,
                          onPressed: _sending ? null : _shareLocation,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _text,
                            minLines: 1,
                            maxLines: 5,
                            maxLength: 4000,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: t('messages.placeholder'),
                              counterText: '',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(22),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(22),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(22),
                                borderSide: BorderSide(color: p.accent, width: 1.6),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        ValueListenableBuilder(
                          valueListenable: _text,
                          builder: (_, v, _) => IconButton.filled(
                            tooltip: t('messages.send'),
                            onPressed: v.text.trim().isEmpty || _sending
                                ? null
                                : () => _send({'body': v.text.trim()}),
                            style: IconButton.styleFrom(
                              backgroundColor: p.accent,
                              foregroundColor: p.accentInk,
                              disabledBackgroundColor: p.accent.withValues(alpha: 0.4),
                              disabledForegroundColor: p.accentInk,
                              minimumSize: const Size(46, 46),
                            ),
                            icon: const Icon(LucideIcons.send, size: 22),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _day(DateTime d, String locale) {
    final now = DateTime.now();
    if (DateUtils.isSameDay(d, now)) return locale == 'tr' ? 'Bugün' : 'Today';
    if (DateUtils.isSameDay(d, now.subtract(const Duration(days: 1)))) {
      return locale == 'tr' ? 'Dün' : 'Yesterday';
    }
    return DateFormat.yMMMMd(locale).format(d);
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.m, required this.mine});
  final ChatMessage m;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = L10n.of(context);
    final time = DateFormat.Hm(t.locale.languageCode).format(m.createdAt);
    final bg = mine ? p.accent : p.surface;
    final fg = mine ? p.accentInk : p.ink;
    final img = m.photo?.feed;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: mine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (m.photo != null && img != null)
                GestureDetector(
                  onTap: () => context.push('/p/${m.photo!.id}'),
                  child: Container(
                    padding: const EdgeInsets.all(Space.s3),
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(Radii.card),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 300),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(Radii.photo),
                            child: AspectRatio(
                              aspectRatio: img.ratio,
                              child: NetPhoto(url: img.url),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 10, 4, 2),
                          child: Text(
                            m.photo!.title ?? m.photo!.user.displayName,
                            style: font(15, weight: 600, color: p.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (m.location != null)
                GestureDetector(
                  onTap: () => context.push(
                    '/map?lat=${m.location!.latitude}&lng=${m.location!.longitude}&photos=1',
                  ),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.mapPin, size: 20, color: fg),
                        const SizedBox(width: 8),
                        Text(
                          m.location!.name ?? t('messages.shared_location'),
                          style: font(16, weight: 600, color: fg),
                        ),
                      ],
                    ),
                  ),
                ),
              if (m.body != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    m.body!,
                    style: font(15.5, height: 1.4, color: fg),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 3, 4, 0),
                child: Text(time, style: font(12, color: p.inkMuted, tabular: true)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
