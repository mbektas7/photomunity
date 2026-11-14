import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Tokens {
  const Tokens(this.access, this.refresh);
  final String access;
  final String refresh;

  factory Tokens.fromJson(Map<String, dynamic> j) =>
      Tokens(j['access_token'] as String, j['refresh_token'] as String);
}

/// Token'lar iOS Keychain / Android Keystore'da saklanır.
class TokenStore {
  TokenStore([FlutterSecureStorage? storage])
    : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  Tokens? _cache;

  static const _a = 'fg_access';
  static const _r = 'fg_refresh';

  Future<Tokens?> read() async {
    if (_cache != null) return _cache;
    final a = await _s.read(key: _a);
    final r = await _s.read(key: _r);
    if (a == null || r == null) return null;
    return _cache = Tokens(a, r);
  }

  Future<void> save(Tokens t) async {
    _cache = t;
    await _s.write(key: _a, value: t.access);
    await _s.write(key: _r, value: t.refresh);
  }

  Future<void> clear() async {
    _cache = null;
    await _s.delete(key: _a);
    await _s.delete(key: _r);
  }
}
