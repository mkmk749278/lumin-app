/// The bottom bar's return-to-top contract, derived from the shell rather
/// than listed here.
///
/// Why this shape: the defect being guarded is not "scrollToTop computes the
/// wrong number" — it is "a sixth tab was added, or a tab page was rewritten,
/// and nobody wired it up". A hand-written list of the five pages would be
/// silent by construction on the next one, which is the failure mode this
/// codebase has paid for under several names. So the list of tabs is read out
/// of `NavShell._tabAt`, and every page it names must satisfy the contract.
///
/// Source-level rather than widget-level because lumin-app has no
/// AppConfigScope test-injection seam (see `region_gate_test`) — the five tab
/// pages cannot be pumped in isolation. What can be checked without one is
/// exactly what goes wrong in practice: the wiring.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

File _lib(String relative) => File('lib/$relative');

/// The widget class each tab index builds, read from `NavShell._tabAt`.
Map<String, String> _tabPagesFromNavShell() {
  final src = _lib('app/nav_shell.dart').readAsStringSync();
  final body = src.substring(src.indexOf('Widget _tabAt(int i)'));
  final end = body.indexOf('void _onSelect');
  final tabAt = body.substring(0, end == -1 ? body.length : end);

  // `return PulsePage(key: _tabKeys[0]);` -> PulsePage
  final widgets = RegExp(r'return (\w+Page)\(key: _tabKeys')
      .allMatches(tabAt)
      .map((m) => m.group(1)!)
      .toList();

  // Map each to the file that declares it, found by searching lib/.
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  final out = <String, String>{};
  for (final w in widgets) {
    final declaring = files.firstWhere(
      (f) => f.readAsStringSync().contains('class $w extends StatefulWidget'),
      orElse: () => throw StateError('no file declares $w'),
    );
    out[w] = declaring.readAsStringSync();
  }
  return out;
}

void main() {
  group('active-tab tap returns the tab to the top', () {
    test('NavShell reaches the active tab instead of swallowing the tap', () {
      final src = _lib('app/nav_shell.dart').readAsStringSync();
      final onSelect = src.substring(src.indexOf('void _onSelect(int i)'));

      // The regression this replaces: `if (i == _index) return;` — a bare
      // early return, so tapping the tab you are on did nothing at all.
      expect(
        RegExp(r'if\s*\(i\s*==\s*_index\)\s*return\s*;').hasMatch(onSelect),
        isFalse,
        reason: 'the already-active tap must be handled, not dropped',
      );
      expect(onSelect, contains('ScrollToTop'));
      expect(onSelect, contains('scrollToTop()'));
    });

    test('every tab NavShell builds implements the contract', () {
      final pages = _tabPagesFromNavShell();
      expect(pages, hasLength(5),
          reason: 'expected the five bottom-nav destinations');

      for (final entry in pages.entries) {
        expect(
          entry.value,
          contains('ScrollToTop'),
          reason: '${entry.key} does not implement ScrollToTop — a tab whose '
              'active icon does nothing is the defect this guards',
        );
        expect(
          entry.value,
          contains('void scrollToTop()'),
          reason: '${entry.key} declares the interface but never defines it',
        );
      }
    });

    test('each implementation guards on hasClients before animating', () {
      // A page can be showing a skeleton, an empty state or an error view,
      // none of which attaches the controller. Animating an unattached
      // controller throws, and it would throw on a tap the user makes
      // constantly — so this is the one runtime failure worth pinning.
      for (final entry in _tabPagesFromNavShell().entries) {
        final body = entry.value.substring(
          entry.value.indexOf('void scrollToTop()'),
        );
        final impl = body.substring(0, body.indexOf('\n  }') + 4);
        expect(
          impl.contains('hasClients') || impl.contains('?.scrollToTop()'),
          isTrue,
          reason: '${entry.key}.scrollToTop() animates without checking that '
              'anything is attached',
        );
      }
    });

    test('all five settle on one duration and curve', () {
      // Two tabs that decelerate differently is noticed even when neither is
      // wrong — the handoff asks for one motion system, not five.
      for (final entry in _tabPagesFromNavShell().entries) {
        expect(entry.value, contains('kScrollToTopDuration'),
            reason: '${entry.key} hardcodes its own duration');
        expect(entry.value, contains('kScrollToTopCurve'),
            reason: '${entry.key} hardcodes its own curve');
      }
    });

    test('the curve stops at the top rather than overshooting it', () {
      // An elastic/bounce curve at offset zero reads as more content above,
      // which there is not. easeOutCubic settles exactly on zero.
      final src = _lib('app/scroll_to_top.dart').readAsStringSync();
      expect(src, contains('Curves.easeOutCubic'));
      expect(src, isNot(contains('Curves.elasticOut')));
      expect(src, isNot(contains('Curves.bounceOut')));
    });
  });

  test('re-tapping Pulse from Alerts returns to the Dashboard', () {
    // Owner, 2026-09-25: on Alerts, tapping Pulse two or three times never
    // came back — scrollToTop only scrolled the Alerts list. Home is the
    // Dashboard, so the first re-tap switches back to it.
    final src = _lib('features/pulse/pulse_page.dart').readAsStringSync();
    final body = src.substring(src.indexOf('void scrollToTop()'));
    final impl = body.substring(0, body.indexOf('\n  }') + 4);
    expect(impl, contains('_tabController.animateTo(0)'));
    expect(impl, isNot(contains('_alertsKey.currentState?.scrollToTop()')));
  });

  group('the auth gate never tears down the open app', () {
    // Owner, 2026-09-25: back from a settings page landed on Pulse. The gate
    // passed `authStateChanges` — a getter returning a NEW Firebase stream on
    // every read — straight into its StreamBuilder, so each rebuild of the
    // gate resubscribed, reported `waiting` for a frame, rendered the splash,
    // and rebuilt NavShell on its default tab underneath the open route.
    final src = _lib('main.dart').readAsStringSync();

    test('the stream is created once, not per build', () {
      expect(src, isNot(contains('stream: scope.auth!.authStateChanges')));
      expect(src, contains('stream: _authStreamFor(scope.auth!)'));
    });

    test('a resubscribe that still carries a user never shows the splash', () {
      expect(
        src,
        contains('snap.connectionState == ConnectionState.waiting && snap.data == null'),
      );
    });
  });
}
