/// Markets board selection logic (2026-09-25 redesign) — pure, no device.
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/features/charts/coin_icon.dart';
import 'package:lumin/features/charts/market_view.dart';
import 'package:lumin/features/charts/models/candle.dart';

MarketTicker _t(String s, double chg, double vol) =>
    MarketTicker(symbol: s, lastPrice: 1, changePct: chg, quoteVolume: vol);

void main() {
  final board = [
    _t('BTCUSDT', -1.1, 1.6e9),
    _t('SOLUSDT', 3.4, 4.4e8),
    _t('SUIUSDT', 10.5, 1.4e8),
    _t('1000PEPEUSDT', -6.2, 9e7),
    _t('THINUSDT', 80.0, 4e4), // a wick on a thin book
    _t('FLATUSDT', 0.0, 2e7),
  ];

  group('baseAsset / contractMultiplier', () {
    test('strips USDT and a numeric contract prefix', () {
      expect(baseAsset('BTCUSDT'), 'BTC');
      expect(baseAsset('1000PEPEUSDT'), 'PEPE');
      expect(baseAsset('1000000MOGUSDT'), 'MOG');
      expect(contractMultiplier('1000PEPEUSDT'), '1000');
      expect(contractMultiplier('BTCUSDT'), isNull);
    });
    test('a base that merely contains digits is left alone', () {
      expect(baseAsset('C98USDT'), 'C98');
      expect(contractMultiplier('C98USDT'), isNull);
    });
  });

  group('segments', () {
    test('Hot is the volume order with live pairs floated up', () {
      final out = segmentRows(board, MarketSegment.hot, favourites: {}, liveSymbols: {'SUIUSDT'});
      expect(out.first.symbol, 'SUIUSDT');
      expect(out.length, board.length);
    });
    test('Gainers skip thin books and sort by change', () {
      final out = segmentRows(board, MarketSegment.gainers, favourites: {}, liveSymbols: {});
      expect([for (final r in out) r.symbol], ['SUIUSDT', 'SOLUSDT']);
    });
    test('Losers are the biggest drops first, never live-floated', () {
      final out = segmentRows(board, MarketSegment.losers, favourites: {}, liveSymbols: {'BTCUSDT'});
      expect([for (final r in out) r.symbol], ['1000PEPEUSDT', 'BTCUSDT']);
    });
    test('Favourites and Lumin live keep only their own pairs', () {
      expect(
        [for (final r in segmentRows(board, MarketSegment.favourites, favourites: {'SOLUSDT'}, liveSymbols: {})) r.symbol],
        ['SOLUSDT'],
      );
      expect(
        [for (final r in segmentRows(board, MarketSegment.live, favourites: {}, liveSymbols: {'BTCUSDT', 'NOPEUSDT'})) r.symbol],
        ['BTCUSDT'],
      );
    });
  });

  test('search runs over the whole board, prefix matches first', () {
    final out = searchRows(board, 'pe');
    expect(out.first.symbol, '1000PEPEUSDT');
    expect(searchRows(board, ''), same(board));
  });

  test('breadth counts only pairs with real volume and names what happened', () {
    final b = marketBreadth(board);
    expect(b.up, 2); // SOL, SUI — THIN is under the floor
    expect(b.down, 2);
    expect(b.flat, 1);
    expect(b.mood, 'Mixed');
    expect(marketBreadth(const []).mood, '—');
  });

  test('prices keep enough digits at every magnitude', () {
    expect(formatMarketPrice(64328.84), '64,328.8');
    expect(formatMarketPrice(3.4123), '3.412');
    expect(formatMarketPrice(0.54421), '0.5442');
    expect(formatMarketPrice(0.000767), '0.000767');
    expect(formatMarketPrice(0), '—');
    expect(formatChangePct(4.444), '+4.44%');
    expect(formatChangePct(-0.001), '0.00%');
    expect(changeDirection(-0.001), 0);
    expect(changeDirection(-1.2), -1);
    expect(formatQuoteVolume(1.68e9), '\$1.68B');
  });

  test('a monogram colour is stable for a coin', () {
    expect(monogramColors('HYPE'), monogramColors('HYPE'));
    expect(monogramColors('HYPE'), isNot(monogramColors('TAO')));
  });
}
