/// Thin HTTP client for the 360 Crypto Eye API.
///
/// Stateless and reusable — give it a base URL + optional bearer token and
/// it'll dispatch GET / POST with sane defaults: 8-second timeout, 2 retries
/// on transient errors with exponential back-off, JSON decoding, ``ApiError``
/// wrapping for callers.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

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
    this.authToken,
    this.timeout = const Duration(seconds: 8),
    this.maxRetries = 2,
  });

  final String baseUrl;
  final String? authToken;
  final Duration timeout;
  final int maxRetries;

  Map<String, String> get _headers {
    final h = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    final token = authToken;
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

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

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    return _request(() => http.get(_uri(path, query), headers: _headers));
  }

  Future<dynamic> post(String path, {Object? body}) async {
    final encoded = body == null ? null : jsonEncode(body);
    return _request(
      () => http.post(_uri(path), headers: _headers, body: encoded),
    );
  }

  Future<dynamic> _request(Future<http.Response> Function() send) async {
    int attempt = 0;
    Object? lastError;
    while (attempt <= maxRetries) {
      try {
        final resp = await send().timeout(timeout);
        // Retry on 5xx — keep auth + payload errors loud.
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
}
