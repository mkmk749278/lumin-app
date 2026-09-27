/// CoinDCX trading-platform models (engine 360-v2 `src/api/coindcx_routes.py`,
/// 2026-09-27).
///
/// A user executes on ONE exchange — the one they choose here.  Binance stays
/// the default; CoinDCX is chosen explicitly and needs an attested key.
///
/// Every status the user reads carries whether the engine could observe it
/// (`readable`).  A failed read is never rendered as "not connected": that is
/// the "an engine unknown is not an engine no" rule in CLAUDE.md, and on a
/// screen about someone's key it decides whether they go and re-create a key
/// that is perfectly fine.
library;

double? _d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
bool? _b(Object? v) => v is bool ? v : null;

/// `GET /api/coindcx/info` — what the connect guide shows.
class CoinDCXInfo {
  const CoinDCXInfo({
    required this.engineIp,
    required this.attestationItems,
    required this.marginCurrencies,
    required this.marginDefault,
    required this.leverageMin,
    required this.leverageMax,
    required this.leverageDefault,
    required this.inrPerUsdt,
    required this.executionEnabled,
    required this.exitProfile,
  });

  final String? engineIp;
  final List<String> attestationItems;
  final List<String> marginCurrencies;
  final String marginDefault;
  final double leverageMin;
  final double leverageMax;
  final double leverageDefault;
  final double? inrPerUsdt;
  final bool executionEnabled;
  final String exitProfile;

  factory CoinDCXInfo.fromJson(Map<String, dynamic> j) => CoinDCXInfo(
        engineIp: j['engine_ip'] as String?,
        attestationItems: [
          for (final s in (j['attestation_items'] as List? ?? const [])) '$s'
        ],
        marginCurrencies: [
          for (final s in (j['margin_currencies'] as List? ?? const ['INR', 'USDT'])) '$s'
        ],
        marginDefault: (j['margin_default'] as String?) ?? 'INR',
        leverageMin: _d(j['leverage_min']) ?? 1,
        leverageMax: _d(j['leverage_max']) ?? 20,
        leverageDefault: _d(j['leverage_default']) ?? 5,
        inrPerUsdt: _d(j['inr_per_usdt']),
        executionEnabled: j['execution_enabled'] == true,
        exitProfile: (j['exit_profile'] as String?) ?? '',
      );
}

/// `GET /api/coindcx/connect/status` — tri-state.
class CoinDCXConnectStatus {
  const CoinDCXConnectStatus({
    required this.readable,
    required this.connected,
    required this.attested,
    this.keyPublicIdFirst8,
    this.connectedAt,
  });

  /// `false` = the engine could not read the key store; `connected` and
  /// `attested` are then `null` and mean nothing.
  final bool readable;
  final bool? connected;
  final bool? attested;
  final String? keyPublicIdFirst8;
  final DateTime? connectedAt;

  static const unreadable =
      CoinDCXConnectStatus(readable: false, connected: null, attested: null);

  factory CoinDCXConnectStatus.fromJson(Map<String, dynamic> j) {
    final readable = j['readable'] != false;
    return CoinDCXConnectStatus(
      readable: readable,
      connected: readable ? _b(j['connected']) : null,
      attested: readable ? _b(j['attested']) : null,
      keyPublicIdFirst8: j['key_public_id_first8'] as String?,
      connectedAt: DateTime.tryParse('${j['connected_at'] ?? ''}'),
    );
  }
}

class CoinDCXConnectSuccess {
  const CoinDCXConnectSuccess({required this.keyPublicIdFirst8, required this.balances});
  final String keyPublicIdFirst8;
  final Map<String, double> balances;

  factory CoinDCXConnectSuccess.fromJson(Map<String, dynamic> j) =>
      CoinDCXConnectSuccess(
        keyPublicIdFirst8: '${j['key_public_id_first8'] ?? ''}',
        balances: {
          for (final e in ((j['balances'] as Map?) ?? const {}).entries)
            '${e.key}': _d(e.value) ?? 0,
        },
      );
}

class CoinDCXConnectError implements Exception {
  const CoinDCXConnectError({
    required this.code,
    required this.detail,
    this.httpStatus,
    this.engineIp,
  });
  final String code;
  final String detail;
  final int? httpStatus;
  final String? engineIp;

  @override
  String toString() => 'CoinDCXConnectError($code): $detail';
}

/// `GET/PUT /api/venue` — which exchange the user trades on.
class VenueSettings {
  const VenueSettings({
    required this.venue,
    required this.marginCurrency,
    required this.leverage,
    required this.readable,
    required this.coindcxConnected,
    required this.coindcxAttested,
    required this.coindcxKeyReadable,
    required this.coindcxExecutionEnabled,
    required this.coindcxAllowListed,
  });

  /// `binance` | `coindcx`.  When [readable] is false this is the engine's
  /// safe fallback (binance), not a choice the user made.
  final String venue;
  final String marginCurrency;
  final double leverage;
  final bool readable;
  final bool? coindcxConnected;
  final bool? coindcxAttested;
  final bool coindcxKeyReadable;
  final bool coindcxExecutionEnabled;
  final bool coindcxAllowListed;

