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

  void start() {
    if (_running) return;
    _running = true;
    _connect();
  }

  Future<void> _connect() async {
    try {
      await beforeConnect?.call();
    } catch (_) {}
    final t = await tokens.read();
    if (!_running || t == null) return;
    try {
      final ch = WebSocketChannel.connect(
        Uri.parse('${AppConfig.wsUrl}?token=${Uri.encodeComponent(t.access)}'),
      );
      await ch.ready;
      _channel = ch;
      _attempt = 0;
      _ping = Timer.periodic(
        const Duration(seconds: 25),
        (_) => ch.sink.add('ping'),
      );
      _sub = ch.stream.listen(
        (data) {
          try {
            _events.add(jsonDecode(data as String) as Map<String, dynamic>);
          } catch (_) {}
        },
        onDone: _scheduleRetry,
        onError: (_) => _scheduleRetry(),
      );
    } catch (e) {
      debugPrint('WebSocket bağlanamadı: $e');
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
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

  void stop() {
    _running = false;
    _retry?.cancel();
    _cleanup();
  }

  void dispose() {
    stop();
    _events.close();
  }
}
