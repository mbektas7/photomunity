import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../core/config.dart';
import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/community_widgets.dart';
import '../widgets/design.dart';
import '../widgets/intro.dart';

const _coverBg = Color(0xFF1B1E27);

/// Koleksiyon kapağı: en fazla üç kare (büyük + iki küçük); kareler kırpılmaz.
class CollectionMosaic extends StatelessWidget {
  const CollectionMosaic({super.key, required this.covers, this.height = 150});
  final List<Map<String, ImageVariant>> covers;
  final double height;

  @override
  Widget build(BuildContext context) {
    String? url(int i) => i < covers.length ? (covers[i]['thumb'] ?? covers[i]['feed'])?.url : null;
    Widget cell(int i) => ContainPhoto(url: url(i), background: _coverBg);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height,
        child: covers.isEmpty
            ? const ColoredBox(
                color: _coverBg,
                child: Center(child: Icon(LucideIcons.images, color: Colors.white38, size: 30)),
              )
            : covers.length == 1
            ? cell(0)
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 2, child: cell(0)),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: cell(1)),
                        const SizedBox(height: 3),
                        Expanded(child: cell(2)),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Profildeki "Koleksiyonlar" sekmesi (sliver).
class SliverCollections extends ConsumerWidget {
  const SliverCollections({super.key, required this.username, required this.isMe});
  final String username;
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final p = context.palette;
    final async = ref.watch(userCollectionsProvider(username));
    final list = async.asData?.value;
    if (list == null) {
      return SliverToBoxAdapter(
        child: async.hasError
            ? ErrorView(error: async.error!, onRetry: () => ref.invalidate(userCollectionsProvider(username)))
            : const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.list(
        children: [
          if (list.isEmpty && !isMe)
            Text(t('collection.empty_other'), style: font(15, color: p.inkMuted)),
          if (isMe && list.length > 1)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _reorderCollections(context, ref, list, username),
                icon: const Icon(LucideIcons.listOrdered, size: 17),
                label: Text(t('collection.reorder')),
              ),
            ),
          for (var i = 0; i < list.length; i += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _CollectionTile(c: list[i])),
                  const SizedBox(width: 10),
                  Expanded(child: i + 1 < list.length ? _CollectionTile(c: list[i + 1]) : const SizedBox()),
                ],
              ),
            ),
          if (isMe)
            Semantics(
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () async {
                  final id = await createCollection(context, ref);
                  if (id != null && context.mounted) context.push('/collections/$id');
                },
                child: CustomPaint(
                  painter: _Dashed(p.line),
                  child: SizedBox(
                    height: 60,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.plus, size: 20, color: p.accentText),
                        const SizedBox(width: 8),
                        Text(t('collection.new'), style: font(15, weight: 700, color: p.accentText)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Dashed extends CustomPainter {
  _Dashed(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18)).deflate(1);
    final path = Path()..addRRect(rr);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 12) {
        canvas.drawPath(m.extractPath(d, d + 6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Dashed old) => old.color != color;
}

class _CollectionTile extends StatelessWidget {
  const _CollectionTile({required this.c});
  final CollectionCard c;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    return Semantics(
      button: true,
      label: '${c.title}, ${t('collection.photos', {'count': c.photoCount})}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => context.push('/collections/${c.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CollectionMosaic(covers: c.covers),
            const SizedBox(height: 6),
            Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: font(14.5, weight: 700, color: p.ink)),
            Text(t('collection.photos', {'count': c.photoCount}), style: font(12.5, color: p.inkMuted)),
          ],
        ),
      ),
    );
  }
}

/// Başlık ve açıklama formu; kaydedilince değerler döner.
Future<({String title, String? description})?> _editCollectionForm(BuildContext context, {String? title, String? description}) {
  final t = L10n.of(context);
  final titleCtrl = TextEditingController(text: title);
  final descCtrl = TextEditingController(text: description);
  return showModalBottomSheet<({String title, String? description})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(c).bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t(title == null ? 'collection.new' : 'collection.edit'), style: font(18, weight: 700, color: c.palette.ink)),
            const SizedBox(height: 8),
            TextField(
              controller: titleCtrl,
              autofocus: true,
              maxLength: 100,
              onChanged: (_) => set(() {}),
              decoration: InputDecoration(labelText: t('collection.title_label')),
            ),
            TextField(
              controller: descCtrl,
              maxLength: 500,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(labelText: t('collection.description')),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: titleCtrl.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(c, (
                      title: titleCtrl.text.trim(),
                      description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                    )),
              child: Text(t('common.save')),
            ),
          ],
        ),
      ),
    ),
  ).whenComplete(() {
    titleCtrl.dispose();
    descCtrl.dispose();
  });
}

