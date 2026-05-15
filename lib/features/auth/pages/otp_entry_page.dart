/// OTP entry — second step of phone signin.
///
/// User enters the 6-digit code that was just delivered.  Two
/// confirmation paths:
///
///   * SMS — Firebase Phone Auth.  We hold the `verificationId`
///     produced by the codeSent callback on PhoneSignInPage and
///     exchange it + the typed code for a session via
///     [AuthService.confirmSmsCode].
///   * Telegram — engine-mediated.  Calls
///     [AuthService.confirmTelegramCode] which POSTs `/verify`,
///     receives a Firebase custom token, and signs in.
///
/// On success the AuthGate stream listener in `main.dart` swaps the
/// shell to NavShell automatically.  For brand-new users (cached
/// `needs_onboarding=true` from the verify response) we route to
/// SignupPage first.
///
/// "Resend" re-issues the OTP on the same channel.  Telegram
/// re-uses [AuthService.startTelegramSignIn]; SMS sends the user
/// back to PhoneSignInPage so Firebase can regenerate the
/// verification ID and resend token.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/nav_shell.dart';
import '../../../data/app_config.dart';
import '../../../data/auth_service.dart';
import '../../../data/country_codes.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/lumin_card.dart';
import 'signup_page.dart';

/// Which provider delivered the OTP — drives the channel-specific
/// hint copy and dictates which `confirm*` method to call on submit.
enum OtpChannel { sms, telegram }

class OtpEntryPage extends StatefulWidget {
  const OtpEntryPage({
    super.key,
    required this.phone,
    required this.channel,
    required this.expiresInSeconds,
    this.verificationId,
    this.channelUsed,
    this.countryHint,
  });

  final String phone;

  /// SMS or Telegram — picks the branch in [_submit].
  final OtpChannel channel;

  /// Firebase `verificationId` from the `codeSent` callback.  Required
  /// for SMS, ignored for Telegram.
  final String? verificationId;

  final int expiresInSeconds;

  /// Channel hint string returned by the engine on Telegram path
  /// (always `"telegram"` today, but kept as a passthrough so future
  /// engine-side multiplexing doesn't require a client change).
  final String? channelUsed;

  /// Country auto-detected on PhoneSignInPage.  Forwarded into
  /// SignupPage so a new user doesn't have to re-pick when filling
  /// their profile.  Null for legacy callers / direct OTP flows.
  final CountryCode? countryHint;

  @override
  State<OtpEntryPage> createState() => _OtpEntryPageState();
}

class _OtpEntryPageState extends State<OtpEntryPage> {
  final _codeCtl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;

