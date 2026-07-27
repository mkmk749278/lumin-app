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
/// Brand-new users land on SignupPage first — Telegram path uses the
/// cached `needs_onboarding` from the verify response; SMS path
/// round-trips `/api/profile` after Firebase signin to learn the same
/// bit (since the SMS verify itself doesn't touch the engine).
///
/// **This page owns its own forward navigation, and must** (2026-07-27).
/// The previous doc here said "the AuthGate stream listener in main.dart
/// swaps the shell to NavShell automatically".  That is false for this
/// route: PhoneSignInPage `push`es OtpEntryPage *on top of* `_AuthGate`,
/// so when the gate re-routes it rebuilds **underneath** the pushed
/// route and this page stays on screen.
///
/// It broke Android auto-retrieval end to end.  Firebase fires `codeSent`
/// (we push this page) and then `verificationCompleted` when it reads the
/// SMS itself — which signs the user in and consumes the verification
/// session.  The gate switched to NavShell below, invisibly; the user sat
/// on the code screen.  Tapping Verify then failed `session-expired`
/// against a session that had already succeeded, so the page reported
/// "That code expired" over a live authenticated account.  Force-quitting
/// rebuilt the navigator from scratch and the user was simply logged in —
/// the report that surfaced this.
///
/// So: [_watchAuthState] completes the flow on *any* sign-in regardless of
/// which callback produced it, and [_submit] never reports a failure while
/// [AuthService.currentUser] is non-null.
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
import '../../../shared/platform_input.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/lumin_card.dart';
import 'signup_page.dart';

/// Which provider delivered the OTP — drives the channel-specific
/// hint copy and dictates which `confirm*` method to call on submit.
enum OtpChannel { sms, telegram }

/// What the UI should do about a failed code exchange.
enum OtpFailureAction {
  /// Not actually a failure — a session already exists, so go forward.
  completeSignIn,

  /// The verification window is gone; only a fresh code can recover.
  promptResend,

  /// Wrong digits; the same session can still accept a retry.
  promptRetryCode,

  /// Anything else — surface the SDK's own message.
  showMessage,
}

