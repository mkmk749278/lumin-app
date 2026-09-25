/// Guards for the first-run install choice (2026-09-13).
///
/// The defect this page repairs was not a rendering bug and no unit test
/// could have caught it: [InstallBanner] carried the same offer, was
/// wired, tested and deployed — and mounted inside `NavShell`, behind the
/// consent gate and Firebase phone sign-in. Every test of the banner
/// passed; the audience it was built for (paid-ad traffic landing on
/// `app.luminapp.org`) could not reach it. A seam, in this repo's usual
/// shape: two halves that each look complete.
///
/// So the first group here pins the *mount point* rather than the widget,
/// by reading `lib/main.dart`. It fails against the pre-fix tree, which is
/// the only way to know a guard tests the fix.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/features/install/install_banner.dart'
    show kPlayStoreListingUrl;
import 'package:lumin/features/install/install_choice_page.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 2026-09-25 (owner: "guest login without asking anything"): the property
  // this group protects — an ad visitor meets the install offer without
  // signing in — now holds through guest mode rather than a first-run page.
  // The gate signs a visitor in as an anonymous guest and opens NavShell,
  // and NavShell mounts [InstallBanner].  So the guard follows the property:
  // the gate must enter as a guest BEFORE it ever shows the phone page, and
  // NavShell must still mount the banner.
  group('the offer is reachable without signing in', () {
    late String authGate;
    late String shell;

    setUpAll(() {
      final text = File('lib/main.dart').readAsStringSync();
      final start = text.indexOf('class _AuthGateState');
      expect(start, greaterThan(-1),
          reason: 'the auth gate moved; this guard must follow it');
      authGate = text.substring(start);
      shell = File('lib/app/nav_shell.dart').readAsStringSync();
    });

    test('the auth gate enters as a guest, not at the phone page', () {
      final guestAt = authGate.indexOf('_enterAsGuest(auth)');
      final phoneAt = authGate.indexOf('return const PhoneSignInPage()');
      expect(guestAt, greaterThan(-1),
          reason: 'Phone-OTP sign-in is the single biggest drop-off in the '
              'flow. A visitor must reach the app, and the install offer in '
              'it, without one.');
      expect(phoneAt, greaterThan(-1));
      expect(
        authGate.contains('if (_guestFailed) return const PhoneSignInPage();'),
        isTrue,
        reason: 'the phone page is only the fallback when guest sign-in fails',
      );
    });

    test('NavShell still mounts the install banner', () {
      expect(shell.contains('InstallBanner('), isTrue);
    });
  });

  group('resolveOffer', () {
    test('offers nothing on a native build', () {
      // The test VM is not `dart.library.js_interop`, so this compiles the
      // same stub the Play and sideload APKs do. A non-`none` answer here
      // would mean a "Get it on Google Play" page rendering inside the
      // Play app itself.
      expect(resolveOffer(), InstallOffer.none);
    });
  });

  group('InstallChoiceStorage', () {
    test('starts unanswered and persists an answer', () async {
      expect(await InstallChoiceStorage.seen(), isFalse);
      await InstallChoiceStorage.recordSeen();
      expect(await InstallChoiceStorage.seen(), isTrue);
    });

    test('answering the door does not silence the in-app banner', () async {
      await InstallChoiceStorage.recordSeen();
      final prefs = await SharedPreferences.getInstance();
      final banner = prefs
          .getKeys()
          .where((k) => k.startsWith('pwa_banner_dismissed_'))
          .toList();
      expect(
        banner,
        isEmpty,
        reason: 'Skipping once at the door is not a decline forever — the '
            'owner asked that the app keep suggesting this while in use, '
            'so the two decisions must not share a key.',
      );
    });
  });

  group('the Android offer', () {
    // Records what the page asked the opener for, and answers with a
    // caller-chosen outcome. The real launchUrl never completes under
    // `flutter test` — no platform implementation is registered — so the
    // widget's own behaviour is only reachable through this seam.
    late List<Uri> opened;
    late List<LaunchMode> modes;

    setUp(() {
      opened = <Uri>[];
      modes = <LaunchMode>[];
    });

    UrlOpener opener(bool outcome) =>
        (Uri url, {LaunchMode mode = LaunchMode.platformDefault}) async {
          opened.add(url);
          modes.add(mode);
          return outcome;
        };

    Future<void> pumpAndroid(
      WidgetTester tester, {
      required VoidCallback onContinue,
      bool launchSucceeds = true,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: InstallChoicePage(
          offer: InstallOffer.play,
          onContinue: onContinue,
          openUrl: opener(launchSucceeds),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('offers Play and a way past it', (tester) async {
      await pumpAndroid(tester, onContinue: () {});
      expect(find.text('Get it on Google Play'), findsOneWidget);
      expect(find.text('Continue in browser'), findsOneWidget);
      // No performance claim on a surface a paid ad lands on — same rule
      // the ad copy itself is bound by.
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('sends the listing URL out to the real browser',
        (tester) async {
      await pumpAndroid(tester, onContinue: () {});
      await tester.tap(find.text('Get it on Google Play'));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse(kPlayStoreListingUrl)]);
      // Not an in-app webview: a Play listing opened inside one cannot
      // hand off to the Play app, which is the whole point of the tap.
      expect(modes, [LaunchMode.externalApplication]);
    });

    testWidgets('a successful launch still records the answer',
        (tester) async {
      var continues = 0;
      await pumpAndroid(tester, onContinue: () => continues++);
      await tester.tap(find.text('Get it on Google Play'));
      await tester.pumpAndSettle();
      expect(continues, 1);
      expect(await InstallChoiceStorage.seen(), isTrue);
      // Play opened, so there is nothing to apologise for.
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a blocked launch still lets the visitor through',
        (tester) async {
      var continues = 0;
      await pumpAndroid(tester,
          onContinue: () => continues++, launchSucceeds: false);
      // Exactly the path the Instagram and Facebook in-app browsers take
      // when they refuse the navigation. The visitor must not be stranded
      // on a dead screen, the flag must still be recorded, and the
      // fallback must name what to search for.
      await tester.tap(find.text('Get it on Google Play'));
      await tester.pumpAndSettle();
      expect(continues, 1);
      expect(await InstallChoiceStorage.seen(), isTrue);
      expect(find.textContaining('Could not open Google Play'), findsOneWidget);
      // pumpAndSettle stops once no frame is scheduled, which leaves the
      // SnackBar's own 4s auto-dismiss timer pending at teardown. Run the
      // clock past it and let the exit animation finish.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
    });

    testWidgets('skipping records the answer and never opens Play',
        (tester) async {
      var continues = 0;
      await pumpAndroid(tester, onContinue: () => continues++);
      await tester.tap(find.text('Continue in browser'));
      await tester.pumpAndSettle();
      expect(continues, 1);
      expect(await InstallChoiceStorage.seen(), isTrue);
      expect(opened, isEmpty);
    });
  });

  group('the iOS offer', () {
    testWidgets('is instructions, never a button that does nothing',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: InstallChoicePage(
          offer: InstallOffer.addToHomeScreen,
          onContinue: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Add to Home Screen'), findsWidgets);
      expect(find.text('Continue without installing'), findsOneWidget);
      // There is no programmatic hook for Add to Home Screen on iOS, and a
      // control that looks tappable and does nothing is worse than none.
      expect(find.text('Get it on Google Play'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('never mentions Play — there is no iOS listing to send to',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: InstallChoicePage(
          offer: InstallOffer.addToHomeScreen,
          onContinue: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Google Play'), findsNothing);
      expect(kPlayStoreListingUrl, contains('play.google.com'));
    });
  });
}
