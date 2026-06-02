/// Thin HTTP client for the 360 Crypto Eye API.
///
/// Post-Firebase-migration: the `Authorization` header carries the
/// current Firebase ID token (auto-refreshed by the SDK).  On a 401
/// we retry once with `forceRefresh: true` then give up — no loop.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
    // 10 s timeout: authenticated engine endpoints (auto-trade runtime
    // status, settings, positions) do several sequential GCP Firestore
    // round-trips per request, which legitimately take 5-9 s on a cold
    // cache or right after a deploy restart.  The previous 5 s was tuned
    // to "fail fast", but that converted slow-but-working responses into
    // an instant error screen — the user wants the data, not a faster
    // error.  10 s clears the real p99 while still bounding the wait.
    this.timeout = const Duration(seconds: 10),
    // 1 retry: a single retry with back-off recovers the common transient
    // — a 5xx / dropped connection from the engine mid-restart (the
    // ~45 s deploy window) or a one-off Firestore latency spike.  The 401
    // auth-token refresh is still a separate "free" retry outside this
    // counter.  Capped at 1 so a hard outage surfaces in bounded time
    // rather than hanging the UI through many attempts.
    this.maxRetries = 1,
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

  /// POST that returns the FULL response (status + body + headers) on
  /// both success and 4xx instead of throwing.  Used by the Binance
  /// connect flow (PR-2 server-side execution) which needs to read
  /// the ``X-Connect-Error-Code`` + ``X-Engine-VPS-IP`` headers on
  /// validation failure to render targeted fix-up UI.
  ///
  /// Still throws on 5xx (caller treats as retryable) and on network
  /// errors.  The auth-retry-on-401 + retry-on-5xx behaviour matches
  /// ``post``; the only difference is the 4xx-doesn't-throw contract.
  Future<http.Response> postRaw(String path, {Object? body}) async {
    final encoded = body == null ? null : jsonEncode(body);
    return _requestRaw((forceRefresh) async {
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

  Future<dynamic> delete(String path) async {
    return _request((forceRefresh) async {
      final h = await _headers(forceRefresh: forceRefresh);
      return _http.delete(_uri(path), headers: h);
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
        return await compute(jsonDecode, resp.body);
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

  /// Variant of [_request] that returns the raw [http.Response] on
  /// success AND on 4xx (caller decides how to interpret the body +
  /// headers).  5xx + network errors still retry + eventually throw
  /// ApiError.
  Future<http.Response> _requestRaw(
    Future<http.Response> Function(bool forceRefresh) send,
  ) async {
    var attempt = 0;
    Object? lastError;
    while (true) {
      try {
        var authRetried = false;
        var resp = await send(authRetried).timeout(timeout);
        if (resp.statusCode == 401 && !authRetried) {
          authRetried = true;
          resp = await send(authRetried).timeout(timeout);
        }
        if (resp.statusCode >= 500 && attempt < maxRetries) {
          attempt += 1;
          await Future<void>.delayed(_backoff(attempt));
          continue;
        }
        // 2xx and 4xx return the full response — caller inspects.
        return resp;
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
