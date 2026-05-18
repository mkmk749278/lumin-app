/// 2FA (TOTP) enrollment screen — required before enabling server-side
/// auto-trade per the 14-PR roadmap PR-12 + the resolved-decisions
/// table in engine #431.
///
/// Why mandatory: server-side execution stores the user's Binance API
/// key in encrypted form on Lumin's infrastructure.  A stolen Firebase
/// ID token + Firestore breach combined would still be defeated by
/// the KMS IAM separation, BUT 2FA on the user's account adds the
/// "stolen-token-still-needs-second-factor" layer for sensitive ops
/// (re-connect, disconnect, raise position cap).
///
/// Implementation: Firebase Auth's TOTP MFA.  Steps:
///   1. User must be recently authenticated (Firebase enforces; the
///      page surfaces a re-auth prompt if not).
///   2. ``TotpMultiFactorGenerator.generateSecret`` produces a secret
///      the user pastes into their authenticator app
///      (Google Authenticator, Authy, 1Password, etc.).
///   3. Display the otpauth:// URL + raw secret string.  The user
///      scans / pastes; we don't render a QR code in this PR (defer
///      to a follow-up — manual paste is fine for MVP).
///   4. User enters the 6-digit TOTP from the authenticator.
///   5. ``user.multiFactor.enroll`` registers the factor.
///
/// Once enrolled, the user can proceed to the server-side execution
/// connect page (gated by [TwoFaGate] in
/// ``server_side_execution_page.dart``).
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/tokens.dart';

class TwoFaEnrollmentPage extends StatefulWidget {
  const TwoFaEnrollmentPage({super.key});

  @override
  State<TwoFaEnrollmentPage> createState() => _TwoFaEnrollmentPageState();
}

class _TwoFaEnrollmentPageState extends State<TwoFaEnrollmentPage> {
  final _otpCtrl = TextEditingController();
  TotpSecret? _secret;
  String? _otpAuthUri;
  bool _generatingSecret = false;
  bool _verifying = false;
  String? _error;
  bool _enrolled = false;

