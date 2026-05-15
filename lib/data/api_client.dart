/// Thin HTTP client for the 360 Crypto Eye API.
///
/// Post-Firebase-migration: the `Authorization` header carries the
/// current Firebase ID token (auto-refreshed by the SDK).  On a 401
/// we retry once with `forceRefresh: true` then give up — no loop.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'auth_service.dart';

class ApiError implements Exception {
  ApiError(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => 'ApiError($statusCode): $message';
}

class LuminApiClient {
  LuminApiClient({
    required this.baseUrl,
    required this.auth,
    this.timeout = const Duration(seconds: 8),
    this.maxRetries = 2,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final AuthService auth;
  final Duration timeout;
  final int maxRetries;

  final http.Client _http;

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final pathPart = path.startsWith('/') ? path : '/$path';
    final raw = '$base$pathPart';
    final parsed = Uri.parse(raw);
    if (query == null || query.isEmpty) return parsed;
    final qp = <String, String>{};
    query.forEach((k, v) {
      if (v != null) qp[k] = '$v';
    });
    return parsed.replace(queryParameters: {
      ...parsed.queryParameters,
      ...qp,
    });
  }

  Future<Map<String, String>> _headers({bool forceRefresh = false}) async {
    final token = await auth.currentIdToken(forceRefresh: forceRefresh);
    final h = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (token != null) {
      h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    return _request((forceRefresh) async {
      final h = await _headers(forceRefresh: forceRefresh);
      return _http.get(_uri(path, query), headers: h);
    });
  }

  Future<dynamic> post(String path, {Object? body}) async {
    final encoded = body == null ? null : jsonEncode(body);
    return _request((forceRefresh) async {
      final h = await _headers(forceRefresh: forceRefresh);
      return _http.post(_uri(path), headers: h, body: encoded);
    });
  }

  Future<dynamic> put(String path, {Object? body}) async {
    final encoded = body == null ? null : jsonEncode(body);
    return _request((forceRefresh) async {
      final h = await _headers(forceRefresh: forceRefresh);
      return _http.put(_uri(path), headers: h, body: encoded);
    });
  }

  Future<dynamic> _request(
    Future<http.Response> Function(bool forceRefresh) send,
  ) async {
    int attempt = 0;
    bool authRetried = false;
    Object? lastError;
    while (attempt <= maxRetries) {
      try {
        final resp = await send(authRetried).timeout(timeout);

        // 401 → cached ID token may be stale; force-refresh once and
        // retry.  After one retry we give up — no loop.
        if (resp.statusCode == 401 && !authRetried) {
          authRetried = true;
          continue; // doesn't increment attempt — auth retry is "free"
        }

        // 5xx → transient, retry with back-off.
        if (resp.statusCode >= 500 && attempt < maxRetries) {
          attempt += 1;
          await Future<void>.delayed(_backoff(attempt));
          continue;
        }

        if (resp.statusCode >= 400) {
          throw ApiError(resp.statusCode, _decodeError(resp.body));
        }
        if (resp.body.isEmpty) return null;
        return jsonDecode(resp.body);
      } on TimeoutException catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        lastError = e;
      }
      attempt += 1;
      if (attempt > maxRetries) break;
      await Future<void>.delayed(_backoff(attempt));
    }
    throw ApiError(0, 'connection failed: $lastError');
  }

  Duration _backoff(int attempt) =>
      Duration(milliseconds: 200 * (1 << (attempt - 1).clamp(0, 4)));

  String _decodeError(String body) {
    if (body.isEmpty) return 'empty body';
    try {
      final j = jsonDecode(body);
      if (j is Map && j['detail'] != null) return '${j['detail']}';
    } catch (_) {}
    return body;
  }

  void dispose() => _http.close();
}