/// Yeni koleksiyon oluşturur (isteğe bağlı ilk kareyle); kimliğini döner.
Future<String?> createCollection(BuildContext context, WidgetRef ref, {String? photoId}) async {
  final form = await _editCollectionForm(context);
  if (form == null || !context.mounted) return null;
  try {
    final res = await ref.read(apiProvider).post<Map<String, dynamic>>('/collections', {
      'title': form.title,
      'description': form.description,
      'photo_ids': [?photoId],
    });
    final me = ref.read(authProvider).asData?.value;
    if (me != null) ref.invalidate(userCollectionsProvider(me.username));
    ref.invalidate(myCollectionsProvider);
    return res['id'] as String;
  } catch (e) {
    if (context.mounted) toast(context, errorText(context, e));
    return null;
  }
}

Future<void> _reorderCollections(BuildContext context, WidgetRef ref, List<CollectionCard> list, String username) async {
  final t = L10n.of(context);
  final order = await showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ReorderSheet(
      title: t('collection.reorder'),
      items: [for (final c in list) (id: c.id, title: c.title, sub: t('collection.photos', {'count': c.photoCount}), thumb: c.covers.firstOrNull?['thumb']?.url)],
    ),
  );
  if (order == null) return;
  try {
    await ref.read(apiProvider).put<dynamic>('/me/collections/order', {'collection_ids': order});
    ref.invalidate(userCollectionsProvider(username));
  } catch (e) {
    if (context.mounted) toast(context, errorText(context, e));
  }
}

typedef _ReorderItem = ({String id, String title, String? sub, String? thumb});

/// Sürükleyerek sıralama (koleksiyonlar ya da koleksiyondaki kareler); [removable] ise satır kaldırılabilir.
class _ReorderSheet extends StatefulWidget {
  const _ReorderSheet({required this.title, required this.items, this.removable = false});
  final String title;
  final List<_ReorderItem> items;
  final bool removable;

  @override
  State<_ReorderSheet> createState() => _ReorderSheetState();
}

