/// Tests for the foreground-refresh throttle decision.
///
/// Scope: the pure `shouldRefreshOnForeground` predicate that NavShell uses
/// to decide whether an app-resume should refresh the visible tab. The
/// widget wiring (WidgetsBindingObserver -> active-tab GlobalKey ->
/// ForegroundRefreshable) is validated by `flutter analyze` + `flutter
/// build` in CI; lumin-app has no AppConfigScope test-injection seam for
/// widget tests (see region_gate_test), so the logic worth asserting lives
/// in the pure function tested here.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/app/foreground_refresh.dart';

void main() {
  group('shouldRefreshOnForeground', () {
    const throttle = Duration(seconds: 30);
    final t0 = DateTime(2026, 6, 2, 12, 0, 0);

    test('first resume (no prior refresh) always refreshes', () {
      expect(
        shouldRefreshOnForeground(
          lastRefresh: null,
          now: t0,
          throttle: throttle,
        ),
        isTrue,
      );
    });

    test('a quick bounce within the throttle window does NOT refresh', () {
      // e.g. notification shade / biometric prompt pulled the app to
      // background and back inside a few seconds.
      expect(
        shouldRefreshOnForeground(
          lastRefresh: t0,
          now: t0.add(const Duration(seconds: 5)),
          throttle: throttle,
        ),
        isFalse,
      );
    });

    test('exactly at the throttle boundary refreshes (>=)', () {
      expect(
        shouldRefreshOnForeground(
          lastRefresh: t0,
          now: t0.add(throttle),
          throttle: throttle,
        ),
        isTrue,
      );
    });

    test('a real return after minutes refreshes', () {
      expect(
        shouldRefreshOnForeground(
          lastRefresh: t0,
          now: t0.add(const Duration(minutes: 7)),
          throttle: throttle,
        ),
        isTrue,
      );
    });

    test('one nanosecond under the boundary does NOT refresh', () {
      expect(
        shouldRefreshOnForeground(
          lastRefresh: t0,
          now: t0.add(throttle - const Duration(microseconds: 1)),
          throttle: throttle,
        ),
        isFalse,
      );
    });
  });
}
