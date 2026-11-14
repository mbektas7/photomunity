import 'dart:async';

import 'package:dio/dio.dart';

import 'config.dart';
import 'token_store.dart';

class ApiException implements Exception {
  ApiException(this.status, this.code, this.message, [this.details = const []]);
  final int status;
  final String code;
  final String message;
  final List<({String code, String message})> details;

  factory ApiException.from(Object error) {
    if (error is ApiException) return error;
    if (error is DioException) {
      final res = error.response;
      final data = res?.data;
      if (data is Map && data['error'] is Map) {
        final e = data['error'] as Map;
        final details = ((e['details'] as List?) ?? const [])
            .map(
              (d) =>
                  (code: d['code'] as String, message: d['message'] as String),
            )
            .toList();
        return ApiException(
          res!.statusCode ?? 0,
          e['code'] as String? ?? 'unknown',
          e['message'] as String? ?? '',
          details,
        );
      }
      if (data is Map &&
          data['detail'] is List &&
          (data['detail'] as List).isNotEmpty) {
        final first = (data['detail'] as List).first;
        return ApiException(
          res?.statusCode ?? 422,
          'validation',
          first is Map ? '${first['msg']}' : '$first',
        );
      }
      return ApiException(res?.statusCode ?? 0, 'network', '');
    }
    return ApiException(0, 'unknown', '$error');
  }

  @override
  String toString() => 'ApiException($status, $code, $message)';
}

/// Backend istemcisi: token ekler, 401'de refresh token ile bir kez yeniler ve isteği tekrarlar.
class ApiClient {
  ApiClient({
    required this.tokens,
    required this.localeCode,
    this.onSessionExpired,
  }) : dio = Dio(
         BaseOptions(
           baseUrl: AppConfig.apiUrl,
           connectTimeout: const Duration(seconds: 15),
           receiveTimeout: const Duration(seconds: 30),
           contentType: Headers.jsonContentType,
         ),
       ) {
    dio.interceptors.add(
      InterceptorsWrapper(onRequest: _onRequest, onError: _onError),
    );
  }

  final Dio dio;
  final TokenStore tokens;
  final String Function() localeCode;
  final void Function()? onSessionExpired;

  /// Eş zamanlı 401'ler tek bir yenilemeyi bekler. Aynı refresh token iki kez kullanılırsa
  /// backend bunu çalıntı token sayıp tüm oturumları kapatır.
  Future<Tokens?>? _refreshing;

  Future<void> _onRequest(RequestOptions o, RequestInterceptorHandler h) async {
    o.headers['Accept-Language'] = localeCode();
    if (o.extra['auth'] != false) {
      final t = await tokens.read();
      if (t != null) o.headers['Authorization'] = 'Bearer ${t.access}';
    }
    h.next(o);
  }

  Future<void> _onError(DioException e, ErrorInterceptorHandler h) async {
    final o = e.requestOptions;
    final canRetry =
        e.response?.statusCode == 401 &&
        o.extra['auth'] != false &&
        o.extra['retried'] != true;
    if (!canRetry || (await tokens.read()) == null) {
      h.next(e);
      return;
    }

    final fresh = await (_refreshing ??= _refresh().whenComplete(
      () => _refreshing = null,
    ));
    if (fresh == null) {
      onSessionExpired?.call();
      h.next(e);
      return;
    }
    try {
      o.headers['Authorization'] = 'Bearer ${fresh.access}';
      o.extra['retried'] = true;
      h.resolve(await dio.fetch(o));
    } on DioException catch (err) {
      h.next(err);
    }
  }

  Future<Tokens?> _refresh() async {
    final current = await tokens.read();
    if (current == null) return null;
    try {
      final res = await dio.post(
        '/auth/refresh',
        data: {'refresh_token': current.refresh},
        options: Options(extra: {'auth': false}),
      );
      final t = Tokens.fromJson(res.data as Map<String, dynamic>);
      await tokens.save(t);
      return t;
    } catch (_) {
      await tokens.clear();
      return null;
    }
  }

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) =>
      _wrap(() => dio.get(path, queryParameters: query));
  Future<T> post<T>(String path, [Object? body]) =>
      _wrap(() => dio.post(path, data: body));
  Future<T> patch<T>(String path, [Object? body]) =>
      _wrap(() => dio.patch(path, data: body));
  Future<T> put<T>(String path, [Object? body]) =>
      _wrap(() => dio.put(path, data: body));
  Future<T> delete<T>(String path) => _wrap(() => dio.delete(path));

  /// Oturum açmayan uçlar (login, register, oauth) — token eklenmez.
  Future<Map<String, dynamic>> postPublic(String path, Object body) => _wrap(
    () => dio.post(
      path,
      data: body,
      options: Options(extra: {'auth': false}),
    ),
  );

  Future<T> _wrap<T>(Future<Response> Function() call) async {
    try {
      final res = await call();
      return res.data as T;
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Presigned POST ile dosyayı doğrudan depolamaya yükler (API sunucusundan geçmez).
  Future<void> uploadToStorage(
    String url,
    Map<String, String> fields,
    String filePath,
    String filename,
    void Function(double) onProgress,
  ) async {
    final form = FormData.fromMap({
      ...fields,
      'file': await MultipartFile.fromFile(filePath, filename: filename),
    });
    try {
      await Dio().post(
        url,
        data: form,
        onSendProgress: (sent, total) {
          if (total > 0) onProgress(sent / total);
        },
      );
    } catch (e) {
      throw ApiException(0, 'upload_failed', '');
    }
  }
}
