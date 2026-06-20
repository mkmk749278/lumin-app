/// Symbol preference picker — per-user choice of which Binance USDT-M
/// pairs are eligible for server-side auto-trade execution.
///
/// Doctrine context (OWNER_BRIEF B18 + engine PR E 2026-05-19):
///
/// * The engine maintains a hard ``TRIPWIRE_SYMBOL_ALLOWLIST`` — that's
///   the rooted-VPS blast-radius floor.  This page CANNOT widen it.
/// * The user picks a subset of that engine cap.  Their choice can
///   only narrow, never widen.
/// * Default (no selection) = all engine-allowed symbols (the
///   "every paid signal is potentially executable" doctrine).
/// * Explicit empty list = "block ALL orders for me" — the strict
///   opt-out path for cautious users.
///
/// Two data sources:
///   * Engine allowlist  — ``AutoTradeRuntimeStatus.allowedSymbols``.
///   * Current preference — ``UserAutoTradeSettings.symbolPreference``.
/// Save path: PUT ``/api/settings/user/auto-trade`` with the
/// ``symbol_preference`` field populated (or null to reset).
library;

import 'package:flutter/material.dart';

import '../../../data/api_client.dart';
import '../../../data/app_config.dart';
import '../../../data/repository.dart';
import '../../../data/server_side_execution_models.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/lumin_card.dart';

import 'eligibility_preference_page.dart' show EligibilityScope;

enum _Preset { all, custom, blockAll }

/// Symbol picker for LIVE-dispatch eligibility (``symbol_preference``).
class SymbolPreferencePage extends StatelessWidget {
  const SymbolPreferencePage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _SymbolPreferenceBody(scope: EligibilityScope.live);
}

/// Symbol picker for PAPER-simulation eligibility
/// (``paper_symbol_preference``) — independent of the live list.
class PaperSymbolPreferencePage extends StatelessWidget {
  const PaperSymbolPreferencePage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _SymbolPreferenceBody(scope: EligibilityScope.paper);
}

class _SymbolPreferenceBody extends StatefulWidget {
  const _SymbolPreferenceBody({required this.scope});

  final EligibilityScope scope;

  @override
  State<_SymbolPreferenceBody> createState() => _SymbolPreferenceBodyState();
}

class _SymbolPreferenceBodyState extends State<_SymbolPreferenceBody> {
  bool get _isPaper => widget.scope == EligibilityScope.paper;

  String get _title =>
      _isPaper ? 'Paper symbol preference' : 'Symbol preference';
  bool _loaded = false;
  bool _saving = false;
  String? _loadError;