  @override
  void dispose() {
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _generateSecret() async {
    if (_generatingSecret) return;
    setState(() {
      _generatingSecret = true;
      _error = null;
      _secret = null;
      _otpAuthUri = null;
    });
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _error =
            'You must be signed in to enable 2FA.  Sign in and try again.';
        _generatingSecret = false;
      });
      return;
    }
    try {
      final session = await user.multiFactor.getSession();
      final secret = await TotpMultiFactorGenerator.generateSecret(session);
      final uri = await secret.generateQrCodeUrl(
        accountName: user.email ?? user.phoneNumber ?? 'Lumin',
        issuer: 'Lumin',
      );
      if (!mounted) return;
      setState(() {
        _secret = secret;
        _otpAuthUri = uri;
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _explainFirebaseAuthError(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not generate 2FA secret: $e';
      });
    } finally {
      if (mounted) setState(() => _generatingSecret = false);
    }
  }

  Future<void> _verifyAndEnroll() async {
    if (_verifying || _secret == null) return;
    final code = _otpCtrl.text.trim();
    if (code.length != 6 || int.tryParse(code) == null) {
      setState(() => _error = 'Enter the 6-digit code from your authenticator');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _error = 'Not signed in.';
        _verifying = false;
      });
      return;
    }
    try {
      final assertion = TotpMultiFactorGenerator.getAssertionForEnrollment(
        _secret!,
        code,
      );
      await user.multiFactor.enroll(
        assertion,
        displayName: 'Lumin 2FA',
      );
      if (!mounted) return;
      setState(() {
        _enrolled = true;
        _otpCtrl.clear();
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _explainFirebaseAuthError(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not enroll 2FA: $e';
      });
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _copySecret() async {
    final raw = _secret?.secretKey;
    if (raw == null) return;
    await Clipboard.setData(ClipboardData(text: raw));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Secret copied to clipboard'),
        backgroundColor: LuminColors.success,
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _explainFirebaseAuthError(FirebaseAuthException e) {
    // Map the common error codes to actionable user messages.  See
    // https://firebase.google.com/docs/auth/admin/errors and
    // FirebaseAuthMultiFactorException for the MFA-specific subset.
    switch (e.code) {
      case 'requires-recent-login':
        return 'For security, please sign out and sign back in, '
            'then try enabling 2FA again.';
      case 'invalid-verification-code':
        return 'That code is incorrect.  Make sure your authenticator '
            'app is in sync and try the latest code.';
      case 'invalid-action-code':
        return 'The 2FA setup expired.  Tap "Generate secret" again.';
      case 'second-factor-already-in-use':
        return '2FA is already enabled on this account.';
      case 'unsupported-first-factor':
        return 'Your sign-in method does not support 2FA yet.  '
            'Sign in with email + password or phone to continue.';
      default:
        return e.message ?? 'Firebase error: ${e.code}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LuminColors.bgDeep,
      appBar: AppBar(
        title: const Text('Two-factor authentication'),
        backgroundColor: LuminColors.bgDeep,
      ),
      body: ListView(
        padding: const EdgeInsets.all(LuminSpacing.lg),
        children: [
          _doctrineCard(),
          const SizedBox(height: LuminSpacing.lg),
          if (_enrolled) _enrolledCard() else _enrollmentForm(),
          if (_error != null) ...[
            const SizedBox(height: LuminSpacing.lg),
            _errorCard(_error!),
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
              'Why 2FA is required',
              style: TextStyle(
                color: LuminColors.warn,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            SizedBox(height: LuminSpacing.sm),
            Text(
              'Server-side auto-trade gives Lumin\'s engine the ability '
              'to sign trades on your Binance account.  We require '
              '2FA on your Lumin account so a stolen phone or token '
              'still needs your authenticator app to make sensitive '
              'changes (connect, disconnect, raise position cap).\n\n'
              'You will use 2FA only for these sensitive operations; '
              'day-to-day viewing of your positions does not require '
              'it.',
              style: TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      );

  Widget _enrollmentForm() => Container(
        padding: const EdgeInsets.all(LuminSpacing.md),
        decoration: BoxDecoration(
          color: LuminColors.bgCard,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enable 2FA',
              style: TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: LuminSpacing.md),
            if (_secret == null) ...[
              const Text(
                'Step 1: Generate a secret for your authenticator app '
                '(Google Authenticator, Authy, 1Password, etc.).',
                style: TextStyle(
                  color: LuminColors.textPrimary,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: LuminSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _generatingSecret ? null : _generateSecret,
                  child: _generatingSecret
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Generate secret'),
                ),
              ),
            ] else ...[
              const Text(
                'Step 2: Paste this secret into your authenticator app '
                '— or scan the otpauth:// URI as a QR code.',
                style: TextStyle(
                  color: LuminColors.textPrimary,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: LuminSpacing.sm),
              _secretChip(_secret!.secretKey, label: 'Secret'),
              if (_otpAuthUri != null) ...[
                const SizedBox(height: LuminSpacing.sm),
                _secretChip(_otpAuthUri!, label: 'otpauth:// URI'),
              ],
              const SizedBox(height: LuminSpacing.md),
              const Text(
                'Step 3: Enter the 6-digit code your app shows.',
                style: TextStyle(
                  color: LuminColors.textPrimary,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: LuminSpacing.sm),
              TextField(
                controller: _otpCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(
                  labelText: '6-digit code',
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(
                  color: LuminColors.textPrimary,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: LuminSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _verifying ? null : _verifyAndEnroll,
                  child: _verifying
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Verify and enable 2FA'),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _secretChip(String value, {required String label}) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: LuminSpacing.sm,
          vertical: LuminSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: LuminColors.bgDeep,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: LuminColors.textMuted,
                      fontSize: 10,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      color: LuminColors.textPrimary,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$label copied'),
                    backgroundColor: LuminColors.success,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'Copy',
            ),
          ],
        ),
      );

  Widget _enrolledCard() => Container(
        padding: const EdgeInsets.all(LuminSpacing.md),
        decoration: BoxDecoration(
          color: LuminColors.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: LuminColors.success, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.check_circle,
                    color: LuminColors.success, size: 20),
                SizedBox(width: LuminSpacing.sm),
                Text(
                  '2FA enabled',
                  style: TextStyle(
                    color: LuminColors.success,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.sm),
            const Text(
              'Your account is now protected by 2FA.  You can proceed '
              'to enable server-side auto-trade.',
              style: TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: LuminSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Continue'),
              ),
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
        child: Row(
          children: [
            const Icon(Icons.error_outline,
                color: LuminColors.loss, size: 18),
            const SizedBox(width: LuminSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: LuminColors.textPrimary,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      );
}

/// Returns true if the signed-in Firebase user has at least one MFA
/// factor enrolled.  Used by [TwoFaGate] to decide whether to gate
/// the server-side execution surface.
Future<bool> isMfaEnrolled() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return false;
  try {
    final factors = await user.multiFactor.getEnrolledFactors();
    return factors.isNotEmpty;
  } catch (_) {
    // Defensive: if Firebase rejects the read (e.g. token expired)
    // treat as "not enrolled" so the gate fires and the user
    // re-authenticates via the enrollment flow.
    return false;
  }
}
