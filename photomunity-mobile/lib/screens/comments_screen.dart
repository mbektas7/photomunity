import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/chat_extras.dart';
import '../widgets/common.dart';
import '../widgets/design.dart';

/// Fotoğraf yorumları: yorum, tek seviye cevap, alıntı.
class CommentsScreen extends ConsumerStatefulWidget {
  const CommentsScreen({super.key, required this.photoId});
  final String photoId;

  @override
  ConsumerState<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends ConsumerState<CommentsScreen> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  PhotoComment? _replyTo;
  PhotoComment? _quote;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        ref.read(commentsProvider(widget.photoId).notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(commentsProvider(widget.photoId).notifier)
          .add(body, parentId: _replyTo?.id, quoteId: _quote?.id);
      _text.clear();
      if (mounted) {
        setState(() {
          _replyTo = null;
          _quote = null;
        });
      }
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _reply(PhotoComment c) {
    HapticFeedback.selectionClick();
    setState(() {
      _replyTo = c;
      _quote = null;
    });
    _focus.requestFocus();
  }

  void _quoteIt(PhotoComment c) {
    HapticFeedback.selectionClick();
    setState(() {
      // Alıntılanan yorum bir cevapsa yeni yorum da aynı konuşmaya düşer
      _quote = c;
      _replyTo = c.parentId != null ? c : null;
    });
    _focus.requestFocus();
  }

  Future<void> _more(PhotoComment c) async {
    final t = L10n.of(context);
    final p = context.palette;
    final me = ref.read(authProvider).asData?.value;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (s) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.copy),
              title: Text(t('messages.copy')),
              onTap: () => Navigator.pop(s, 'copy'),
            ),
            if (c.canDelete)
              ListTile(
                leading: Icon(LucideIcons.trash2, color: p.danger),
                title: Text(t('comments.delete'), style: TextStyle(color: p.danger)),
                onTap: () => Navigator.pop(s, 'delete'),
              ),
            if (me != null && c.user.id != me.id)
              ListTile(
                leading: Icon(LucideIcons.flag, color: p.danger),
                title: Text(t('report.button'), style: TextStyle(color: p.danger)),
                onTap: () => Navigator.pop(s, 'report'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'copy':
        await copyText(context, c.body);
      case 'report':
        await reportContent(context, ref, 'comment', c.id);
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            content: Text(t(c.parentId == null && c.replyCount > 0 ? 'comments.delete_confirm_thread' : 'comments.delete_confirm')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: Text(t('common.cancel'))),
              TextButton(onPressed: () => Navigator.pop(d, true), child: Text(t('comments.delete'))),
            ],
          ),
        );
        if (ok != true) return;
        try {
          await ref.read(commentsProvider(widget.photoId).notifier).remove(c);
        } catch (e) {
          if (mounted) toast(context, errorText(context, e));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final photo = ref.watch(photoProvider(widget.photoId)).asData?.value;
    final state = ref.watch(commentsProvider(widget.photoId));
    final me = ref.watch(authProvider).asData?.value;
    final img = photo?.feed;

    Widget composer() {
      if (photo == null) return const SizedBox.shrink();
      if (!photo.canComment) {
        final key = me == null
            ? 'comments.sign_in'
            : photo.commentPolicy == 'off'
            ? 'comments.closed'
            : photo.commentPolicy == 'followers'
            ? 'comments.followers_only'
            : 'comments.not_allowed';
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              children: [
                Icon(LucideIcons.lock, size: 18, color: p.inkMuted),
                const SizedBox(width: 10),
                Expanded(child: Text(t(key), style: font(14, color: p.inkMuted))),
              ],
            ),
          ),
        );
      }
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_quote != null)
                ReplyChip(
                  icon: LucideIcons.quote,
                  title: t('comments.quoting', {'name': _quote!.user.displayName}),
                  text: _quote!.body,
                  onClose: () => setState(() {
                    _quote = null;
                    _replyTo = null;
                  }),
                )
              else if (_replyTo != null)
                ReplyChip(
                  title: t('messages.replying_to', {'name': _replyTo!.user.displayName}),
                  text: _replyTo!.body,
                  onClose: () => setState(() => _replyTo = null),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 2000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: t('comments.placeholder'),
                        counterText: '',
                        isDense: true,
                        filled: true,
                        fillColor: p.surface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ValueListenableBuilder(
                    valueListenable: _text,
                    builder: (_, v, _) => IconButton.filled(
                      tooltip: t('messages.send'),
                      onPressed: v.text.trim().isEmpty || _sending ? null : _send,
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
      );
    }

    final items = <Widget>[];
    for (final c in state.items) {
      items.add(_CommentTile(c: c, onReply: _reply, onQuote: _quoteIt, onMore: _more, canWrite: photo?.canComment ?? false));
      final replies = state.replies[c.id];
      if (replies != null) {
        for (final r in replies) {
          items.add(_CommentTile(c: r, indent: true, onReply: _reply, onQuote: _quoteIt, onMore: _more, canWrite: photo?.canComment ?? false));
        }
      }
      final shown = replies?.length ?? 0;
      if (c.replyCount > shown) {
        items.add(
          Padding(
            padding: const EdgeInsets.only(left: 46, bottom: 6),
            child: GestureDetector(
              onTap: () => ref.read(commentsProvider(widget.photoId).notifier).loadReplies(c.id),
              child: Text(
                '— ${t('comments.show_replies', {'count': '${c.replyCount - shown}'})}',
                style: font(12.5, weight: 700, color: p.accentText),
              ),
            ),
          ),
        );
      }
    }

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          photo?.title ?? t('comments.title'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: font(16.5, weight: 700, color: p.ink),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(commentsProvider(widget.photoId));
                ref.invalidate(photoProvider(widget.photoId));
              },
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  if (img != null)
                    GestureDetector(
                      onTap: () => context.pop(),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          height: 120,
                          color: p.surface2,
                          child: NetPhoto(url: img.url, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                    decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(22)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 10, 0, 2),
                          child: Text.rich(
                            TextSpan(
                              text: t('comments.title'),
                              style: font(15, weight: 700, color: p.ink),
                              children: [
                                TextSpan(
                                  text: ' · ${state.total}',
                                  style: font(15, weight: 600, color: p.inkMuted),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (photo?.commentPolicy == 'off')
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(t('comments.closed'), style: font(14, color: p.inkMuted)),
                          )
                        else if (state.items.isEmpty && state.loading)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (state.items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(t('comments.empty'), style: font(14, color: p.inkMuted)),
                          ),
                        ...items,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          composer(),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.c,
    required this.onReply,
    required this.onQuote,
    required this.onMore,
    required this.canWrite,
    this.indent = false,
  });
  final PhotoComment c;
  final bool indent;
  final bool canWrite;
  final void Function(PhotoComment) onReply;
  final void Function(PhotoComment) onQuote;
  final void Function(PhotoComment) onMore;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final locale = t.locale.languageCode;
    return Padding(
      padding: EdgeInsets.fromLTRB(indent ? 46 : 0, 10, 0, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => context.push('/u/${c.user.username}'),
            child: Avatar(name: c.user.displayName, url: c.user.avatarUrl, size: indent ? 32 : 36),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    Text(c.user.displayName, style: font(13.5, weight: 700, color: p.ink)),
                    if (c.byPhotoOwner)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: p.accentTint, borderRadius: BorderRadius.circular(6)),
                        child: Text(t('comments.photographer'), style: font(11, weight: 700, color: p.accentText)),
                      ),
                    Text('· ${relativeTime(c.createdAt, locale)}', style: font(13, color: p.inkMuted)),
                  ],
                ),
                if (c.hasQuote)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: QuoteBlock(
                      name: c.quoteUser?.displayName ?? '',
                      text: c.quoteBody ?? t('comments.deleted'),
                      onDark: false,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(c.body, style: font(14.5, height: 1.45, color: p.ink)),
                ),
                Row(
                  children: [
                    if (canWrite) ...[
                      _Action(label: t('messages.reply'), onTap: () => onReply(c)),
                      _Action(label: t('comments.quote'), onTap: () => onQuote(c)),
                    ],
                    const Spacer(),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: t('ui.more'),
                      onPressed: () => onMore(c),
                      icon: Icon(LucideIcons.ellipsis, size: 18, color: p.inkMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 16, 6),
      child: Text(label, style: font(12.5, weight: 700, color: context.palette.inkMuted)),
    ),
  );
}
