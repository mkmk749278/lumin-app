/// Single Live-tab auto-trade status surface (2026-07-17 redesign).
///
/// Replaces the pre-redesign stack of `_AutoTradeDisabledBanner` +
/// `_AutoPauseBanner` + `_AutoTradeArmedCard`: one card, one verdict,
/// one next step.  The full truthful gate list survives behind a
/// Details expander — friendlier language, zero hidden problems (the
/// armed verdict is computed by [resolveLiveStatus], byte-identical to
/// the old card's expression).
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/app_config.dart';
import '../../data/legal_urls.dart';
import '../../data/repository.dart' show AutoTradeSettings;
import '../../data/server_side_execution_models.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/lumin_card.dart';
import '../settings/pages/server_side_execution_page.dart';
import '../settings/pages/subscription_page.dart';
import '../settings/pages/symbol_preference_page.dart';
import '../settings/pages/auto_trade_settings_page.dart';
import 'live_status_resolver.dart';

class LiveStatusCard extends StatefulWidget {
  const LiveStatusCard({
    super.key,
    required this.runtime,
    required this.userStatus,
    required this.userSettings,
    required this.onResumed,
  });

  final AutoTradeRuntimeStatus runtime;
  final AutoTradeUserStatus? userStatus;
  final AutoTradeSettings userSettings;

  /// Called after a successful Resume so the parent refreshes its
  /// streams (mirrors the old `_AutoPauseBanner.onResumed` contract).
  final Future<void> Function() onResumed;

  @override
  State<LiveStatusCard> createState() => _LiveStatusCardState();
}

class _LiveStatusCardState extends State<LiveStatusCard> {
  bool _expanded = false;
  bool _resuming = false;
  bool _reenabling = false;

  LiveStatus get _status => resolveLiveStatus(
        runtime: widget.runtime,
        userStatus: widget.userStatus,
        userSettings: widget.userSettings,
      );

  // ---- reason → copy + action -----------------------------------------

  String _title(LiveBlockReason r) => switch (r) {
        LiveBlockReason.userDisabled => 'Trading paused on your account',
        LiveBlockReason.autoPaused =>
          widget.userSettings.pausedReason == 'insufficient_margin'
              ? 'Paused — Futures wallet is empty'
              : 'Paused on your account',
        LiveBlockReason.globalOff => 'Trading briefly paused for everyone',
        LiveBlockReason.statusUnknown => 'We can\'t confirm your trading status',
        LiveBlockReason.keyNotConnected => 'Connect your Binance account',
        LiveBlockReason.keyStatusUnknown =>
          'We can\'t confirm your Binance connection',
        LiveBlockReason.modeOff => 'Live trading is switched off',
        LiveBlockReason.tierBlocked => 'Auto plan needed for hands-off trading',
        LiveBlockReason.filtersBlockAll => 'Your filters exclude every signal',
      };

  String _body(LiveBlockReason r) => switch (r) {
        LiveBlockReason.userDisabled =>
          'A safety check stopped orders on your account after repeated '
              'failures. Fix the cause shown in your activity below, then '
              're-enable trading. If it keeps happening, email support.',
        LiveBlockReason.autoPaused =>
          widget.userSettings.pausedReason == 'insufficient_margin'
              ? 'Your Binance Futures wallet doesn\'t have enough USDT for '
                  'your position size. Top it up, then tap Resume.'
              : 'Lumin paused placing orders for you. Fix the underlying '
                  'issue, then tap Resume.',
        LiveBlockReason.globalOff =>
          'A safety pause is active for all accounts. No action needed — '
              'trading resumes automatically.',
        // Deliberately promises no automatic resume and names no cause.
        // Until 2026-09-02 this state was rendered with the sentence above:
        // a subscriber whose orders had stopped because a Firestore read was
        // failing was told to sit and wait for a resume that was never
        // coming, while their capital sat idle behind nothing at all.
        LiveBlockReason.statusUnknown =>
          'Orders are paused because we couldn\'t reach the service that '
              'confirms your trading status. Nothing is wrong with your '
              'account and nothing is needed from you — but this will not '
              'clear on its own, so contact support if it lasts.',
        LiveBlockReason.keyNotConnected =>
          'Link a Binance API key so Lumin can place and manage trades '
              'for you. Takes about two minutes.',
        // The owner saw "Connect your Binance account" over an account whose
        // key was connected. Telling somebody to redo finished work on the
        // screen that spends their money is worse than saying nothing.
        LiveBlockReason.keyStatusUnknown =>
          'We couldn\'t check whether your Binance key is connected. If you '
              'have already added one, don\'t add it again — this is on our '
              'side and should clear shortly. Contact support if it doesn\'t.',
        LiveBlockReason.modeOff =>
          'Flip the Live auto-trade toggle above to start placing real '
              'orders on the next signal.',
        LiveBlockReason.tierBlocked =>
          'Signals stay free — the Auto plan unlocks hands-off '
              'execution on your own Binance account.',
        LiveBlockReason.filtersBlockAll =>
          'Your setup/market filters currently match no signals, so '
              'nothing will ever trade. Loosen them to resume.',
      };

