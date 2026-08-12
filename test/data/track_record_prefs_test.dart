/// `TrackRecordPrefs` — the reader's own position size.
///
/// The property that matters is not "it stores a double". It is that **unset
/// and 100 are different states**: unset sends no `amount` at all and inherits
/// whatever the engine assumes, while 100 asserts a number this file would
/// then own. If those ever collapse, changing the engine's default silently
/// stops moving the app — the drifting-mirror shape at a single constant.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/track_record_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TrackRecordPrefs.instance.resetForTest();
  });

  group('unset means "the engine\'s default", not 100', () {
    test('nothing stored sends no amount at all', () async {
      await TrackRecordPrefs.instance.load();
      expect(TrackRecordPrefs.instance.amountOrNull, isNull);
    });

    test('...while still having something to DISPLAY', () async {
      // The fallback is display-only. Every payload also carries
      // `amount_usdt`, so a rendered figure is labelled with the size the
      // ENGINE used — never with this constant.
      await TrackRecordPrefs.instance.load();
      expect(TrackRecordPrefs.instance.amountForDisplay, 100.0);
    });

    test('clearing goes back to unset, not to 100', () async {
      await TrackRecordPrefs.instance.setAmount(250);
      expect(TrackRecordPrefs.instance.amountOrNull, 250);
      await TrackRecordPrefs.instance.clear();
      expect(TrackRecordPrefs.instance.amountOrNull, isNull);
    });
  });

  group('persistence', () {
    test('a stored size survives a reload', () async {
      await TrackRecordPrefs.instance.setAmount(250);
      TrackRecordPrefs.instance.resetForTest();
      await TrackRecordPrefs.instance.load();
      expect(TrackRecordPrefs.instance.amountOrNull, 250);
    });

    test('a cleared size does not come back', () async {
      await TrackRecordPrefs.instance.setAmount(250);
      await TrackRecordPrefs.instance.clear();
      TrackRecordPrefs.instance.resetForTest();
      await TrackRecordPrefs.instance.load();
      expect(TrackRecordPrefs.instance.amountOrNull, isNull);
    });

    test('a stored value outside the bounds is ignored on load', () async {
      // Not clamped: a size the reader never typed would price a whole book
      // and be labelled as theirs.
      SharedPreferences.setMockInitialValues(
        {'lumin.trackRecord.amountUsdt': 0.0},
      );
      TrackRecordPrefs.instance.resetForTest();
      await TrackRecordPrefs.instance.load();
      expect(TrackRecordPrefs.instance.amountOrNull, isNull);
    });
  });

  group('bounds', () {
    test('zero is refused rather than clamped', () async {
      // A size of zero renders a book of +$0.00, which reads as "the signals
      // made nothing".
      expect(await TrackRecordPrefs.instance.setAmount(0), isFalse);
      expect(TrackRecordPrefs.instance.amountOrNull, isNull);
    });

    test('negative and absurd values are refused', () async {
      for (final bad in [-1.0, 1e9, double.nan, double.infinity]) {
        expect(await TrackRecordPrefs.instance.setAmount(bad), isFalse,
            reason: '$bad');
      }
      expect(TrackRecordPrefs.instance.amountOrNull, isNull);
    });

    test('the bounds themselves are accepted', () async {
      expect(
        await TrackRecordPrefs.instance.setAmount(TrackRecordPrefs.minAmount),
        isTrue,
      );
      expect(
        await TrackRecordPrefs.instance.setAmount(TrackRecordPrefs.maxAmount),
        isTrue,
      );
    });
  });

  group('one number, app-wide', () {
    test('a change notifies listeners so every surface re-prices', () async {
      // The engine does the arithmetic, so a surface holding a priced book
      // cannot scale it — it has to ask again. That only happens if it hears
      // about the change.
      var heard = 0;
      void listener() => heard++;
      TrackRecordPrefs.instance.amount.addListener(listener);
      addTearDown(
        () => TrackRecordPrefs.instance.amount.removeListener(listener),
      );

      await TrackRecordPrefs.instance.setAmount(500);
      expect(heard, 1);
      await TrackRecordPrefs.instance.clear();
      expect(heard, 2);
    });

    test('it is a single instance', () {
      expect(
        identical(TrackRecordPrefs.instance, TrackRecordPrefs.instance),
        isTrue,
      );
    });
  });
}
