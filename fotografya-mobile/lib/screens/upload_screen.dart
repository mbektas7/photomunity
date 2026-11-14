import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../core/config.dart';
import '../core/l10n.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import 'feed_screen.dart' show navClearance;
import '../widgets/design.dart';

const _types = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heif',
};

/// Sunucudaki kontrolün hızlı ön kopyası; kullanıcıyı boşuna yükleme yapmaktan kurtarır.
Future<List<String>> precheck(XFile file) async {
  final ext = file.name.split('.').last.toLowerCase();
  final type = _types[ext];
  if (type == null) return ['unsupported_format'];
  final size = await file.length();
  final codes = <String>[];
  if (size < AppConfig.minBytes) codes.add('file_too_small');
  if (size > AppConfig.maxBytes) return [...codes, 'file_too_large'];
  try {
    // Görseli tamamen açmadan yalnızca başlığından boyutları okur
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      await file.readAsBytes(),
    );
    final desc = await ui.ImageDescriptor.encoded(buffer);
    if ((desc.width > desc.height ? desc.width : desc.height) <
        AppConfig.minLongEdge) {
      codes.add('resolution_too_low');
    }
    desc.dispose();
    buffer.dispose();
  } catch (_) {
    if (!type.contains('hei')) codes.add('corrupt_image');
  }
  return codes;
}

