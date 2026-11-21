import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';
import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import 'common.dart';
import 'design.dart';

/// Fotoğraf paylaşım menüsü: uygulama içi mesaj, WhatsApp, Instagram hikâyesi
/// (EXIF şeritli hazır görsel), diğer uygulamalar, bağlantıyı kopyala.
Future<void> showPhotoShareSheet(BuildContext context, PhotoDetail photo) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.palette.bg,
    builder: (_) => _ShareSheet(photo: photo),
  );
}

/// Fotoğrafın üstündeki EXIF şeridindeki parçalar (gövde, odak, diyafram, enstantane, ISO).
List<String> exifParts(Exif? e, String locale) => e == null
    ? const []
    : [
        e.camera,
        formatFocal(e.focalLength),
        formatAperture(e.aperture),
        formatShutter(e.shutter, locale),
        if (e.iso != null) 'ISO ${e.iso}',
      ].whereType<String>().toList();

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({required this.photo});
  final PhotoDetail photo;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  bool _busy = false;

  String get _link {
    final lang = L10n.of(context).locale.languageCode;
    return '${AppConfig.webUrl}/$lang/p/${widget.photo.id}';
  }

  String get _text {
    final title = widget.photo.title;
    return title == null ? _link : '$title · $_link';
  }

  Rect? _origin() {
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _sendTo(UserCard u) async {
    final t = L10n.of(context);
    try {
      await ref.read(apiProvider).post<dynamic>('/conversations', {
        'username': u.username,
        'photo_id': widget.photo.id,
      });
      ref.invalidate(conversationsProvider);
      if (!mounted) return;
      Navigator.pop(context);
      toast(context, t('share.sent', {'name': u.displayName}));
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    }
  }

  Future<void> _search() async {
    final u = await showModalBottomSheet<UserCard>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _UserPicker(),
    );
    if (u != null) await _sendTo(u);
  }

  Future<void> _whatsapp() async {
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_text)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _story() async {
    if (_busy) return;
    setState(() => _busy = true);
    final origin = _origin();
    final locale = L10n.of(context).locale.languageCode;
    try {
      final file = await renderStoryImage(widget.photo, locale);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: 'image/png')], sharePositionOrigin: origin),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _other() async {
    await SharePlus.instance.share(ShareParams(text: _text, sharePositionOrigin: _origin()));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _copy() async {
    final t = L10n.of(context);
    await Clipboard.setData(ClipboardData(text: _link));
    if (!mounted) return;
    Navigator.pop(context);
    toast(context, t('ui.link_copied'));
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final me = ref.watch(authProvider).asData?.value;
    final recent = me == null
        ? const <Conversation>[]
        : (ref.watch(conversationsProvider('inbox')).asData?.value ?? const <Conversation>[])
            .where((c) => c.status == 'accepted')
            .take(8)
            .toList();
    Widget row(IconData icon, Color bg, Color fg, String title, String? sub, VoidCallback onTap, {bool busy = false}) =>
        InkWell(
          onTap: busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
                  child: busy
                      ? Padding(padding: const EdgeInsets.all(11), child: CircularProgressIndicator(strokeWidth: 2, color: fg))
                      : Icon(icon, size: 20, color: fg),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: font(15, weight: 700, color: p.ink)),
                      if (sub != null) Text(sub, style: font(12.5, color: p.inkMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
    Widget divider() => Padding(padding: const EdgeInsets.only(left: 70), child: Divider(height: 1, color: p.line));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text(t('ui.share'), style: font(18, weight: 700, color: p.ink)),
            ),
            if (me != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(t('share.in_app'), style: font(13, weight: 700, color: p.inkMuted)),
              ),
              SizedBox(
                height: 84,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final c in recent)
                      _Person(
                        label: c.other.displayName.split(' ').first,
                        child: Avatar(name: c.other.displayName, url: c.other.avatarUrl, size: 56),
                        onTap: () => _sendTo(c.other),
                      ),
                    _Person(
                      label: t('share.search'),
                      onTap: _search,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(color: p.surface, shape: BoxShape.circle),
                        child: Icon(LucideIcons.search, size: 22, color: p.ink),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(22)),
              clipBehavior: Clip.antiAlias,
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  children: [
                    row(LucideIcons.messageCircle, const Color(0xFF25D366), Colors.white, t('share.whatsapp'),
                        t('share.whatsapp_sub'), _whatsapp),
                    divider(),
                    row(LucideIcons.camera, const Color(0xFFD6249F), Colors.white, t('share.story'),
                        t('share.story_sub'), _story, busy: _busy),
                    divider(),
                    row(LucideIcons.share, p.surface2, p.ink, t('share.other'), t('share.other_sub'), _other),
                    divider(),
                    row(LucideIcons.link, p.surface2, p.ink, t('share.copy'), null, _copy),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Person extends StatelessWidget {
  const _Person({required this.label, required this.child, required this.onTap});
  final String label;
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 64,
        child: Column(
          children: [
            child,
            const SizedBox(height: 6),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: font(12, weight: 600, color: context.palette.ink)),
          ],
        ),
      ),
    ),
  );
}

