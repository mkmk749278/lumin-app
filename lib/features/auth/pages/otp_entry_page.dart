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
/// shell to NavShell automatically.  Brand-new users land on
/// SignupPage first — Telegram path uses the cached
/// `needs_onboarding` from the verify response; SMS path round-trips
/// `/api/profile` after Firebase signin to learn the same bit (since
/// the SMS verify itself doesn't touch the engine).
///
/// "Resend" re-issues the OTP on the same channel.  Telegram re-uses
/// [AuthService.startTelegramSignIn].  SMS re-invokes the same call
/// with the saved `forceResendingToken` so Firebase dispatches a
/// fresh code on the same session (no reCAPTCHA round-trip), and the
/// page swaps in the new verificationId + resendToken without
/// navigating away.  If Firebase reports `session-expired`, the
/// resend CTA is promoted to primary so the user has a one-tap
/// recovery instead of a dead-end error.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/nav_shell.dart';
import '../../../data/app_config.dart';
import '../../../data/auth_service.dart';
import '../../../data/country_codes.dart';
import '../../../data/repository.dart';
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
    this.resendToken,
    this.channelUsed,
    this.countryHint,
  });

  final String phone;

  /// SMS or Telegram — picks the branch in [_submit].
  final OtpChannel channel;

  /// Firebase `verificationId` from the `codeSent` callback.  Required
  /// for SMS, ignored for Telegram.
  final String? verificationId;

  /// Firebase resend token captured alongside [verificationId] on the
  /// initial `codeSent` callback.  Passed back into
  /// [AuthService.startSmsSignIn] on resend so Firebase reuses the
  /// same Phone Auth session (skipping the reCAPTCHA round-trip).
  /// Null for the Telegram channel.
  final int? resendToken;

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

  /// True when the most recent failure was a `session-expired` from
  /// Firebase — in that state the Verify button is useless until a
  /// fresh code arrives, so we swap the bottom CTA to "Send a new
  /// code" and hide the countdown.
  bool _sessionExpired = false;

  /// Live verificationId / resendToken — start with whatever
  /// PhoneSignInPage handed us, then update on each successful resend
  /// so the next [_submit] uses the most-recent session.
  String? _verificationId;
  int? _resendToken;

  late int _secondsLeft;
  late int _windowSeconds;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _resendToken = widget.resendToken;
    _windowSeconds = widget.expiresInSeconds;
    _secondsLeft = _windowSeconds;
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _secondsLeft = (_secondsLeft - 1).clamp(0, _windowSeconds);
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
    final scope = AppConfigScope.of(context);
    final auth = scope.auth;
    if (auth == null) {
      setState(() => _error = 'Live backend not configured.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _sessionExpired = false;
    });
    try {
      if (widget.channel == OtpChannel.sms) {
        final vid = _verificationId;
        if (vid == null) {
          throw AuthError(
            'SMS verification id missing — restart signin from the phone page.',
          );
        }
        await auth.confirmSmsCode(vid, _codeCtl.text.trim());
        // SMS path doesn't go through the engine for the OTP itself —
        // ask `/api/profile` whether this user is new so we route them
        // to SignupPage like the Telegram path does.  Failure here
        // (engine down, transient 5xx) falls through to NavShell; the
        // user can complete profile from Settings → Profile later.
        try {
          final Profile profile = await scope.repo.fetchProfile();
          auth.cacheEngineMetadata(
            userId: profile.userId,
            tier: profile.tier,
            paidUntil: profile.paidUntil,
            needsOnboarding: profile.needsOnboarding,
          );
        } catch (_) {
          // Swallow — needsOnboarding stays at its default (false for
          // the SMS path).  Worst case: a brand-new user lands on
          // NavShell instead of SignupPage and finishes profile from
          // Settings → Profile.  Better than blocking signin on a
          // transient profile-fetch failure.
        }
      } else {
        await auth.confirmTelegramCode(widget.phone, _codeCtl.text.trim());
      }
      if (!mounted) return;
      // Brand-new users land on SignupPage before NavShell.  Telegram
      // populates `currentNeedsOnboarding` from the verify response;
      // SMS populates it from the `/api/profile` round-trip above.
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
      // `session-expired` means the Firebase verification window
      // (pinned to 120s in AuthService.startSmsSignIn) elapsed before
      // the user typed the code, OR the SDK invalidated the session
      // for some other reason.  In either case the same code-entry
      // can't recover; the user needs a fresh SMS.  Surface a clear
      // "Send a new code" CTA and stop the countdown.
      if (e.code == 'session-expired') {
        _ticker?.cancel();
        setState(() {
          _sessionExpired = true;
          _secondsLeft = 0;
          _error = 'That code expired — tap "Send a new code" below '
              'and we\'ll text you a fresh one.';
        });
      } else if (e.code == 'invalid-verification-code') {
        setState(() => _error = 'That code didn\'t match — double-check '
            'and try again.');
      } else {
        setState(() => _error = e.message ?? 'Verify failed (${e.code})');
      }
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
          _windowSeconds = result.expiresInSeconds;
          _secondsLeft = result.expiresInSeconds;
          _sessionExpired = false;
        });
        _startTicker();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Resent via Telegram'),
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        // SMS resend — re-issue on the same Firebase Phone Auth
        // session by handing the saved [_resendToken] back via
        // `forceResendingToken`.  Firebase skips the reCAPTCHA step
        // and dispatches a fresh code; the `codeSent` callback hands
        // us a refreshed verificationId + resendToken which we swap
        // into state so the next [_submit] uses them.
        final completer = Completer<void>();
        await auth.startSmsSignIn(
          phoneE164: widget.phone,
          resendToken: _resendToken,
          onCodeSent: (verificationId, resendToken) {
            if (!mounted) {
              if (!completer.isCompleted) completer.complete();
              return;
            }
            setState(() {
              _verificationId = verificationId;
              _resendToken = resendToken;
              _windowSeconds = 120;
              _secondsLeft = 120;
              _sessionExpired = false;
              _codeCtl.clear();
            });
            _startTicker();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('New code sent'),
                duration: Duration(seconds: 2),
              ),
            );
            if (!completer.isCompleted) completer.complete();
          },
          onVerificationFailed: (FirebaseAuthException e) {
            if (mounted) {
              setState(() => _error = e.message ?? 'Couldn\'t resend (${e.code})');
            }
            if (!completer.isCompleted) completer.complete();
          },
          onAutoVerified: (_) {
            // Auto-resolution signed the user in directly — the
            // AuthGate stream listener will route forward on the next
            // tick.  Nothing for us to do here.
            if (!completer.isCompleted) completer.complete();
          },
        );
        await completer.future;
      }
    } on AuthError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Couldn\'t resend: $e');
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
    final canResend = (_secondsLeft == 0 || _sessionExpired) && !_busy;
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
                  onPressed: (_busy || _sessionExpired) ? null : _submit,
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
                      _sessionExpired
                          ? 'Send a new code'
                          : canResend
                              ? 'Resend code'
                              : 'Resend in ${_formatCountdown(_secondsLeft)}',
                      style: TextStyle(
                        color: canResend
                            ? LuminColors.accent
                            : LuminColors.textMuted,
                        fontSize: 13,
                        fontWeight: _sessionExpired
                            ? FontWeight.w600
                            : FontWeight.w400,
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
