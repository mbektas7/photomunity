import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import 'common.dart';

/// Mesajlara hızlı tepki emojileri.
const quickReactions = ['❤️', '😂', '😮', '😢', '👍', '🔥'];

/// Yorumu ya da mesajı şikâyet et (sebep seçtirir).
Future<void> reportContent(
  BuildContext context,
  WidgetRef ref,
  String type,
  String id,
) async {
  final t = L10n.of(context);
  final reason = await pickReportReason(context);
  if (reason == null || !context.mounted) return;
  try {
    await ref.read(apiProvider).post<dynamic>('/reports', {
      'target_type': type,
      'target_id': id,
      'reason': reason,
    });
    if (context.mounted) toast(context, t('report.thanks'));
  } catch (e) {
    if (context.mounted) toast(context, errorText(context, e));
  }
}

/// Alıntılanan mesajın kısa metni.
String quoteText(L10n t, MessageQuote q) => switch (q.kind) {
  'image' || 'photo' => q.preview ?? t('messages.photo'),
  'gif' => q.preview ?? 'GIF',
  'location' => q.preview ?? t('messages.location'),
  _ => q.preview ?? '',
};

/// Baloncuğun içindeki alıntı kutusu.
class QuoteBlock extends StatelessWidget {
  const QuoteBlock({
    super.key,
    required this.name,
    required this.text,
    required this.onDark,
  });
  final String name;
  final String text;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = onDark ? p.accentInk : p.ink;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withValues(alpha: 0.16) : p.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
            color: onDark ? Colors.white.withValues(alpha: 0.7) : p.accent,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: font(13, weight: 700, color: fg)),
          Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: font(13, color: fg.withValues(alpha: 0.85)),
          ),
        ],
      ),
    );
  }
}

