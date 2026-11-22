import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'config.dart';
import 'token_store.dart';

/// API'ye WebSocket bağlantısı. Koparsa artan aralıklarla yeniden bağlanır.
class RealtimeService {
  RealtimeService(this.tokens, {this.beforeConnect});
  final TokenStore tokens;

  /// Bağlanmadan önce çağrılır: yetkili bir API isteği süresi dolmuş erişim token'ını yeniler.
  final Future<void> Function()? beforeConnect;

  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _events.stream;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _ping;
  Timer? _retry;
  int _attempt = 0;
  bool _running = false;
  DateTime _lastSeen = DateTime.now();
  DateTime? _pausedAt;
  int _gen = 0; // üst üste başlayan bağlantı denemelerinden yalnız sonuncusu geçerli

  /// Bağlantı açık ve son 60 saniyede sunucudan bir şey geldi mi.
  bool get connected =>
      _channel != null &&
      DateTime.now().difference(_lastSeen) < const Duration(seconds: 60);

  void start() {
    if (_running) return;
    _running = true;
    _connect();
  }

  Future<void> _connect() async {
    final gen = ++_gen;
    try {
      await beforeConnect?.call();
    } catch (_) {}
    final t = await tokens.read();
    if (!_running || t == null || gen != _gen) return;
    try {
      final ch = WebSocketChannel.connect(
        Uri.parse('${AppConfig.wsUrl}?token=${Uri.encodeComponent(t.access)}'),
      );
      await ch.ready;
      if (gen != _gen || !_running) {
        ch.sink.close();
        return;
      }
      _channel = ch;
      _attempt = 0;
      _lastSeen = DateTime.now();
      _ping = Timer.periodic(const Duration(seconds: 20), (_) {
        // Yanıt vermeyen (yarı açık) bağlantıyı fark et: iOS arka planda soketi sessizce öldürebilir
        if (DateTime.now().difference(_lastSeen) > const Duration(seconds: 50)) {
          _scheduleRetry();
          return;
        }
        ch.sink.add('ping');
      });
      _sub = ch.stream.listen(
        (data) {
          _lastSeen = DateTime.now();
          try {
            _events.add(jsonDecode(data as String) as Map<String, dynamic>);
          } catch (_) {}
        },
        onDone: _scheduleRetry,
        onError: (_) => _scheduleRetry(),
      );
      // Bağlantı kopukken kaçan mesajlar için dinleyiciler yeniden eşitlesin
      _events.add({'type': 'connected'});
    } catch (e) {
      debugPrint('WebSocket bağlanamadı: $e');
      if (gen == _gen) _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    _retry?.cancel();
    _cleanup();
    if (!_running) return;
    _attempt += 1;
    // Erişim token'ı süresi dolmuş olabilir; bir sonraki denemede güncel token okunur
    _retry = Timer(
      Duration(
        milliseconds: (1000 * (1 << _attempt.clamp(0, 5))).clamp(1000, 30000),
      ),
      _connect,
    );
  }

  void _cleanup() {
    _ping?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
  }

  /// Uygulama arka plana geçti.
  void pause() => _pausedAt = DateTime.now();

  /// Uygulama öne geldi: bağlantı kopmuş ya da uzun süre arka plandaysa hemen yeniden bağlan.
  void resume() {
    if (!_running) return;
    final away = _pausedAt == null
        ? Duration.zero
        : DateTime.now().difference(_pausedAt!);
    _pausedAt = null;
    if (connected && away < const Duration(seconds: 10)) return;
    _retry?.cancel();
    _cleanup();
    _attempt = 0;
    _connect();
  }

  void stop() {
    _running = false;
    _gen++;
    _retry?.cancel();
    _cleanup();
  }

  void dispose() {
    stop();
    _events.close();
  }
}
