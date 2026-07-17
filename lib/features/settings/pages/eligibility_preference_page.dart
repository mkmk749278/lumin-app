/// Per-user trade-eligibility pickers — which evaluator **paths** and
/// which market **regimes** are allowed to auto-trade live for this user.
///
/// These are the path/regime analogues of the Symbol picker
/// (``symbol_preference_page.dart``) and share its doctrine:
///
/// * Default (no selection) = ALL paths / ALL regimes eligible — every
///   live-tier signal the engine fires is potentially executable.
/// * Custom = the user narrows to a chosen subset.
/// * Block all = explicit empty list — no signal of that dimension
///   auto-trades (signals still show in Pulse / Signals).
///
/// The selectable universe is supplied BY THE ENGINE
/// (``AutoTradeRuntimeStatus.allowedPaths`` / ``.regimeOptions``) so the
/// app can never drift from the engine's actual SetupClass / regime
/// vocabulary.  Save path: PUT ``/api/settings/user/auto-trade`` with the
/// ``path_preference`` / ``regime_preference`` field populated (list),
/// emptied (``[]`` = block all) or nulled (reset to all).
///
/// Scope (2026-06-20): each dimension has an independent LIVE and PAPER
/// selection.  The LIVE triple (``path_preference`` / ``regime_preference``)
/// filters real-order dispatch; the PAPER triple
/// (``paper_path_preference`` / ``paper_regime_preference``) filters the
/// per-user paper-book simulation.  ``EligibilityScope`` picks which set a
/// picker instance edits — same widget, different wire fields.
library;

import 'package:flutter/material.dart';

import '../../../data/api_client.dart';
import '../../../data/app_config.dart';
import '../../../data/repository.dart';
import '../../../data/server_side_execution_models.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/lumin_card.dart';

/// Which eligibility dimension a picker instance edits.
enum EligibilityDimension { path, regime }

/// Whether a picker edits the LIVE or PAPER eligibility set.
enum EligibilityScope { live, paper }

enum _Preset { all, custom, blockAll }

/// Picker for the evaluator-path eligibility list (LIVE dispatch).
class PathPreferencePage extends StatelessWidget {
  const PathPreferencePage({super.key});

  @override
  Widget build(BuildContext context) => const _EligibilityPickerPage(
        dimension: EligibilityDimension.path,
        scope: EligibilityScope.live,
      );
}

/// Picker for the entry-regime eligibility list (LIVE dispatch).
class RegimePreferencePage extends StatelessWidget {
  const RegimePreferencePage({super.key});

  @override
  Widget build(BuildContext context) => const _EligibilityPickerPage(
        dimension: EligibilityDimension.regime,
        scope: EligibilityScope.live,
      );
}

/// Picker for the evaluator-path eligibility list (PAPER simulation).
class PaperPathPreferencePage extends StatelessWidget {
  const PaperPathPreferencePage({super.key});

  @override
  Widget build(BuildContext context) => const _EligibilityPickerPage(
        dimension: EligibilityDimension.path,
        scope: EligibilityScope.paper,
      );
}

/// Picker for the entry-regime eligibility list (PAPER simulation).
class PaperRegimePreferencePage extends StatelessWidget {
  const PaperRegimePreferencePage({super.key});

  @override
  Widget build(BuildContext context) => const _EligibilityPickerPage(
        dimension: EligibilityDimension.regime,
        scope: EligibilityScope.paper,
      );
}

class _EligibilityPickerPage extends StatefulWidget {
  const _EligibilityPickerPage({required this.dimension, required this.scope});

  final EligibilityDimension dimension;
  final EligibilityScope scope;

  @override
  State<_EligibilityPickerPage> createState() => _EligibilityPickerPageState();
}

class _EligibilityPickerPageState extends State<_EligibilityPickerPage> {
  bool _loaded = false;
  bool _saving = false;
  String? _loadError;

  List<String> _universe = const [];
  Set<String> _selected = {};
  _Preset _preset = _Preset.all;

