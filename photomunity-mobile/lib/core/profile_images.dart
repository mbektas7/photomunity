import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../state/providers.dart';
import '../widgets/common.dart';
import 'l10n.dart';
import 'models.dart';

const _types = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heif',
};

/// Profil fotoğrafı ya da kapak: galeriden seç, depoya yükle, profili güncelle.
/// [kind]: `avatar` | `cover`. Seçim yapılmadıysa false döner.
Future<bool> uploadProfileImage(BuildContext context, WidgetRef ref, String kind) async {
  final file = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (file == null) return false;
  final type = _types[file.name.split('.').last.toLowerCase()];
  if (type == null) {
    if (context.mounted) toast(context, L10n.of(context)('quality.unsupported_format'));
    return false;
  }
  final api = ref.read(apiProvider);
  try {
    final slot = await api.post<Map<String, dynamic>>(
      '/me/images/upload-url',
      {'kind': kind, 'content_type': type, 'size_bytes': await file.length()},
    );
    final fields = (slot['fields'] as Map).map((k, v) => MapEntry('$k', '$v'));
    await api.uploadToStorage(slot['upload_url'] as String, fields, file.path, file.name, (_) {});
    final res = await api.post<Map<String, dynamic>>('/me/images/complete', {'kind': kind, 'key': fields['key']});
    ref.read(authProvider.notifier).setMe(Me.fromJson(res));
    ref.invalidate(profileProvider);
    return true;
  } catch (e) {
    if (context.mounted) toast(context, errorText(context, e));
    return false;
  }
}

Future<void> removeProfileImage(BuildContext context, WidgetRef ref, String kind) async {
  try {
    final res = await ref.read(apiProvider).delete<Map<String, dynamic>>('/me/images/$kind');
    ref.read(authProvider.notifier).setMe(Me.fromJson(res));
    ref.invalidate(profileProvider);
  } catch (e) {
    if (context.mounted) toast(context, errorText(context, e));
  }
}
