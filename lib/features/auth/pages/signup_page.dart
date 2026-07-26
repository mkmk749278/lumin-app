/// Signup — Phase 3 onboarding form.
///
/// Pushed by [OtpEntryPage] when the engine reports
/// ``needs_onboarding=true`` on the verify-otp response.  Collects:
///
///   * Display name (required)
///   * Country (defaulted from the phone E.164 prefix; editable picker)
///   * Currency (defaulted from country; common ISO 4217 picker)
///   * Terms acceptance (required)
///
/// Timezone isn't user-facing here — we send the device default and
/// let the user edit it later from Settings → Profile if they want.
/// Most users will never touch it; keeping the signup form short
/// matters more.
///
/// "Get started" → ``PUT /api/profile`` → ``AuthService.markOnboarded``
/// → replace stack with NavShell.
import 'package:flutter/material.dart';

import '../../../app/nav_shell.dart';
import '../../../data/app_config.dart';
import '../../../data/country_codes.dart';
import '../../../data/repository.dart';
import '../../../shared/platform_input.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/lumin_card.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({
    super.key,
    required this.phoneE164,
    this.countryHint,
  });

  /// The phone number the user verified with — shown back to them as
  /// confirmation ("Signed in as +14155551234").
  final String phoneE164;

  /// Country chip picked on PhoneSignInPage.  Forwarded so the user
  /// doesn't have to re-confirm the same country here unless they
  /// want to change it.  Null forces re-detection from the phone
  /// prefix below.
  final CountryCode? countryHint;

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtl = TextEditingController();
  final _referralCtl = TextEditingController();
  CountryCode? _country;
  String _currency = 'USD';
  bool _acceptTerms = false;
  bool _busy = false;
  String? _error;

  static const _commonCurrencies = <String>[
    'USD', 'EUR', 'GBP', 'AUD', 'NZD', 'CAD', 'CHF',
    'JPY', 'CNY', 'HKD', 'SGD', 'MYR', 'INR', 'IDR', 'THB',
    'PHP', 'VND', 'KRW', 'TWD',
    'AED', 'SAR', 'ILS', 'TRY', 'ZAR', 'BRL', 'MXN', 'ARS',
  ];

  @override
  void initState() {
    super.initState();
    _country = widget.countryHint ?? countryForE164(widget.phoneE164);
    _currency = currencyForCountry(_country?.iso2);
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _referralCtl.dispose();
    super.dispose();
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
      builder: (ctx) => _PickerSheet<CountryCode>(
        title: 'Country',
        items: kCountryCodes,
        labelOf: (c) => c.name,
        leadingOf: (c) => Text(c.flag, style: const TextStyle(fontSize: 20)),
        trailingOf: (c) => Text(
          '+${c.dial}',
          style:
              const TextStyle(color: LuminColors.textMuted, fontSize: 13),
        ),
        isSelected: (c) => c.iso2 == _country?.iso2,
        filter: (c, q) =>
            c.iso2.toLowerCase().contains(q) ||
            c.dial.contains(q) ||
            c.name.toLowerCase().contains(q),
      ),
    );
    if (pick != null && mounted) {
      setState(() {
        _country = pick;
        _currency = currencyForCountry(pick.iso2);
      });
    }
  }

  Future<void> _openCurrencyPicker() async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: LuminColors.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(LuminRadii.lg)),
      ),
      builder: (ctx) => _PickerSheet<String>(
        title: 'Display currency',
        items: _commonCurrencies,
        labelOf: (c) => c,
        isSelected: (c) => c == _currency,
        filter: (c, q) => c.toLowerCase().contains(q),
      ),
    );
    if (pick != null && mounted) {
      setState(() => _currency = pick);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_acceptTerms) {
      setState(() => _error = 'Please accept the terms to continue.');
      return;
    }
    final scope = AppConfigScope.of(context);
    final repo = scope.repo;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final partial = Profile(
        displayName: _nameCtl.text.trim(),
        countryCode: _country?.iso2 ?? 'US',
        timezone: DateTime.now().timeZoneName,
        currency: _currency,
      );
      await repo.updateProfile(partial, acceptTerms: true);
      final referral = _referralCtl.text.trim();
      var discountUnlocked = false;
      if (referral.isNotEmpty) {
        // Best-effort: a stale/garbled invite code never blocks signup.
        try {
          final claim = await repo.claimReferralCode(referral);
          discountUnlocked = claim.ok && claim.discountEligible;
        } catch (_) {}
      }
      await scope.auth?.markOnboarded();
      scope.auth?.cacheDisplayName(_nameCtl.text.trim());
      if (!mounted) return;
      if (discountUnlocked) {
        // Engine-confirmed (referral Phase 2): tell them the 50%-off
        // first month is waiting on the Subscription page.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Invite code accepted — 50% off your first month of any '
              'plan is unlocked.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const NavShell()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Couldn\'t save profile: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LuminColors.bgDeep,
      // No back button: the user has already verified their phone; the
      // signin pages above are gone (pushAndRemoveUntil).  They can
      // sign out from Settings → API keys if they really want to start
      // over, but signing out then back in with the same phone lands
      // here again until they finish.
      appBar: AppBar(
        backgroundColor: LuminColors.bgDeep,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: LuminSpacing.lg,
            vertical: LuminSpacing.md,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Welcome to Lumin',
                  style: TextStyle(
                    color: LuminColors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: LuminSpacing.sm),
                Text(
                  'Signed in as ${widget.phoneE164}.\n'
                  'A few quick details and we\'re done.',
                  style: const TextStyle(
                    color: LuminColors.textSecondary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: LuminSpacing.xl),
                _displayNameCard(),
                const SizedBox(height: LuminSpacing.md),
                _countryCard(),
                const SizedBox(height: LuminSpacing.md),
                _currencyCard(),
                const SizedBox(height: LuminSpacing.md),
                _termsCard(),
                const SizedBox(height: LuminSpacing.md),
                _referralCard(),
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
                          'Get started',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                const SizedBox(height: LuminSpacing.md),
                const Text(
                  'You can change any of these later from '
                  'Menu → Profile.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: LuminColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _displayNameCard() {
    return LuminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DISPLAY NAME',
            style: TextStyle(
              color: LuminColors.textMuted,
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: LuminSpacing.sm),
          TextFormField(
            controller: _nameCtl,
            autofocus: kAutofocusTextFields,
            textCapitalization: TextCapitalization.words,
            maxLength: 64,
            validator: (raw) {
              final s = raw?.trim() ?? '';
              if (s.isEmpty) return 'How should we address you?';
              if (s.length < 2) return 'A little longer please';
              return null;
            },
            style: const TextStyle(
              color: LuminColors.textPrimary,
              fontSize: 15,
            ),
            decoration: _inputDecoration('e.g. Alex'),
          ),
        ],
      ),
    );
  }

  Widget _countryCard() {
    final c = _country;
    return _pickerRow(
      label: 'COUNTRY',
      leading: c == null ? null : Text(c.flag, style: const TextStyle(fontSize: 20)),
      title: c?.name ?? 'Pick a country',
      subtitle: c == null ? null : 'Dial +${c.dial}',
      onTap: _busy ? null : _openCountryPicker,
    );
  }

  Widget _currencyCard() {
    return _pickerRow(
      label: 'DISPLAY CURRENCY',
      title: _currency,
      subtitle: 'Shown alongside USD values on Pulse / Trade',
      onTap: _busy ? null : _openCurrencyPicker,
    );
  }

  Widget _termsCard() {
    return LuminCard(
      child: InkWell(
        onTap: _busy ? null : () => setState(() => _acceptTerms = !_acceptTerms),
        borderRadius: BorderRadius.circular(LuminRadii.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _acceptTerms,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _acceptTerms = v ?? false),
              activeColor: LuminColors.accent,
              checkColor: LuminColors.bgDeep,
            ),
            const SizedBox(width: LuminSpacing.xs),
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'I understand that crypto trading carries substantial '
                  'risk and that past signal performance does not '
                  'guarantee future results.',
                  style: TextStyle(
                    color: LuminColors.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _referralCard() {
    return LuminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'INVITE CODE (OPTIONAL)',
            style: TextStyle(
              color: LuminColors.textMuted,
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: LuminSpacing.sm),
          TextFormField(
            controller: _referralCtl,
            textCapitalization: TextCapitalization.characters,
            maxLength: 16,
            style: const TextStyle(
              color: LuminColors.textPrimary,
              fontSize: 15,
            ),
            decoration: _inputDecoration('Have a friend\'s code?'),
          ),
          const SizedBox(height: LuminSpacing.xs),
          // Referral Phase 2 (2026-07-21): the code is worth real money
          // to both sides — say so, or nobody types it.
          const Text(
            'A friend\'s code gets you 50% off your first month of any '
            'plan — and gives them free Auto days.',
            style: TextStyle(
              color: LuminColors.textMuted,
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pickerRow({
    required String label,
    required String title,
    String? subtitle,
    Widget? leading,
    VoidCallback? onTap,
  }) {
    return LuminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: LuminColors.textMuted,
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: LuminSpacing.sm),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(LuminRadii.sm),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: LuminSpacing.md,
                vertical: LuminSpacing.md,
              ),
              decoration: BoxDecoration(
                color: LuminColors.bgElevated,
                borderRadius: BorderRadius.circular(LuminRadii.sm),
                border: Border.all(color: LuminColors.cardBorder),
              ),
              child: Row(
                children: [
                  if (leading != null) ...[
                    leading,
                    const SizedBox(width: LuminSpacing.md),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: LuminColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: LuminColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    color: LuminColors.textMuted,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ],
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

/// Generic picker bottom sheet used for both country and currency lists
/// on SignupPage.  Trades a tiny bit of generics ceremony for a single
/// renderer instead of copy-pasting the layout twice.
class _PickerSheet<T> extends StatefulWidget {
  const _PickerSheet({
    required this.title,
    required this.items,
    required this.labelOf,
    required this.isSelected,
    required this.filter,
    this.leadingOf,
    this.trailingOf,
  });

  final String title;
  final List<T> items;
  final String Function(T) labelOf;
  final bool Function(T) isSelected;
  final bool Function(T, String query) filter;
  final Widget Function(T)? leadingOf;
  final Widget Function(T)? trailingOf;

  @override
  State<_PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T> extends State<_PickerSheet<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.items
        : widget.items.where((c) => widget.filter(c, q)).toList(growable: false);
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
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: LuminColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: LuminSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
            child: TextField(
              autofocus: kAutofocusTextFields,
              decoration: InputDecoration(
                hintText: 'Search',
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
                final selected = widget.isSelected(c);
                return InkWell(
                  onTap: () => Navigator.of(context).pop(c),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LuminSpacing.lg,
                      vertical: LuminSpacing.md,
                    ),
                    child: Row(
                      children: [
                        if (widget.leadingOf != null) ...[
                          widget.leadingOf!(c),
                          const SizedBox(width: LuminSpacing.md),
                        ],
                        Expanded(
                          child: Text(
                            widget.labelOf(c),
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
                        if (widget.trailingOf != null)
                          widget.trailingOf!(c),
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