  Widget? _actionButton(LiveBlockReason r) {
    switch (r) {
      case LiveBlockReason.userDisabled:
        // Self-serve recovery (2026-07-18): the primary action clears the
        // breaker via POST /api/auto-trade/resume-disabled-mine (rate-
        // limited server-side); support stays as the escalation path.
        return Wrap(
          spacing: LuminSpacing.sm,
          runSpacing: LuminSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.end,
          children: [
            TextButton.icon(
              onPressed: _emailSupport,
              icon: const Icon(Icons.mail_outline, size: 16),
              label: const Text(
                'Email support',
                style: TextStyle(fontSize: 12),
              ),
            ),
            _button(
              'Re-enable auto-trade',
              Icons.restart_alt_rounded,
              _reenabling ? null : _reenable,
              busy: _reenabling,
            ),
          ],
        );
      case LiveBlockReason.autoPaused:
        return _button(
          'Resume',
          Icons.play_arrow_rounded,
          _resuming ? null : _resume,
          busy: _resuming,
        );
      case LiveBlockReason.keyNotConnected:
        return _button(
          'Connect key',
          Icons.link_rounded,
          () => _push(const ServerSideExecutionPage()),
        );
      case LiveBlockReason.tierBlocked:
        return _button(
          'See plans',
          Icons.workspace_premium_outlined,
          () => _push(const SubscriptionPage()),
        );
      case LiveBlockReason.filtersBlockAll:
        return _button(
          'Adjust filters',
          Icons.tune_rounded,
          () => _push(const AutoTradeSettingsPage()),
        );
      case LiveBlockReason.globalOff:
      case LiveBlockReason.modeOff:
      // Both unknown states offer no button ON PURPOSE. There is nothing the
      // user can do, and the tempting action — "Reconnect key" on
      // keyStatusUnknown — would send them to redo work that may already be
      // done, on the screen that spends their money.
      case LiveBlockReason.statusUnknown:
      case LiveBlockReason.keyStatusUnknown:
        return null; // nothing for the user to do / the toggle is above
    }
  }

  // ---- actions ---------------------------------------------------------

