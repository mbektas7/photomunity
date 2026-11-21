import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/community_widgets.dart';
import '../widgets/design.dart' show RoundIconButton;
import 'notifications_screen.dart' show relativeTime;

const _maxImages = 10;
const _types = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heif',
};

/// Yöneticiler için fotoğraflı haber yazma.
class NewsComposeScreen extends ConsumerStatefulWidget {
  const NewsComposeScreen({super.key, required this.slug});
  final String slug;

  @override
  ConsumerState<NewsComposeScreen> createState() => _NewsComposeScreenState();
}

class _NewsComposeScreenState extends ConsumerState<NewsComposeScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _images = <NewsImage>[];
  int _uploading = 0;
  bool _publishing = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _addImages() async {
    final left = _maxImages - _images.length - _uploading;
    if (left <= 0) return;
    final files = await ImagePicker().pickMultiImage(limit: left);
    if (files.isEmpty) return;
    final api = ref.read(apiProvider);
    for (final f in files.take(left)) {
      final type = _types[f.name.split('.').last.toLowerCase()] ?? 'image/jpeg';
      setState(() => _uploading++);
      try {
        final slot = await api.post<Map<String, dynamic>>(
          '/communities/${widget.slug}/news-images/upload-url',
          {'content_type': type, 'size_bytes': await f.length()},
        );
        final fields = (slot['fields'] as Map).map((k, v) => MapEntry('$k', '$v'));
        await api.uploadToStorage(slot['upload_url'] as String, fields, f.path, f.name, (_) {});
        final res = await api.post<Map<String, dynamic>>(
          '/communities/${widget.slug}/news-images/complete',
          {'key': fields['key']},
        );
        if (mounted) setState(() => _images.add(NewsImage.fromJson(res)));
      } catch (e) {
        if (mounted) toast(context, errorText(context, e));
      } finally {
        if (mounted) setState(() => _uploading--);
      }
    }
  }

  Future<void> _publish() async {
    final t = L10n.of(context);
    if (_title.text.trim().isEmpty) {
      toast(context, t('news.title_required'));
      return;
    }
    setState(() => _publishing = true);
    try {
      await ref.read(apiProvider).post<dynamic>('/communities/${widget.slug}/posts', {
        'kind': 'news',
        'title': _title.text.trim(),
        'body': _body.text.trim().isEmpty ? null : _body.text.trim(),
        'images': [for (final i in _images) i.toJson()],
      });
      ref.invalidate(communityPostsProvider(widget.slug));
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final community = ref.watch(communityProvider(widget.slug)).asData?.value;
    final busy = _publishing || _uploading > 0;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        leading: IconButton(
          tooltip: t('ui.close'),
          icon: const Icon(LucideIcons.x, size: 26),
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: Text(
          community == null ? t('news.write') : t('news.write_in', {'name': community.name}),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: font(18, weight: 700, color: p.ink),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton(
              onPressed: busy ? null : _publish,
              child: BusyLabel(busy: _publishing, label: t('community.publish')),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(22)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _title,
                  maxLength: 200,
                  style: font(18, weight: 700, color: p.ink),
                  decoration: InputDecoration(labelText: t('community.news_title'), counterText: ''),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _body,
                  maxLength: 5000,
                  minLines: 4,
                  maxLines: 12,
                  style: font(15, height: 1.5, color: p.ink),
                  decoration: InputDecoration(labelText: t('community.news_body'), alignLabelWithHint: true),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
            child: Row(
              children: [
                Expanded(child: Text(t('news.photos'), style: font(15, weight: 700, color: p.ink))),
                Text('${_images.length} / $_maxImages', style: font(12.5, color: p.inkMuted)),
              ],
            ),
          ),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              // Önizleme küçük karelerdir; detayda fotoğraflar kırpılmadan gösterilir
              for (final (i, img) in _images.indexed)
                Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(borderRadius: BorderRadius.circular(14), child: NetPhoto(url: img.url)),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: IconButton(
                        tooltip: t('news.remove_photo'),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0x9914161B),
                          minimumSize: const Size(30, 30),
                          fixedSize: const Size(30, 30),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: busy ? null : () => setState(() => _images.removeAt(i)),
                        icon: const Icon(LucideIcons.x, size: 16, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              for (var i = 0; i < _uploading; i++)
                Container(
                  decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(14)),
                  child: const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                ),
              if (_images.length + _uploading < _maxImages)
                Semantics(
                  button: true,
                  label: t('news.add_photos'),
                  excludeSemantics: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _publishing ? null : _addImages,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: p.ringIdle, width: 1.5),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.plus, size: 22, color: p.inkMuted),
                          const SizedBox(height: 4),
                          Text(t('news.add_photos'), style: font(12.5, weight: 600, color: p.inkMuted)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Haber detayı: başlık, yazar, yana kaydırılan galeri ve tüm metin.
class NewsDetailScreen extends ConsumerStatefulWidget {
  const NewsDetailScreen({super.key, required this.slug, required this.id});
  final String slug;
  final String id;

  @override
  ConsumerState<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends ConsumerState<NewsDetailScreen> {
  int _page = 0;
  PageController? _pager;

  @override
  void dispose() {
    _pager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final community = ref.watch(communityProvider(widget.slug)).asData?.value;
    final async = ref.watch(communityPostProvider((widget.slug, widget.id)));
    final post = async.asData?.value;
    final width = MediaQuery.sizeOf(context).width;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 0,
        leadingWidth: 70,
        automaticallyImplyLeading: false,
        leading: Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Center(
            child: RoundIconButton(
              icon: LucideIcons.chevronLeft,
              label: t('ui.back'),
              onPressed: () => context.canPop() ? context.pop() : context.go('/c/${widget.slug}'),
            ),
          ),
        ),
        title: community == null
            ? null
            : InkWell(
                borderRadius: BorderRadius.circular(Radii.box),
                onTap: () => context.push('/c/${widget.slug}'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CommunityLogo(name: community.name, url: community.logoUrl, size: 34),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(community.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: font(14.5, weight: 700, color: p.ink)),
                          if (post != null)
                            Text('${t('news.label')} · ${relativeTime(post.createdAt, t.locale.languageCode)}',
                                style: font(12, color: p.inkMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
      body: post == null
          ? (async.hasError
                ? ErrorView(error: async.error!, onRetry: () => ref.invalidate(communityPostProvider((widget.slug, widget.id))))
                : const Center(child: CircularProgressIndicator()))
          : ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: Text(post.title ?? '', style: font(26, weight: 700, height: 1.15, spacing: -0.8, color: p.ink)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: InkWell(
                    onTap: () => context.push('/u/${post.author.username}'),
                    child: Row(
                      children: [
                        Avatar(name: post.author.displayName, url: post.author.avatarUrl, size: 28),
                        const SizedBox(width: 8),
                        Text(post.author.displayName, style: font(13.5, color: p.inkMuted)),
                      ],
                    ),
                  ),
                ),
                if (post.images.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  // Yükseklik en uzun kareye göre (en fazla 4:5); her kare kendi oranında, kırpılmadan, üste hizalı
                  SizedBox(
                    height: (width * (post.images.length > 1 ? 0.9 : 1) - 16) /
                        post.images.map((i) => i.ratio).fold<double>(0.8, (a, b) => a > b ? b : a).clamp(0.8, 10),
                    child: PageView.builder(
                      controller: _pager ??= PageController(viewportFraction: post.images.length > 1 ? 0.9 : 1),
                      padEnds: post.images.length == 1,
                      itemCount: post.images.length,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemBuilder: (_, i) => Padding(
                        padding: EdgeInsets.only(left: i == 0 ? 12 : 4, right: 4),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                              fullscreenDialog: true,
                              builder: (_) => FullscreenGallery(images: post.images, initial: i),
                            )),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: AspectRatio(
                                aspectRatio: post.images[i].ratio,
                                child: NetPhoto(url: post.images[i].url, fit: BoxFit.contain),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (post.images.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < post.images.length; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: i == _page ? 18 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: i == _page ? p.ink : p.ringIdle,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
                if (post.body != null)
                  Container(
                    margin: const EdgeInsets.fromLTRB(12, 14, 12, 0),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(22)),
                    child: Text(post.body!, style: font(15.5, height: 1.55, color: p.ink)),
                  ),
              ],
            ),
    );
  }
}

/// Tam ekran galeri: kaydırılır, yakınlaştırılır, kırpılmaz.
class FullscreenGallery extends StatefulWidget {
  const FullscreenGallery({super.key, required this.images, this.initial = 0});
  final List<NewsImage> images;
  final int initial;

  @override
  State<FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<FullscreenGallery> {
  late int _page = widget.initial;
  late final _controller = PageController(initialPage: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: t('ui.close'),
          icon: const Icon(LucideIcons.x, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: widget.images.length > 1
            ? Text('${_page + 1} / ${widget.images.length}', style: font(15, weight: 600, color: Colors.white))
            : null,
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _page = i),
        itemBuilder: (_, i) => InteractiveViewer(
          maxScale: 5,
          child: Center(child: NetPhoto(url: widget.images[i].url, fit: BoxFit.contain)),
        ),
      ),
    );
  }
}