  List<String> _engineAllowed = const [];
  Set<String> _selected = {};
  _Preset _preset = _Preset.all;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) _load();
  }

  Future<void> _load() async {
    final repo = AppConfigScope.of(context).repo;
    try {
      final results = await Future.wait([
        repo.getAutoTradeRuntimeStatus(),
        repo.fetchUserAutoTradeSettings(),
      ]);
      if (!mounted) return;
      final runtime = results[0] as AutoTradeRuntimeStatus;
      final settings = results[1] as AutoTradeSettings;
      final allowed = List<String>.from(runtime.allowedSymbols);
      allowed.sort();
      final stored =
          _isPaper ? settings.paperSymbolPreference : settings.symbolPreference;
      setState(() {
        _engineAllowed = allowed;
        if (stored == null) {
          // Server returned no preference → default-all.
          _preset = _Preset.all;
          _selected = allowed.toSet();
        } else if (stored.isEmpty) {
          _preset = _Preset.blockAll;
          _selected = <String>{};
        } else {
          _preset = _Preset.custom;
          _selected = stored.toSet();
        }
        _loaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loaded = true;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final repo = AppConfigScope.of(context).repo;

    // Resolve the payload from the chosen preset.
    //
    // * "All" → send symbol_preference=null so the row clears and
    //   the user falls back to the engine-wide allowlist (handles
    //   future engine-wide widens automatically — they'd otherwise
    //   stay stuck at today's snapshot).
    // * "Custom" → send the explicit selected list.
    // * "Block all" → send the explicit empty list.
    final List<String>? value = _preset == _Preset.all
        ? null
        : _preset == _Preset.blockAll
            ? const <String>[]
            : (_selected.toList()..sort());
    final partial = _isPaper
        ? AutoTradeSettings(
            paperSymbolPreference: value, paperSymbolPreferenceSet: true)
        : AutoTradeSettings(
            symbolPreference: value, symbolPreferenceSet: true);

    try {
      await repo.updateUserAutoTradeSettings(partial);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$_title saved'),
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.of(context).pop();
    } on ApiError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: ${e.message}'),
          backgroundColor: LuminColors.loss,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: LuminColors.loss,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
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
          else
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _loaded && _loadError == null ? _save : null,
              tooltip: 'Save',
            ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
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
                'Could not load symbol list',
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
                    _loaded = false;
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
      padding: const EdgeInsets.all(LuminSpacing.lg),
      children: [
        _doctrineNote(),
        const SizedBox(height: LuminSpacing.md),
        _presetCard(),
        if (_preset == _Preset.custom) ...[
          const SizedBox(height: LuminSpacing.md),
          _customChipsCard(),
        ],
        const SizedBox(height: LuminSpacing.xl),
      ],
    );
  }

  Widget _doctrineNote() => LuminCard(
        padding: const EdgeInsets.all(LuminSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shield_outlined,
                    size: 16, color: LuminColors.textSecondary),
                const SizedBox(width: LuminSpacing.sm),
                Text(
                  _isPaper
                      ? 'WHICH PAIRS PAPER-TRADE FOR YOU'
                      : 'WHICH PAIRS AUTO-TRADE FOR YOU',
                  style: const TextStyle(
                    color: LuminColors.textMuted,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.sm),
            Text(
              _isPaper
                  ? 'Which pairs the engine simulates in your paper book.  '
                      'The engine allowlist holds ${_engineAllowed.length} '
                      'pairs (blast-radius cap); narrow it to focus your '
                      'paper testing.  Independent of your live symbol list.'
                  : 'Lumin executes server-side from the engine VPS.  The '
                      'engine maintains an allowlist of '
                      '${_engineAllowed.length} pairs (blast-radius cap).  '
                      'You can narrow that list — pick which pairs trigger '
                      'orders for your account.  You cannot widen it; that '
                      'needs an operator change for everyone.',
              style: const TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      );

  Widget _presetCard() => LuminCard(
        padding: const EdgeInsets.all(LuminSpacing.sm),
        child: Column(
          children: [
            _presetRow(
              preset: _Preset.all,
              icon: Icons.all_inclusive,
              label: 'All allowed symbols',
              subtitle:
                  'Every pair on the engine allowlist (${_engineAllowed.length}). '
                  'Recommended — you get every paid signal that\'s eligible.',
            ),
            const Divider(
                color: LuminColors.cardBorder, height: 1, indent: 56),
            _presetRow(
              preset: _Preset.custom,
              icon: Icons.tune,
              label: 'Custom',
              subtitle: 'Pick specific pairs below.',
            ),
            const Divider(
                color: LuminColors.cardBorder, height: 1, indent: 56),
            _presetRow(
              preset: _Preset.blockAll,
              icon: Icons.block,
              label: 'Block all (opt-out)',
              subtitle: 'No pairs trigger auto-trade orders for you. '
                  'Signals still appear in Pulse / Signals tabs.',
              destructive: true,
            ),
          ],
        ),
      );

  Widget _presetRow({
    required _Preset preset,
    required IconData icon,
    required String label,
    required String subtitle,
    bool destructive = false,
  }) {
    final accent = destructive ? LuminColors.loss : LuminColors.accent;
    return InkWell(
      onTap: () => setState(() {
        _preset = preset;
        if (preset == _Preset.all) {
          _selected = _engineAllowed.toSet();
        } else if (preset == _Preset.blockAll) {
          _selected = <String>{};
        }
        // Custom keeps whatever the user had selected.
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LuminSpacing.md,
          vertical: LuminSpacing.md,
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.10),
                borderRadius: BorderRadius.circular(LuminRadii.sm),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: LuminSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: destructive
                          ? LuminColors.loss
                          : LuminColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: LuminColors.textSecondary,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Radio<_Preset>(
              value: preset,
              groupValue: _preset,
              activeColor: accent,
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _preset = v;
                    if (v == _Preset.all) {
                      _selected = _engineAllowed.toSet();
                    } else if (v == _Preset.blockAll) {
                      _selected = <String>{};
                    }
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _customChipsCard() {
    return LuminCard(
      padding: const EdgeInsets.all(LuminSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Tap to toggle (${_selected.length}/${_engineAllowed.length})',
                style: const TextStyle(
                  color: LuminColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    setState(() => _selected = _engineAllowed.toSet()),
                child: const Text('Select all',
                    style: TextStyle(fontSize: 11)),
              ),
              TextButton(
                onPressed: () => setState(() => _selected = <String>{}),
                child: const Text('Clear',
                    style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.sm),
          Wrap(
            spacing: LuminSpacing.xs,
            runSpacing: LuminSpacing.xs,
            children: [
              for (final sym in _engineAllowed)
                _symbolChip(sym, _selected.contains(sym)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _symbolChip(String symbol, bool on) {
    return InkWell(
      onTap: () => setState(() {
        if (on) {
          _selected.remove(symbol);
        } else {
          _selected.add(symbol);
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: LuminSpacing.sm,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: on
              ? LuminColors.accent.withOpacity(0.16)
              : LuminColors.bgDeep,
          borderRadius: BorderRadius.circular(LuminRadii.pill),
          border: Border.all(
            color: on
                ? LuminColors.accent.withOpacity(0.60)
                : LuminColors.cardBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (on) ...[
              const Icon(Icons.check, size: 12, color: LuminColors.accent),
              const SizedBox(width: 4),
            ],
            Text(
              symbol,
              style: TextStyle(
                color: on ? LuminColors.accent : LuminColors.textSecondary,
                fontSize: 11,
                fontWeight: on ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
