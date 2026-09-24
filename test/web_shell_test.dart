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

    // The web build takes 3-4s to boot; before 2026-09-23 that was a blank
    // navy page, and a startup failure left it blank forever.
    test('shows a branded splash until Flutter paints its first frame', () {
      expect(html, contains('id="lumin-splash"'));
      // Removed on the engine's own first-frame event, not on a timer — a
      // timer would either cut the splash early or leave it over the app.
      expect(html, contains("addEventListener('flutter-first-frame'"));
    });

    test('offers a reload if no frame ever arrives', () {
      expect(html, contains('class="stuck"'));
      expect(html, contains('location.reload()'));
    });

    test('the splash respects reduced motion', () {
      expect(html, contains('prefers-reduced-motion'));
    });

    // 2026-09-24: a browser reporting `en-US@posix` (or `en_US.UTF-8`)
    // made Flutter's web bootstrap throw a RangeError before runApp, so the
    // app never opened on it — Reload reproduced the crash forever.
    test('sanitises the browser locale before Flutter boots', () {
      final sanitiser = html.indexOf('Browser-locale sanitiser');
      final bootstrap = html.indexOf('flutter_bootstrap.js');
      expect(sanitiser, greaterThan(-1));
      expect(bootstrap, greaterThan(sanitiser),
          reason: 'it must run before the bootstrap reads navigator.languages');
      expect(html, contains("split('@')"));
      expect(html, contains('Intl.getCanonicalLocales'));
      // Only overrides when something was invalid; an ordinary browser is
      // left exactly as it was.
      expect(html, contains('if (!changed) return;'));
    });

    test('keeps the iOS home-screen (standalone) meta tags', () {
      expect(html, contains('apple-mobile-web-app-capable'));
      expect(html, contains('viewport-fit=cover'));
    });
  });
}
