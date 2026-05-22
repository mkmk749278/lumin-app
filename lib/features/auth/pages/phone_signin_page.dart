/// Phone signin — entry step.
///
/// Captures a phone number in two parts:
///   * country chip (flag + dial code), auto-detected from device locale
///   * national-format number input
///
/// Two submit paths:
///   * "Send via SMS" — Firebase Phone Auth.  Google's SDK delivers
///     the code (Play Integrity invisible verification when
///     available, reCAPTCHA fallback otherwise) and hands us back a
///     `verificationId` we forward to [OtpEntryPage].
///   * "Send via Telegram" — engine-mediated fallback.  POSTs
///     `/api/auth/telegram-otp/issue`; the engine drops a 6-digit
///     code into the user's Telegram, and OtpEntryPage will exchange
///     it for a Firebase custom token via `/verify`.
///
/// Operator bypasses (admin-token signin, anonymous skip) live in the
/// separate ops app — Lumin is consumer-only.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/app_config.dart';
import '../../../data/auth_service.dart';
import '../../../data/country_codes.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/lumin_card.dart';
import 'otp_entry_page.dart';

class PhoneSignInPage extends StatefulWidget {
  const PhoneSignInPage({super.key});

  @override
  State<PhoneSignInPage> createState() => _PhoneSignInPageState();
}

