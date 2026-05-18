/// Server-side execution opt-in (engine PR-2 + roadmap PR-10).
///
/// User flow:
///   1. Paste Binance API key + secret.
///   2. Tap "Connect for server-side trading."
///   3. Engine validates against Binance (withdraw=off, futures=on,
///      IP whitelist set to engine VPS IP).  On success, engine
///      encrypts the secret with Cloud KMS + stores in Firestore.
///      Plaintext secret never leaves the engine signing service.
///   4. On validation failure, engine returns a typed error code
///      (WITHDRAW_ENABLED / FUTURES_DISABLED / IP_RESTRICT_DISABLED
///      / IP_NOT_WHITELISTED / KEY_INVALID / BINANCE_UNREACHABLE)
///      with a human-readable detail message.  This page renders
///      the detail + (for IP errors) the engine VPS IP with a
///      one-tap copy-to-clipboard so the user can paste it into
///      Binance's API Management page.
///
/// Doctrine reminder (OWNER_BRIEF §3.9 + B18):
///   * Non-custodial of funds.
///   * Custodial of trade-authorisation keys only.
///   * Withdraw permission MUST be disabled on the connected key.
///   * No staged beta — production-default blast-radius caps apply
///     (see #431).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/app_config.dart';
import '../../../data/repository.dart';
import '../../../data/server_side_execution_models.dart';
import '../../../shared/tokens.dart';

class ServerSideExecutionPage extends StatefulWidget {
  const ServerSideExecutionPage({super.key});

  @override
  State<ServerSideExecutionPage> createState() =>
      _ServerSideExecutionPageState();
}

