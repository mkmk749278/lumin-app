/// ToS click-through opt-in (PR-13 of the 14-PR roadmap + #431).
///
/// Displayed BEFORE the server-side execution connect form for any
/// user who hasn't accepted the current :data:`latestTosVersion`.
/// The text below is the non-custodial / no-warranty / bounded-
/// blast-radius doctrine spelled out per OWNER_BRIEF B18.
///
/// Acceptance recorded via :class:`TosService` (per-device
/// SharedPreferences in v1 — a follow-up syncs to Firestore for
/// cross-device + audit metadata).
library;

import 'package:flutter/material.dart';

import '../../../data/tos_service.dart';
import '../../../shared/tokens.dart';


class TosAcceptancePage extends StatefulWidget {
  const TosAcceptancePage({super.key});

  @override
  State<TosAcceptancePage> createState() => _TosAcceptancePageState();
}


class _TosAcceptancePageState extends State<TosAcceptancePage> {
  final _service = TosService();
  bool _checked = false;
  bool _saving = false;
  String? _error;

  Future<void> _accept() async {
    if (!_checked || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.recordAcceptance();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not record acceptance: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LuminColors.bgDeep,
      appBar: AppBar(
        title: const Text('Terms of service'),
        backgroundColor: LuminColors.bgDeep,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(LuminSpacing.lg),
              children: [
                _termsCard(),
                if (_error != null) ...[
                  const SizedBox(height: LuminSpacing.md),
                  _errorCard(_error!),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(LuminSpacing.lg),
            decoration: const BoxDecoration(
              color: LuminColors.bgCard,
              border: Border(
                top: BorderSide(color: LuminColors.bgDeep, width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  value: _checked,
                  onChanged: (v) => setState(() => _checked = v ?? false),
                  title: const Text(
                    'I have read and accept these terms.',
                    style: TextStyle(
                      color: LuminColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: LuminSpacing.sm),
                FilledButton(
                  onPressed: (_checked && !_saving) ? _accept : null,
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Accept and continue'),
                ),
                const SizedBox(height: LuminSpacing.sm),
                Text(
                  'Version $latestTosVersion',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: LuminColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _termsCard() => Container(
        padding: const EdgeInsets.all(LuminSpacing.md),
        decoration: BoxDecoration(
          color: LuminColors.bgCard,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Server-side auto-trade terms',
              style: TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: LuminSpacing.md),
            _Section(
              heading: '1. Non-custodial',
              body:
                  'Lumin does not hold or control your funds.  Your Binance '
                  'wallet remains under your sole ownership and control.  '
                  'Lumin signs trade orders on your behalf within the '
                  'limits described below — that is the only authority '
                  'you grant.',
            ),
            _Section(
              heading: '2. Key custody — encrypted, withdraw-disabled',
              body:
                  'When you connect a Binance API key, Lumin stores it '
                  'encrypted using a Google Cloud KMS master key that '
                  'Lumin operators cannot read.  Withdraw permission '
                  'must be DISABLED on the connected key.  We refuse '
                  'keys with withdraw enabled — no exceptions, no '
                  'admin override.',
            ),
            _Section(
              heading: '3. Bounded blast radius',
              body:
                  'Even in a worst-case breach of Lumin\'s infrastructure, '
                  'an attacker cannot withdraw your funds (withdraw is '
                  'disabled on the key).  They cannot trade from outside '
                  'Lumin\'s servers (the IP whitelist on your key only '
                  'permits Lumin\'s engine VPS).  They cannot trade '
                  'arbitrary symbols (symbol allowlist).  They cannot '
                  'exceed your configured position cap (default \$500).  '
                  'They cannot fire orders faster than 5/min, 30/hour.',
            ),
            _Section(
              heading: '4. No warranty / no insurance',
              body:
                  'This service is provided AS-IS, without warranty of '
                  'any kind.  Lumin is a personal project, not a '
                  'registered broker-dealer.  No insurance covers losses '
                  'caused by software bugs, our infrastructure being '
                  'compromised, exchange outages, your own configuration '
                  'errors, or market conditions.',
            ),
            _Section(
              heading: '5. You bear all execution risk',
              body:
                  'Including but not limited to: incorrect orders, missed '
                  'orders, slippage, exchange outages, Lumin service '
                  'going offline, network failures, and any other '
                  'circumstance that affects trade execution.',
            ),
            _Section(
              heading: '6. Geographic restriction',
              body:
                  'Server-side auto-trade is not available to users in '
                  'the United States.  By accepting these terms you '
                  'confirm that you are not a US person and are not '
                  'accessing the service from US territory.',
            ),
            _Section(
              heading: '7. Right to disconnect',
              body:
                  'You can disconnect your Binance key at any time from '
                  'Settings → Server-side auto-trade.  Disconnection '
                  'cancels any open orders Lumin has placed on your '
                  'behalf and stops all future order placement.',
            ),
            _Section(
              heading: '8. Service may be discontinued',
              body:
                  'Lumin may discontinue server-side auto-trade at any '
                  'time, with or without notice.  In the event of '
                  'discontinuation we will close any open positions and '
                  'disconnect all keys before shutdown.',
            ),
          ],
        ),
      );

  Widget _errorCard(String message) => Container(
        padding: const EdgeInsets.all(LuminSpacing.md),
        decoration: BoxDecoration(
          color: LuminColors.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: LuminColors.loss, width: 1),
        ),
        child: Text(
          message,
          style: const TextStyle(
            color: LuminColors.textPrimary,
            fontSize: 12,
          ),
        ),
      );
}


class _Section extends StatelessWidget {
  const _Section({required this.heading, required this.body});
  final String heading;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: LuminSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              heading,
              style: const TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: LuminSpacing.xs),
            Text(
              body,
              style: const TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
}


/// Standalone helper used by the connect-page gate.  Returns true
/// when the user has accepted the current :data:`latestTosVersion`,
/// false otherwise (no prior acceptance, or accepted an older
/// version after a doctrine change).
Future<bool> isTosCurrentlyAccepted() async {
  return TosService().isCurrentVersionAccepted();
}
