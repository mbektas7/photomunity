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
        AppConfig.minLongEdge)
      codes.add('resolution_too_low');
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
      if (perm == LocationPermission.denied)
        perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever)
        return;
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

    return Scaffold(
      appBar: AppBar(title: Text(t('upload.heading'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          Text(
            t('upload.requirements'),
            style: font(14.5, height: 1.45, color: p.inkMuted),
          ),
          const SizedBox(height: 18),
          if (_file == null)
            InkWell(
              onTap: _pick,
              child: Container(
                height: 220,
                decoration: BoxDecoration(
                  color: p.surface,
                  border: Border.all(color: p.line, width: 1.5),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.imagePlus,
                      size: 34,
                      color: p.ink,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      t('upload.choose'),
                      style: font(17, weight: 600, color: p.ink),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              color: p.surface,
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 380),
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _file!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: font(13, color: p.inkMuted),
                        ),
                      ),
                      if (!uploading)
                        TextButton(
                          onPressed: _pick,
                          child: Text(t('upload.change')),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          if (_issues.isNotEmpty) ...[
            const SizedBox(height: 12),
            Notice(
              _issues.map((c) => t('quality.$c')).join('\n'),
              tone: NoticeTone.error,
            ),
          ],
          const SizedBox(height: 22),
          TextField(
            controller: _title,
            maxLength: 150,
            decoration: InputDecoration(labelText: t('upload.title')),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _desc,
            maxLength: 2000,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(labelText: t('upload.description')),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _tags,
            decoration: InputDecoration(
              labelText: t('upload.tags'),
              helperText: t('upload.tags_hint'),
            ),
          ),
          const SizedBox(height: 22),
          Divider(color: p.line),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  t('upload.location'),
                  style: font(15, weight: 600, color: p.ink),
                ),
              ),
              if (_location != null)
                TextButton(
                  onPressed: () => setState(() => _location = null),
                  child: Text(t('upload.remove_location')),
                )
              else
                TextButton.icon(
                  onPressed: _locating ? null : _locate,
                  icon: const Icon(LucideIcons.locateFixed, size: 18),
                  label: Text(
                    _locating
                        ? t('upload.locating')
                        : t('upload.use_my_location'),
                  ),
                ),
            ],
          ),
          if (_location == null)
            Text(
              t('upload.location_hint'),
              style: font(13.5, height: 1.45, color: p.inkMuted),
            )
          else ...[
            Text(
              '${_location!.latitude}, ${_location!.longitude}',
              style: font(13.5, color: p.inkMuted, tabular: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _place,
              decoration: InputDecoration(
                labelText: t('upload.place_name'),
                hintText: t('upload.place_placeholder'),
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (_error != null) ...[
            Notice(_error!, tone: NoticeTone.error),
            const SizedBox(height: 14),
          ],
          if (uploading) ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text(
              t('upload.uploading', {'pct': (_progress! * 100).round()}),
              style: font(13.5, color: p.inkMuted, tabular: true),
            ),
            const SizedBox(height: 14),
          ],
          FilledButton(
            onPressed: _file == null || _issues.isNotEmpty || uploading
                ? null
                : _publish,
            child: BusyLabel(busy: uploading, label: t('upload.publish')),
          ),
          const SizedBox(height: 12),
          Text(
            t('upload.quality_note'),
            style: font(13.5, height: 1.45, color: p.inkMuted),
          ),
        ],
      ),
    );
  }
}
