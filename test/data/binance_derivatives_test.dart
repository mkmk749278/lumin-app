/// Derivatives strip parsers (2026-09-25 Charts redesign, part 2).
/// Payload shapes are Binance's documented USDⓈ-M responses.
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/binance_derivatives.dart';

void main() {
  test('funding: rate and next time; junk is null, never zero', () {
    final (rate, next) = parseFunding({
      'symbol': 'BTCUSDT',
      'lastFundingRate': '0.00010000',
      'nextFundingTime': 1790380800000,
    });
    expect(rate, closeTo(0.0001, 1e-12));
    expect(next, DateTime.fromMillisecondsSinceEpoch(1790380800000, isUtc: true));
    expect(parseFunding(null), (null, null));
    expect(parseFunding({'lastFundingRate': 'x'}).$1, isNull);
  });

  test('open interest: newest value and a true 24h change', () {
    final rows = [
      for (var i = 0; i < 25; i++) {'sumOpenInterestValue': '${100 + i * 1.0}'},
    ];
    final (now, chg) = parseOpenInterest(rows);
    expect(now, 124);
    expect(chg, closeTo(24.0, 1e-9));
  });

  test('open interest: fewer than 25 buckets gives a value but no "24h" change', () {
    final (now, chg) = parseOpenInterest([
      {'sumOpenInterestValue': '50'},
      {'sumOpenInterestValue': '60'},
    ]);
    expect(now, 60);
    expect(chg, isNull);
  });

  test('long accounts share and taker buy share', () {
    expect(parseLongAccountShare([{'longAccount': '0.6214', 'shortAccount': '0.3786'}]), closeTo(0.6214, 1e-9));
    expect(parseLongAccountShare([{'longAccount': '7'}]), isNull);
    expect(parseTakerBuyShare([{'buyVol': '300', 'sellVol': '100'}]), 0.75);
    expect(parseTakerBuyShare([{'buyVol': '0', 'sellVol': '0'}]), isNull);
    expect(parseTakerBuyShare(const []), isNull);
  });

  test('words for the numbers: funding to four places, who pays, countdown', () {
    expect(formatFundingRate(0.0001), '+0.0100%');
    expect(formatFundingRate(-0.00005), '-0.0050%');
    expect(fundingPayer(0.0001), 'Longs pay shorts');
    expect(fundingPayer(-0.0001), 'Shorts pay longs');
    expect(fundingPayerShort(0.0001), 'Longs pay');
    expect(fundingPayerShort(0), 'Nobody pays');
    final now = DateTime.utc(2026, 9, 25, 12);
    expect(formatCountdown(now.add(const Duration(hours: 3, minutes: 12)), now), '3h 12m');
    expect(formatCountdown(now.add(const Duration(minutes: 9)), now), '9m');
    expect(formatCountdown(now.subtract(const Duration(minutes: 1)), now), 'now');
  });
}
