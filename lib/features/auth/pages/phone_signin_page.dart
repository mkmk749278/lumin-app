/// Phone signin — entry step.
///
/// Captures an E.164 phone number and asks the backend to deliver a
/// 6-digit OTP via WhatsApp / SMS / engine logs (depending on
/// ``OTP_PRIMARY_CHANNEL``).  On success pushes [OtpEntryPage]; on
/// completion of that page the app returns to [NavShell] with a stored
/// user-id JWT.
///
/// Debug builds expose a "skip with anonymous" link that mints an
/// anonymous JWT directly — covers CI / manual testing on builds where
/// the OTP delivery stack isn't wired (the closed-beta default is
/// ``LogOnly`` which still works, but skipping is faster for iteration).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/nav_shell.dart';
import '../../../data/app_config.dart';
import '../../../data/auth_service.dart';
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
  final _adminTokenCtl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  bool _adminPanelOpen = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtl.dispose();
    _adminTokenCtl.dispose();
    super.dispose();
  }

  // E.164: optional leading +, then 8-15 digits.  Engine layer
  // re-validates; this is just first-line filter so the user gets a
  // typo'd-input error before the network round-trip.
  static final _e164 = RegExp(r'^\+?[1-9]\d{7,14}$');

  String? _validatePhone(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return 'Enter your phone number';
    if (!_e164.hasMatch(s)) {
      return 'Use international format, e.g. +14155551234';
    }
    return null;
  }

  String _normalised(String raw) {
    final s = raw.trim();
    return s.startsWith('+') ? s : '+$s';
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final scope = AppConfigScope.of(context);
    final auth = scope.auth;
    if (auth == null) {
      setState(() => _error = 'Live backend not configured. Check API keys page.');
      return;
    }
    final phone = _normalised(_phoneCtl.text);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await auth.requestOtp(phone);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpEntryPage(
            phone: phone,
            channelUsed: result.channelUsed,
            expiresInSeconds: result.expiresInSeconds,
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

  Future<void> _useAnonymous() async {
    final scope = AppConfigScope.of(context);
    final auth = scope.auth;
    if (auth == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.mintAnonymous();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const NavShell()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Anonymous mint failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithAdminToken() async {
    final token = _adminTokenCtl.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'Paste the engine\'s API_AUTH_TOKEN');
      return;
    }
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
      await auth.signInWithAdminToken(token);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const NavShell()),
        (_) => false,
      );
    } on AuthError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Token signin failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  'Sign in',
                  style: TextStyle(
                    color: LuminColors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: LuminSpacing.sm),
                const Text(
                  'We\'ll send a 6-digit code to verify your phone.',
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
                      TextFormField(
                        controller: _phoneCtl,
                        autofocus: true,
                        keyboardType: TextInputType.phone,
                        autocorrect: false,
                        validator: _validatePhone,
                        style: const TextStyle(
                          color: LuminColors.textPrimary,
                          fontSize: 15,
                          letterSpacing: 0.4,
                        ),
                        decoration: _inputDecoration('+14155551234'),
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
                          'Send code',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                const SizedBox(height: LuminSpacing.lg),
                _ownerAdminTokenPanel(),
                const Spacer(),
                if (kDebugMode)
                  TextButton(
                    onPressed: _busy ? null : _useAnonymous,
                    child: const Text(
                      'Skip with anonymous (debug)',
                      style: TextStyle(
                        color: LuminColors.textMuted,
                        fontSize: 12,
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

  /// Owner-only bypass: paste the engine's static ``API_AUTH_TOKEN`` and
  /// skip phone-OTP entirely.  Engine grants ``tier=owner`` for this
  /// exact bearer string (PR #355).  Collapsible because it's only
  /// relevant to the one operator on the system; testers see the
  /// phone field and ignore this section.
  Widget _ownerAdminTokenPanel() {
    return LuminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _adminPanelOpen = !_adminPanelOpen),
            borderRadius: BorderRadius.circular(LuminRadii.sm),
            child: Row(
              children: [
                const Icon(
                  Icons.admin_panel_settings_outlined,
                  color: LuminColors.textMuted,
                  size: 16,
                ),
                const SizedBox(width: LuminSpacing.sm),
                const Expanded(
                  child: Text(
                    'Sign in with admin token (owner)',
                    style: TextStyle(
                      color: LuminColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  _adminPanelOpen
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: LuminColors.textMuted,
                  size: 18,
                ),
              ],
            ),
          ),
          if (_adminPanelOpen) ...[
            const SizedBox(height: LuminSpacing.md),
            TextField(
              controller: _adminTokenCtl,
              autocorrect: false,
              obscureText: true,
              enableSuggestions: false,
              style: const TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 13,
              ),
              decoration: _inputDecoration('API_AUTH_TOKEN'),
            ),
            const SizedBox(height: LuminSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: LuminColors.bgElevated,
                  foregroundColor: LuminColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(LuminRadii.sm),
                  ),
                ),
                onPressed: _busy ? null : _signInWithAdminToken,
                child: const Text(
                  'Sign in',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
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