class _ReorderSheetState extends State<_ReorderSheet> {
  late final _items = [...widget.items];

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
              child: Row(
                children: [
                  Expanded(child: Text(widget.title, style: font(18, weight: 700, color: p.ink))),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, [for (final x in _items) x.id]),
                    child: Text(t('common.save')),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(t('collection.drag_hint'), style: font(13, color: p.inkMuted)),
            ),
            Expanded(
              child: ReorderableListView.builder(
                itemCount: _items.length,
                onReorderItem: (a, b) => setState(() => _items.insert(b, _items.removeAt(a))),
                itemBuilder: (_, i) {
                  final x = _items[i];
                  return ListTile(
                    key: ValueKey(x.id),
                    leading: SizedBox(
                      width: 52,
                      height: 52,
                      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: ContainPhoto(url: x.thumb)),
                    ),
                    title: Text(x.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: font(15, weight: 600, color: p.ink)),
                    subtitle: x.sub == null ? null : Text(x.sub!, style: font(12.5, color: p.inkMuted)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.removable)
                          IconButton(
                            tooltip: t('collection.remove_photo'),
                            icon: Icon(LucideIcons.x, size: 18, color: p.inkMuted),
                            onPressed: () => setState(() => _items.removeAt(i)),
                          ),
                        ReorderableDragStartListener(index: i, child: Icon(LucideIcons.gripVertical, color: p.inkSubtle)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Koleksiyon detayı: kapak, sıralı kareler; sahibine düzenleme, kare ekleme, sıralama, silme.
class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  bool _busy = false;

  void _changed(PhotoCollection c) {
    ref.invalidate(collectionProvider(widget.id));
    ref.invalidate(userCollectionsProvider(c.owner.username));
    ref.invalidate(myCollectionsProvider);
  }

  Future<void> _call(PhotoCollection c, Future<void> Function() call) async {
    setState(() => _busy = true);
    try {
      await call();
      _changed(c);
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPhoto(PhotoCollection c) async {
    final t = L10n.of(context);
    final photo = await pickMyPhoto(context, ref, t('collection.add_photo'));
    if (photo == null || !mounted) return;
    await _call(c, () => ref.read(apiProvider).post<dynamic>('/collections/${c.id}/photos', {'photo_id': photo.id}));
  }

  Future<void> _edit(PhotoCollection c) async {
    final form = await _editCollectionForm(context, title: c.title, description: c.description ?? '');
    if (form == null || !mounted) return;
    await _call(c, () => ref.read(apiProvider).patch<dynamic>('/collections/${c.id}', {
          'title': form.title,
          'description': form.description ?? '',
        }));
  }

  Future<void> _reorder(PhotoCollection c) async {
    final t = L10n.of(context);
    final order = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReorderSheet(
        title: t('collection.arrange'),
        removable: true,
        items: [
          for (final ph in c.photos)
            (id: ph.id, title: ph.title ?? t('critique.untitled'), sub: null, thumb: ph.thumb?.url),
        ],
      ),
    );
    if (order == null || !mounted) return;
    await _call(c, () => ref.read(apiProvider).put<dynamic>('/collections/${c.id}/photos', {'photo_ids': order}));
  }

  Future<void> _delete(PhotoCollection c) async {
    final t = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        content: Text(t('collection.delete_confirm', {'title': c.title})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(t('common.cancel'))),
          TextButton(onPressed: () => Navigator.pop(d, true), child: Text(t('common.delete'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(apiProvider).delete<dynamic>('/collections/${c.id}');
      ref.invalidate(userCollectionsProvider(c.owner.username));
      ref.invalidate(myCollectionsProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    }
  }

  Future<void> _menu(PhotoCollection c) async {
    final t = L10n.of(context);
    final p = context.palette;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (s) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(LucideIcons.pencil), title: Text(t('collection.edit')), onTap: () => Navigator.pop(s, 'edit')),
            if (c.photos.isNotEmpty)
              ListTile(
                leading: const Icon(LucideIcons.listOrdered),
                title: Text(t('collection.arrange')),
                onTap: () => Navigator.pop(s, 'reorder'),
              ),
            ListTile(
              leading: Icon(LucideIcons.trash2, color: p.danger),
              title: Text(t('collection.delete'), style: TextStyle(color: p.danger)),
              onTap: () => Navigator.pop(s, 'delete'),
            ),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'edit':
        await _edit(c);
      case 'reorder':
        await _reorder(c);
      case 'delete':
        await _delete(c);
    }
  }

  /// Koleksiyonun web bağlantısını sistem paylaşım menüsüyle paylaşır.
  Future<void> _share(BuildContext anchor, PhotoCollection c) async {
    final t = L10n.of(context);
    final link = '${AppConfig.webUrl}/${t.locale.languageCode}/collections/${c.id}';
    final box = anchor.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(ShareParams(
      text: '${c.title} · $link',
      subject: c.title,
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(collectionProvider(widget.id));
    return Scaffold(
      body: async.hasValue
          ? _body(context, async.requireValue)
          : async.hasError
          ? SafeArea(child: ErrorView(error: async.error!, onRetry: () => ref.invalidate(collectionProvider(widget.id))))
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _body(BuildContext context, PhotoCollection c) {
    final t = L10n.of(context);
    final p = context.palette;
    final top = MediaQuery.paddingOf(context).top;
    final cover = c.photos.firstOrNull;
    Widget glass(IconData icon, String label, VoidCallback onTap) => Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: const Color(0x66000000),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 21, color: Colors.white)),
        ),
      ),
    );
    final secondary = FilledButton.styleFrom(
      backgroundColor: p.surface,
      foregroundColor: p.ink,
      minimumSize: const Size.fromHeight(50),
      shape: const StadiumBorder(),
    );
    final primary = FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: const StadiumBorder());
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(collectionProvider(widget.id)),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: 300 + top,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: const Color(0xFF0B0E1A),
                    child: cover?.feed == null
                        ? const SizedBox()
                        : Padding(
                            padding: EdgeInsets.only(top: top),
                            child: NetPhoto(url: cover!.feed!.url, fit: BoxFit.contain),
                          ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xB3000000)],
                        stops: [0.4, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    top: top + 8,
                    child: Row(
                      children: [
                        glass(LucideIcons.chevronLeft, t('ui.back'), () => Navigator.of(context).maybePop()),
                        const Spacer(),
                        IntroGate(
                          module: 'collections',
                          trailing: const SizedBox(width: 8),
                          child: glass(LucideIcons.circleQuestionMark, t('intro.how_it_works'), () => Intros.show(context, 'collections')),
                        ),
                        Builder(
                          builder: (b) => glass(LucideIcons.share2, t('ui.share'), () => _share(b, c)),
                        ),
                        if (c.isMine) ...[const SizedBox(width: 8), glass(LucideIcons.ellipsis, t('ui.more'), () => _menu(c))],
                      ],
                    ),
                  ),
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('collection.series', {'count': c.photoCount}).toUpperCase(),
                          style: font(12, weight: 700, spacing: 0.3, color: Colors.white.withValues(alpha: 0.8)),
                        ),
                        Text(c.title, style: font(26, weight: 700, height: 1.15, color: Colors.white)),
                        if (c.description != null)
                          Text(c.description!, style: font(13.5, color: Colors.white.withValues(alpha: 0.85))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            sliver: SliverToBoxAdapter(
              child: c.isMine
                  ? Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: primary,
                            onPressed: _busy ? null : () => _addPhoto(c),
                            icon: const Icon(LucideIcons.plus, size: 18),
                            label: Text(t('collection.add_photo')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            style: secondary,
                            onPressed: _busy ? null : () => _edit(c),
                            child: Text(t('collection.edit')),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: FollowButton(username: c.owner.username, height: 50)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            style: secondary,
                            onPressed: () => context.push('/u/${c.owner.username}'),
                            child: Text(t('collection.owner_profile'), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          if (c.photos.isEmpty)
            SliverToBoxAdapter(
              child: SectionCard(
                child: Text(t(c.isMine ? 'collection.empty_mine' : 'collection.empty'), style: font(15, color: p.inkMuted)),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: SliverPhotoColumns(photos: c.photos, gap: 4),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

/// Fotoğraf detayından (sahibi): koleksiyona ekle / çıkar, yeni koleksiyon.
Future<void> showAddToCollectionSheet(BuildContext context, String photoId) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _AddToCollection(photoId: photoId),
);

class _AddToCollection extends ConsumerStatefulWidget {
  const _AddToCollection({required this.photoId});
  final String photoId;

  @override
  ConsumerState<_AddToCollection> createState() => _AddToCollectionState();
}

class _AddToCollectionState extends ConsumerState<_AddToCollection> {
  final _local = <String, bool>{};

  Future<void> _toggle(CollectionCard c, bool on) async {
    setState(() => _local[c.id] = on);
    try {
      final api = ref.read(apiProvider);
      on
          ? await api.post<dynamic>('/collections/${c.id}/photos', {'photo_id': widget.photoId})
          : await api.delete<dynamic>('/collections/${c.id}/photos/${widget.photoId}');
      ref.invalidate(collectionProvider(c.id));
      final me = ref.read(authProvider).asData?.value;
      if (me != null) ref.invalidate(userCollectionsProvider(me.username));
    } catch (e) {
      if (!mounted) return;
      setState(() => _local[c.id] = !on);
      toast(context, errorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final async = ref.watch(myCollectionsProvider(widget.photoId));
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(t('collection.add_to'), style: font(18, weight: 700, color: p.ink)),
            ),
            ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: p.accentTint, borderRadius: BorderRadius.circular(12)),
                child: Icon(LucideIcons.folderPlus, color: p.accentText),
              ),
              title: Text(t('collection.new'), style: font(15, weight: 700, color: p.accentText)),
              onTap: () async {
                final id = await createCollection(context, ref, photoId: widget.photoId);
                if (id != null && context.mounted) toast(context, t('collection.added'));
              },
            ),
            Expanded(
              child: switch (async) {
                AsyncData(:final value) when value.isEmpty => Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(t('collection.none_yet'), style: font(14.5, color: p.inkMuted)),
                ),
                AsyncData(:final value) => ListView(
                  children: [
                    for (final c in value)
                      CheckboxListTile(
                        value: _local[c.id] ?? c.containsPhoto ?? false,
                        onChanged: (v) => _toggle(c, v ?? false),
                        secondary: SizedBox(
                          width: 48,
                          height: 48,
                          child: CollectionMosaic(covers: c.covers.take(1).toList(), height: 48),
                        ),
                        title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: font(15, weight: 600, color: p.ink)),
                        subtitle: Text(t('collection.photos', {'count': c.photoCount}), style: font(12.5, color: p.inkMuted)),
                      ),
                  ],
                ),
                AsyncError(:final error) => ErrorView(error: error),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
          ],
        ),
      ),
    );
  }
}
