import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/comment_policy.dart';
import '../widgets/common.dart';
import '../widgets/design.dart';
import '../widgets/share_sheet.dart';

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
    final p = context.palette;
    final t = L10n.of(context);
    final isOwner = photo != null && me?.id == photo.user.id;
    final when = photo?.publishedAt ?? photo?.exif?.takenAt;
    final prof = photo == null ? null : ref.watch(profileProvider(photo.user.username)).asData?.value;
    final meta = [
      photo?.place ?? prof?.city,
      if (when != null) relativeTime(when, t.locale.languageCode),
    ].whereType<String>().join(' · ');
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 72,
        leadingWidth: 70,
        titleSpacing: 0,
        automaticallyImplyLeading: false,
        leading: Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Center(
            child: RoundIconButton(
              icon: LucideIcons.chevronLeft,
              label: t('ui.back'),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
        // Yazar üstte: kim, nerede, ne zaman; fotoğraf altta
        title: photo == null
            ? null
            : InkWell(
                borderRadius: BorderRadius.circular(Radii.box),
                onTap: () => context.push('/u/${photo.user.username}'),
                child: Row(
                  children: [
                    Avatar(name: photo.user.displayName, url: photo.user.avatarUrl, size: 40),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(photo.user.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: font(15.5, weight: 700, color: p.ink)),
                          if (meta.isNotEmpty)
                            Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: font(12.5, color: p.inkMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        actions: [
          if (photo != null) ...[
            const SizedBox(width: 8),
            FollowButton(username: photo.user.username, height: 36),
          ],
          if (photo != null && me != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 10),
              child: IconButton(
                icon: Icon(LucideIcons.ellipsisVertical, color: p.ink),
                tooltip: t('ui.more'),
                onPressed: () => _menu(photo, isOwner),
              ),
            )
          else
            const SizedBox(width: 14),
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

  Future<void> _menu(PhotoDetail photo, bool isOwner) async {
    final t = L10n.of(context);
    final p = context.palette;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOwner) ...[
              ListTile(
                leading: const Icon(LucideIcons.pencil),
                title: Text(t('photo.edit')),
                onTap: () => Navigator.pop(c, 'edit'),
              ),
              ListTile(
                leading: Icon(LucideIcons.trash2, color: p.danger),
                title: Text(t('common.delete'), style: TextStyle(color: p.danger)),
                onTap: () => Navigator.pop(c, 'delete'),
              ),
            ] else
              ListTile(
                leading: const Icon(LucideIcons.flag),
                title: Text(t('report.button')),
                onTap: () => Navigator.pop(c, 'report'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'edit':
        await _edit(photo);
      case 'delete':
        await _delete();
      case 'report':
        await _report(photo.id);
    }
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: p.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(Radii.box),
                ),
                child: Text(r, style: font(15, color: p.danger)),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.push('/upload'),
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
    final parts = exifParts(photo.exif, locale);
    final lens = photo.exif?.lens;
    final hasCard = photo.title != null || photo.description != null || photo.tags.isNotEmpty || lens != null;
    final shadow = const [Shadow(color: Color(0x99000000), blurRadius: 3, offset: Offset(0, 1))];
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(photoProvider(widget.id)),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // Fotoğraf kendi oranında; asla kırpılmaz. EXIF koyu şerit üstünde, gölgeli yazıyla.
          if (img != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.72),
                  child: AspectRatio(
                    aspectRatio: img.ratio,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        NetPhoto(url: img.url, fit: BoxFit.contain, semanticLabel: photo.title),
                        if (parts.isNotEmpty)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              color: const Color(0x8C080A14),
                              child: Wrap(
                                spacing: 14,
                                runSpacing: 6,
                                children: [
                                  for (final s in parts)
                                    Text(s, style: font(13, weight: 600, color: Colors.white, tabular: true)
                                        .copyWith(shadows: shadow)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                LikePill(photo: photo),
                const SizedBox(width: Space.s2),
                if (photo.commentPolicy != 'off' || isOwner) ...[
                  Material(
                    color: p.surface,
                    shape: const StadiumBorder(),
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: () => context.push('/p/${photo.id}/comments'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              photo.commentPolicy == 'off' ? LucideIcons.messageCircleOff : LucideIcons.messageCircle,
                              size: 19,
                              color: p.ink,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${photo.commentCount}',
                              semanticsLabel: t('comments.count', {'count': '${photo.commentCount}'}),
                              style: font(14, weight: 700, color: p.ink, tabular: true),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.s2),
                ],
                RoundIconButton(
                  icon: LucideIcons.share,
                  label: t('ui.share'),
                  size: 38,
                  onPressed: () => showPhotoShareSheet(context, photo),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasCard)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(22)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (photo.title != null)
                          Text(photo.title!, style: font(20, weight: 700, spacing: -0.4, height: 1.2, color: p.ink)),
                        if (photo.description != null) ...[
                          if (photo.title != null) const SizedBox(height: 10),
                          Text(t('photo.story'), style: font(12, weight: 700, color: p.inkMuted)),
                          const SizedBox(height: 4),
                          Text(photo.description!, style: font(14.5, height: 1.5, color: p.ink)),
                        ],
                        if (lens != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(LucideIcons.aperture, size: 16, color: p.inkMuted),
                              const SizedBox(width: 8),
                              Expanded(child: Text(lens, style: font(13.5, color: p.inkMuted))),
                            ],
                          ),
                        ],
                        if (photo.tags.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [for (final tag in photo.tags) ExifChip('#$tag')],
                          ),
                        ],
                      ],
                    ),
                  ),
                if (photo.location != null) ...[
                  const SizedBox(height: Space.s4),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: p.surface2,
                      borderRadius: BorderRadius.circular(Radii.box),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: p.accentTint,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(LucideIcons.mapPin, size: 20, color: p.accentText),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            photo.location!.name ??
                                '${photo.location!.latitude.toStringAsFixed(3)}, ${photo.location!.longitude.toStringAsFixed(3)}',
                            style: font(16, weight: 600, color: p.ink),
                          ),
                        ),
                        TextButton(
                          onPressed: () => context.push(
                            '/map?lat=${photo.location!.latitude}&lng=${photo.location!.longitude}&photos=1',
                          ),
                          child: Text(t('photo.see_on_map')),
                        ),
                      ],
                    ),
                  ),
                ],
                if (isOwner && photo.suggestedLocation != null) ...[
                  const SizedBox(height: Space.s4),
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
    var policy = photo.commentPolicy;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(builder: (c, setSheet) => SingleChildScrollView(child: Padding(
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
            CommentPolicyPicker(value: policy, onChanged: (v) => setSheet(() => policy = v)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(t('common.save')),
            ),
          ],
        ),
      ))),
    );
    if (saved == true) {
      await _patch({
        'comment_policy': policy,
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
