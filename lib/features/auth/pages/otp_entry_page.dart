/// OTP entry — second step of phone signin.
///
/// User enters the 6-digit code that was just delivered.  On success
/// the user-id JWT is persisted by [AuthService.verifyOtpAndStore] and
/// we replace the navigation stack with [NavShell].
///
/// "Resend" calls back to [AuthService.requestOtp] for the same phone.
/// The countdown reflects the OTP TTL returned by the engine; once it
/// hits zero the user can resend without burning a rate-limit slot
/// unnecessarily.  The engine still enforces 3-issues-per-hour,
/// surfaced as a 429 here.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/nav_shell.dart';
import '../../../data/app_config.dart';
import '../../../data/auth_service.dart';
import '../../../data/country_codes.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/lumin_card.dart';
import 'signup_page.dart';

class OtpEntryPage extends StatefulWidget {
  const OtpEntryPage({
    super.key,
    required this.phone,
    required this.channelUsed,
    required this.expiresInSeconds,
    this.countryHint,
  });

  final String phone;
  final String channelUsed;
  final int expiresInSeconds;

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
      final needsOnboarding =
          await auth.verifyOtpAndStore(widget.phone, _codeCtl.text.trim());
      if (!mounted) return;
      // Replace the entire stack — the user is authed now and we don't
      // want them back-buttoning into the signin pages.  Fork on the
      // engine's ``needs_onboarding`` flag: brand-new users + returning
      // users who never completed signup → SignupPage; otherwise →
      // NavShell.
      final Widget next = needsOnboarding
          ? SignupPage(phoneE164: widget.phone, countryHint: widget.countryHint)
          : const NavShell();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => next),
        (_) => false,
      );
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
      final result = await auth.requestOtp(widget.phone);
      if (!mounted) return;
      setState(() {
        _secondsLeft = result.expiresInSeconds;
      });
      _startTicker();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_resendConfirmation(result.channelUsed)),
          duration: const Duration(seconds: 2),
        ),
      );
    } on AuthError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _channelHint() {
    switch (widget.channelUsed) {
      case 'whatsapp':
        return 'Check WhatsApp for the code we just sent.';
      case 'sms':
        return 'Check your SMS for the code we just sent.';
      case 'log':
        return 'Code sent to engine logs (closed-beta delivery).';
      default:
        return 'Code sent.';
    }
  }

  String _resendConfirmation(String channel) {
    switch (channel) {
      case 'whatsapp':
        return 'Resent via WhatsApp';
      case 'sms':
        return 'Resent via SMS';
      case 'log':
        return 'Resent (check engine logs)';
      default:
        return 'Resent';
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