  bool get isCoinDCX => venue == 'coindcx';

  /// CoinDCX is chosen, the key is good, and the engine will actually place
  /// orders for this user.  Anything short of that is said on screen.
  bool get coindcxLive =>
      isCoinDCX &&
      coindcxConnected == true &&
      coindcxAttested == true &&
      coindcxExecutionEnabled &&
      coindcxAllowListed;

  factory VenueSettings.fromJson(Map<String, dynamic> j) {
    final c = (j['coindcx'] as Map?)?.cast<String, dynamic>() ?? const {};
    final keyReadable = c['readable'] == true;
    return VenueSettings(
      venue: (j['venue'] as String?) ?? 'binance',
      marginCurrency: (j['margin_currency'] as String?) ?? 'INR',
      leverage: _d(j['leverage']) ?? 5,
      readable: j['readable'] == true,
      coindcxConnected: keyReadable ? _b(c['connected']) : null,
      coindcxAttested: keyReadable ? _b(c['attested']) : null,
      coindcxKeyReadable: keyReadable,
      coindcxExecutionEnabled: c['execution_enabled'] == true,
      coindcxAllowListed: c['allow_listed'] == true,
    );
  }
}

/// One CoinDCX position (`GET /api/coindcx/positions`).
class CoinDCXPosition {
  const CoinDCXPosition({
    required this.signalId,
    required this.symbol,
    required this.side,
    required this.state,
    required this.marginCurrency,
    required this.leverage,
    required this.qty,
    required this.entryFilled,
    required this.slPrice,
    required this.tpPrice,
    required this.slResting,
    required this.closeReason,
    required this.exitPrice,
    required this.realizedPnlUsdt,
    required this.realizedPnlInr,
    required this.notionalUsdt,
    required this.notionalInr,
    required this.feesUsdt,
    required this.lastError,
    this.conversionPrice = 0,
  });

  final String signalId;
  final String symbol;
  final String side;
  final String state;
  final String marginCurrency;
  final double leverage;
  final double qty;
  final double entryFilled;
  final double slPrice;
  final double tpPrice;
  final bool slResting;
  final String closeReason;
  final double exitPrice;
  final double? realizedPnlUsdt;
  final double? realizedPnlInr;
  final double notionalUsdt;
  final double? notionalInr;
  final double? feesUsdt;
  final String lastError;

  /// CoinDCX's own INR/USDT price used for this trade (0 on USDT margin).
  final double conversionPrice;

  /// The engine's `realized_pnl_usdt` is GROSS — price move × qty, before
  /// fees.  Net subtracts the fees CoinDCX reported for both fills; `null`
  /// when either figure is unknown, so a missing fee is never read as zero.
  double? get netPnlUsdt {
    final g = realizedPnlUsdt;
    final f = feesUsdt;
    if (g == null || f == null) return null;
    return g - f;
  }

  /// Net P&L in ₹, only at CoinDCX's own published rate — never ours.
  double? get netPnlInr {
    final n = netPnlUsdt;
    if (n == null || marginCurrency != 'INR' || conversionPrice <= 0) return null;
    return n * conversionPrice;
  }

  bool get isLive => const {'PENDING', 'ENTRY_UNCERTAIN', 'OPEN', 'CLOSING'}.contains(state);

  factory CoinDCXPosition.fromJson(Map<String, dynamic> j) => CoinDCXPosition(
        signalId: '${j['signal_id'] ?? ''}',
        symbol: '${j['symbol'] ?? ''}',
        side: '${j['side'] ?? ''}',
        state: '${j['state'] ?? ''}',
        marginCurrency: '${j['margin_currency'] ?? 'USDT'}',
        leverage: _d(j['leverage']) ?? 0,
        qty: _d(j['qty']) ?? 0,
        entryFilled: _d(j['entry_filled']) ?? 0,
        slPrice: _d(j['sl_price']) ?? 0,
        tpPrice: _d(j['tp_price']) ?? 0,
        slResting: j['sl_resting'] == true,
        closeReason: '${j['close_reason'] ?? ''}',
        exitPrice: _d(j['exit_price']) ?? 0,
        realizedPnlUsdt: _d(j['realized_pnl_usdt']),
        realizedPnlInr: _d(j['realized_pnl_inr']),
        notionalUsdt: _d(j['notional_usdt']) ?? 0,
        notionalInr: _d(j['notional_inr']),
        feesUsdt: _d(j['fees_usdt']),
        lastError: '${j['last_error'] ?? ''}',
        conversionPrice: _d(j['conversion_price']) ?? 0,
      );
}

class CoinDCXPositions {
  const CoinDCXPositions({required this.readable, required this.positions});
  final bool readable;
  final List<CoinDCXPosition> positions;

  factory CoinDCXPositions.fromJson(Map<String, dynamic> j) => CoinDCXPositions(
        readable: j['readable'] == true,
        positions: [
          for (final p in (j['positions'] as List? ?? const []))
            if (p is Map) CoinDCXPosition.fromJson(p.cast<String, dynamic>()),
        ],
      );
}