class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({super.key});

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _tags = TextEditingController();
  final _place = TextEditingController();

  XFile? _file;
  List<String> _issues = const [];
  GeoPoint? _location;
  bool _locating = false;
  double? _progress;
  String? _error;

  @override
  void dispose() {
    for (final c in [_title, _desc, _tags, _place]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    // ÖNEMLİ: maxWidth/imageQuality verilmez; verilirse görsel yeniden sıkıştırılır ve EXIF kaybolur.
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: true,
    );
    if (file == null) return;
    final issues = await precheck(file);
    setState(() {
      _file = file;
      _issues = issues;
      _error = null;
    });
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      setState(
        () => _location = GeoPoint(
          double.parse(pos.latitude.toStringAsFixed(5)),
          double.parse(pos.longitude.toStringAsFixed(5)),
        ),
      );
    } catch (_) {
      // Konum servisi kapalı olabilir; konum isteğe bağlı
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _publish() async {
    final file = _file;
    if (file == null || _issues.isNotEmpty) return;
    final api = ref.read(apiProvider);
    final ext = file.name.split('.').last.toLowerCase();
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      final slot = await api.post<Map<String, dynamic>>('/photos/upload-url', {
        'content_type': _types[ext],
        'size_bytes': await file.length(),
      });
      await api.uploadToStorage(
        slot['upload_url'] as String,
        (slot['fields'] as Map).map((k, v) => MapEntry('$k', '$v')),
        file.path,
        file.name,
        (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      final id = slot['photo_id'] as String;
      await api.post<Map<String, dynamic>>('/photos/$id/complete', {
        'title': _title.text.trim().isEmpty ? null : _title.text.trim(),
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'tags': _tags.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        'location': _location == null
            ? null
            : GeoPoint(
                _location!.latitude,
                _location!.longitude,
                _place.text.trim().isEmpty ? null : _place.text.trim(),
              ).toJson(),
      });
      if (!mounted) return;
      _reset();
      context.push('/p/$id');
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = errorText(context, e);
        });
      }
    }
  }

  void _reset() {
    for (final c in [_title, _desc, _tags, _place]) {
      c.clear();
    }
    setState(() {
      _file = null;
      _issues = const [];
      _location = null;
      _progress = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final p = context.palette;
    final uploading = _progress != null;
    final canPublish = _file != null && _issues.isEmpty && !uploading;

    Widget field(TextEditingController c, String label, {int minLines = 1, int maxLines = 1, int? maxLength, String? hint}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: font(14, weight: 500, color: p.inkMuted)),
              TextField(
                controller: c,
                minLines: minLines,
                maxLines: maxLines,
                maxLength: maxLength,
                style: font(19, weight: 600, color: p.ink),
                decoration: InputDecoration(
                  hintText: hint,
                  isDense: true,
                  filled: false,
                  counterText: '',
                  contentPadding: const EdgeInsets.only(top: 6),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ],
          ),
        );

    Widget iconTile(IconData icon) => Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(Radii.photo)),
      child: Icon(icon, size: 22, color: p.ink),
    );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        leading: _file == null
            ? null
            : IconButton(
                tooltip: t('ui.close'),
                icon: const Icon(LucideIcons.x, size: 28),
                onPressed: uploading ? null : _reset,
              ),
        title: Text(t('upload.heading'), style: font(24, weight: 700, spacing: -0.7, color: p.ink)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton(
              onPressed: canPublish ? _publish : null,
              child: Text(t('upload.publish')),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, navClearance),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          SurfaceCard(
            padding: const EdgeInsets.all(Space.s3),
            child: _file == null
                ? InkWell(
                    onTap: _pick,
                    borderRadius: BorderRadius.circular(Radii.photo),
                    child: Container(
                      height: 240,
                      decoration: BoxDecoration(
                        color: p.surface2,
                        borderRadius: BorderRadius.circular(Radii.photo),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(color: p.accentTint, shape: BoxShape.circle),
                            child: Icon(LucideIcons.imagePlus, size: 30, color: p.accentText),
                          ),
                          const SizedBox(height: 14),
                          Text(t('upload.choose'), style: font(18, weight: 700, color: p.ink)),
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              t('upload.requirements'),
                              textAlign: TextAlign.center,
                              style: font(13.5, height: 1.4, color: p.inkMuted),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 380),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.photo),
                          child: Image.file(
                            File(_file!.path),
                            fit: BoxFit.contain,
                            cacheWidth: 1200,
                            errorBuilder: (_, _, _) => const SizedBox(
                              height: 160,
                              child: Center(child: Icon(LucideIcons.image)),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _file!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.caption(p.inkMuted),
                            ),
                          ),
                          if (!uploading)
                            TextButton(onPressed: _pick, child: Text(t('upload.change'))),
                        ],
                      ),
                      if (_issues.isNotEmpty)
                        Notice(
                          _issues.map((c) => t('quality.$c')).join('\n'),
                          tone: NoticeTone.error,
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: Space.s3),
          SurfaceCard(
            padding: const EdgeInsets.fromLTRB(Space.s4, 4, Space.s4, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                field(_title, t('upload.title'), maxLength: 150),
                Divider(color: p.line),
                field(_desc, t('upload.description'), minLines: 1, maxLines: 6, maxLength: 2000),
                Divider(color: p.line),
                field(_tags, t('upload.tags'), hint: t('upload.tags_hint')),
                Divider(color: p.line),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      iconTile(LucideIcons.mapPin),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t('upload.location'), style: font(17, weight: 600, color: p.ink)),
                            Text(
                              _locating
                                  ? t('upload.locating')
                                  : _location == null
                                  ? t('upload.use_my_location')
                                  : (_place.text.trim().isNotEmpty
                                        ? _place.text.trim()
                                        : '${_location!.latitude.toStringAsFixed(3)}, ${_location!.longitude.toStringAsFixed(3)}'),
                              style: font(14, color: p.inkMuted, tabular: true),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _location != null,
                        onChanged: _locating
                            ? null
                            : (on) => on ? _locate() : setState(() => _location = null),
                      ),
                    ],
                  ),
                ),
                if (_location != null) ...[
                  Divider(color: p.line),
                  field(_place, t('upload.place_name'), hint: t('upload.place_placeholder')),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s3, Space.s4, Space.s3, 0),
            child: Text(t('upload.location_hint'), style: font(14, height: 1.45, color: p.inkMuted)),
          ),
          const SizedBox(height: Space.s5),
          if (_error != null) ...[
            Notice(_error!, tone: NoticeTone.error),
            const SizedBox(height: 14),
          ],
          if (uploading) ...[
            LinearProgressIndicator(value: _progress, borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 8),
            Text(
              t('upload.uploading', {'pct': (_progress! * 100).round()}),
              style: font(13.5, color: p.inkMuted, tabular: true),
            ),
            const SizedBox(height: 14),
          ],
          LargeButton(
            label: t('upload.publish'),
            busy: uploading,
            onPressed: canPublish ? _publish : null,
          ),
          const SizedBox(height: 12),
          Text(t('upload.quality_note'), style: font(13.5, height: 1.45, color: p.inkMuted)),
        ],
      ),
    );
  }
}
