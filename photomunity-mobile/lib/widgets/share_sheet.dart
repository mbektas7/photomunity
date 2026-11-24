import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr/qr.dart';
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
  final t = L10n.of(context);
  final lang = t.locale.languageCode;
  final link = '${AppConfig.webUrl}/$lang/p/${photo.id}';
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.palette.bg,
    builder: (_) => _ShareSheet(
      title: t('ui.share'),
      link: link,
      text: photo.title == null ? link : '${photo.title} · $link',
      message: {'photo_id': photo.id},
      whatsappSub: t('share.whatsapp_sub'),
      storySub: t('share.story_sub'),
      story: (_, signed) => renderStoryImage(photo, lang, signature: signed ? '© ${photo.user.displayName}' : null),
      signatureLabel: '© ${photo.user.displayName}',
    ),
  );
}

/// Profil paylaşım menüsü: fotoğraf paylaşımıyla aynı; hikâye görseli profil kartı ve QR kodla, önizlemeli.
Future<void> showProfileShareSheet(BuildContext context, Profile prof) {
  final t = L10n.of(context);
  final lang = t.locale.languageCode;
  final link = '${AppConfig.webUrl}/$lang/u/${prof.username}';
  final labels = ProfileStoryLabels(
    photos: t('share.story_photos'),
    followers: t('share.story_followers'),
    following: t('share.story_following'),
    cta: t('share.story_cta'),
    specialty: prof.specialties.isEmpty ? null : t('specialties.${prof.specialties.first}'),
  );
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.palette.bg,
    builder: (_) => _ShareSheet(
      title: t('share.profile'),
      link: link,
      text: '${prof.displayName} · $link',
      message: {'body': link},
      whatsappSub: t('share.whatsapp_profile_sub'),
      storySub: t('share.story_profile_sub'),
      story: (ref, _) async => renderProfileStoryImage(prof, link, labels, await _recentThumbs(ref, prof)),
      previewStory: true,
    ),
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
  const _ShareSheet({
    required this.title,
    required this.link,
    required this.text,
    required this.message,
    required this.whatsappSub,
    required this.storySub,
    required this.story,
    this.previewStory = false,
    this.signatureLabel,
  });
  final String title;
  final String link;
  final String text;
  final Map<String, dynamic> message; // uygulama içi mesajla gönderilecek içerik
  final String whatsappSub;
  final String storySub;
  final Future<File> Function(WidgetRef ref, bool signed) story;
  final bool previewStory; // hikâye görselini menünün üstünde önizle

  /// Doluysa hikâye görseline isteğe bağlı "© Ad" imzası (varsayılan kapalı).
  final String? signatureLabel;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  bool _busy = false;
  Future<File>? _storyFile; // bir kez çizilir; önizleme ve paylaşım aynı dosyayı kullanır

  String get _link => widget.link;
  String get _text => widget.text;

  bool _signed = false;

  Future<File> _storyImage() => _storyFile ??= widget.story(ref, _signed);

  @override
  void initState() {
    super.initState();
    if (widget.previewStory) _storyImage();
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
        ...widget.message,
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
    try {
      final file = await _storyImage();
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: 'image/png')], sharePositionOrigin: origin),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _storyFile = null; // bir sonraki denemede yeniden çiz
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
              child: Text(widget.title, style: font(18, weight: 700, color: p.ink)),
            ),
            if (widget.previewStory)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  height: 220,
                  child: FutureBuilder<File>(
                    future: _storyFile,
                    builder: (_, snap) => Center(
                      child: snap.hasData
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.file(snap.data!, fit: BoxFit.contain),
                            )
                          : snap.hasError
                          ? const SizedBox.shrink()
                          : const CircularProgressIndicator(),
                    ),
                  ),
                ),
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
                        widget.whatsappSub, _whatsapp),
                    divider(),
                    row(LucideIcons.camera, const Color(0xFFD6249F), Colors.white, t('share.story'),
                        widget.storySub, _story, busy: _busy),
                    if (widget.signatureLabel != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(70, 0, 12, 4),
                        child: ToggleRow(
                          title: t('share.signature'),
                          sub: t('share.signature_sub', {'name': widget.signatureLabel!}),
                          value: _signed,
                          onChanged: (v) => setState(() {
                            _signed = v;
                            _storyFile = null; // imza değişti: görsel yeniden çizilir
                          }),
                        ),
                      ),
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
Future<File> renderStoryImage(PhotoDetail photo, String locale, {String? signature}) async {
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

  // İsteğe bağlı imza: fotoğrafın altında sağda (fotoğrafın üstüne yazılmaz)
  if (signature != null) {
    final sig = text(signature, 30, weight: FontWeight.w600, color: Colors.white70);
    sig.paint(c, Offset(photoRect.right - sig.width, photoRect.bottom + 18));
  }

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

/// Profil hikâyesi görselindeki metinler (çeviri, çizimden önce alınır).
class ProfileStoryLabels {
  const ProfileStoryLabels({
    required this.photos,
    required this.followers,
    required this.following,
    required this.cta,
    this.specialty,
  });
  final String photos, followers, following, cta;
  final String? specialty;
}

Future<ui.Image?> _netImage(String? url) async {
  if (url == null) return null;
  try {
    final bytes = await NetworkAssetBundle(Uri.parse(url)).load(url);
    return (await (await ui.instantiateImageCodec(bytes.buffer.asUint8List())).getNextFrame()).image;
  } catch (_) {
    return null;
  }
}

void _drawCover(Canvas c, ui.Image img, Rect dst, {Paint? paint}) {
  // Kapak/küçük resim alanını doldurur (fotoğraf değil, profil kartı süsü)
  final sr = img.width / img.height, dr = dst.width / dst.height;
  final src = sr > dr
      ? Rect.fromCenter(center: Offset(img.width / 2, img.height / 2), width: img.height * dr, height: img.height.toDouble())
      : Rect.fromCenter(center: Offset(img.width / 2, img.height / 2), width: img.width.toDouble(), height: img.width / dr);
  c.drawImageRect(img, src, dst, paint ?? (Paint()..filterQuality = FilterQuality.high));
}

String _compact(int n) => n >= 1000000
    ? '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M'
    : n >= 1000
    ? '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}K'
    : '$n';

/// Profil hikâyesi (1080×1920): bulanık kapak zemini, kapak + profil fotoğrafı, ad, uzmanlık,
/// istatistikler, son 3 paylaşım ve profile giden QR kod.
Future<File> renderProfileStoryImage(Profile prof, String link, ProfileStoryLabels l, List<String> recent) async {
  const w = 1080.0, h = 1920.0, pad = 66.0;
  final cover = await _netImage(prof.coverUrl);
  final avatar = await _netImage(prof.avatarUrl);
  final thumbs = [for (final u in recent) await _netImage(u)].whereType<ui.Image>().toList();
  final logoData = await rootBundle.load('assets/brand/3.0x/logo.png');
  final logo = (await (await ui.instantiateImageCodec(logoData.buffer.asUint8List())).getNextFrame()).image;

  final rec = ui.PictureRecorder();
  final c = Canvas(rec, const Rect.fromLTWH(0, 0, w, h));
  const full = Rect.fromLTWH(0, 0, w, h);
  c.drawRect(full, Paint()..color = const Color(0xFF0F1115));
  final bgImg = cover ?? (thumbs.isNotEmpty ? thumbs.first : null);
  if (bgImg != null) {
    c.saveLayer(full, Paint());
    _drawCover(c, bgImg, full.inflate(80), paint: Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 50, sigmaY: 50));
    c.drawRect(full, Paint()..color = const Color(0x99000000));
    c.restore();
  }

  TextPainter text(String s, double size, {FontWeight weight = FontWeight.w600, Color color = Colors.white, double? maxW}) =>
      TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(fontFamily: 'BricolageGrotesque', fontSize: size, fontWeight: weight, color: color, height: 1.2),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: maxW ?? w - pad * 2);

  // Üst: logo
  const logoH = 56.0;
  final lw = logoH * logo.width / logo.height;
  c.drawImageRect(logo, Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
      Rect.fromLTWH(pad, 110, lw, logoH),
      Paint()
        ..colorFilter = const ColorFilter.mode(Colors.white, BlendMode.srcIn)
        ..filterQuality = FilterQuality.high);

  // Kart
  final cardTop = 230.0;
  const coverH = 300.0, avatarD = 190.0;
  final cardW = w - pad * 2;
  final name = text(prof.displayName, 64, weight: FontWeight.w700);
  final handle = text(['@${prof.username}', ?l.specialty].join(' · '), 36, weight: FontWeight.w500, color: Colors.white70);
  final thumbH = thumbs.isEmpty ? 0.0 : 260.0;
  final cardH = coverH + avatarD / 2 + 28 + name.height + 8 + handle.height + 40 + 90 + (thumbs.isEmpty ? 40 : 40 + thumbH + 48);
  final card = RRect.fromRectAndRadius(Rect.fromLTWH(pad, cardTop, cardW, cardH), const Radius.circular(48));
  c.drawRRect(card, Paint()..color = const Color(0x1FFFFFFF));
  c.drawRRect(card, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..color = const Color(0x29FFFFFF));
  c.save();
  c.clipRRect(card);
  final coverRect = Rect.fromLTWH(pad, cardTop, cardW, coverH);
  if (cover != null) {
    _drawCover(c, cover, coverRect);
  } else {
    c.drawRect(coverRect, Paint()..color = const Color(0xFF2E5BFF));
  }
  c.restore();

  // Profil fotoğrafı (beyaz halkalı daire)
  final ac = Offset(pad + 48 + avatarD / 2, cardTop + coverH);
  c.drawCircle(ac, avatarD / 2 + 8, Paint()..color = Colors.white);
  final avRect = Rect.fromCircle(center: ac, radius: avatarD / 2);
  c.save();
  c.clipPath(Path()..addOval(avRect));
  if (avatar != null) {
    _drawCover(c, avatar, avRect);
  } else {
    c.drawRect(avRect, Paint()..color = const Color(0xFFE6ECFF));
    final ini = prof.displayName.trim().split(RegExp(r'\s+')).take(2).map((s) => s.isEmpty ? '' : s[0]).join().toUpperCase();
    final tp = text(ini, 72, weight: FontWeight.w700, color: const Color(0xFF2E5BFF));
    tp.paint(c, ac - Offset(tp.width / 2, tp.height / 2));
  }
  c.restore();

  var y = cardTop + coverH + avatarD / 2 + 28;
  name.paint(c, Offset(pad + 48, y));
  y += name.height + 8;
  handle.paint(c, Offset(pad + 48, y));
  y += handle.height + 40;

  // İstatistikler
  var x = pad + 48;
  for (final (n, label) in [
    (prof.photosCount, l.photos),
    (prof.followersCount, l.followers),
    (prof.followingCount, l.following),
  ]) {
    final num = text(_compact(n), 52, weight: FontWeight.w700);
    final lab = text(label, 30, weight: FontWeight.w500, color: Colors.white70);
    num.paint(c, Offset(x, y));
    lab.paint(c, Offset(x, y + num.height));
    x += (num.width > lab.width ? num.width : lab.width) + 64;
  }
  y += 90 + 40;

  // Son paylaşımlar
  if (thumbs.isNotEmpty) {
    const gap = 16.0;
    final tw = (cardW - 96 - gap * 2) / 3;
    for (var i = 0; i < thumbs.length && i < 3; i++) {
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(pad + 48 + i * (tw + gap), y, tw, thumbH), const Radius.circular(24));
      c.save();
      c.clipRRect(r);
      _drawCover(c, thumbs[i], r.outerRect);
      c.restore();
    }
  }

  // Alt: QR kod ve bağlantı
  const qrBox = 230.0;
  final bottom = h - 150 - qrBox;
  final panel = RRect.fromRectAndRadius(Rect.fromLTWH(pad, bottom - 24, cardW, qrBox + 48), const Radius.circular(40));
  c.drawRRect(panel, Paint()..color = const Color(0x1FFFFFFF));
  final qrRect = Rect.fromLTWH(pad + 24, bottom, qrBox, qrBox);
  c.drawRRect(RRect.fromRectAndRadius(qrRect, const Radius.circular(24)), Paint()..color = Colors.white);
  final qr = QrImage(QrCode(payload: QrPayload.fromString(link), errorCorrectLevel: QrErrorCorrectLevel.medium));
  final inner = qrRect.deflate(18);
  final cell = inner.width / qr.moduleCount;
  final dark = Paint()..color = const Color(0xFF14161B);
  for (var r = 0; r < qr.moduleCount; r++) {
    for (var col = 0; col < qr.moduleCount; col++) {
      if (qr.isDark(r, col)) {
        c.drawRect(Rect.fromLTWH(inner.left + col * cell, inner.top + r * cell, cell + 0.5, cell + 0.5), dark);
      }
    }
  }
  final tx = qrRect.right + 36;
  final cta = text(l.cta, 44, weight: FontWeight.w700, maxW: w - pad - 24 - tx);
  final url = text(link.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/(tr|en)/'), '/'), 30,
      weight: FontWeight.w500, color: Colors.white70, maxW: w - pad - 24 - tx);
  final ty = qrRect.center.dy - (cta.height + 10 + url.height) / 2;
  cta.paint(c, Offset(tx, ty));
  url.paint(c, Offset(tx, ty + cta.height + 10));

  final out = await rec.endRecording().toImage(w.toInt(), h.toInt());
  final png = await out.toByteData(format: ui.ImageByteFormat.png);
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/photomunity-profile-${prof.username}.png');
  await file.writeAsBytes(png!.buffer.asUint8List());
  return file;
}

/// Profilin son 3 yayınlanmış fotoğrafının küçük resimleri (görülebiliyorsa).
Future<List<String>> _recentThumbs(WidgetRef ref, Profile prof) async {
  if (!prof.canViewPhotos) return const [];
  try {
    final res = await ref
        .read(apiProvider)
        .get<Map<String, dynamic>>('/users/${prof.username}/photos', query: {'limit': 3});
    return [
      for (final e in (res['items'] as List).take(3))
        PhotoCard.fromJson(e as Map<String, dynamic>).thumb?.url,
    ].whereType<String>().toList();
  } catch (_) {
    return const [];
  }
}