/// Decide what a code-exchange failure means, given whether we are signed in.
///
/// Pulled out as a pure function because the ordering *is* the bug
/// (2026-07-27): the page used to branch on `e.code` alone and never asked
/// whether the account was already authenticated. Android SMS auto-retrieval
/// signs the user in through `verificationCompleted` and consumes the
/// verification session doing it, so a later Verify tap throws
/// `session-expired` against a session that had already succeeded — and the
/// screen said "That code expired" to someone who was logged in.
///
/// **A live session outranks every error code.** None of the codes below
/// describe the account state; they describe one exchange attempt, and an
/// attempt can fail redundantly after the account is already signed in.
OtpFailureAction classifyOtpFailure({
  required String code,
  required bool signedIn,
}) {
  if (signedIn) return OtpFailureAction.completeSignIn;
  if (code == 'session-expired') return OtpFailureAction.promptResend;
  if (code == 'invalid-verification-code') {
    return OtpFailureAction.promptRetryCode;
  }
  return OtpFailureAction.showMessage;
}

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

  /// Guards the forward navigation so it runs exactly once. Sign-in can be
  /// observed twice in a race — the auth-state stream and a successful
  /// [_submit] both reach [_completeSignIn] — and two `pushAndRemoveUntil`
  /// calls would stack two NavShells.
  bool _completing = false;

  /// Auth-state subscription. Cancelled in [dispose]; without that a fired
  /// callback on a disposed State throws on `setState`/`Navigator`.
  StreamSubscription<User?>? _authSub;
  bool _watchingAuth = false;

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _resendToken = widget.resendToken;
    _windowSeconds = widget.expiresInSeconds;
    _secondsLeft = _windowSeconds;
    _startTicker();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _watchAuthState();
  }

  /// Complete the flow whenever Firebase reports a signed-in user, no matter
  /// which path produced it.
  ///
  /// The one that used to fall through the cracks is Android SMS
  /// auto-retrieval: `verificationCompleted` fires inside
  /// [AuthService.startSmsSignIn] and signs the user in there, so the
  /// callback that would have navigated lives on PhoneSignInPage — a route
  /// this page is stacked on top of. Nothing here ever learned about it.
  /// Watching the stream catches that case, the resend case, and any future
  /// path, instead of enumerating callbacks.
  ///
  /// Subscribed from [didChangeDependencies] rather than [initState] because
  /// it needs the [AppConfigScope] inherited widget.
  ///
  /// Uses `maybeOf`, not `of`: unlike [_submit] this runs on every mount, so
  /// asserting here would make the page un-buildable standalone in a widget
  /// test. A missing scope simply means no auth to watch.
  void _watchAuthState() {
    if (_watchingAuth) return;
    final auth = AppConfigScope.maybeOf(context)?.auth;
    if (auth == null) return;
    _watchingAuth = true;
    _authSub = auth.authStateChanges.listen((user) {
      if (user == null || !mounted) return;
      _completeSignIn();
    });
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
    _authSub?.cancel();
    _codeCtl.dispose();
    super.dispose();
  }

  /// Leave this page for wherever a freshly signed-in user belongs.
  ///
  /// Deliberately the *same* routine whether the code was typed or
  /// auto-retrieved: an auto-filled sign-in is the identical event arriving
  /// by a different callback, and giving it its own routing behaviour is how
  /// the two drift apart.
  Future<void> _completeSignIn() async {
    if (_completing || !mounted) return;
    _completing = true;
    _ticker?.cancel();
    final scope = AppConfigScope.of(context);
    final auth = scope.auth;
    if (auth == null) return;

    if (widget.channel == OtpChannel.sms) {
      // The SMS verify never touches the engine, so ask /api/profile whether
      // this user is new. Failure falls through to NavShell — a transient
      // 5xx must not strand someone who is already authenticated; worst case
      // a new user finishes their profile from Settings → Profile.
      try {
        final Profile profile = await scope.repo.fetchProfile();
        auth.cacheEngineMetadata(
          userId: profile.userId,
          tier: profile.tier,
          paidUntil: profile.paidUntil,
          needsOnboarding: profile.needsOnboarding,
          displayName: profile.displayName,
        );
      } catch (_) {
        // Intentionally swallowed — see above.
      }
    }
    if (!mounted) return;
    // Replace the stack so the user can't back-button into the signin pages.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => auth.currentNeedsOnboarding()
            ? SignupPage(
                phoneE164: widget.phone,
                countryHint: widget.countryHint,
              )
            : const NavShell(),
      ),
      (_) => false,
    );
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
      } else {
        await auth.confirmTelegramCode(widget.phone, _codeCtl.text.trim());
      }
      if (!mounted) return;
      await _completeSignIn();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      switch (classifyOtpFailure(
        code: e.code,
        signedIn: auth.currentUser != null,
      )) {
        case OtpFailureAction.completeSignIn:
          // The exchange failed but the account is already authenticated —
          // auto-retrieval got there first. Go forward; reporting an error
          // here is the app contradicting its own state.
          await _completeSignIn();
          return;
        case OtpFailureAction.promptResend:
          // The Firebase verification window (pinned to 120s in
          // AuthService.startSmsSignIn) elapsed before the user typed the
          // code, or the SDK invalidated the session. The same code-entry
          // can't recover; promote the resend CTA and stop the countdown.
          _ticker?.cancel();
          setState(() {
            _sessionExpired = true;
            _secondsLeft = 0;
            _error = 'That code expired — tap "Send a new code" below '
                'and we\'ll text you a fresh one.';
          });
        case OtpFailureAction.promptRetryCode:
          setState(() => _error = 'That code didn\'t match — double-check '
              'and try again.');
        case OtpFailureAction.showMessage:
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
            // Auto-resolution signed the user in directly.  Routing is
            // [_watchAuthState]'s job, not this callback's — the AuthGate
            // cannot do it for us, because this route sits ON TOP of the
            // gate and the gate re-routing rebuilds underneath it.  Just
            // release the completer.
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
                        autofocus: kAutofocusTextFields,
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