class _PhoneSignInPageState extends State<PhoneSignInPage> {
  final _phoneCtl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;
  CountryCode? _country;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Resolve a country default once, on the first frame where we have
    // a BuildContext to read the locale from.  ``View.of(context)``
    // gives us the device locale without depending on Localizations
    // delegates (this app doesn't ship MaterialLocalizations beyond
    // the default English).
    if (_country == null) {
      final locale = View.of(context).platformDispatcher.locale;
      _country = defaultCountryFromLocale(locale, fallbackIso2: 'US');
    }
  }

  @override
  void dispose() {
    _phoneCtl.dispose();
    super.dispose();
  }

  // National part: 6–14 digits.  Server re-validates the full E.164.
  static final _digits = RegExp(r'^\d{6,14}$');

  String? _validatePhone(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return 'Enter your phone number';
    if (!_digits.hasMatch(s)) {
      return '6–14 digits, no spaces';
    }
    return null;
  }

  String _composeE164() {
    final dial = _country?.dial ?? '1';
    final national = _phoneCtl.text.trim();
    return '+$dial$national';
  }

  Future<void> _openCountryPicker() async {
    final pick = await showModalBottomSheet<CountryCode>(
      context: context,
      backgroundColor: LuminColors.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(LuminRadii.lg)),
      ),
      builder: (ctx) => _CountryPickerSheet(initial: _country),
    );
    if (pick != null && mounted) {
      setState(() => _country = pick);
    }
  }

  AuthService? _resolveAuth() {
    final scope = AppConfigScope.of(context);
    final auth = scope.auth;
    if (auth == null) {
      setState(
          () => _error = 'Live backend not configured. Check API keys page.');
    }
    return auth;
  }

  Future<void> _submitSms() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final auth = _resolveAuth();
    if (auth == null) return;
    final phone = _composeE164();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.startSmsSignIn(
        phoneE164: phone,
        onCodeSent: (verificationId, resendToken) {
          if (!mounted) return;
          setState(() => _busy = false);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OtpEntryPage(
                phone: phone,
                channel: OtpChannel.sms,
                verificationId: verificationId,
                resendToken: resendToken,
                // Firebase session timeout is pinned to 120s in
                // AuthService.startSmsSignIn — match it here so the
                // countdown's "Resend" enables exactly when the prior
                // session has actually expired.
                expiresInSeconds: 120,
                countryHint: _country,
              ),
            ),
          );
        },
        onVerificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          setState(() {
            _busy = false;
            _error = e.message ?? 'Couldn\'t send code (${e.code})';
          });
        },
        onAutoVerified: (_) {
          // Auto-resolution landed us a session — the AuthGate stream
          // listener in main.dart will swap to NavShell on the next
          // frame.  Nothing more to do here.
          if (!mounted) return;
          setState(() => _busy = false);
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Couldn\'t send code: $e';
      });
    }
  }

  Future<void> _submitTelegram() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final auth = _resolveAuth();
    if (auth == null) return;
    final phone = _composeE164();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await auth.startTelegramSignIn(phone);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpEntryPage(
            phone: phone,
            channel: OtpChannel.telegram,
            expiresInSeconds: result.expiresInSeconds,
            channelUsed: result.channelUsed,
            countryHint: _country,
          ),
        ),
      );
    } on AuthError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Couldn\'t send code: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final country = _country;
    return Scaffold(
      backgroundColor: LuminColors.bgDeep,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: LuminSpacing.lg,
            vertical: LuminSpacing.xl,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: LuminSpacing.xl),
                const Text(
                  'Sign in or sign up',
                  style: TextStyle(
                    color: LuminColors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: LuminSpacing.sm),
                const Text(
                  'Enter your phone number — we\'ll text you a 6-digit '
                  'code. Same flow whether you\'re new or returning.',
                  style: TextStyle(
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
                        'PHONE',
                        style: TextStyle(
                          color: LuminColors.textMuted,
                          fontSize: 10,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: LuminSpacing.sm),
                      Row(
                        children: [
                          InkWell(
                            onTap: _busy ? null : _openCountryPicker,
                            borderRadius:
                                BorderRadius.circular(LuminRadii.sm),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: LuminSpacing.md,
                                vertical: LuminSpacing.md,
                              ),
                              decoration: BoxDecoration(
                                color: LuminColors.bgElevated,
                                borderRadius:
                                    BorderRadius.circular(LuminRadii.sm),
                                border: Border.all(
                                  color: LuminColors.cardBorder,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    country?.flag ?? '\u{1F310}',
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                  const SizedBox(width: LuminSpacing.sm),
                                  Text(
                                    '+${country?.dial ?? '1'}',
                                    style: const TextStyle(
                                      color: LuminColors.textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.keyboard_arrow_down,
                                    color: LuminColors.textMuted,
                                    size: 16,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: LuminSpacing.sm),
                          Expanded(
                            child: TextFormField(
                              controller: _phoneCtl,
                              autofocus: true,
                              keyboardType: TextInputType.phone,
                              autocorrect: false,
                              maxLength: 14,
                              validator: _validatePhone,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              style: const TextStyle(
                                color: LuminColors.textPrimary,
                                fontSize: 15,
                                letterSpacing: 0.4,
                              ),
                              decoration: _inputDecoration('Phone number'),
                            ),
                          ),
                        ],
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
                  onPressed: _busy ? null : _submitSms,
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
                          'Send via SMS',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                const SizedBox(height: LuminSpacing.md),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: LuminColors.accent,
                    side: const BorderSide(color: LuminColors.accent),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(LuminRadii.md),
                    ),
                  ),
                  onPressed: _busy ? null : _submitTelegram,
                  child: const Text(
                    'Send via Telegram',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      counterText: '',
      hintStyle: const TextStyle(color: LuminColors.textMuted, fontSize: 15),
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

/// Bottom-sheet country picker.  Search field at the top filters the
/// hand-maintained ``kCountryCodes`` list by ISO code, dial code, or
/// name.  Tap a row → returns the selection to the caller via
/// ``Navigator.pop(context, country)``.
class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet({this.initial});

  final CountryCode? initial;

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? kCountryCodes
        : kCountryCodes.where((c) {
            return c.iso2.toLowerCase().contains(q) ||
                c.dial.contains(q) ||
                c.name.toLowerCase().contains(q);
          }).toList(growable: false);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scrollController) => Column(
        children: [
          const SizedBox(height: LuminSpacing.sm),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: LuminColors.cardBorder,
              borderRadius: BorderRadius.circular(LuminRadii.pill),
            ),
          ),
          const SizedBox(height: LuminSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search country',
                hintStyle:
                    const TextStyle(color: LuminColors.textMuted, fontSize: 14),
                prefixIcon: const Icon(
                  Icons.search,
                  color: LuminColors.textMuted,
                  size: 18,
                ),
                filled: true,
                fillColor: LuminColors.bgElevated,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: LuminSpacing.sm),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(LuminRadii.sm),
                  borderSide: BorderSide.none,
                ),
              ),
              style:
                  const TextStyle(color: LuminColors.textPrimary, fontSize: 14),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: LuminSpacing.sm),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final c = filtered[i];
                final selected = widget.initial?.iso2 == c.iso2;
                return InkWell(
                  onTap: () => Navigator.of(context).pop(c),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LuminSpacing.lg,
                      vertical: LuminSpacing.md,
                    ),
                    child: Row(
                      children: [
                        Text(c.flag, style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: LuminSpacing.md),
                        Expanded(
                          child: Text(
                            c.name,
                            style: TextStyle(
                              color: selected
                                  ? LuminColors.accent
                                  : LuminColors.textPrimary,
                              fontSize: 14,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        Text(
                          '+${c.dial}',
                          style: const TextStyle(
                            color: LuminColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                        if (selected) ...[
                          const SizedBox(width: LuminSpacing.sm),
                          const Icon(
                            Icons.check,
                            color: LuminColors.accent,
                            size: 18,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
