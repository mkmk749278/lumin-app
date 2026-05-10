/// In-app update — polls the GitHub Releases API for the latest signed APK.
///
/// CI workflow (.github/workflows/build-apk.yml) creates a new
/// ``v{run_number}`` GitHub Release on every push to ``main``, with the
/// signed release APK attached.  This service compares the installed
/// build number (``PackageInfo.buildNumber``) against the latest tag,
/// and exposes a one-shot [check] method the UI calls on app start /
/// resume.
///
/// We poll GitHub directly (no engine endpoint) so the engine doesn't
/// have to know about app build artifacts — app version is an app
/// concern.  GitHub's unauthenticated rate limit is 60/hr/IP; the 5 min
/// in-memory cache means a single device makes at most 12 calls/hr,
/// well below the limit at any plausible closed-beta scale.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Where the service polls.  The repo is owner-fixed; if this ever
/// forks, swap the constant here.  No env var — bakes into the binary
/// so a tampered runtime config can't redirect updates to a malicious
/// APK source.
const String _kReleasesLatestUrl =
    'https://api.github.com/repos/mkmk749278/lumin-app/releases/latest';

/// Cache TTL.  Shorter is wasteful; longer means slower banner appearance
/// after a fresh release.  5 min is the sweet spot for a closed beta.
const Duration _kCacheTtl = Duration(minutes: 5);

class UpdateAvailable {
  UpdateAvailable({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.releaseNotes,
  });

  /// Build number from the release tag (e.g. ``v42`` → 42).  Compared
  /// against the installed ``PackageInfo.buildNumber``.
  final int versionCode;

  /// Human-readable name for the banner — e.g. ``v42`` or ``0.0.42``.
  final String versionName;

  /// Direct download URL for the signed APK asset on the release.
  final String apkUrl;

  /// First N chars of the release notes / commit message.  Used as the
  /// banner's secondary line so the user sees what's changing.
  final String releaseNotes;
}

class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  UpdateAvailable? _cached;
  DateTime _cachedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Returns an [UpdateAvailable] if a newer release exists, ``null``
  /// otherwise.  Silent on any error (offline, GitHub down, rate-limited)
  /// — banner just won't appear.
  Future<UpdateAvailable?> check() async {
    if (DateTime.now().difference(_cachedAt) < _kCacheTtl) {
      return _cached;
    }
    try {
      final installed = await PackageInfo.fromPlatform();
      final installedBuild = int.tryParse(installed.buildNumber) ?? 0;

      final resp = await _client
          .get(
            Uri.parse(_kReleasesLatestUrl),
            headers: const {
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
            },
          )
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) {
        debugPrint('UpdateService: GitHub returned ${resp.statusCode}');
        _setCache(null);
        return null;
      }
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String?) ?? '';
      final latestBuild = _parseBuildFromTag(tag);
      if (latestBuild <= installedBuild) {
        _setCache(null);
        return null;
      }
      final assets = (json['assets'] as List?) ?? const [];
      // Pick the first .apk asset.  CI uploads exactly one.
      Map<String, dynamic>? apkAsset;
      for (final a in assets) {
        if (a is Map<String, dynamic> &&
            (a['name'] as String? ?? '').endsWith('.apk')) {
          apkAsset = a;
          break;
        }
      }
      if (apkAsset == null) {
        debugPrint('UpdateService: release $tag has no .apk asset');
        _setCache(null);
        return null;
      }
      final notes = (json['body'] as String? ?? '').trim();
      final result = UpdateAvailable(
        versionCode: latestBuild,
        versionName: tag,
        apkUrl: apkAsset['browser_download_url'] as String,
        releaseNotes: notes.length > 280 ? '${notes.substring(0, 280)}…' : notes,
      );
      _setCache(result);
      return result;
    } catch (e) {
      debugPrint('UpdateService: check failed: $e');
      _setCache(null);
      return null;
    }
  }

  void _setCache(UpdateAvailable? v) {
    _cached = v;
    _cachedAt = DateTime.now();
  }

  /// Tag format from the workflow: ``v{run_number}`` (e.g. ``v42``).
  /// Future-proof: also accept ``v0.0.42`` by taking the trailing int.
  static int _parseBuildFromTag(String tag) {
    if (tag.isEmpty) return 0;
    final cleaned = tag.startsWith('v') ? tag.substring(1) : tag;
    // Try the whole string first (``42``).
    final asInt = int.tryParse(cleaned);
    if (asInt != null) return asInt;
    // Else last dotted segment (``0.0.42`` → 42).
    final parts = cleaned.split('.');
    return int.tryParse(parts.last) ?? 0;
  }

  void dispose() => _client.close();
}
