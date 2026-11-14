import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/photo_widgets.dart';
import '../widgets/viewfinder.dart';

class PhotoScreen extends ConsumerStatefulWidget {
  const PhotoScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<PhotoScreen> createState() => _PhotoScreenState();
}

class _PhotoScreenState extends ConsumerState<PhotoScreen> {
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// İşlenmekte olan fotoğrafın durumunu 2 saniyede bir yoklar.
  void _schedulePoll(PhotoDetail photo) {
    _poll?.cancel();
    if (photo.isProcessing) {
      _poll = Timer(
        const Duration(seconds: 2),
        () => ref.invalidate(photoProvider(widget.id)),
      );
    }
  }

  Future<void> _patch(Map<String, dynamic> body) async {
    try {
      await ref
          .read(apiProvider)
          .patch<Map<String, dynamic>>('/photos/${widget.id}', body);
      ref.invalidate(photoProvider(widget.id));
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    }
  }

  Future<void> _delete({bool confirm = true}) async {
    final t = L10n.of(context);
    if (confirm) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          content: Text(t('photo.delete_confirm')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(t('common.cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(t('common.delete')),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await ref.read(apiProvider).delete<dynamic>('/photos/${widget.id}');
      ref.invalidate(photoPagesProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(photoProvider(widget.id));
    ref.listen(
      photoProvider(widget.id),
      (_, next) => next.whenData(_schedulePoll),
    );

    final me = ref.watch(authProvider).asData?.value;
    final photo = async.asData?.value;
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (photo != null && me != null && me.id != photo.user.id)
            IconButton(
              tooltip: L10n.of(context)('report.button'),
              icon: const Icon(LucideIcons.flag),
              onPressed: () => _report(photo.id),
            ),
        ],
      ),
      // Yenileme sırasında önceki veri gösterilmeye devam eder (titreme olmaz)
      body: async.hasValue
          ? _body(context, async.requireValue)
          : async.hasError
          ? ErrorView(
              error: async.error!,
              onRetry: () => ref.invalidate(photoProvider(widget.id)),
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _body(BuildContext context, PhotoDetail photo) {
    final t = L10n.of(context);
    final p = context.palette;
    final me = ref.watch(authProvider).asData?.value;
    final isOwner = me?.id == photo.user.id;

    if (photo.isProcessing) {
      return _StatusView(
        title: t('photo.processing_title'),
        body: t('photo.processing_body'),
        child: const LinearProgressIndicator(),
      );
    }
    if (photo.status == 'rejected') {
      return _StatusView(
        title: t('photo.rejected_title'),
        body: t('photo.rejected_body'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final r in photo.rejection)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.only(left: 12),
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: p.danger, width: 2)),
                ),
                child: Text(r, style: font(15, color: p.ink)),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go('/upload'),
              child: Text(t('photo.try_another')),
            ),
            TextButton(
              onPressed: () => _delete(confirm: false),
              child: Text(t('photo.discard')),
            ),
          ],
        ),
      );
    }

    final img = photo.full;
    final locale = t.locale.languageCode;
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(photoProvider(widget.id)),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (img != null)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.72,
              ),
              child: AspectRatio(
                aspectRatio: img.ratio,
                child: NetPhoto(
                  url: img.url,
                  fit: BoxFit.contain,
                  semanticLabel: photo.title,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 6),
            child: Row(
              children: [
                Expanded(child: UserRow(user: photo.user, size: 44)),
                LikeButton(photo: photo, large: true),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Divider(color: p.line),
          ),
          if (photo.exif != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Viewfinder(exif: photo.exif!),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (photo.title != null)
                  Text(
                    photo.title!,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                if (photo.description != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    photo.description!,
                    style: font(16, height: 1.55, color: p.ink),
                  ),
                ],
                if (photo.tags.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in photo.tags)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: ShapeDecoration(
                            shape: StadiumBorder(
                              side: BorderSide(color: p.line),
                            ),
                          ),
                          child: Text('#$tag', style: font(14, color: p.inkMuted)),
                        ),
                    ],
                  ),
                ],
                if (photo.location != null) ...[
                  const SizedBox(height: 14),
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => context.push(
                      '/map?lat=${photo.location!.latitude}&lng=${photo.location!.longitude}&photos=1',
                    ),
                    icon: const Icon(LucideIcons.mapPin, size: 18),
                    label: Text(
                      photo.location!.name ??
                          '${photo.location!.latitude.toStringAsFixed(3)}, ${photo.location!.longitude.toStringAsFixed(3)}',
                    ),
                  ),
                ],
                if (isOwner && photo.suggestedLocation != null) ...[
                  const SizedBox(height: 16),
                  Notice(
                    t('photo.suggested_location'),
                    action: TextButton(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      onPressed: () => _patch({
                        'location': photo.suggestedLocation!.toJson(),
                      }),
                      child: Text(t('photo.add_location')),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  [
                    if (photo.publishedAt != null)
                      DateFormat.yMMMMd(locale)
                          .format(photo.publishedAt!.toLocal()),
                    if (photo.width != null && photo.height != null)
                      '${photo.width} × ${photo.height} px',
                  ].join('    '),
                  style: font(13, color: p.inkMuted, tabular: true),
                ),
                if (isOwner) ...[
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => _edit(photo),
                        child: Text(t('photo.edit')),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _delete,
                        child: Text(t('common.delete')),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _report(String id) async {
    final t = L10n.of(context);
    final reason = await pickReportReason(context);
    if (reason == null || !mounted) return;
    try {
      await ref.read(apiProvider).post<dynamic>('/reports', {
        'target_type': 'photo',
        'target_id': id,
        'reason': reason,
      });
      if (mounted) toast(context, t('report.thanks'));
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    }
  }

  Future<void> _edit(PhotoDetail photo) async {
    final t = L10n.of(context);
    final title = TextEditingController(text: photo.title);
    final desc = TextEditingController(text: photo.description);
    final tags = TextEditingController(text: photo.tags.join(', '));
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(c).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: title,
              maxLength: 150,
              decoration: InputDecoration(labelText: t('upload.title')),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: desc,
              maxLength: 2000,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(labelText: t('upload.description')),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: tags,
              decoration: InputDecoration(
                labelText: t('upload.tags'),
                helperText: t('upload.tags_hint'),
              ),
            ),
            if (photo.location != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(c, false);
                    _patch({'clear_location': true});
                  },
                  child: Text(t('photo.remove_location')),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(t('common.save')),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      await _patch({
        'title': title.text,
        'description': desc.text,
        'tags': tags.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
      });
    }
    title.dispose();
    desc.dispose();
    tags.dispose();
  }
}

class _StatusView extends StatelessWidget {
  const _StatusView({
    required this.title,
    required this.body,
    required this.child,
  });
  final String title;
  final String body;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(body, style: font(15, height: 1.5, color: context.palette.inkMuted)),
      const SizedBox(height: 24),
      child,
    ],
  );
}
