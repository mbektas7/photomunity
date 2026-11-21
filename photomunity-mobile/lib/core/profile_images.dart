import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../state/providers.dart';
import '../widgets/common.dart';
import 'l10n.dart';
import 'models.dart';


/// Profil fotoğrafı ya da kapak: galeriden seç, depoya yükle, profili güncelle.
/// [kind]: `avatar` | `cover`. Seçim yapılmadıysa false döner.
Future<bool> uploadProfileImage(BuildContext context, WidgetRef ref, String kind) async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (picked == null || !context.mounted) return false;
  final t = L10n.of(context);
  final cover = kind == 'cover';
  // Kırpma: kapak 3:1 afiş (web ile aynı), profil fotoğrafı daire içinde kare
  final cropped = await ImageCropper().cropImage(
    sourcePath: picked.path,
    aspectRatio: cover ? const CropAspectRatio(ratioX: 3, ratioY: 1) : const CropAspectRatio(ratioX: 1, ratioY: 1),
    compressQuality: 92,
    uiSettings: [
      IOSUiSettings(
        title: t(cover ? 'crop.cover' : 'crop.avatar'),
        doneButtonTitle: t('crop.done'),
        cancelButtonTitle: t('common.cancel'),
        aspectRatioLockEnabled: true,
        resetAspectRatioEnabled: false,
        aspectRatioPickerButtonHidden: true,
        cropStyle: cover ? CropStyle.rectangle : CropStyle.circle,
      ),
      AndroidUiSettings(
        toolbarTitle: t(cover ? 'crop.cover' : 'crop.avatar'),
        lockAspectRatio: true,
        hideBottomControls: true,
        cropStyle: cover ? CropStyle.rectangle : CropStyle.circle,
      ),
    ],
  );
  if (cropped == null) return false; // kırpmadan vazgeçti
  const type = 'image/jpeg'; // kırpılan dosya her zaman JPEG
  final path = cropped.path;
  final name = '$kind.jpg';
  final api = ref.read(apiProvider);
  try {
    final size = await XFile(path).length();
    final slot = await api.post<Map<String, dynamic>>(
      '/me/images/upload-url',
      {'kind': kind, 'content_type': type, 'size_bytes': size},
    );
    final fields = (slot['fields'] as Map).map((k, v) => MapEntry('$k', '$v'));
    await api.uploadToStorage(slot['upload_url'] as String, fields, path, name, (_) {});
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