  late int _secondsLeft;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.expiresInSeconds;
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _secondsLeft = (_secondsLeft - 1).clamp(0, widget.expiresInSeconds);
      });
      if (_secondsLeft == 0) {
        _ticker?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _codeCtl.dispose();
    super.dispose();
  }

  String? _validateCode(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return 'Enter the 6-digit code';
    if (s.length != 6 || int.tryParse(s) == null) {
      return 'Code is 6 digits';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final auth = AppConfigScope.of(context).auth;
    if (auth == null) {
      setState(() => _error = 'Live backend not configured.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.channel == OtpChannel.sms) {
        final vid = widget.verificationId;
        if (vid == null) {
          throw AuthError(
            'SMS verification id missing — restart signin from the phone page.',
          );
        }
        await auth.confirmSmsCode(vid, _codeCtl.text.trim());
      } else {
        await auth.confirmTelegramCode(widget.phone, _codeCtl.text.trim());
      }
      if (!mounted) return;
      // Brand-new users still need to land on SignupPage before the
      // AuthGate stream routes them to NavShell.  The cached flag is
      // populated by [AuthService.confirmTelegramCode]; the SMS path
      // leaves it false (engine backfills `firebase_uid` on existing
      // users — if they actually are new the `/api/profile` round-trip
      // surfaces it and Settings → Profile picks up the slack).
      if (auth.currentNeedsOnboarding()) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => SignupPage(
              phoneE164: widget.phone,
              countryHint: widget.countryHint,
            ),
          ),
          (_) => false,
        );
      } else {
        // Replace the stack with NavShell so the user can't back-button
        // into the signin pages.  The AuthGate would also route here
        // on the next stream tick; doing it explicitly avoids the
        // single-frame flash of PhoneSignInPage between pop and tick.
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const NavShell()),
          (_) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message ?? 'Verify failed (${e.code})');
    } on AuthError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Verify failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final auth = AppConfigScope.of(context).auth;
    if (auth == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.channel == OtpChannel.telegram) {
        final result = await auth.startTelegramSignIn(widget.phone);
        if (!mounted) return;
        setState(() {
          _secondsLeft = result.expiresInSeconds;
        });
        _startTicker();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Resent via Telegram'),
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        // For SMS we'd need to call `verifyPhoneNumber` again and that
        // produces a brand-new verificationId — easier (and less
        // confusing) to send the user back to PhoneSignInPage so they
        // can re-confirm the number first.  Firebase's resend token
        // is opaque + can't survive a Navigator.pop without state
        // hoisting; that's a future polish.
        if (!mounted) return;
        Navigator.of(context).pop();
      }
    } on AuthError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _channelHint() {
    switch (widget.channel) {
      case OtpChannel.sms:
        return 'Check your SMS for the code we just sent.';
      case OtpChannel.telegram:
        return 'Check Telegram for the code we just sent.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final canResend = _secondsLeft == 0 && !_busy;
    return Scaffold(
      backgroundColor: LuminColors.bgDeep,
      appBar: AppBar(
        backgroundColor: LuminColors.bgDeep,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: LuminColors.textSecondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: LuminSpacing.lg,
            vertical: LuminSpacing.lg,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Enter code',
                  style: TextStyle(
                    color: LuminColors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: LuminSpacing.sm),
                Text(
                  '${_channelHint()} Sent to ${widget.phone}.',
                  style: const TextStyle(
                    color: LuminColors.textSecondary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: LuminSpacing.xl),
                LuminCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CODE',
                        style: TextStyle(
                          color: LuminColors.textMuted,
                          fontSize: 10,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: LuminSpacing.sm),
                      TextFormField(
                        controller: _codeCtl,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        autocorrect: false,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        validator: _validateCode,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        style: const TextStyle(
                          color: LuminColors.textPrimary,
                          fontSize: 22,
                          letterSpacing: 8,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                        decoration: _inputDecoration('• • • • • •'),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: LuminSpacing.md),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: LuminColors.loss,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: LuminSpacing.xl),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: LuminColors.accent,
                    foregroundColor: LuminColors.bgDeep,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(LuminRadii.md),
                    ),
                  ),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: LuminColors.bgDeep,
                          ),
                        )
                      : const Text(
                          'Verify',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                const SizedBox(height: LuminSpacing.md),
                Center(
                  child: TextButton(
                    onPressed: canResend ? _resend : null,
                    child: Text(
                      canResend
                          ? 'Resend code'
                          : 'Resend in ${_formatCountdown(_secondsLeft)}',
                      style: TextStyle(
                        color: canResend
                            ? LuminColors.accent
                            : LuminColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatCountdown(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: LuminColors.textMuted,
        fontSize: 22,
        letterSpacing: 8,
      ),
      counterText: '',
      filled: true,
      fillColor: LuminColors.bgElevated,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: LuminSpacing.md,
        vertical: LuminSpacing.md,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LuminRadii.sm),
        borderSide: const BorderSide(color: LuminColors.cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LuminRadii.sm),
        borderSide: const BorderSide(color: LuminColors.accent),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LuminRadii.sm),
        borderSide: const BorderSide(color: LuminColors.loss),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LuminRadii.sm),
        borderSide: const BorderSide(color: LuminColors.loss),
      ),
    );
  }
}