  bool get _isPath => widget.dimension == EligibilityDimension.path;

  bool get _isPaper => widget.scope == EligibilityScope.paper;

  String get _title {
    final dim = _isPath ? 'Path preference' : 'Regime preference';
    return _isPaper ? 'Paper $dim' : dim;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) _load();
  }

  /// Pull the option-universe (engine-supplied) + the current stored
  /// preference, in parallel.
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
      final universe = List<String>.from(
        _isPath ? runtime.allowedPaths : runtime.regimeOptions,
      );
      universe.sort();
      final stored = _isPaper
          ? (_isPath
              ? settings.paperPathPreference
              : settings.paperRegimePreference)
          : (_isPath ? settings.pathPreference : settings.regimePreference);
      setState(() {
        _universe = universe;
        if (stored == null) {
          _preset = _Preset.all;
          _selected = universe.toSet();
        } else if (stored.isEmpty) {
          _preset = _Preset.blockAll;
          _selected = <String>{};
        } else {
          _preset = _Preset.custom;
          // Regimes are stored on the wire as backend labels (TRENDING_UP…)
          // but the UI universe is the bucket tokens (TRENDING…); fold the
          // stored value back onto the bucket so the chips reflect it.
          _selected = _foldStoredOntoUniverse(stored, universe);
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

  /// Map stored tokens onto the displayed universe.  Paths match 1:1.
  /// Regimes: a stored backend label maps onto its UI bucket so a
  /// previously-saved selection lights the right chips.
  Set<String> _foldStoredOntoUniverse(List<String> stored, List<String> universe) {
    if (_isPath) return stored.toSet();
    const backendToBucket = <String, String>{
      'TRENDING_UP': 'TRENDING',
      'TRENDING_DOWN': 'TRENDING',
      'RANGING': 'RANGING',
      'VOLATILE': 'CHOPPY',
      'QUIET': 'CHOPPY',
    };
    final out = <String>{};
    for (final tok in stored) {
      final upper = tok.toUpperCase();
      final bucket = backendToBucket[upper] ?? upper;
      if (universe.contains(bucket)) out.add(bucket);
    }
    return out;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final repo = AppConfigScope.of(context).repo;

    // Resolve the wire value from the preset.
    //   All       → null   (clear the row → all eligible)
    //   Block all → []      (explicit nothing)
    //   Custom    → the selected list
    final List<String>? value = _preset == _Preset.all
        ? null
        : _preset == _Preset.blockAll
            ? const <String>[]
            : (_selected.toList()..sort());

    final partial = _isPaper
        ? (_isPath
            ? AutoTradeSettings(
                paperPathPreference: value, paperPathPreferenceSet: true)
            : AutoTradeSettings(
                paperRegimePreference: value, paperRegimePreferenceSet: true))
        : (_isPath
            ? AutoTradeSettings(pathPreference: value, pathPreferenceSet: true)
            : AutoTradeSettings(
                regimePreference: value, regimePreferenceSet: true));

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

  /// Humanise a raw token for display while storing the raw value.
  String _pretty(String token) {
    if (!_isPath) {
      // TRENDING / RANGING / CHOPPY → Trending / Ranging / Choppy.
      final lower = token.toLowerCase();
      return lower.isEmpty ? token : '${lower[0].toUpperCase()}${lower.substring(1)}';
    }
    return token
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
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
          else ...[
            // Reset selection to engine default (all eligible).  Always
            // visible so it's discoverable; sets the preset to "All" then
            // the user saves.
            IconButton(
              icon: const Icon(Icons.restart_alt),
              tooltip: 'Reset to all (default)',
              onPressed: _loaded && _loadError == null
                  ? () => setState(() {
                        _preset = _Preset.all;
                        _selected = _universe.toSet();
                      })
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _loaded && _loadError == null ? _save : null,
              tooltip: 'Save',
            ),
          ],
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
              const Icon(Icons.cloud_off, color: LuminColors.textMuted, size: 36),
              const SizedBox(height: LuminSpacing.md),
              Text(
                'Could not load $_title',
                style: const TextStyle(
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

  Widget _doctrineNote() {
    final act = _isPaper ? 'paper-trade in simulation' : 'place live orders';
    final body = _isPath
        ? 'Choose which signal setups may $act for you — '
            'the path version of the symbol picker.  The engine offers '
            '${_universe.length} active paths.  Leaving this on "All" means '
            'every eligible signal is included.'
        : 'Choose which market regimes may $act for you.  '
            'Trending = momentum continuation; Ranging = rotation between '
            'levels; Choppy = volatile/quiet.  "All" means every regime is '
            'eligible.';
    return LuminCard(
      padding: const EdgeInsets.all(LuminSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_isPath ? Icons.account_tree_outlined : Icons.show_chart,
                  size: 16, color: LuminColors.textSecondary),
              const SizedBox(width: LuminSpacing.sm),
              Text(
                _isPath
                    ? 'WHICH PATHS AUTO-TRADE FOR YOU'
                    : 'WHICH REGIMES AUTO-TRADE FOR YOU',
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
            body,
            style: const TextStyle(
              color: LuminColors.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _presetCard() => LuminCard(
        padding: const EdgeInsets.all(LuminSpacing.sm),
        child: Column(
          children: [
            _presetRow(
              preset: _Preset.all,
              icon: Icons.all_inclusive,
              label: _isPath ? 'All paths' : 'All regimes',
              subtitle: 'Recommended — every eligible signal can auto-trade.',
            ),
            const Divider(color: LuminColors.cardBorder, height: 1, indent: 56),
            _presetRow(
              preset: _Preset.custom,
              icon: Icons.tune,
              label: 'Custom',
              subtitle: _isPath ? 'Pick specific paths below.' : 'Pick specific regimes below.',
            ),
            const Divider(color: LuminColors.cardBorder, height: 1, indent: 56),
            _presetRow(
              preset: _Preset.blockAll,
              icon: Icons.block,
              label: 'Block all (opt-out)',
              subtitle: 'None auto-trade for you. Signals still appear in '
                  'Pulse / Signals.',
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
      onTap: () => _applyPreset(preset),
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
                      color: destructive ? LuminColors.loss : LuminColors.textPrimary,
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
                if (v != null) _applyPreset(v);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _applyPreset(_Preset preset) {
    setState(() {
      _preset = preset;
      if (preset == _Preset.all) {
        _selected = _universe.toSet();
      } else if (preset == _Preset.blockAll) {
        _selected = <String>{};
      }
      // Custom keeps the existing selection.
    });
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
                'Tap to toggle (${_selected.length}/${_universe.length})',
                style: const TextStyle(
                  color: LuminColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _selected = _universe.toSet()),
                child: const Text('Select all', style: TextStyle(fontSize: 11)),
              ),
              TextButton(
                onPressed: () => setState(() => _selected = <String>{}),
                child: const Text('Clear', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.sm),
          if (_universe.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: LuminSpacing.sm),
              child: Text(
                'No options reported by the engine yet — pull to retry from '
                'the previous screen.',
                style: TextStyle(color: LuminColors.textMuted, fontSize: 11),
              ),
            )
          else
            Wrap(
              spacing: LuminSpacing.xs,
              runSpacing: LuminSpacing.xs,
              children: [
                for (final tok in _universe) _chip(tok, _selected.contains(tok)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _chip(String token, bool on) {
    return InkWell(
      onTap: () => setState(() {
        if (on) {
          _selected.remove(token);
        } else {
          _selected.add(token);
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: LuminSpacing.sm,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: on ? LuminColors.accent.withOpacity(0.16) : LuminColors.bgDeep,
          borderRadius: BorderRadius.circular(LuminRadii.pill),
          border: Border.all(
            color: on ? LuminColors.accent.withOpacity(0.60) : LuminColors.cardBorder,
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
              _pretty(token),
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
