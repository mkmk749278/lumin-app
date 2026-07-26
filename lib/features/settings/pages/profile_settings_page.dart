/// Profile — edit the user's signup data (name / country / currency /
/// timezone).  GETs ``/api/profile`` on init, PUTs partial updates on
/// Save.  Mirrors the Phase-1 SignupPage layout but as an edit view
/// (no terms re-prompt, since they were accepted at signup).
import 'package:flutter/material.dart';

import '../../../data/app_config.dart';
import '../../../data/country_codes.dart';
import '../../../data/repository.dart';
import '../../../shared/format.dart';
import '../../../shared/platform_input.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/free_tier_gate.dart';
import '../../../shared/widgets/lumin_card.dart';
import 'subscription_page.dart';

class ProfileSettingsPage extends StatefulWidget {
  const ProfileSettingsPage({super.key});

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  Profile? _profile;
  final _nameCtl = TextEditingController();
  CountryCode? _country;
  String? _currency;
  bool _loading = true;
  String? _loadError;
  bool _saving = false;
  bool _dirty = false;

  static const _commonCurrencies = <String>[
    'USD', 'EUR', 'GBP', 'AUD', 'NZD', 'CAD', 'CHF',
    'JPY', 'CNY', 'HKD', 'SGD', 'MYR', 'INR', 'IDR', 'THB',
    'PHP', 'VND', 'KRW', 'TWD',
    'AED', 'SAR', 'ILS', 'TRY', 'ZAR', 'BRL', 'MXN', 'ARS',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final scope = AppConfigScope.of(context);
    try {
      final p = await scope.repo.fetchProfile();
      // Keep the app-wide entitlement cache in lockstep with what this
      // page renders — a Profile visit doubles as a tier refresh.
      scope.auth?.cacheEngineMetadata(
        userId: p.userId,
        tier: p.tier,
        paidUntil: p.paidUntil,
        needsOnboarding: p.needsOnboarding,
        displayName: p.displayName,
      );
      if (!mounted) return;
      setState(() {
        _profile = p;
        _nameCtl.text = p.displayName ?? '';
        _country = (p.countryCode != null
                ? lookupCountry(p.countryCode!)
                : null) ??
            (p.phoneE164 != null ? countryForE164(p.phoneE164!) : null);
        _currency = p.currency ?? currencyForCountry(_country?.iso2);
        _loading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError =
            'Check your connection and try again in a moment.';
      });
    }
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
      builder: (_) => _PickerSheet<CountryCode>(
        title: 'Country',
        items: kCountryCodes,
        labelOf: (c) => c.name,
        leadingOf: (c) =>
            Text(c.flag, style: const TextStyle(fontSize: 20)),
        trailingOf: (c) => Text('+${c.dial}',
            style: const TextStyle(
                color: LuminColors.textMuted, fontSize: 13)),
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
        _dirty = true;
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
      builder: (_) => _PickerSheet<String>(
        title: 'Display currency',
        items: _commonCurrencies,
        labelOf: (c) => c,
        isSelected: (c) => c == _currency,
        filter: (c, q) => c.toLowerCase().contains(q),
      ),
    );
    if (pick != null && mounted) {
      setState(() {
        _currency = pick;
        _dirty = true;
      });
    }
  }

  Future<void> _save() async {
    if (_saving || !_dirty) return;
    final repo = AppConfigScope.of(context).repo;
    setState(() => _saving = true);
    try {
      final partial = Profile(
        displayName: _nameCtl.text.trim().isEmpty ? null : _nameCtl.text.trim(),
        countryCode: _country?.iso2,
        timezone: DateTime.now().timeZoneName,
        currency: _currency,
      );
      final saved = await repo.updateProfile(partial);
      if (!mounted) return;
      setState(() {
        _profile = saved;
        _saving = false;
        _dirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile saved'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_dirty)
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Save',
              onPressed: _save,
            ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(LuminSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off,
                  color: LuminColors.textMuted, size: 36),
              const SizedBox(height: LuminSpacing.md),
              const Text(
                'Could not load profile',
                style: TextStyle(
                  color: LuminColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: LuminColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: LuminSpacing.md),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _loadError = null;
                  });
                  _load();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        const SizedBox(height: LuminSpacing.md),
        _phoneRow(),
        const SizedBox(height: LuminSpacing.md),
        _subscriptionCard(),
        const SizedBox(height: LuminSpacing.md),
        _displayNameCard(),
        const SizedBox(height: LuminSpacing.md),
        _pickerRow(
          label: 'COUNTRY',
          leading: _country == null
              ? null
              : Text(_country!.flag,
                  style: const TextStyle(fontSize: 20)),
          title: _country?.name ?? 'Pick a country',
          subtitle: _country == null ? null : 'Dial +${_country!.dial}',
          onTap: _saving ? null : _openCountryPicker,
        ),
        const SizedBox(height: LuminSpacing.md),
        _pickerRow(
          label: 'DISPLAY CURRENCY',
          title: _currency ?? 'USD',
          subtitle: 'Shown alongside USD values on Pulse / Trade',
          onTap: _saving ? null : _openCurrencyPicker,
        ),
        const SizedBox(height: LuminSpacing.xl),
      ],
    );
  }