/// Mesaj gönderilecek kişiyi ara.
class _UserPicker extends ConsumerStatefulWidget {
  const _UserPicker();
  @override
  ConsumerState<_UserPicker> createState() => _UserPickerState();
}

class _UserPickerState extends ConsumerState<_UserPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final res = ref.watch(userSearchProvider(_q));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(prefixIcon: const Icon(LucideIcons.search), hintText: t('share.search_hint')),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final u in res.asData?.value ?? const <UserCard>[])
                    ListTile(
                      leading: Avatar(name: u.displayName, url: u.avatarUrl, size: 40),
                      title: Text(u.displayName),
                      subtitle: Text('@${u.username}'),
                      onTap: () => Navigator.pop(context, u),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Instagram hikâyesi boyutunda (1080×1920) paylaşım görseli: koyu zemin, fotoğraf
/// kırpılmadan ortada, altında EXIF şeridi, en altta Photomunity logosu.
Future<File> renderStoryImage(PhotoDetail photo, String locale) async {
  const w = 1080.0, h = 1920.0, pad = 72.0;
  final img = photo.full ?? photo.thumb;
  if (img == null) throw StateError('no image');
  final bytes = await NetworkAssetBundle(Uri.parse(img.url)).load(img.url);
  final photoImg = (await (await ui.instantiateImageCodec(bytes.buffer.asUint8List())).getNextFrame()).image;
  final logoData = await rootBundle.load('assets/brand/3.0x/logo.png');
  final logo = (await (await ui.instantiateImageCodec(logoData.buffer.asUint8List())).getNextFrame()).image;

  final rec = ui.PictureRecorder();
  final c = Canvas(rec, const Rect.fromLTWH(0, 0, w, h));
  c.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF0B0D12));

  TextPainter text(String s, double size, {FontWeight weight = FontWeight.w600, Color color = Colors.white}) =>
      TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(fontFamily: 'BricolageGrotesque', fontSize: size, fontWeight: weight, color: color, height: 1.2),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: w - pad * 2);

  final parts = exifParts(photo.exif, locale);
  final title = photo.title == null ? null : text(photo.title!, 52, weight: FontWeight.w700);
  final by = text('${photo.user.displayName}${photo.place == null ? '' : ' · ${photo.place}'}', 34,
      weight: FontWeight.w500, color: Colors.white70);
  final exif = parts.isEmpty ? null : text(parts.join('   '), 32);

  // Fotoğraf alanı: başlık/logoya yer bırakarak, oran korunur
  const logoH = 64.0;
  final topText = (title?.height ?? 0) + 14 + by.height;
  final maxPhotoH = h - 220 - topText - 60 - logoH - 160;
  final maxPhotoW = w - pad * 2;
  final ratio = photoImg.width / photoImg.height;
  var pw = maxPhotoW, ph = maxPhotoW / ratio;
  if (ph > maxPhotoH) {
    ph = maxPhotoH;
    pw = ph * ratio;
  }
  final blockH = topText + 48 + ph;
  var y = (h - logoH - 120 - blockH) / 2 + 20;
  if (title != null) {
    title.paint(c, Offset(pad, y));
    y += title.height + 14;
  }
  by.paint(c, Offset(pad, y));
  y += by.height + 48;

  final photoRect = Rect.fromLTWH((w - pw) / 2, y, pw, ph);
  final rr = RRect.fromRectAndRadius(photoRect, const Radius.circular(28));
  c.save();
  c.clipRRect(rr);
  c.drawImageRect(photoImg, Rect.fromLTWH(0, 0, photoImg.width.toDouble(), photoImg.height.toDouble()), photoRect,
      Paint()..filterQuality = FilterQuality.high);
  if (exif != null) {
    final band = Rect.fromLTWH(photoRect.left, photoRect.bottom - exif.height - 48, pw, exif.height + 48);
    c.drawRect(band, Paint()..color = const Color(0x8C080A14));
    final shadow = TextPainter(
      text: TextSpan(
        text: parts.join('   '),
        style: const TextStyle(
          fontFamily: 'BricolageGrotesque',
          fontSize: 32,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          height: 1.2,
          shadows: [Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: pw - 56);
    shadow.paint(c, Offset(band.left + 28, band.top + 24));
  }
  c.restore();

  final lw = logoH * logo.width / logo.height;
  c.drawImageRect(
    logo,
    Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
    Rect.fromLTWH((w - lw) / 2, h - 120 - logoH, lw, logoH),
    Paint()
      ..colorFilter = const ColorFilter.mode(Colors.white, BlendMode.srcIn)
      ..filterQuality = FilterQuality.high,
  );

  final out = await rec.endRecording().toImage(w.toInt(), h.toInt());
  final png = await out.toByteData(format: ui.ImageByteFormat.png);
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/photomunity-${photo.id}.png');
  await file.writeAsBytes(png!.buffer.asUint8List());
  return file;
}
