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
import '../../launch/region_gate.dart';
import 'tos_acceptance_page.dart';

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
  bool _disconnecting = false;
  BinanceConnectSuccess? _success;
  BinanceConnectError? _error;
  // ToS gate (PR-13).  ``null`` while we're checking; ``true`` once
  // accepted; ``false`` if the user needs to accept before the
  // connect form is shown.
  //
  // The TOTP 2FA gate from yesterday's PR-12 was DROPPED in this
  // PR — Firebase's MFA enrollment is fundamentally incompatible
  // with phone-OTP as the first factor (per B13).  See OWNER_BRIEF
  // B18 ship notes for the trade-off + the Firebase-side
  // ``requires-recent-login`` substitute that covers the same
  // surface (sensitive ops require fresh SMS OTP within 5 min).
  bool? _tosAccepted;

  // Existing-connection state (2026-05-19).  ``null`` while the on-mount
  // ``GET /api/binance/connect/status`` fetch is in flight; non-null
  // afterwards.  When ``connected == true`` the page renders the
  // connected-state card (truncated key id + connect timestamp +
  // Disconnect / Replace actions) instead of the connect form.
  BinanceConnectStatus? _existing;
  bool _replacing = false;

  // Engine VPS IP the user must whitelist on their Binance key
  // (2026-07-16).  Fetched up front from ``GET /api/binance/connect/info``
  // and shown in the doctrine card with one-tap copy, so the user can
  // whitelist it BEFORE connecting rather than only discovering it on a
  // failed connect.  ``null`` while the fetch is in flight, or if the
  // engine hasn't been configured with an IP — in which case the
  // doctrine card falls back to generic whitelist wording.
  String? _engineVpsIp;

  @override
  void initState() {
    super.initState();
    _refreshTosStatus();
    _refreshConnectStatus();
    _refreshConnectInfo();
  }

  Future<void> _refreshTosStatus() async {
    final accepted = await isTosCurrentlyAccepted();
    if (!mounted) return;
    setState(() => _tosAccepted = accepted);
  }

  Future<void> _refreshConnectStatus() async {
    // Soft failure on this fetch — if the engine is unreachable or the
    // endpoint 5xx's, fall through to the connect form rather than
    // blocking the page.  The connect flow itself surfaces real errors.
    try {
      final status =
          await AppConfigScope.of(context).repo.fetchBinanceConnectStatus();
      if (!mounted) return;
      setState(() => _existing = status);
    } catch (_) {
      if (!mounted) return;
      setState(() => _existing = BinanceConnectStatus.notConnected);
    }
  }

  Future<void> _refreshConnectInfo() async {
    // Soft failure — the whitelist IP is a nice-to-have hint shown up
    // front.  If the engine is unreachable or hasn't been configured
    // with an IP, leave ``_engineVpsIp`` null and fall back to the
    // generic whitelist wording; never block the page on this fetch.
    try {
      final info =
          await AppConfigScope.of(context).repo.fetchBinanceConnectInfo();
      if (!mounted) return;
      setState(() => _engineVpsIp = info.engineVpsIp);
    } catch (_) {
      if (!mounted) return;
      setState(() => _engineVpsIp = null);
    }
  }

  Future<void> _goToTos() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const TosAcceptancePage()),
    );
    await _refreshTosStatus();
  }

  Future<void> _disconnect() async {
    if (_disconnecting) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LuminColors.bgCard,
        title: const Text(
          'Disconnect Binance?',
          style: TextStyle(color: LuminColors.textPrimary),
        ),
        content: const Text(
          'This deletes the encrypted key from Lumin\'s engine.  Any '
          'open positions on Binance are NOT closed — close them on '
          'Binance directly before disconnecting if you want to flatten.',
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
    if (confirm != true) return;
    if (!mounted) return;
    setState(() => _disconnecting = true);
    try {
      await AppConfigScope.of(context).repo.disconnectBinanceServerSide();
      if (!mounted) return;
      setState(() {
        _existing = BinanceConnectStatus.notConnected;
        _success = null;
        _error = null;
        _replacing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Binance disconnected'),
          backgroundColor: LuminColors.success,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Disconnect failed: $e'),
          backgroundColor: LuminColors.loss,
        ),
      );
    } finally {
      if (mounted) setState(() => _disconnecting = false);
    }
  }

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
      setState(() {
        _success = result;
        _replacing = false;
      });
      // Re-fetch status so a subsequent revisit (or hot-reload of this
      // page in test) sees the connected-state card without a manual
      // pull-to-refresh.
      await _refreshConnectStatus();
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
        content: Text("Lumin's server IP $ip copied to clipboard"),
        backgroundColor: LuminColors.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _copyEngineVpsIp() async {
    final ip = _engineVpsIp;
    if (ip == null) return;
    await Clipboard.setData(ClipboardData(text: ip));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Lumin's server IP $ip copied to clipboard"),
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
      // Region gate (Play Store launch A6, 2026-05-20).  Replaces
      // the entire connect surface with a "not available in your
      // region" card when CF-IPCountry reports the user is in a
      // blocked jurisdiction.  Soft-fail open — render child if
      // the region fetch is in-flight, errors, or returns unknown.
      body: RegionGate(
        child: ListView(
        padding: const EdgeInsets.all(LuminSpacing.lg),
        children: [
          _doctrineCard(),
          const SizedBox(height: LuminSpacing.lg),
          // ToS gate (PR-13) — must be satisfied before the connect
          // form renders.  The 2FA gate from PR-12 was DROPPED in
          // this PR because Firebase MFA enrollment is fundamentally
          // incompatible with phone-OTP as the first factor — see
          // OWNER_BRIEF B18 for the v1 trade-off + the
          // ``requires-recent-login`` substitute that covers the
          // same surface (sensitive ops require fresh SMS OTP).
          //
          // Existing-connection gate (2026-05-19) — when a Firestore
          // key blob already exists for this Firebase uid we render
          // the connected-state card.  The user can tap Replace to
          // surface the connect form again (existing blob is over-
          // written cleanly by ``put_key_blob``) or Disconnect to
          // hard-delete it.
          if (_tosAccepted == null || _existing == null)
            const Center(child: CircularProgressIndicator())
          else if (_tosAccepted == false)
            _tosGateCard()
          else if (_existing!.connected && !_replacing && _success == null)
            _connectedCard(_existing!)
          else
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
      ),
    );
  }

  Widget _tosGateCard() => Container(
        padding: const EdgeInsets.all(LuminSpacing.md),
        decoration: BoxDecoration(
          color: LuminColors.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: LuminColors.warn, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.gavel_outlined,
                    color: LuminColors.warn, size: 20),
                SizedBox(width: LuminSpacing.sm),
                Text(
                  'Accept terms to continue',
                  style: TextStyle(
                    color: LuminColors.warn,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.sm),
            const Text(
              'Before connecting Binance for server-side trading, '
              'please read and accept the terms of service.  They '
              'cover the non-custodial nature of the service, the '
              'no-warranty posture, and the blast-radius limits '
              'that bound damage in any worst-case scenario.',
              style: TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: LuminSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _goToTos,
                icon: const Icon(Icons.description_outlined),
                label: const Text('Read terms'),
              ),
            ),
          ],
        ),
      );

  Widget _doctrineCard() {
    final hasIp = _engineVpsIp != null;
    return Container(
      padding: const EdgeInsets.all(LuminSpacing.md),
      decoration: BoxDecoration(
        color: LuminColors.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: LuminColors.warn, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Read this before connecting',
            style: TextStyle(
              color: LuminColors.warn,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: LuminSpacing.sm),
          Text(
            '• Withdraw permission must be DISABLED on your Binance key.\n'
            '• Your key\'s IP access list must include Lumin\'s server IP'
            '${hasIp ? ' (below — one-tap copy).' : ' (shown on '
                'validation failure with one-tap copy).'}\n'
            '• Lumin never sees your funds — only signs trade orders '
            'within configured limits (default \$500 max position, '
            '5 orders/min, signal-channel symbols only).\n'
            '• You can disconnect at any time from Settings.',
            style: const TextStyle(
              color: LuminColors.textPrimary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          if (hasIp) _engineIpWhitelistBlock(_engineVpsIp!),
        ],
      ),
    );
  }

  /// Up-front whitelist block: the engine VPS IP + a one-tap Copy so the
  /// user can add it to their Binance API-key whitelist BEFORE connecting.
  /// Mirrors the on-failure IP affordance in ``_errorCard`` so the two
  /// paths look and behave identically.
  Widget _engineIpWhitelistBlock(String ip) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: LuminSpacing.md),
          const Text(
            'Add Lumin\'s server IP to your Binance key\'s IP access list:',
            style: TextStyle(
              color: LuminColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: LuminSpacing.sm),
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
                    ip,
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
                onPressed: _copyEngineVpsIp,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.xs),
          const Text(
            'Adding this IP locks your key so it only works from Lumin\'s '
            'server — an extra layer of protection for your account.',
            style: TextStyle(
              color: LuminColors.textSecondary,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      );

  Widget _connectedCard(BinanceConnectStatus status) {
    final connectedAt = status.connectedAt;
    final keyId = status.keyPublicIdFirst8 ?? '????????';
    final since = connectedAt == null
        ? 'unknown date'
        : '${connectedAt.year.toString().padLeft(4, '0')}-'
            '${connectedAt.month.toString().padLeft(2, '0')}-'
            '${connectedAt.day.toString().padLeft(2, '0')}';
    return Container(
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
              const Icon(Icons.cloud_done, color: LuminColors.success, size: 18),
              const SizedBox(width: LuminSpacing.sm),
              const Expanded(
                child: Text(
                  'Binance connected',
                  style: TextStyle(
                    color: LuminColors.success,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.sm),
          Text(
            'Key: $keyId…\nConnected on $since',
            style: const TextStyle(
              color: LuminColors.textPrimary,
              fontSize: 12,
              height: 1.5,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: LuminSpacing.sm),
          Wrap(
            spacing: LuminSpacing.sm,
            runSpacing: LuminSpacing.xs,
            children: [
              _validationChip(
                ok: status.withdrawDisabledOk ?? false,
                label: 'Withdraw OFF',
              ),
              _validationChip(
                ok: status.ipWhitelistOk ?? false,
                label: 'IP access list',
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _disconnecting
                      ? null
                      : () => setState(() => _replacing = true),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Replace key'),
                ),
              ),
              const SizedBox(width: LuminSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _disconnecting ? null : _disconnect,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: LuminColors.loss,
                    side: const BorderSide(color: LuminColors.loss),
                  ),
                  icon: _disconnecting
                      ? const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link_off, size: 16),
                  label: const Text('Disconnect'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _validationChip({required bool ok, required String label}) =>
      Container(
        padding: const EdgeInsets.symmetric(
          horizontal: LuminSpacing.sm,
          vertical: LuminSpacing.xs,
        ),
        decoration: BoxDecoration(
          color:
              (ok ? LuminColors.success : LuminColors.warn).withOpacity(0.12),
          borderRadius: BorderRadius.circular(LuminRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ok ? Icons.check_circle_outline : Icons.warning_amber,
              color: ok ? LuminColors.success : LuminColors.warn,
              size: 12,
            ),
            const SizedBox(width: LuminSpacing.xs),
            Text(
              label,
              style: TextStyle(
                color: ok ? LuminColors.success : LuminColors.warn,
                fontSize: 10,
                fontWeight: FontWeight.w700,
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
            _checkRow('IP access list OK', success.ipWhitelistOk),
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
        return 'IP restriction required';
      case 'IP_NOT_WHITELISTED':
        return 'Add Lumin\'s server IP to the key\'s IP access list';
      case 'KEY_INVALID':
        return 'API key invalid';
      case 'BINANCE_UNREACHABLE':
        return 'Could not reach Binance';
      default:
        return 'Connection failed';
    }
  }
}
