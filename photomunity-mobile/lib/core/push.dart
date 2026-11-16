import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// FCM kaydı ve bildirime dokunma yönlendirmesi.
/// Firebase yapılandırılmamışsa (google-services dosyaları yoksa) sessizce devre dışı kalır.
class PushService {
  PushService({
    required this.api,
    required this.onOpen,
    required this.onForeground,
  });

  final ApiClient api;
  final void Function(Map<String, String> data) onOpen;
  final void Function() onForeground;

  bool _ready = false;
  String? _token;
  final _subs = <StreamSubscription<dynamic>>[];

  Future<void> _init() async {
    if (_ready) return;
    try {
      await Firebase.initializeApp();
      _ready = true;
    } catch (e) {
      debugPrint('Push devre dışı: $e');
      return;
    }
    final m = FirebaseMessaging.instance;
    // Uygulama kapalıyken bildirime dokunulduysa
    final initial = await m.getInitialMessage();
    if (initial != null) onOpen(_data(initial));
    _subs
      ..add(
        FirebaseMessaging.onMessageOpenedApp.listen(
          (msg) => onOpen(_data(msg)),
        ),
      )
      ..add(FirebaseMessaging.onMessage.listen((_) => onForeground()))
      ..add(m.onTokenRefresh.listen(_register));
  }

  Map<String, String> _data(RemoteMessage m) =>
      m.data.map((k, v) => MapEntry(k, '$v'));

  /// Oturum açıldığında çağrılır: izin ister, token'ı backend'e kaydeder.
  Future<void> enable() async {
    await _init();
    if (!_ready) return;
    final m = FirebaseMessaging.instance;
    final settings = await m.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;
    if (Platform.isIOS && await m.getAPNSToken() == null) {
      // APNs token'ı ilk açılışta birkaç saniye gecikebilir
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    final token = await m.getToken();
    if (token != null) await _register(token);
  }

  Future<void> _register(String token) async {
    _token = token;
    try {
      await api.post<dynamic>('/devices', {
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
    } catch (e) {
      debugPrint('Cihaz kaydı başarısız: $e');
    }
  }

  /// Çıkışta (token'lar silinmeden önce) çağrılır; bu cihaz artık bu hesabın bildirimlerini almaz.
  Future<void> disable() async {
    final token = _token;
    if (token == null) return;
    try {
      await api.delete<dynamic>('/devices/${Uri.encodeComponent(token)}');
    } catch (_) {}
    _token = null;
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
  }
}
