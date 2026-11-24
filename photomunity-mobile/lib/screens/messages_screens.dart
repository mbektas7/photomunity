import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/design.dart';
import '../widgets/intro.dart';
import '../widgets/chat_extras.dart';
import '../widgets/community_widgets.dart' show pickMyPhoto;

/// Akış ekranının üst çubuğundaki mesaj simgesi ve okunmamış rozeti.
class MessagesButton extends ConsumerWidget {
  const MessagesButton({super.key, this.filled = false});

  /// Ana sayfa üst çubuğu: beyaz yuvarlak zemin.
  final bool filled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final u = ref.watch(messageUnreadProvider).asData?.value;
    final count = (u?.inbox ?? 0) + (u?.requests ?? 0);
    return IconButton(
      style: filled
          ? IconButton.styleFrom(
              backgroundColor: p.surface,
              fixedSize: const Size(44, 44),
              minimumSize: const Size(44, 44),
            )
          : null,
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
    final requests = ref.watch(messageUnreadProvider).asData?.value.requests ?? 0;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('messages.title')),
          actions: const [IntroButton(module: 'messages'), SizedBox(width: 12)],
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
                      Badge(backgroundColor: p.accent, textColor: p.accentInk, label: Text('$requests')),
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

/// Gelen kutusunun üstünde: bekleyen mesaj istekleri ("2 mesaj isteği · Ayşe ve 1 kişi daha…").
class _RequestsBanner extends ConsumerWidget {
  const _RequestsBanner({required this.padding});
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reqs = ref.watch(conversationsProvider('requests')).asData?.value ?? const [];
    if (reqs.isEmpty) return const SizedBox.shrink();
    final t = L10n.of(context);
    final p = context.palette;
    final first = reqs.first.other.displayName;
    return Padding(
      padding: padding,
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => DefaultTabController.of(context).animateTo(1),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: [
                SizedBox(
                  width: reqs.length > 1 ? 64 : 40,
                  height: 40,
                  child: Stack(
                    children: [
                      for (final (i, c) in reqs.take(2).indexed)
                        Positioned(
                          left: i * 24.0,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: p.surface, width: 2),
                            ),
                            child: Avatar(name: c.other.displayName, url: c.other.avatarUrl, size: 36),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('messages.requests_banner', {'count': reqs.length}), style: font(15, weight: 700)),
                      Text(
                        reqs.length == 1
                            ? t('messages.requests_one', {'name': first})
                            : t('messages.requests_many', {'name': first, 'n': reqs.length - 1}),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: font(13, color: p.inkMuted),
                      ),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight, size: 20, color: p.inkSubtle),
              ],
            ),
          ),
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
            if (folder == 'inbox') const _RequestsBanner(padding: EdgeInsets.only(bottom: 16)),
            Text(
              folder == 'requests' ? t('messages.no_requests') : t('messages.empty'),
              style: font(15, height: 1.5, color: p.inkMuted),
            ),
          ],
        ),
        AsyncData(:final value) => ListView.separated(
          itemCount: value.length + (folder == 'inbox' ? 1 : 0),
          separatorBuilder: (_, i) =>
              folder == 'inbox' && i == 0 ? const SizedBox.shrink() : Divider(color: p.line, indent: 76),
          itemBuilder: (context, i) {
            if (folder == 'inbox') {
              if (i == 0) return const _RequestsBanner(padding: EdgeInsets.fromLTRB(16, 12, 16, 4));
              i -= 1;
            }
            final c = value[i];
            final m = c.lastMessage;
            final preview = m == null
                ? ''
                : '${m.senderId == me?.id ? '${t('messages.you')}: ' : ''}${m.body ?? (m.photo != null || m.image != null
                          ? '📷 ${t('messages.photo')}'
                          : m.gif != null
                          ? 'GIF'
                          : m.location != null
                          ? '📍 ${t('messages.location')}'
                          : t('messages.removed'))}';
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              onTap: () => context.push('/messages/${c.id}'),
              leading: Avatar(name: c.other.displayName, url: c.other.avatarUrl, size: 48),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      c.other.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: font(15.5, weight: c.unread > 0 ? 700 : 500, color: p.ink),
                    ),
                  ),
                  Text(relativeTime(c.lastMessageAt, locale), style: font(12, color: p.inkMuted)),
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
                    Badge(backgroundColor: p.accent, textColor: p.accentInk, label: Text('${c.unread}')),
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
  const ChatScreen({super.key, this.conversationId, this.username, this.initialText});
  final String? conversationId;
  final String? username;

  /// Yazma kutusuna önceden konan metin (ör. "Lisans iste").
  final String? initialText;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  late final _text = TextEditingController(text: widget.initialText);
  final _scroll = ScrollController();
  bool _sending = false;
  bool _uploading = false;
  bool _gifOpen = false;
  ChatMessage? _replyTo; // alıntıyla cevaplanan mesaj
  final _focus = FocusNode();
  String? _lastReadFor;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      // Liste ters çevrili: en üste yaklaşınca eski mesajları yükle
      final cid = widget.conversationId;
      if (cid != null && _scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        ref.read(messagesProvider(cid).notifier).loadOlder();
      }
    });
    _maybeRedirectToExisting();
  }

  Future<void> _maybeRedirectToExisting() async {
    final u = widget.username;
    if (widget.conversationId != null || u == null) return;
    try {
      final res = await ref.read(apiProvider).get<Map<String, dynamic>?>('/conversations/with/$u');
      if (res != null && mounted) {
        context.pushReplacement('/messages/${res['id']}');
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Metin ve GIF: anında sohbete düşer, istek arka planda gider (Instagram gibi).
  /// Gidemezse baloncukta "Gönderilemedi · Tekrar dene" görünür.
  void _sendInstant(String cid, Map<String, dynamic> payload, {GifItem? gif}) {
    final me = ref.read(authProvider).asData?.value;
    if (me == null) return;
    final reply = _replyTo;
    if (reply != null) payload = {...payload, 'reply_to_id': reply.id};
    final local = ChatMessage.pending(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      conversationId: cid,
      senderId: me.id,
      payload: payload,
      body: payload['body'] as String?,
      gif: gif,
      replyTo: reply == null
          ? null
          : MessageQuote(
              id: reply.id,
              senderId: reply.senderId,
              kind: reply.body != null
                  ? 'text'
                  : reply.gif != null
                  ? 'gif'
                  : reply.image != null
                  ? 'image'
                  : reply.photo != null
                  ? 'photo'
                  : 'location',
              preview: reply.body,
            ),
    );
    if (payload.containsKey('body')) _text.clear();
    setState(() => _replyTo = null);
    ref.read(messagesProvider(cid).notifier).addLocal(local);
    _deliver(cid, local);
  }

  Future<void> _deliver(String cid, ChatMessage local) async {
    final ctrl = ref.read(messagesProvider(cid).notifier);
    final api = ref.read(apiProvider);
    try {
      final m = await api.post<Map<String, dynamic>>('/conversations/$cid/messages', local.payload);
      ctrl.resolveLocal(local.id, ChatMessage.fromJson(m));
      if (mounted) {
        ref.invalidate(conversationsProvider);
        ref.invalidate(conversationProvider(cid));
      }
    } catch (e) {
      ctrl.setLocalState(local.id, 'failed');
      // Sınır ya da engel gibi kalıcı hatalarda sebebi göster; ağ hatası baloncuktan anlaşılır
      if (mounted && e is ApiException && e.status >= 400 && e.status < 500) toast(context, errorText(context, e));
    }
  }

  /// Gidemeyen mesaja dokununca: tekrar dene ya da sil.
  Future<void> _failedMenu(String cid, ChatMessage m) async {
    final t = L10n.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.rotateCw),
              title: Text(t('common.retry')),
              onTap: () => Navigator.pop(c, 'retry'),
            ),
            ListTile(
              leading: Icon(LucideIcons.trash2, color: context.palette.danger),
              title: Text(t('messages.failed_delete'), style: TextStyle(color: context.palette.danger)),
              onTap: () => Navigator.pop(c, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    final ctrl = ref.read(messagesProvider(cid).notifier);
    if (choice == 'delete') return ctrl.removeLocal(m.id);
    ctrl.setLocalState(m.id, 'sending');
    _deliver(cid, m.withSendState('sending'));
  }

  Future<void> _send(Map<String, dynamic> payload, {GifItem? gif}) async {
    final cid0 = widget.conversationId;
    if (cid0 != null && (payload.containsKey('body') || gif != null)) {
      return _sendInstant(cid0, payload, gif: gif);
    }
    // Çift dokunma ya da klavyenin gönder tuşu aynı mesajı iki kez göndermesin
    if (_sending) return;
    final draft = _text.text;
    final isText = payload.containsKey('body');
    setState(() => _sending = true);
    // Metin hemen temizlenir; hata olursa geri konur
    if (isText) _text.clear();
    final api = ref.read(apiProvider);
    final reply = _replyTo;
    if (reply != null) payload = {...payload, 'reply_to_id': reply.id};
    try {
      final cid = widget.conversationId;
      if (cid == null) {
        final c = await api.post<Map<String, dynamic>>('/conversations', {'username': widget.username, ...payload});
        ref.invalidate(conversationsProvider);
        if (mounted) context.pushReplacement('/messages/${c['id']}');
        return;
      }
      final m = await api.post<Map<String, dynamic>>('/conversations/$cid/messages', payload);
      ref.read(messagesProvider(cid).notifier).receive(ChatMessage.fromJson(m));
      ref.invalidate(conversationsProvider);
      ref.invalidate(conversationProvider(cid));
      if (mounted && _replyTo?.id == reply?.id) setState(() => _replyTo = null);
    } catch (e) {
      if (isText && _text.text.isEmpty) _text.text = draft;
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attach() async {
    setState(() => _gifOpen = false);
    final choice = await showAttachSheet(context);
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'camera':
        await _sendImage(ImageSource.camera);
      case 'gallery':
        await _sendImage(ImageSource.gallery);
      case 'mine':
        await _sharePhoto();
      case 'location':
        await _shareLocation();
    }
  }

  Future<void> _sendImage(ImageSource source) async {
    setState(() => _uploading = true);
    try {
      final key = await pickAndUploadChatImage(ref, source);
      if (key != null) await _send({'image_key': key});
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _toggleGifs() {
    if (_gifOpen) {
      setState(() => _gifOpen = false);
      _focus.requestFocus();
    } else {
      _focus.unfocus();
      setState(() => _gifOpen = true);
    }
  }

  Future<void> _messageMenu(ChatMessage m, String? meId, UserCard other) async {
    final mine = m.senderId == meId;
    final myReaction = m.reactions.where((r) => r.userId == meId).firstOrNull?.emoji;
    final action = await showMessageMenu(
      context,
      preview: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: _Bubble(m: m, mine: mine, meId: meId, otherName: other.displayName, compact: true),
        ),
      ),
      mine: mine,
      canCopy: m.body != null,
      myReaction: myReaction,
    );
    if (!mounted || action == null) return;
    if (action.startsWith('react:')) {
      await _react(m, action.substring(6), meId);
    } else if (action == 'reply') {
      _startReply(m);
    } else if (action == 'copy') {
      await copyText(context, m.body!);
    } else if (action == 'report') {
      await reportContent(context, ref, 'message', m.id);
    }
  }

  Future<void> _react(ChatMessage m, String emoji, String? meId) async {
    if (meId == null) return;
    try {
      await ref.read(messagesProvider(m.conversationId).notifier).react(m.id, emoji, meId);
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    }
  }

  void _startReply(ChatMessage m) {
    if (m.removed) return;
    HapticFeedback.selectionClick();
    setState(() {
      _replyTo = m;
      _gifOpen = false;
    });
    _focus.requestFocus();
  }

  Future<void> _sharePhoto() async {
    final photo = await pickMyPhoto(context, ref, L10n.of(context)('messages.attach_photo'));
    if (photo != null) await _send({'photo_id': photo.id});
  }

  Future<void> _shareLocation() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
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
          content: Text(t('messages.block_confirm', {'name': other.displayName})),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('common.cancel'))),
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text(t('messages.block'))),
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
    if (items.isEmpty || items.last.senderId == meId || _lastReadFor == items.last.id) {
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead(cid, msgs.items, me?.id));
    return _scaffold(context, c, c.other, msgs.items);
  }

  Widget _scaffold(BuildContext context, Conversation? c, UserCard other, List<ChatMessage> items) {
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
                  child: Text(t('messages.block'), style: font(15, color: p.danger)),
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
                      final newDay = prev == null || !DateUtils.isSameDay(prev.createdAt, m.createdAt);
                      return Column(
                        children: [
                          if (newDay)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Text(_day(m.createdAt, locale), style: font(13, weight: 600, color: p.inkMuted)),
                            ),
                          _Swipe(
                            onReply: m.isLocal ? null : () => _startReply(m),
                            child: GestureDetector(
                              onTap: m.sendState == 'failed' && widget.conversationId != null
                                  ? () => _failedMenu(widget.conversationId!, m)
                                  : null,
                              onLongPress: m.removed || m.isLocal
                                  ? null
                                  : () {
                                      HapticFeedback.mediumImpact();
                                      _messageMenu(m, me?.id, other);
                                    },
                              child: _Bubble(
                                m: m,
                                mine: m.senderId == me?.id,
                                meId: me?.id,
                                otherName: other.displayName,
                                onReact: (e) => _react(m, e, me?.id),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          if (requestToMe)
            Container(
              margin: EdgeInsets.fromLTRB(12, 0, 12, 12 + MediaQuery.paddingOf(context).bottom),
              padding: const EdgeInsets.all(Space.s4),
              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(Radii.card)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t('messages.request_from', {'name': other.displayName}), style: font(15, color: p.ink)),
                  const SizedBox(height: 4),
                  Text(t('messages.request_hint'), style: font(13, height: 1.4, color: p.inkMuted)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(onPressed: () => _act('accept', other), child: Text(t('messages.accept'))),
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
              bottom: !_gifOpen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (c != null && c.status == 'request' && !c.isRequestToMe)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 0, 6),
                        child: Text(t('messages.pending_hint'), style: font(12, color: p.inkMuted)),
                      ),
                    if (_replyTo != null)
                      ReplyChip(
                        title: t('messages.replying_to', {
                          'name': _replyTo!.senderId == me?.id ? t('messages.you') : other.displayName,
                        }),
                        text:
                            _replyTo!.body ??
                            (_replyTo!.gif != null
                                ? 'GIF'
                                : _replyTo!.location != null
                                ? t('messages.location')
                                : t('messages.photo')),
                        onClose: () => setState(() => _replyTo = null),
                      ),
                    if (_uploading)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            const SizedBox(width: 10),
                            Text(t('messages.uploading'), style: font(13, color: p.inkMuted)),
                          ],
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        RoundIconButton(
                          icon: LucideIcons.plus,
                          label: t('messages.attach'),
                          color: p.surface,
                          onPressed: _sending || _uploading ? null : _attach,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _text,
                            focusNode: _focus,
                            onTap: () {
                              if (_gifOpen) setState(() => _gifOpen = false);
                            },
                            minLines: 1,
                            maxLines: 5,
                            maxLength: 4000,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: t('messages.placeholder'),
                              counterText: '',
                              suffixIcon: IconButton(
                                tooltip: t('messages.emoji_gif'),
                                onPressed: _sending ? null : _toggleGifs,
                                icon: Icon(_gifOpen ? LucideIcons.keyboard : LucideIcons.smile, size: 22, color: p.ink),
                              ),
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
                            onPressed: v.text.trim().isEmpty || _sending ? null : () => _send({'body': v.text.trim()}),
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
          if (_gifOpen && !requestToMe)
            Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
              child: GifPanel(
                onPick: (g) {
                  setState(() => _gifOpen = false);
                  _send({
                    'gif': {'id': g.id, 'kind': g.kind},
                  }, gif: g);
                },
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

/// Mesajı sağa kaydırınca cevapla (WhatsApp/Instagram gibi).
class _Swipe extends StatefulWidget {
  const _Swipe({required this.child, required this.onReply});
  final Widget child;
  final VoidCallback? onReply; // null: kaydırarak cevap kapalı (henüz gitmemiş mesaj)

  @override
  State<_Swipe> createState() => _SwipeState();
}

class _SwipeState extends State<_Swipe> {
  double _dx = 0;
  static const _trigger = 64.0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (widget.onReply == null) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (d) {
        final next = (_dx + d.delta.dx).clamp(0.0, 90.0);
        if (_dx < _trigger && next >= _trigger) HapticFeedback.selectionClick();
        setState(() => _dx = next);
      },
      onHorizontalDragEnd: (_) {
        if (_dx >= _trigger) widget.onReply?.call();
        setState(() => _dx = 0);
      },
      onHorizontalDragCancel: () => setState(() => _dx = 0),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Opacity(
            opacity: (_dx / _trigger).clamp(0.0, 1.0),
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(LucideIcons.reply, size: 20, color: p.inkMuted),
            ),
          ),
          AnimatedContainer(
            duration: Duration(milliseconds: _dx == 0 ? 180 : 0),
            transform: Matrix4.translationValues(_dx, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.m,
    required this.mine,
    required this.meId,
    required this.otherName,
    this.onReact,
    this.compact = false,
  });
  final ChatMessage m;
  final bool mine;
  final String? meId;
  final String otherName;
  final void Function(String emoji)? onReact;
  final bool compact; // uzun basma menüsündeki önizleme

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = L10n.of(context);
    final time = DateFormat.Hm(t.locale.languageCode).format(m.createdAt);
    final failed = m.sendState == 'failed';
    final bg = failed
        ? p.surface
        : mine
        ? p.accent
        : p.surface;
    final fg = failed
        ? p.ink
        : mine
        ? p.accentInk
        : p.ink;
    final img = m.photo?.feed;
    final width = MediaQuery.sizeOf(context).width;
    final q = m.replyTo;
    final quote = q == null
        ? null
        : QuoteBlock(
            name: q.senderId == meId ? t('messages.you') : otherName,
            text: quoteText(t, q),
            onDark: mine && (m.body != null),
          );
    // Alıntı, metin varsa metin baloncuğunun içinde; yoksa medyanın üstünde ayrı durur
    final quoteAboveMedia = quote != null && m.body == null;

    Widget media(Widget child, {double maxH = 300}) => Container(
      margin: const EdgeInsets.only(bottom: 4),
      constraints: BoxConstraints(maxHeight: maxH, maxWidth: width * 0.66),
      child: ClipRRect(borderRadius: BorderRadius.circular(16), child: child),
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width * 0.78),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: m.sendState == 'sending' ? 0.6 : 1,
            child: Column(
              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (m.removed)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: p.line),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      t('messages.removed'),
                      style: font(14.5, color: p.inkMuted).copyWith(fontStyle: FontStyle.italic),
                    ),
                  ),
                if (quoteAboveMedia)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: width * 0.66),
                    child: quote,
                  ),
                if (m.image != null)
                  GestureDetector(
                    onTap: compact ? null : () => _openImage(context, m.image!.url),
                    child: media(
                      AspectRatio(
                        aspectRatio: m.image!.ratio,
                        child: NetPhoto(url: m.image!.url),
                      ),
                      maxH: 340,
                    ),
                  ),
                if (m.gif != null)
                  media(
                    AspectRatio(
                      aspectRatio: m.gif!.ratio,
                      child: Image.network(
                        m.gif!.url,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => Container(color: p.surface2),
                      ),
                    ),
                    maxH: m.gif!.kind == 'sticker' ? 160 : 240,
                  ),
                if (m.photo != null && img != null)
                  GestureDetector(
                    onTap: compact ? null : () => context.push('/p/${m.photo!.id}'),
                    child: Container(
                      padding: const EdgeInsets.all(Space.s3),
                      margin: const EdgeInsets.only(bottom: 4),
                      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(Radii.card)),
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
                    onTap: compact
                        ? null
                        : () => context.push('/map?lat=${m.location!.latitude}&lng=${m.location!.longitude}&photos=1'),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
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
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(20),
                      border: failed ? Border.all(color: p.danger.withValues(alpha: 0.45), width: 1.5) : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ?(quoteAboveMedia ? null : quote),
                        Text(m.body!, style: font(15.5, height: 1.4, color: fg)),
                      ],
                    ),
                  ),
                if (m.reactions.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(left: mine ? 0 : 10, right: mine ? 10 : 0, top: 2),
                    child: ReactionPills(reactions: m.reactions, meId: meId, onTap: onReact ?? (_) {}),
                  ),
                if (!compact)
                  Padding(
                    padding: EdgeInsets.fromLTRB(4, m.reactions.isNotEmpty ? 0 : 3, 4, 0),
                    child: switch (m.sendState) {
                      'sending' => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.clock3, size: 12, color: p.inkMuted),
                          const SizedBox(width: 4),
                          Text(t('messages.sending'), style: font(12, color: p.inkMuted)),
                        ],
                      ),
                      'failed' => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.circleAlert, size: 14, color: p.danger),
                          const SizedBox(width: 4),
                          Text(t('messages.failed'), style: font(12.5, weight: 700, color: p.danger)),
                        ],
                      ),
                      _ => Text(time, style: font(12, color: p.inkMuted, tabular: true)),
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openImage(BuildContext context, String url) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (c) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
          body: Center(
            child: InteractiveViewer(
              maxScale: 5,
              child: NetPhoto(url: url, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}
