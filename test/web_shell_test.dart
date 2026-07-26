/// Guards the hand-maintained web (PWA) shell in `web/index.html`.
///
/// `flutter create` regenerates this file from its own template, and the
/// template does not contain the viewport lock.  Losing it silently
/// reintroduces the 2026-07-26 iPhone setup-screen bug: with the document
/// free to scroll, iOS Safari rubber-bands it under Flutter's canvas on any
/// vertical drag the scene did not consume — which is every drag on the
/// onboarding slides and the sign-in form — and the following tap resets
/// the overscroll instead of pressing the button.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('web/index.html', () {
    final html = File('web/index.html').readAsStringSync();

    test('pins the document to the viewport so iOS cannot rubber-band it',
        () {
      expect(html, contains('position: fixed'));
      expect(html, contains('overflow: hidden'));
      expect(html, contains('overscroll-behavior: none'));
    });

    test('opts out of double-tap-to-zoom so a quick second tap is a tap', () {
      expect(html, contains('touch-action: manipulation'));
    });

    test('keeps the iOS home-screen (standalone) meta tags', () {
      expect(html, contains('apple-mobile-web-app-capable'));
      expect(html, contains('viewport-fit=cover'));
    });
  });
}