/// Baloncuğun altındaki tepki hapı (emoji ve sayısı); kendi tepkim vurgulu.
class ReactionPills extends StatelessWidget {
  const ReactionPills({
    super.key,
    required this.reactions,
    required this.meId,
    required this.onTap,
  });
  final List<Reaction> reactions;
  final String? meId;
  final void Function(String emoji) onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final counts = <String, int>{};
    for (final r in reactions) {
      counts[r.emoji] = (counts[r.emoji] ?? 0) + 1;
    }
    final mine = reactions.where((r) => r.userId == meId).firstOrNull?.emoji;
    return Transform.translate(
      offset: const Offset(0, -6),
      child: Wrap(
        spacing: 4,
        children: [
          for (final e in counts.entries)
            GestureDetector(
              onTap: () => onTap(e.key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: e.key == mine
                      ? p.accent.withValues(alpha: 0.14)
                      : p.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: e.key == mine ? p.accent : p.bg,
                    width: 2,
                  ),
                ),
                child: Text(
                  e.value > 1 ? '${e.key} ${e.value}' : e.key,
                  style: font(13, weight: 700, color: p.ink),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Uzun basınca: bulanık arka plan, tepki çubuğu, mesaj ve eylem menüsü.
/// Seçilen eylemi döner: reply, copy, report ya da `react:<emoji>`.
Future<String?> showMessageMenu(
  BuildContext context, {
  required Widget preview,
  required bool mine,
  required bool canCopy,
  String? myReaction,
}) {
  final t = L10n.of(context);
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: t('common.cancel'),
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (c, _, _) {
      final p = c.palette;
      Widget item(String value, String label, IconData icon, {bool danger = false}) => InkWell(
        onTap: () => Navigator.pop(c, value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: font(15.5, weight: 600, color: danger ? p.danger : p.ink),
                ),
              ),
              Icon(icon, size: 20, color: danger ? p.danger : p.ink),
            ],
          ),
        ),
      );
      final align = mine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: align,
              children: [
                Material(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(999),
                  elevation: 6,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final e in quickReactions)
                          InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () => Navigator.pop(c, 'react:$e'),
                            child: Container(
                              width: 42,
                              height: 42,
                              alignment: Alignment.center,
                              decoration: e == myReaction
                                  ? BoxDecoration(
                                      color: p.accent.withValues(alpha: 0.14),
                                      shape: BoxShape.circle,
                                    )
                                  : null,
                              child: Text(e, style: const TextStyle(fontSize: 26)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                IgnorePointer(child: preview),
                const SizedBox(height: 10),
                Material(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(18),
                  elevation: 6,
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(
                    width: 230,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        item('reply', t('messages.reply'), LucideIcons.reply),
                        if (canCopy) ...[
                          Divider(height: 1, color: p.line),
                          item('copy', t('messages.copy'), LucideIcons.copy),
                        ],
                        if (!mine) ...[
                          Divider(height: 1, color: p.line),
                          item('report', t('report.button'), LucideIcons.flag, danger: true),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Metni panoya kopyalar ve bildirir.
Future<void> copyText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) toast(context, L10n.of(context)('messages.copied'));
}

/// + menüsü: kamera, galeri, Photomunity paylaşımlarım, konum. Seçimi döner.
Future<String?> showAttachSheet(BuildContext context) {
  final t = L10n.of(context);
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) {
      final p = c.palette;
      Widget tile(String v, IconData icon, String label, String sub, Color bg, Color fg) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.pop(c, v),
        child: SizedBox(
          width: 80,
          child: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
                child: Icon(icon, size: 26, color: fg),
              ),
              const SizedBox(height: 8),
              Text(label, textAlign: TextAlign.center, style: font(13, weight: 700, color: p.ink)),
              Text(sub, textAlign: TextAlign.center, style: font(11, color: p.inkMuted)),
            ],
          ),
        ),
      );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(22)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    tile('camera', LucideIcons.camera, t('messages.attach_camera'), t('messages.attach_camera_sub'),
                        const Color(0xFFE6ECFF), const Color(0xFF2E5BFF)),
                    tile('gallery', LucideIcons.image, t('messages.attach_gallery'), t('messages.attach_gallery_sub'),
                        const Color(0xFFFDEBD9), const Color(0xFFB45309)),
                    tile('mine', LucideIcons.layoutGrid, t('messages.attach_mine'), 'Photomunity',
                        const Color(0xFFE3F4EC), const Color(0xFF0F6E56)),
                    tile('location', LucideIcons.mapPin, t('messages.location'), t('messages.attach_location_sub'),
                        const Color(0xFFFBE4EA), const Color(0xFFC0264F)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 12, 6, 0),
                child: Text(
                  t('messages.attach_private_hint'),
                  style: font(12, height: 1.45, color: p.inkMuted),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Kameradan ya da galeriden seçilen görseli depoya yükler; mesajda kullanılacak anahtarı döner.
/// Kırpılmaz; telefonda uzun kenar 2048 px'e küçültülür (sunucu da aynı sınırı uygular).
Future<String?> pickAndUploadChatImage(WidgetRef ref, ImageSource source) async {
  final picked = await ImagePicker().pickImage(
    source: source,
    maxWidth: 2048,
    maxHeight: 2048,
    imageQuality: 88,
  );
  if (picked == null) return null;
  final api = ref.read(apiProvider);
  final size = await picked.length();
  final slot = await api.post<Map<String, dynamic>>('/me/images/upload-url', {
    'kind': 'message',
    'content_type': 'image/jpeg',
    'size_bytes': size,
  });
  final fields = (slot['fields'] as Map).map((k, v) => MapEntry('$k', '$v'));
  await api.uploadToStorage(slot['upload_url'] as String, fields, picked.path, 'image.jpg', (_) {});
  return fields['key'];
}

/// Yazı alanının altında açılan GIF / çıkartma paneli (GIPHY).
class GifPanel extends ConsumerStatefulWidget {
  const GifPanel({super.key, required this.onPick});
  final void Function(GifItem gif) onPick;

  @override
  ConsumerState<GifPanel> createState() => _GifPanelState();
}

class _GifPanelState extends ConsumerState<GifPanel> {
  String _kind = 'gif';
  String _q = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final res = ref.watch(gifsProvider((_kind, _q)));
    Widget tab(String kind, String label) => Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _kind = kind),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _kind == kind ? p.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: font(14, weight: _kind == kind ? 700 : 600, color: _kind == kind ? p.ink : p.inkMuted),
          ),
        ),
      ),
    );
    return Container(
      height: 330,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(999)),
            child: Row(children: [tab('gif', 'GIF'), tab('sticker', t('messages.sticker'))]),
          ),
          const SizedBox(height: 8),
          TextField(
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), () {
                if (mounted) setState(() => _q = v.trim());
              });
            },
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: t('messages.gif_search'),
              prefixIcon: const Icon(LucideIcons.search, size: 18),
              filled: true,
              fillColor: p.surface2,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: switch (res) {
              AsyncData(:final value) when value.isEmpty => Center(
                child: Text(t('messages.gif_empty'), style: font(14, color: p.inkMuted)),
              ),
              AsyncData(:final value) => _Masonry(items: value, onPick: widget.onPick),
              AsyncError(:final error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    errorText(context, error),
                    textAlign: TextAlign.center,
                    style: font(14, color: p.inkMuted),
                  ),
                ),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Powered by GIPHY',
              style: font(11, weight: 700, color: p.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// İki sütunlu, kırpmasız ızgara: her öğe kendi en-boy oranıyla, kısa sütuna eklenir.
class _Masonry extends StatelessWidget {
  const _Masonry({required this.items, required this.onPick});
  final List<GifItem> items;
  final void Function(GifItem) onPick;

  @override
  Widget build(BuildContext context) {
    final cols = [<GifItem>[], <GifItem>[]];
    final heights = [0.0, 0.0];
    for (final g in items) {
      final i = heights[0] <= heights[1] ? 0 : 1;
      cols[i].add(g);
      heights[i] += 1 / g.ratio;
    }
    return SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final col in cols) ...[
            Expanded(
              child: Column(
                children: [
                  for (final g in col)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: GestureDetector(
                        onTap: () => onPick(g),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: AspectRatio(
                            aspectRatio: g.ratio,
                            child: Image.network(g.url, fit: BoxFit.contain, gaplessPlayback: true),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (col == cols.first) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

/// Yazı alanının üstündeki "cevap veriyorsun / alıntılıyorsun" şeridi.
class ReplyChip extends StatelessWidget {
  const ReplyChip({
    super.key,
    required this.title,
    required this.text,
    required this.onClose,
    this.icon = LucideIcons.reply,
  });
  final String title;
  final String text;
  final VoidCallback onClose;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: p.accent, width: 3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: p.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: font(13, weight: 700, color: p.accent)),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: font(13, color: p.inkMuted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: L10n.of(context)('common.cancel'),
            onPressed: onClose,
            icon: Icon(LucideIcons.x, size: 18, color: p.inkMuted),
          ),
        ],
      ),
    );
  }
}
