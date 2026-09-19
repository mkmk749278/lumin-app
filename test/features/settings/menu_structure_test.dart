/// The Menu's shape after the 2026-09-19 restructure (handoff §27-§29).
///
/// Two kinds of assertion, and the split matters:
///
///  * The hub pages are pumped for real — `TradingSettingsPage` and
///    `LegalPage` take no `AppConfigScope`, so unlike the root Menu they can
///    be rendered in a widget test. What is checked is that nesting did not
///    *lose* anything: every row that left the root list is reachable here.
///  * The root Menu is checked at the source level, because it reads
///    `AppConfigScope.of(context).tierRevision` and this repo has no
///    injection seam for that (see `region_gate_test`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/features/settings/pages/legal_page.dart';
import 'package:lumin/features/settings/pages/trading_settings_page.dart';

import 'dart:io';

String get _menuSource =>
    File('lib/features/settings/settings_page.dart').readAsStringSync();

void main() {
  group('advanced settings are nested, not deleted', () {
    testWidgets('the Trading hub still reaches all five moved pages',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: TradingSettingsPage()),
      );
      await tester.pump();

      // These five rows were the root Menu's entire AUTO-TRADE section. The
      // restructure is only defensible because none of them was removed.
      expect(find.text('Auto-trade'), findsOneWidget);
      expect(find.text('Exchange connection'), findsOneWidget);
      expect(find.text('Symbol preference'), findsOneWidget);
      expect(find.text('Pre-TP grab'), findsOneWidget);
      expect(find.text('Invalidation'), findsOneWidget);
    });

    testWidgets('each advanced row explains what the setting does',
        (tester) async {
      // Handoff §30: `Pre-TP grab` and `Invalidation` are Lumin's own
      // vocabulary. A name with no sentence under it teaches nobody what the
      // switch changes, and these two are the ones a user is least able to
      // guess.
      await tester.pumpWidget(
        const MaterialApp(home: TradingSettingsPage()),
      );
      await tester.pump();

      expect(
        find.textContaining('secured before the primary target'),
        findsOneWidget,
      );
      expect(
        find.textContaining('no longer valid'),
        findsOneWidget,
      );
    });

    testWidgets('the Legal hub still reaches all three documents',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LegalPage()));
      await tester.pump();

      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Terms of Service'), findsOneWidget);
      expect(find.text('Risk Disclosure'), findsOneWidget);
    });
  });

  group('the root Menu stays uncluttered', () {
    test('the advanced pages are no longer pushed from the root', () {
      final src = _menuSource;
      // Each of these used to be its own root-level row. If one comes back,
      // it should come back deliberately — not by a merge quietly restoring
      // the flat list.
      for (final page in const [
        'PreTpSettingsPage',
        'InvalidationSettingsPage',
        'SymbolPreferencePage',
        'ServerSideExecutionPage',
        'AutoTradeSettingsPage',
      ]) {
        expect(
          src,
          isNot(contains(page)),
          reason: '$page is reachable from the root Menu again — it belongs '
              'behind TradingSettingsPage',
        );
      }
    });

    test('the root Menu opens the two hubs', () {
      final src = _menuSource;
      expect(src, contains('TradingSettingsPage()'));
      expect(src, contains('LegalPage()'));
    });

    test('the promo banners sit below the settings, not above them', () {
      // They used to occupy the whole first screen, so opening the Menu to
      // change a setting showed two adverts and no settings (handoff §6).
      final src = _menuSource;
      final firstSection = src.indexOf("title: 'ACCOUNT'");
      final upgradeBanner = src.indexOf("UpgradeBanner(slot: 'menu')");
      final inviteBanner = src.indexOf("InviteBanner(slot: 'menu')");

      expect(firstSection, greaterThan(0));
      expect(upgradeBanner, greaterThan(firstSection),
          reason: 'the upgrade banner is above the first settings group');
      expect(inviteBanner, greaterThan(firstSection),
          reason: 'the invite banner is above the first settings group');
    });

    test('the destructive rows are still marked destructive', () {
      // Sign-out and delete-account moved into MORE. They must not have lost
      // the loss accent on the way — an irreversible row that looks like
      // `Profile` is one careless tap from a deleted account.
      final src = _menuSource;
      final signOut = src.indexOf("label: 'Sign out'");
      final deleteAccount = src.indexOf("label: 'Delete account'");
      expect(signOut, greaterThan(0));
      expect(deleteAccount, greaterThan(0));
      expect(src.substring(signOut, signOut + 200), contains('destructive: true'));
      expect(src.substring(deleteAccount, deleteAccount + 260),
          contains('destructive: true'));
    });
  });
}
