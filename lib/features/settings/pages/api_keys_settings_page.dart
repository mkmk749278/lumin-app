/// Binance API — per-user encrypted key storage.
///
/// Lumin is consumer-facing now: this page is purely about connecting
/// the user's Binance Futures account.  Engine-side concerns (Lumin
/// backend URL, mock/live toggle, /api/health reachability, sign-out
/// routing) moved to the ops app.  Sign-out lives at Settings →
/// Sign out as its own entry.
///
/// Keys are validated against ``GET /fapi/v2/account`` before save.
/// Phase 3b's OrderExecutor + AutoTradeWatcher use these stored
/// credentials to fire orders directly from the app on signal
/// arrival; the engine never holds user keys.
import 'package:flutter/material.dart';

import '../../../data/app_config.dart';
import '../../../data/binance_client.dart';
import '../../../data/binance_keys_service.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/lumin_card.dart';

class ApiKeysSettingsPage extends StatefulWidget {
  const ApiKeysSettingsPage({super.key});

  @override
  State<ApiKeysSettingsPage> createState() => _ApiKeysSettingsPageState();
}

class _ApiKeysSettingsPageState extends State<ApiKeysSettingsPage> {
  // Binance — encrypted-at-rest via flutter_secure_storage, namespaced
  // by current user_id so a sign-out → sign-in-as-different-user
  // doesn't leak the prior user's keys.
  final _binanceKeyCtl = TextEditingController();
  final _binanceSecretCtl = TextEditingController();
  bool _showBinanceSecret = false;
  bool _testnet = false;
  final _keysService = BinanceKeysService();
  BinanceKeys? _savedKeys;
  bool _binanceLoaded = false;
  String? _binanceTestResult;
  bool _binanceTestOk = false;
  bool _binanceTesting = false;
  bool _binanceSaving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_binanceLoaded) {
      _loadBinanceKeys();
    }
  }

  Future<void> _loadBinanceKeys() async {
    final uid = AppConfigScope.of(context).userId;
    if (uid == null) {
      // Mock mode or anonymous JWT — no per-user storage namespace.
      // Show the empty form; user can still type values for inspection
      // but Save will surface a clear error.
      setState(() {
        _binanceLoaded = true;
      });
      return;
    }
    final keys = await _keysService.load(uid);
    if (!mounted) return;
    setState(() {
      _savedKeys = keys;
      _binanceLoaded = true;
      if (keys != null) {
        _binanceKeyCtl.text = keys.apiKey;
        _binanceSecretCtl.text = keys.apiSecret;
        _testnet = keys.testnet;
      }
    });
  }

  @override
  void dispose() {
    _binanceKeyCtl.dispose();
    _binanceSecretCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Binance')),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          const SizedBox(height: LuminSpacing.md),
          _binanceCard(),
          const SizedBox(height: LuminSpacing.md),
          _envCard(),
          const SizedBox(height: LuminSpacing.md),
          _safetyCard(),
          const SizedBox(height: LuminSpacing.xl),
        ],
      ),
    );
  }


  Widget _binanceCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'BINANCE FUTURES',
                    style: TextStyle(
                      color: LuminColors.textMuted,
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _binanceStatusBadge(),
              ],
            ),
            const SizedBox(height: LuminSpacing.md),
            _label('API key'),
            TextField(
              controller: _binanceKeyCtl,
              autocorrect: false,
              enabled: !_binanceTesting && !_binanceSaving,
              style: const TextStyle(color: LuminColors.textPrimary, fontSize: 13),
              decoration: _inputDecoration('Paste API key'),
              onChanged: (_) => _onBinanceFieldChanged(),
            ),
            const SizedBox(height: LuminSpacing.md),
            _label('API secret'),
            TextField(
              controller: _binanceSecretCtl,
              obscureText: !_showBinanceSecret,
              autocorrect: false,
              enabled: !_binanceTesting && !_binanceSaving,
              style: const TextStyle(color: LuminColors.textPrimary, fontSize: 13),
              decoration: _inputDecoration('Paste API secret').copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _showBinanceSecret ? Icons.visibility_off : Icons.visibility,
                    color: LuminColors.textMuted,
                    size: 18,
                  ),
                  onPressed: () =>
                      setState(() => _showBinanceSecret = !_showBinanceSecret),
                ),
              ),
              onChanged: (_) => _onBinanceFieldChanged(),
            ),
            const SizedBox(height: LuminSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _actionButton(
                    label: _binanceTesting ? 'Testing…' : 'Test connection',
                    icon: Icons.bolt_outlined,
                    primary: false,
                    busy: _binanceTesting,
                    onTap: _binanceTesting ||
                            _binanceSaving ||
                            _binanceKeyCtl.text.trim().isEmpty ||
                            _binanceSecretCtl.text.trim().isEmpty
                        ? null
                        : _testBinance,
                  ),
                ),
                const SizedBox(width: LuminSpacing.sm),
                Expanded(
                  child: _actionButton(
                    label: _binanceSaving ? 'Saving…' : 'Save',
                    icon: Icons.check,
                    primary: true,
                    busy: _binanceSaving,
                    // Require a successful Test before Save — saving an
                    // un-validated key/secret pair is an easy footgun.
                    onTap: _binanceTesting ||
                            _binanceSaving ||
                            !_binanceTestOk
                        ? null
                        : _saveBinance,
                  ),
                ),
              ],
            ),
            if (_savedKeys != null) ...[
              const SizedBox(height: LuminSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _binanceTesting || _binanceSaving
                      ? null
                      : _disconnectBinance,
                  icon: const Icon(
                    Icons.link_off,
                    color: LuminColors.loss,
                    size: 16,
                  ),
                  label: const Text(
                    'Disconnect',
                    style: TextStyle(
                      color: LuminColors.loss,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
            if (_binanceTestResult != null) ...[
              const SizedBox(height: LuminSpacing.sm),
              Text(
                _binanceTestResult!,
                style: TextStyle(
                  color: _binanceTestOk
                      ? LuminColors.success
                      : LuminColors.loss,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _binanceStatusBadge() {
    final keys = _savedKeys;
    final connected = keys != null && keys.isValid;
    final color = connected ? LuminColors.success : LuminColors.textMuted;
    final label = connected
        ? (keys.testnet ? 'TESTNET' : 'CONNECTED')
        : 'NOT CONNECTED';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(LuminRadii.pill),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required bool primary,
    required bool busy,
    required VoidCallback? onTap,
  }) {
    final disabled = onTap == null;
    final fg = primary ? LuminColors.bgDeep : LuminColors.accent;
    final bg = primary
        ? (disabled ? LuminColors.textMuted : LuminColors.accent)
        : (disabled
            ? LuminColors.bgElevated
            : LuminColors.accent.withOpacity(0.12));
    final border = primary
        ? Colors.transparent
        : (disabled
            ? LuminColors.cardBorder
            : LuminColors.accent.withOpacity(0.30));
    final fgResolved = disabled
        ? (primary ? LuminColors.bgDeep : LuminColors.textMuted)
        : fg;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(LuminRadii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(LuminRadii.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: LuminSpacing.md),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(LuminRadii.md),
            border: Border.all(color: border),
          ),
          child: Center(
            child: busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: fgResolved,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: fgResolved, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          color: fgResolved,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  void _onBinanceFieldChanged() {
    // Edit invalidates the prior Test result — Save must re-test.
    if (_binanceTestOk || _binanceTestResult != null) {
      setState(() {
        _binanceTestOk = false;
        _binanceTestResult = null;
      });
    }
  }

  Future<void> _testBinance() async {
    final key = _binanceKeyCtl.text.trim();
    final secret = _binanceSecretCtl.text.trim();
    if (key.isEmpty || secret.isEmpty) {
      setState(() {
        _binanceTestOk = false;
        _binanceTestResult = 'Enter both API key and secret first.';
      });
      return;
    }
    setState(() {
      _binanceTesting = true;
      _binanceTestResult = null;
    });
    final client = BinanceClient(
      apiKey: key,
      apiSecret: secret,
      testnet: _testnet,
    );
    try {
      // Sanity-check clock skew before the signed call.  -1021 from the
      // signed endpoint would be confusing ("are my keys wrong?"); a
      // clear "device clock off by Xs" here is much better UX.
      final serverTime = await client.getServerTime();
      final localTime = DateTime.now().millisecondsSinceEpoch;
      final skewMs = (localTime - serverTime).abs();
      if (skewMs > 5000) {
        setState(() {
          _binanceTesting = false;
          _binanceTestOk = false;
          _binanceTestResult =
              'Device clock off by ${(skewMs / 1000).toStringAsFixed(1)}s. '
              'Sync system time and retry.';
        });
        return;
      }
      final account = await client.getAccount();
      if (!mounted) return;
      setState(() {
        _binanceTesting = false;
        _binanceTestOk = true;
        _binanceTestResult =
            'OK — ${_testnet ? "testnet" : "mainnet"}, balance \$${account.totalWalletBalance.toStringAsFixed(2)}, '
            'fee tier ${account.feeTier}, '
            '${account.openPositionCount} open position(s)'
            '${account.canTrade ? "" : ". WARNING: trading disabled on this key"}.';
      });
    } on BinanceError catch (e) {
      if (!mounted) return;
      setState(() {
        _binanceTesting = false;
        _binanceTestOk = false;
        _binanceTestResult = _friendlyBinanceError(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _binanceTesting = false;
        _binanceTestOk = false;
        _binanceTestResult = 'ERR: $e';
      });
    } finally {
      client.dispose();
    }
  }

  String _friendlyBinanceError(BinanceError e) {
    // A few common codes get a clearer rephrase; fall back to the raw
    // message Binance returned otherwise.
    switch (e.code) {
      case -2014:
        return 'API key format invalid — double-check the key string.';
      case -2015:
        return 'Key rejected — check IP whitelist + Futures permission.';
      case -1022:
        return 'Signature failed — secret is wrong (or has trailing spaces).';
      case -1021:
        return 'Timestamp out of recvWindow — sync your device clock.';
      default:
        return 'ERR: ${e.message} (code ${e.code ?? "?"}, HTTP ${e.statusCode})';
    }
  }

  Future<void> _saveBinance() async {
    final uid = AppConfigScope.of(context).userId;
    if (uid == null) {
      setState(() {
        _binanceTestResult =
            'Sign in with phone first — keys are stored per user.';
        _binanceTestOk = false;
      });
      return;
    }
    setState(() => _binanceSaving = true);
    try {
      final saved = await _keysService.save(
        uid,
        BinanceKeys(
          apiKey: _binanceKeyCtl.text.trim(),
          apiSecret: _binanceSecretCtl.text.trim(),
          testnet: _testnet,
          // markVerified after Test — but if user pressed Save right
          // after a successful Test, stamp it now to capture the
          // verified state in the persisted blob.
          lastVerifiedAt: _binanceTestOk ? DateTime.now().toUtc() : null,
        ),
      );
      if (!mounted) return;
      setState(() {
        _savedKeys = saved;
        _binanceSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Binance keys saved'
            '${_testnet ? " (testnet)" : ""}.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _binanceSaving = false;
        _binanceTestResult = 'Save failed: $e';
        _binanceTestOk = false;
      });
    }
  }

  Future<void> _disconnectBinance() async {
    final uid = AppConfigScope.of(context).userId;
    if (uid == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LuminColors.bgCard,
        title: const Text(
          'Disconnect Binance?',
          style: TextStyle(color: LuminColors.textPrimary),
        ),
        content: const Text(
          'Your API key and secret will be wiped from this device.  '
          'Auto-trade will stop until you reconnect.',
          style: TextStyle(color: LuminColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: LuminColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Disconnect',
              style: TextStyle(
                color: LuminColors.loss,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _keysService.clear(uid);
    if (!mounted) return;
    setState(() {
      _savedKeys = null;
      _binanceKeyCtl.clear();
      _binanceSecretCtl.clear();
      _binanceTestOk = false;
      _binanceTestResult = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Disconnected from Binance.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _envCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Row(
          children: [
            const Icon(Icons.cloud_outlined, color: LuminColors.accent, size: 18),
            const SizedBox(width: LuminSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _testnet ? 'Testnet' : 'Mainnet',
                    style: const TextStyle(
                      color: LuminColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _testnet
                        ? 'fapi-testnet.binance.com — fake balance, real APIs'
                        : 'fapi.binance.com — real money, real fills',
                    style: const TextStyle(
                      color: LuminColors.textSecondary,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _testnet,
              activeColor: LuminColors.warn,
              onChanged: _binanceTesting || _binanceSaving
                  ? null
                  : (v) {
                      setState(() {
                        _testnet = v;
                        // Switching env invalidates any prior Test result.
                        _binanceTestOk = false;
                        _binanceTestResult = null;
                      });
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _safetyCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(LuminSpacing.md),
        decoration: BoxDecoration(
          color: LuminColors.warn.withOpacity(0.08),
          borderRadius: BorderRadius.circular(LuminRadii.md),
          border: Border.all(color: LuminColors.warn.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Row(
              children: [
                Icon(Icons.lock_outline, color: LuminColors.warn, size: 16),
                SizedBox(width: LuminSpacing.sm),
                Text(
                  'Required permissions',
                  style: TextStyle(
                    color: LuminColors.warn,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            SizedBox(height: LuminSpacing.sm),
            Text(
              '• Enable Reading\n'
              '• Enable Futures\n'
              '• DO NOT enable Withdrawals\n'
              '• Restrict to your IP if possible',
              style: TextStyle(
                color: LuminColors.warn,
                fontSize: 11,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LuminSpacing.xs),
      child: Text(
        text,
        style: const TextStyle(
          color: LuminColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: LuminColors.textMuted,
        fontSize: 13,
      ),
      filled: true,
      fillColor: LuminColors.bgElevated,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: LuminSpacing.md,
        vertical: LuminSpacing.sm,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LuminRadii.sm),
        borderSide: const BorderSide(color: LuminColors.cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LuminRadii.sm),
        borderSide: const BorderSide(color: LuminColors.accent),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LuminRadii.sm),
        borderSide: const BorderSide(color: LuminColors.cardBorder),
      ),
    );
  }

  Future<void> _save() async {
    final scope = AppConfigScope.of(context);
    final next = scope.config.copyWith(
      dataSource: _liveMode ? DataSource.live : DataSource.mock,
      apiBaseUrl: _baseUrlCtl.text.trim(),
    );
    await scope.update(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saved'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