  Widget _phoneRow() {
    final p = _profile;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Row(
          children: [
            const Icon(Icons.phone_outlined,
                color: LuminColors.textMuted, size: 18),
            const SizedBox(width: LuminSpacing.md),
            Expanded(
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
                  const SizedBox(height: 2),
                  Text(
                    p?.phoneE164 ?? '—',
                    style: const TextStyle(
                      color: LuminColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The user's plan, stated plainly.  Replaces the old unlabeled
  /// "AUTO" pill on the phone row that paying subscribers didn't
  /// recognise as their subscription status (owner screenshots,
  /// 2026-07-17).  Taps through to the Subscription page.
  Widget _subscriptionCard() {
    final p = _profile;
    final paid = isPaidTier(p?.tier);
    final renewal = formatPaidUntil(p?.paidUntil);
    final title = paid
        ? '${tierDisplayName(p?.tier)} plan — active'
        : 'Free plan';
    final subtitle = paid
        ? (renewal != null
            ? 'Renews via Google Play · paid until $renewal'
            : 'Renews via Google Play')
        : 'Upgrade to automate your trades';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: InkWell(
          borderRadius: BorderRadius.circular(LuminRadii.md),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<bool>(
              builder: (_) => const SubscriptionPage(),
            ),
          ),
          child: Row(
            children: [
              Icon(
                paid ? Icons.verified_rounded : Icons.workspace_premium_outlined,
                color: paid ? LuminColors.success : LuminColors.textMuted,
                size: 18,
              ),
              const SizedBox(width: LuminSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SUBSCRIPTION',
                      style: TextStyle(
                        color: LuminColors.textMuted,
                        fontSize: 10,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: TextStyle(
                        color: paid
                            ? LuminColors.success
                            : LuminColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: LuminColors.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: LuminColors.textMuted, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _displayNameCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
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
            TextField(
              controller: _nameCtl,
              textCapitalization: TextCapitalization.words,
              maxLength: 64,
              onChanged: (_) {
                if (!_dirty) setState(() => _dirty = true);
              },
              style: const TextStyle(
                  color: LuminColors.textPrimary, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'How should we address you?',
                counterText: '',
                hintStyle: const TextStyle(
                    color: LuminColors.textMuted, fontSize: 15),
                filled: true,
                fillColor: LuminColors.bgElevated,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: LuminSpacing.md,
                    vertical: LuminSpacing.md),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(LuminRadii.sm),
                  borderSide:
                      const BorderSide(color: LuminColors.cardBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(LuminRadii.sm),
                  borderSide:
                      const BorderSide(color: LuminColors.accent),
                ),
              ),
            ),
          ],
        ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
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
                    vertical: LuminSpacing.md),
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
                    const Icon(Icons.keyboard_arrow_down,
                        color: LuminColors.textMuted, size: 18),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
        : widget.items
            .where((c) => widget.filter(c, q))
            .toList(growable: false);
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
            padding:
                const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
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
            padding:
                const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
            child: TextField(
              autofocus: kAutofocusTextFields,
              decoration: InputDecoration(
                hintText: 'Search',
                hintStyle: const TextStyle(
                    color: LuminColors.textMuted, fontSize: 14),
                prefixIcon: const Icon(Icons.search,
                    color: LuminColors.textMuted, size: 18),
                filled: true,
                fillColor: LuminColors.bgElevated,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: LuminSpacing.sm),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(LuminRadii.sm),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(
                  color: LuminColors.textPrimary, fontSize: 14),
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
                        if (widget.trailingOf != null) widget.trailingOf!(c),
                        if (selected) ...[
                          const SizedBox(width: LuminSpacing.sm),
                          const Icon(Icons.check,
                              color: LuminColors.accent, size: 18),
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
