/// Tests for the sideload self-updater (2026-07-17).
///
/// Every sideload user gets new builds ONLY through this service — a
/// version-comparison bug either bricks the update channel (banner never
/// shows) or loops it (banner for the installed build).  Pinned here:
///
/// * tag → build-number parsing for both CI's `v{run_number}` form and the
///   future-proofed dotted form, via the public [check] surface;
/// * newer-build detection against `PackageInfo.buildNumber`;
/// * the silent-failure contract: non-200, malformed JSON, missing .apk
///   asset and network errors all yield null (no banner) — never a throw
///   into app boot;
/// * release-notes truncation for the banner's secondary line;
/// * the 5-minute cache actually suppresses repeat GitHub calls (the
///   unauthenticated rate-limit budget depends on it).
///
/// The Play-channel inertness (`kSelfUpdateEnabled == false` ⇒ [check]
/// hard-stops) cannot be exercised here: the flag is a compile-time
/// constant and tests build as sideload.  test/app/distribution_test.dart
/// pins the flag wiring itself.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumin/data/update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

void _installedBuild(String buildNumber) {
  PackageInfo.setMockInitialValues(
    appName: 'Lumin',
    packageName: 'org.luminapp.lumin',
    version: '0.1.0',
    buildNumber: buildNumber,
    buildSignature: '',
  );
}

Map<String, dynamic> _release({
  String tag = 'v42',
  String? body = 'Fixes',
  List<Map<String, dynamic>>? assets,
}) =>
    {
      'tag_name': tag,
      'body': body,
      'assets': assets ??
          [
            {
              'name': 'lumin-release.apk',
              'browser_download_url': 'https://example.org/lumin-release.apk',
            },
          ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  UpdateService service(
    Map<String, dynamic> release, {
    int status = 200,
    List<int>? callCounter,
  }) {
    return UpdateService(
      client: MockClient((request) async {
        callCounter?.add(1);
        expect(request.url.host, 'api.github.com');
        return http.Response(jsonEncode(release), status);
      }),
    );
  }

  group('newer-release detection', () {
    test('newer v{run_number} tag surfaces an update', () async {
      _installedBuild('23');
      final update = await service(_release(tag: 'v42')).check();
      expect(update, isNotNull);
      expect(update!.versionCode, 42);
      expect(update.versionName, 'v42');
      expect(update.apkUrl, 'https://example.org/lumin-release.apk');
    });

    test('dotted tag takes the trailing segment', () async {
      _installedBuild('23');
      final update = await service(_release(tag: 'v0.0.42')).check();
      expect(update!.versionCode, 42);
    });

    test('same build shows no banner (no update loop)', () async {
      _installedBuild('42');
      expect(await service(_release(tag: 'v42')).check(), isNull);
    });

    test('older release shows no banner', () async {
      _installedBuild('50');
      expect(await service(_release(tag: 'v42')).check(), isNull);
    });

    test('unparseable tag is treated as build 0, not a crash', () async {
      _installedBuild('23');
      expect(await service(_release(tag: 'nightly')).check(), isNull);
    });
  });

  group('silent-failure contract', () {
    test('non-200 yields null', () async {
      _installedBuild('23');
      expect(
        await service(_release(), status: 403).check(),
        isNull,
      );
    });

    test('malformed payload yields null', () async {
      _installedBuild('23');
      final svc = UpdateService(
        client: MockClient((_) async => http.Response('not json', 200)),
      );
      expect(await svc.check(), isNull);
    });

    test('release without an .apk asset yields null', () async {
      _installedBuild('23');
      final svc = service(_release(assets: [
        {'name': 'symbols.zip', 'browser_download_url': 'https://x/y.zip'},
      ]));
      expect(await svc.check(), isNull);
    });

    test('network error yields null', () async {
      _installedBuild('23');
      final svc = UpdateService(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      expect(await svc.check(), isNull);
    });
  });

  group('release notes', () {
    test('long notes are truncated for the banner', () async {
      _installedBuild('23');
      final update =
          await service(_release(body: 'x' * 500)).check();
      expect(update!.releaseNotes.length, 281); // 280 chars + ellipsis
      expect(update.releaseNotes.endsWith('…'), isTrue);
    });

    test('missing notes render as empty, not null-crash', () async {
      _installedBuild('23');
      final update = await service(_release(body: null)).check();
      expect(update!.releaseNotes, '');
    });
  });

  group('cache', () {
    test('a second check within the TTL does not hit GitHub again', () async {
      _installedBuild('23');
      final calls = <int>[];
      final svc = service(_release(tag: 'v42'), callCounter: calls);
      final first = await svc.check();
      final second = await svc.check();
      expect(calls, hasLength(1));
      expect(second!.versionCode, first!.versionCode);
    });

    test('a null result is cached too (no hammering on up-to-date)',
        () async {
      _installedBuild('42');
      final calls = <int>[];
      final svc = service(_release(tag: 'v42'), callCounter: calls);
      expect(await svc.check(), isNull);
      expect(await svc.check(), isNull);
      expect(calls, hasLength(1));
    });
  });
}
