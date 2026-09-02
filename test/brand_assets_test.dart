/// Guards the Lumin brand resources and the CI step that installs them.
///
/// `android/` is not checked in — CI regenerates it with `flutter create` on
/// every run — so until 2026-09-02 there was nowhere for a launcher icon to
/// live and every Play release shipped the stock Flutter chevron, an
/// `android:label` of "lumin" (the --project-name, lowercase) and the
/// template's white `launch_background`, which flashed white before a
/// deep-navy app on every cold start.
///
/// The fix is a committed resource tree plus one workflow step that copies
/// it in. Both halves are load-bearing and neither is visible from Dart at
/// runtime, so this is the only thing that can notice if one goes missing:
/// a template restore would put the white drawable back, and nothing in the
/// app would fail.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Android density buckets and their multiple of the mdpi baseline.
const _densities = <String, double>{
  'mdpi': 1,
  'hdpi': 1.5,
  'xhdpi': 2,
  'xxhdpi': 3,
  'xxxhdpi': 4,
};

/// Baseline dp for each bitmap the resource tree ships, keyed by file stem.
/// Wrong-sized mipmaps do not fail a build — Android silently rescales them,
/// which is how a blurry icon ships.
const _baselineDp = <String, int>{
  'ic_launcher': 48,
  'ic_launcher_foreground': 108,
  'ic_launcher_monochrome': 108,
  'ic_launcher_splash': 160,
};

const _resRoot = 'assets/brand/android/res';

/// An XML file's *declarations* — comments stripped.
///
/// The "must not contain" assertions below are about what a resource file
/// declares, and a comment declares nothing. Asserting against the raw text
/// makes a prose explanation of a defect indistinguishable from the defect:
/// the first run of this suite failed because `values/styles.xml` explains,
/// in a comment, that it pins a colour *rather than* `?android:colorBackground`
/// — and the words tripped the guard against the thing they describe.
String _declarations(File f) =>
    f.readAsStringSync().replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

/// Reads a PNG's dimensions straight out of the IHDR chunk — cheaper than
/// decoding, and enough to catch an asset generated at the wrong density.
({int width, int height}) _pngSize(File f) {
  final b = f.readAsBytesSync();
  expect(b.length, greaterThan(24), reason: '${f.path} is too short to be a PNG');
  expect(b.sublist(1, 4), equals('PNG'.codeUnits), reason: '${f.path} is not a PNG');
  int be32(int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  return (width: be32(16), height: be32(20));
}

void main() {
  group('android brand resources', () {
    test('every density ships every bitmap, at the right size', () {
      for (final MapEntry(key: bucket, value: mult) in _densities.entries) {
        for (final MapEntry(key: stem, value: dp) in _baselineDp.entries) {
          final f = File('$_resRoot/mipmap-$bucket/$stem.png');
          expect(f.existsSync(), isTrue, reason: 'missing $bucket/$stem.png');

          final expected = (dp * mult).round();
          final size = _pngSize(f);
          expect(size.width, expected,
              reason: '$bucket/$stem.png is ${size.width}px, expected $expected');
          expect(size.height, expected,
              reason: '$bucket/$stem.png is ${size.height}px, expected $expected');
        }
      }
    });

    test('declares an adaptive icon with a monochrome layer', () {
      final xml = File('$_resRoot/mipmap-anydpi-v26/ic_launcher.xml');
      expect(xml.existsSync(), isTrue);
      final s = xml.readAsStringSync();
      expect(s, contains('<adaptive-icon'));
      expect(s, contains('@color/ic_launcher_background'));
      expect(s, contains('@mipmap/ic_launcher_foreground'));
      // Without this, Android 13+ themed icons fall back to shrinking the
      // whole icon into a grey circle.
      expect(s, contains('<monochrome'));
    });

    test('the splash paints bgDeep, never the template white', () {
      // drawable-v21 shadows drawable on every device this app supports, so
      // a fix applied to only one of them is not applied at all.
      for (final dir in ['drawable', 'drawable-v21']) {
        final f = File('$_resRoot/$dir/launch_background.xml');
        expect(f.existsSync(), isTrue, reason: 'missing $dir/launch_background.xml');
        final s = _declarations(f);
        expect(s, isNot(contains('@android:color/white')),
            reason: '$dir still paints the Flutter template white');
        expect(s, contains('@color/lumin_splash_background'));
        expect(s, contains('@mipmap/ic_launcher_splash'));
      }
    });

    test('both styles variants pin a dark window background', () {
      // NormalTheme takes over the moment the splash tears down. The template
      // hands it ?android:colorBackground, which is white under a light
      // system theme — a white frame after the splash we just fixed.
      for (final dir in ['values', 'values-night']) {
        final s = _declarations(File('$_resRoot/$dir/styles.xml'));
        expect(s, contains('name="LaunchTheme"'));
        expect(s, contains('name="NormalTheme"'));
        expect(s, contains('@color/lumin_splash_background'));
        expect(s, isNot(contains('?android:colorBackground')));
      }
    });

    test('the colours are the app tokens, not near-misses', () {
      final s = File('$_resRoot/values/ic_launcher_background.xml').readAsStringSync();
      expect(s, contains('#7BD3F7')); // LuminColors.accent
      expect(s, contains('#0A0E1A')); // LuminColors.bgDeep
    });
  });

  group('web / PWA icons', () {
    test('ship at their declared sizes', () {
      const expected = {
        'web/icons/Icon-192.png': 192,
        'web/icons/Icon-512.png': 512,
        'web/icons/Icon-maskable-192.png': 192,
        'web/icons/Icon-maskable-512.png': 512,
      };
      for (final MapEntry(key: path, value: px) in expected.entries) {
        final size = _pngSize(File(path));
        expect(size.width, px, reason: '$path is ${size.width}px, expected $px');
      }
    });

    test('manifest.json names every icon that exists on disk', () {
      final manifest = File('web/manifest.json').readAsStringSync();
      for (final f in Directory('web/icons').listSync().whereType<File>()) {
        final name = f.uri.pathSegments.last;
        expect(manifest, contains(name), reason: '$name is on disk but unreferenced');
      }
    });
  });

  group('build-apk.yml installs them', () {
    final wf = File('.github/workflows/build-apk.yml').readAsStringSync();

    test('copies the committed resource tree into the generated android/', () {
      // The whole point: `flutter create` runs every build, so the icon has
      // to be re-applied every build.
      expect(wf, contains('assets/brand/android/res'));
      expect(wf, contains(r'cp -R assets/brand/android/res/. "$RES/"'));
    });

    test('rewrites the app label away from the --project-name', () {
      expect(wf, contains('--project-name=lumin'),
          reason: 'scaffolding step changed; re-check what label it produces');
      expect(wf, contains(r'android:label="Lumin"'));
    });

    test('the step verifies itself rather than copying and hoping', () {
      expect(wf, contains('FAIL: app label is not Lumin'));
      expect(wf, contains('FAIL: adaptive icon missing'));
      expect(wf, contains('FAIL: launch_background still paints white'));
    });
  });
}
