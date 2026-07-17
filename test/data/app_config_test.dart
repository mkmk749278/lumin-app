/// Tests for the boot-time config + repository selection (2026-07-17).
///
/// `AppConfig.load` decides whether a real user sees LIVE engine data or
/// the offline mock set — a wrong fallback silently ships mock signals to
/// a production install.  Pinned:
///
/// * first-run defaults: LIVE against the production base URL (mock is
///   the explicit opt-in, never the fallback);
/// * unknown persisted values collapse to live, not to mock;
/// * save/load round-trip;
/// * `AppConfigScope` in mock mode wires MockRepository with NO auth, and
///   `maybeOf` degrades to null outside the scope (the widget-test
///   affordance the pages rely on).
///
/// The live branch of `_buildDeps` (HttpRepository + AuthService) is
/// exercised indirectly by the HttpRepository suite; constructing it here
/// would need a Firebase app, which flutter_test doesn't have.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/app_config.dart';
import 'package:lumin/data/repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AppConfig.load', () {
    test('first run defaults to LIVE against the production URL', () async {
      SharedPreferences.setMockInitialValues({});
      final config = await AppConfig.load();
      expect(config.dataSource, DataSource.live);
      expect(config.apiBaseUrl, AppConfig.defaultBaseUrl);
    });

    test('persisted mock mode is honoured', () async {
      SharedPreferences.setMockInitialValues({
        'lumin.dataSource': 'mock',
        'lumin.apiBaseUrl': 'http://10.0.2.2:8000',
      });
      final config = await AppConfig.load();
      expect(config.dataSource, DataSource.mock);
      expect(config.apiBaseUrl, 'http://10.0.2.2:8000');
    });

    test('an unknown persisted value collapses to live, never mock',
        () async {
      // Fail-safe direction: a corrupted pref must not silently switch a
      // production install onto fake data.
      SharedPreferences.setMockInitialValues({'lumin.dataSource': 'banana'});
      final config = await AppConfig.load();
      expect(config.dataSource, DataSource.live);
    });

    test('save round-trips through load', () async {
      SharedPreferences.setMockInitialValues({});
      await AppConfig(
        dataSource: DataSource.mock,
        apiBaseUrl: 'https://staging.example.org',
      ).save();
      final config = await AppConfig.load();
      expect(config.dataSource, DataSource.mock);
      expect(config.apiBaseUrl, 'https://staging.example.org');
    });
  });

  group('copyWith', () {
    test('changes only the named field', () {
      final base = AppConfig(
        dataSource: DataSource.live,
        apiBaseUrl: AppConfig.defaultBaseUrl,
      );
      final flipped = base.copyWith(dataSource: DataSource.mock);
      expect(flipped.dataSource, DataSource.mock);
      expect(flipped.apiBaseUrl, AppConfig.defaultBaseUrl);
    });
  });

  group('AppConfigScope (mock mode)', () {
    testWidgets('wires MockRepository with no auth service', (tester) async {
      late LuminRepository repo;
      late Object? auth;
      await tester.pumpWidget(
        AppConfigScope(
          initial: AppConfig(dataSource: DataSource.mock, apiBaseUrl: ''),
          child: MaterialApp(
            home: Builder(builder: (context) {
              final scope = AppConfigScope.of(context);
              repo = scope.repo;
              auth = scope.auth;
              return const SizedBox();
            }),
          ),
        ),
      );
      expect(repo, isA<MockRepository>());
      expect(repo.isLive, isFalse);
      // Mock mode carries no identity: tier-gates render their safe
      // defaults and the auth-gate mock-bypass path stays consistent.
      expect(auth, isNull);
    });

    testWidgets('maybeOf returns null outside a scope', (tester) async {
      Object? found = 'sentinel';
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (context) {
            found = AppConfigScope.maybeOf(context);
            return const SizedBox();
          }),
        ),
      );
      expect(found, isNull);
    });
  });
}