  void _push(Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  Future<void> _emailSupport() async {
    try {
      await launchUrl(
        LegalUrls.supportMailto(subject: 'Re-enable auto-trade'),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Email us at ${LegalUrls.supportEmail}')),
      );
    }
  }

  Future<void> _reenable() async {
    setState(() => _reenabling = true);
    final repo = AppConfigScope.of(context).repo;
    try {
      final result = await repo.resumeDisabledMine();
      if (!mounted) return;
      final String text;
      final Color color;
      if (result.ok) {
        text = result.alreadyEnabled
            ? 'Your account is already active.'
            : 'Auto-trade re-enabled. The next signal will trade.';
        color = LuminColors.success;
      } else {
        // Cooldown refusal — the server's copy says when to retry.
        text = result.message ??
            'Could not re-enable right now — try again later.';
        color = LuminColors.warn;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(text),
          duration: const Duration(seconds: 4),
          backgroundColor: color,
        ),
      );
      if (result.ok) await widget.onResumed();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not re-enable — check your connection and try again.',
          ),
          duration: Duration(seconds: 4),
          backgroundColor: LuminColors.loss,
        ),
      );
    } finally {
      if (mounted) setState(() => _reenabling = false);
    }
  }

  Future<void> _resume() async {
    setState(() => _resuming = true);
    final repo = AppConfigScope.of(context).repo;
    try {
      final cleared = await repo.resumeMineAutoTrade();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cleared
                ? 'Auto-trade resumed. The next signal will trade.'
                : 'Already active — nothing to resume.',
          ),
          duration: const Duration(seconds: 3),
          backgroundColor: LuminColors.success,
        ),
      );
      await widget.onResumed();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not resume — check your connection and try again.',
          ),
          duration: Duration(seconds: 4),
          backgroundColor: LuminColors.loss,
        ),
      );
    } finally {
      if (mounted) setState(() => _resuming = false);
    }
  }

  // ---- build -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final reason = status.reason;
    final Color accent = status.active
        ? LuminColors.success
        : reason == LiveBlockReason.userDisabled
            ? LuminColors.loss
            : LuminColors.warn;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        padding: const EdgeInsets.all(LuminSpacing.md),
        border: Border.all(color: accent.withOpacity(0.45)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  status.active
                      ? Icons.verified_rounded
                      : reason == LiveBlockReason.userDisabled
                          ? Icons.block_rounded
                          : Icons.error_outline_rounded,
                  size: 18,
                  color: accent,
                ),
                const SizedBox(width: LuminSpacing.sm),
                Expanded(
                  child: Text(
                    status.active
                        ? 'Auto-trade active'
                        : (reason != null
                            ? _title(reason)
                            : 'Auto-trade not active'),
                    style: TextStyle(
                      color: accent,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.xs),
            Text(
              status.active
                  ? 'Watching ${status.watchedSymbols} symbols — eligible '
                      'signals place automatically on your Binance account.'
                  : (reason != null
                      ? _body(reason)
                      : 'Live orders can\'t be placed right now — open '
                          'Details below.'),
              style: const TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 12,
                height: 1.45,
              ),
            ),
            if (!status.active && reason != null) ...[
              () {
                final btn = _actionButton(reason);
                return btn == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: LuminSpacing.sm),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: btn,
                        ),
                      );
              }(),
            ],
            const SizedBox(height: LuminSpacing.sm),
            _detailsToggle(),
            if (_expanded) ...[
              const SizedBox(height: LuminSpacing.xs),
              for (final g in status.gates) _gateRow(g),
              if (widget.runtime.binanceKeyConnected &&
                  widget.runtime.allowedSymbols.isNotEmpty) ...[
                const SizedBox(height: LuminSpacing.sm),
                SymbolAllowlistSummary(runtime: widget.runtime),
              ],
              if (!widget.runtime.preferencesBlockAll &&
                  (widget.runtime.pathPreference != null ||
                      widget.runtime.regimePreference != null)) ...[
                const SizedBox(height: LuminSpacing.xs),
                Text(
                  _prefsFootnote(),
                  style: const TextStyle(
                    color: LuminColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _button(
    String label,
    IconData icon,
    VoidCallback? onPressed, {
    bool busy = false,
  }) {
    final status = _status;
    final color = status.reason == LiveBlockReason.userDisabled
        ? LuminColors.loss
        : LuminColors.warn;
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: LuminColors.bgDeep,
        padding: const EdgeInsets.symmetric(
          horizontal: LuminSpacing.lg,
          vertical: LuminSpacing.sm,
        ),
      ),
      onPressed: onPressed,
      icon: busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: LuminColors.bgDeep,
              ),
            )
          : Icon(icon, size: 16),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
      ),
    );
  }

  Widget _detailsToggle() {
    final status = _status;
    final failing = status.gates.where((g) => !g.ok).length;
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      borderRadius: BorderRadius.circular(LuminRadii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(
              _expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: LuminColors.textMuted,
            ),
            const SizedBox(width: 2),
            Text(
              _expanded
                  ? 'Hide details'
                  : failing == 0
                      ? 'Details'
                      : 'Details ($failing to fix)',
              style: const TextStyle(
                color: LuminColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gateRow(LiveGate g) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            g.ok ? Icons.check_circle_outline : Icons.cancel_outlined,
            size: 14,
            color: g.ok ? LuminColors.success : LuminColors.warn,
          ),
          const SizedBox(width: LuminSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  g.label,
                  style: const TextStyle(
                    color: LuminColors.textPrimary,
                    fontSize: 12,
                  ),
                ),
                if (g.hint != null)
                  Text(
                    g.hint!,
                    style: const TextStyle(
                      color: LuminColors.textMuted,
                      fontSize: 10,
                      height: 1.3,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One-line summary of the user's live eligibility filters, e.g.
  /// "Filtered: 3 of 7 setups · 2 market types auto-trade for you."
  String _prefsFootnote() {
    final r = widget.runtime;
    final parts = <String>[];
    final paths = r.pathPreference;
    if (paths != null) {
      final total = r.allowedPaths.length;
      parts.add(
        total > 0
            ? '${paths.length} of $total setups'
            : '${paths.length} setup${paths.length == 1 ? "" : "s"}',
      );
    }
    final regimes = r.regimePreference;
    if (regimes != null) {
      parts.add(
        '${regimes.length} market type${regimes.length == 1 ? "" : "s"}',
      );
    }
    return 'Filtered: ${parts.join(" · ")} auto-trade for you.';
  }
}

/// Compact symbol-allowlist summary (moved from trade_page.dart in the
/// 2026-07-17 redesign; behaviour unchanged).  One line + Edit link to
/// Settings → Symbol preference.
class SymbolAllowlistSummary extends StatelessWidget {
  const SymbolAllowlistSummary({super.key, required this.runtime});

  final AutoTradeRuntimeStatus runtime;

  @override
  Widget build(BuildContext context) {
    final effective = runtime.effectiveAllowedSymbols.length;
    final total = runtime.allowedSymbols.length;
    final narrowed = effective != total;
    final String headline;
    final Color headlineColor;
    if (effective == 0) {
      headline = 'You opted out of every symbol';
      headlineColor = LuminColors.loss;
    } else if (narrowed) {
      headline = '$effective of $total symbols enabled';
      headlineColor = LuminColors.accent;
    } else {
      headline = '$total symbols enabled';
      headlineColor = LuminColors.textSecondary;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(LuminRadii.sm),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const SymbolPreferencePage(),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: LuminSpacing.sm,
            vertical: LuminSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: LuminColors.bgDeep,
            borderRadius: BorderRadius.circular(LuminRadii.sm),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.filter_list,
                size: 14,
                color: LuminColors.textMuted,
              ),
              const SizedBox(width: LuminSpacing.xs),
              Expanded(
                child: Text(
                  headline,
                  style: TextStyle(
                    color: headlineColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const Text(
                'Edit',
                style: TextStyle(
                  color: LuminColors.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.arrow_forward,
                size: 12,
                color: LuminColors.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
