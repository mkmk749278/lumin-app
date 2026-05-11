/// AUTO indicator — sticky banner above NavShell when auto-trade is
/// active.  Shows mode (LIVE / PAPER) + last fired signal + a quick
/// kill-switch button.
///
/// Phase 3b-2.  Visible only when ``AutoTradeWatcher.status.running``
/// is true.  Subscribes to the watcher's status stream so toggling
/// from any page (Auto-trade settings, kill button here) reflects
/// immediately.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/app_config.dart';
import '../../data/auto_trade_watcher.dart';
import '../../data/repository.dart';
import '../../shared/tokens.dart';

class AutoTradeIndicator extends StatefulWidget {
  const AutoTradeIndicator({super.key});

  @override
  State<AutoTradeIndicator> createState() => _AutoTradeIndicatorState();
}

class _AutoTradeIndicatorState extends State<AutoTradeIndicator> {
  AutoTradeStatus _status = const AutoTradeStatus(running: false, mode: null);
  StreamSubscription<AutoTradeStatus>? _sub;
  bool _killing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final watcher = AppConfigScope.of(context).autoTradeWatcher;
    _status = watcher.status;
    _sub ??= watcher.statusStream.listen((s) {
      if (mounted) setState(() => _status = s);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _killSwitch() async {
    if (_killing) return;
    setState(() => _killing = true);
    final scope = AppConfigScope.of(context);
    try {
      await scope.repo.updateUserAutoTradeSettings(
        const AutoTradeSettings(mode: 'off'),
      );
      await scope.autoTradeWatcher.refreshSettings();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kill failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _killing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show even when there's a meaningful error to surface (live mode
    // configured but keys missing, etc.), so the user doesn't wonder
    // why nothing's firing.
    final running = _status.running;
    final showError = _status.lastError != null && _status.mode != 'off';
    if (!running && !showError) return const SizedBox.shrink();

    final isLive = _status.mode == 'live';
    final isPaper = _status.mode == 'paper';
    final accent = showError && !running
        ? LuminColors.loss
        : isLive
            ? LuminColors.warn
            : LuminColors.accent;
    final label = !running
        ? 'AUTO PAUSED'
        : isLive
            ? 'AUTO LIVE'
            : isPaper
                ? 'AUTO PAPER'
                : 'AUTO';

    return Material(
      color: accent.withOpacity(0.12),
      child: InkWell(
        onTap: _killing ? null : _killSwitch,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: LuminSpacing.md,
            vertical: LuminSpacing.sm,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: accent.withOpacity(0.30)),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(LuminRadii.pill),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: LuminColors.bgDeep,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: LuminSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _statusLine(),
                      style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_status.lastError != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        _status.lastError!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: LuminColors.textMuted,
                          fontSize: 10,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_killing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: LuminSpacing.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: LuminColors.bgDeep,
                    borderRadius: BorderRadius.circular(LuminRadii.pill),
                    border: Border.all(color: accent.withOpacity(0.50)),
                  ),
                  child: Text(
                    'TAP TO STOP',
                    style: TextStyle(
                      color: accent,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLine() {
    final fired = _status.lastFiredAt;
    if (fired != null) {
      final delta = DateTime.now().difference(fired);
      final age = delta.inMinutes < 1
          ? '${delta.inSeconds}s'
          : delta.inHours < 1
              ? '${delta.inMinutes}m'
              : '${delta.inHours}h';
      return 'Last fired ${_status.lastFiredSignalId ?? ""} • $age ago';
    }
    if (_status.lastTickAt != null) {
      return 'Watching for new signals…';
    }
    return 'Waiting for first tick…';
  }
}