class _ServerSideExecutionPageState extends State<ServerSideExecutionPage> {
  final _apiKeyCtrl = TextEditingController();
  final _apiSecretCtrl = TextEditingController();
  bool _submitting = false;
  BinanceConnectSuccess? _success;
  BinanceConnectError? _error;

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _apiSecretCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_submitting) return;
    final apiKey = _apiKeyCtrl.text.trim();
    final apiSecret = _apiSecretCtrl.text.trim();
    if (apiKey.length < 8 || apiSecret.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paste both API key and secret to continue.'),
          backgroundColor: LuminColors.warn,
        ),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _success = null;
      _error = null;
    });
    final repo = AppConfigScope.of(context).repo;
    try {
      final result = await repo.connectBinanceServerSide(
        apiKey: apiKey,
        apiSecret: apiSecret,
      );
      if (!mounted) return;
      // Wipe the local controllers — plaintext secret should not
      // linger in the text field after successful connect.
      _apiKeyCtrl.clear();
      _apiSecretCtrl.clear();
      setState(() => _success = result);
    } on BinanceConnectError catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = BinanceConnectError(
            code: 'UNKNOWN',
            detail: 'Unexpected error: $e',
          ));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _copyEngineIp() async {
    final ip = _error?.engineVpsIp;
    if (ip == null) return;
    await Clipboard.setData(ClipboardData(text: ip));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Engine IP $ip copied to clipboard'),
        backgroundColor: LuminColors.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LuminColors.bgDeep,
      appBar: AppBar(
        title: const Text('Server-side auto-trade'),
        backgroundColor: LuminColors.bgDeep,
      ),
      body: ListView(
        padding: const EdgeInsets.all(LuminSpacing.lg),
        children: [
          _doctrineCard(),
          const SizedBox(height: LuminSpacing.lg),
          _connectForm(),
          if (_error != null) ...[
            const SizedBox(height: LuminSpacing.lg),
            _errorCard(_error!),
          ],
          if (_success != null) ...[
            const SizedBox(height: LuminSpacing.lg),
            _successCard(_success!),
          ],
        ],
      ),
    );
  }

  Widget _doctrineCard() => Container(
        padding: const EdgeInsets.all(LuminSpacing.md),
        decoration: BoxDecoration(
          color: LuminColors.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: LuminColors.warn, width: 1),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Read this before connecting',
              style: TextStyle(
                color: LuminColors.warn,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            SizedBox(height: LuminSpacing.sm),
            Text(
              '• Withdraw permission must be DISABLED on your Binance key.\n'
              '• IP whitelist must include Lumin\'s engine IP (shown on '
              'validation failure with one-tap copy).\n'
              '• Lumin never sees your funds — only signs trade orders '
              'within configured limits (default \$500 max position, '
              '5 orders/min, signal-channel symbols only).\n'
              '• You can disconnect at any time from Settings.',
              style: TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      );

  Widget _connectForm() => Container(
        padding: const EdgeInsets.all(LuminSpacing.md),
        decoration: BoxDecoration(
          color: LuminColors.bgCard,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Connect Binance Futures API key',
              style: TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: LuminSpacing.md),
            TextField(
              controller: _apiKeyCtrl,
              decoration: const InputDecoration(
                labelText: 'API key',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(color: LuminColors.textPrimary),
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: LuminSpacing.sm),
            TextField(
              controller: _apiSecretCtrl,
              decoration: const InputDecoration(
                labelText: 'API secret',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(color: LuminColors.textPrimary),
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: LuminSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _connect,
                child: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Connect for server-side trading'),
              ),
            ),
          ],
        ),
      );

  Widget _errorCard(BinanceConnectError error) => Container(
        padding: const EdgeInsets.all(LuminSpacing.md),
        decoration: BoxDecoration(
          color: LuminColors.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: LuminColors.loss, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: LuminColors.loss,
                  size: 18,
                ),
                const SizedBox(width: LuminSpacing.sm),
                Expanded(
                  child: Text(
                    _errorTitle(error.code),
                    style: const TextStyle(
                      color: LuminColors.loss,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.sm),
            Text(
              error.detail,
              style: const TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            if (error.engineVpsIp != null) ...[
              const SizedBox(height: LuminSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: LuminSpacing.sm,
                        vertical: LuminSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: LuminColors.bgDeep,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        error.engineVpsIp!,
                        style: const TextStyle(
                          color: LuminColors.textPrimary,
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: LuminSpacing.sm),
                  TextButton.icon(
                    onPressed: _copyEngineIp,
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy'),
                  ),
                ],
              ),
            ],
          ],
        ),
      );

  Widget _successCard(BinanceConnectSuccess success) => Container(
        padding: const EdgeInsets.all(LuminSpacing.md),
        decoration: BoxDecoration(
          color: LuminColors.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: LuminColors.success, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: LuminColors.success,
                  size: 20,
                ),
                const SizedBox(width: LuminSpacing.sm),
                const Text(
                  'Connected',
                  style: TextStyle(
                    color: LuminColors.success,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.sm),
            Text(
              'Key ${success.keyPublicIdFirst8}… stored encrypted '
              'engine-side.  Validation passed:',
              style: const TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: LuminSpacing.sm),
            _checkRow('Withdraw disabled', success.withdrawDisabledOk),
            _checkRow('Futures enabled', success.futuresEnabledOk),
            _checkRow('IP whitelist OK', success.ipWhitelistOk),
          ],
        ),
      );

  Widget _checkRow(String label, bool ok) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(
              ok ? Icons.check : Icons.close,
              color: ok ? LuminColors.success : LuminColors.loss,
              size: 14,
            ),
            const SizedBox(width: LuminSpacing.sm),
            Text(
              label,
              style: const TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );

  String _errorTitle(String code) {
    switch (code) {
      case 'WITHDRAW_ENABLED':
        return 'Withdraw permission must be disabled';
      case 'FUTURES_DISABLED':
        return 'Futures permission required';
      case 'IP_RESTRICT_DISABLED':
        return 'IP whitelist required';
      case 'IP_NOT_WHITELISTED':
        return 'Add Lumin\'s engine IP to whitelist';
      case 'KEY_INVALID':
        return 'API key invalid';
      case 'BINANCE_UNREACHABLE':
        return 'Could not reach Binance';
      default:
        return 'Connection failed';
    }
  }
}
