/// API keys + backend connection.
///
/// v0.0.5 expansion: in addition to Binance API keys, this page now controls
/// the data source the entire app talks to.  Toggle Mock ↔ Live, set the
/// FastAPI base URL, paste the bearer token issued by `setup-vps-api.sh`,
/// and tap "Test connection" to verify before saving.
import 'package:flutter/material.dart';

import '../../../data/api_client.dart';
import '../../../data/app_config.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/lumin_card.dart';
import '../../../shared/widgets/preview_badge.dart';

class ApiKeysSettingsPage extends StatefulWidget {
  const ApiKeysSettingsPage({super.key});

  @override
  State<ApiKeysSettingsPage> createState() => _ApiKeysSettingsPageState();
}

class _ApiKeysSettingsPageState extends State<ApiKeysSettingsPage> {
  // Binance creds — session-only until backend wires up encrypted storage.
  final _binanceKeyCtl = TextEditingController();
  final _binanceSecretCtl = TextEditingController();
  bool _showBinanceSecret = false;
  bool _testnet = false;

  // Lumin backend.
  late final TextEditingController _baseUrlCtl;
  late final TextEditingController _tokenCtl;
  bool _showToken = false;
  bool _liveMode = false;

  String? _testResult;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final cfg = AppConfigScope.of(context).config;
    _baseUrlCtl = TextEditingController(text: cfg.apiBaseUrl);
    _tokenCtl = TextEditingController(text: cfg.apiAuthToken);
    _liveMode = cfg.dataSource == DataSource.live;
  }

  @override
  void dispose() {
    _binanceKeyCtl.dispose();
    _binanceSecretCtl.dispose();
    _baseUrlCtl.dispose();
    _tokenCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('API keys'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _save,
            tooltip: 'Save',
          ),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          const PreviewBadge(),
          _backendCard(),
          const SizedBox(height: LuminSpacing.md),
          _testCard(),
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

  // ------------------------------------------------------------------
  // Lumin backend (data source toggle + base URL + token)
  // ------------------------------------------------------------------

  Widget _backendCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'LUMIN BACKEND',
              style: TextStyle(
                color: LuminColors.textMuted,
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: LuminSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _liveMode ? 'Live engine' : 'Mock data',
                        style: const TextStyle(
                          color: LuminColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _liveMode
                            ? 'Calls FastAPI backend at the URL below'
                            : 'Reads built-in sample data — works offline',
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
                  value: _liveMode,
                  activeColor: LuminColors.accent,
                  onChanged: (v) => setState(() => _liveMode = v),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.md),
            _label('Base URL'),
            TextField(
              controller: _baseUrlCtl,
              enabled: _liveMode,
              autocorrect: false,
              keyboardType: TextInputType.url,
              style: const TextStyle(color: LuminColors.textPrimary, fontSize: 13),
              decoration: _inputDecoration('https://api.luminapp.org'),
            ),
            const SizedBox(height: LuminSpacing.md),
            _label('Bearer token'),
            TextField(
              controller: _tokenCtl,
              enabled: _liveMode,
              obscureText: !_showToken,
              autocorrect: false,
              style: const TextStyle(color: LuminColors.textPrimary, fontSize: 13),
              decoration: _inputDecoration('Paste token from setup-vps-api.sh').copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _showToken ? Icons.visibility_off : Icons.visibility,
                    color: LuminColors.textMuted,
                    size: 18,
                  ),
                  onPressed: () => setState(() => _showToken = !_showToken),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _testCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(LuminRadii.md),
                child: InkWell(
                  borderRadius: BorderRadius.circular(LuminRadii.md),
                  onTap: _testing || !_liveMode ? null : _runTest,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: LuminSpacing.md),
                    decoration: BoxDecoration(
                      color: _liveMode
                          ? LuminColors.accent.withOpacity(0.12)
                          : LuminColors.bgElevated,
                      borderRadius: BorderRadius.circular(LuminRadii.md),
                      border: Border.all(
                        color: _liveMode
                            ? LuminColors.accent.withOpacity(0.30)
                            : LuminColors.cardBorder,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: LuminColors.accent,
                            ),
                          )
                        : Text(
                            _liveMode ? 'Test connection' : 'Enable Live to test',
                            style: TextStyle(
                              color: _liveMode
                                  ? LuminColors.accent
                                  : LuminColors.textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ),
            ),
            if (_testResult != null) ...[
              const SizedBox(height: LuminSpacing.md),
              Text(
                _testResult!,
                style: TextStyle(
                  color: _testResult!.startsWith('OK')
                      ? LuminColors.success
                      : LuminColors.loss,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _runTest() async {
    final url = _baseUrlCtl.text.trim();
    final token = _tokenCtl.text.trim();
    if (url.isEmpty) {
      setState(() => _testResult = 'ERR: enter a base URL');
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final client = LuminApiClient(baseUrl: url, authToken: token);
    try {
      // Health is unauthenticated — confirms basic reachability.
      final health = await client.get('/api/health');
      if (health is! Map || health['ok'] != true) {
        if (!mounted) return;
        setState(() {
          _testing = false;
          _testResult = 'ERR: unexpected /api/health response';
        });
        return;
      }
      // Pulse requires auth — confirms the bearer token works.
      if (token.isNotEmpty) {
        await client.get('/api/pulse');
      }
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testResult = token.isEmpty
            ? 'OK — health 200 (no auth tested; paste a token to verify)'
            : 'OK — health 200, pulse 200 (auth works)';
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testResult = 'ERR: ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testResult = 'ERR: $e';
      });
    }
  }

  // ------------------------------------------------------------------
  // Binance (unchanged from v0.0.4 — session-only)
  // ------------------------------------------------------------------

  Widget _binanceCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'BINANCE FUTURES',
              style: TextStyle(
                color: LuminColors.textMuted,
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: LuminSpacing.md),
            _label('API key'),
            TextField(
              controller: _binanceKeyCtl,
              autocorrect: false,
              style: const TextStyle(color: LuminColors.textPrimary, fontSize: 13),
              decoration: _inputDecoration('Paste API key'),
            ),
            const SizedBox(height: LuminSpacing.md),
            _label('API secret'),
            TextField(
              controller: _binanceSecretCtl,
              obscureText: !_showBinanceSecret,
              autocorrect: false,
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
            ),
          ],
        ),
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
              onChanged: (v) => setState(() => _testnet = v),
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
      apiAuthToken: _tokenCtl.text.trim(),
    );
    await scope.update(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _liveMode
              ? 'Saved — app now reads from $_baseUrlText'
              : 'Saved — app now uses mock data',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String get _baseUrlText {
    final v = _baseUrlCtl.text.trim();
    return v.isEmpty ? 'mock' : v;
  }
}
