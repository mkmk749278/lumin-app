/// The button that takes a user from a failed order to the page that fixes
/// it (handoff §16).
///
/// A public widget rather than a private method on the review sheet, for the
/// same reason `PlannedLossRow` is: that sheet cannot be pumped in a test —
/// reaching it needs Binance keys, per-user settings, an `AppConfigScope` and
/// an Assist entitlement — so a control defined inside it can be routed
/// correctly and still render wrong, and nothing would say so.
///
/// The routing decision is not made here. [TakeRecovery] arrives on the
/// message, chosen beside the copy that names the destination, so the button
/// and the sentence above it cannot disagree about where the user is going.
library;

import 'package:flutter/material.dart';

import '../../app/distribution.dart';
import '../../data/take_error_mapper.dart';
import '../../shared/tokens.dart';
import '../settings/pages/auto_trade_settings_page.dart';
import '../settings/pages/server_side_execution_page.dart';
import '../settings/pages/subscription_page.dart';
import '../settings/pages/web_paywall_page.dart';

class TakeRecoveryAction extends StatelessWidget {
  const TakeRecoveryAction({
    super.key,
    required this.recovery,
    required this.colour,
    this.onNavigate,
  });

  final TakeRecovery recovery;

  /// Matches the banner it sits in, so the action reads as part of the same
  /// message rather than as an unrelated control that happened to land there.
  final Color colour;

  /// Called before pushing, so the host sheet can close itself. Without it
  /// the user lands on a settings page stacked over a stale order review they
  /// can no longer confirm, and Back returns them to it.
  final VoidCallback? onNavigate;

  /// The label and destination for each route, or null where there is none.
  ///
  /// [TakeRecovery.signIn] is deliberately null: the auth gate owns that
  /// route, and pushing a sign-in page over a signed-in shell would leave the
  /// user somewhere the Back button cannot sensibly return from. The copy
  /// already tells them what to do, and no button is the honest answer.
  static (String, Widget Function())? destinationFor(TakeRecovery recovery) {
    switch (recovery) {
      case TakeRecovery.exchangeConnection:
        return ('Fix connection', () => const ServerSideExecutionPage());
      case TakeRecovery.autoTradeSettings:
        return (
          'Open auto-trade settings',
          () => const AutoTradeSettingsPage(),
        );
      case TakeRecovery.subscription:
        return (
          'See plans',
          () => kDistribution == AppDistribution.web
              ? const WebPaywallPage()
              : const SubscriptionPage(),
        );
      case TakeRecovery.signIn:
      case TakeRecovery.none:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final destination = destinationFor(recovery);
    if (destination == null) return const SizedBox.shrink();
    final (label, build) = destination;
    return Padding(
      padding: const EdgeInsets.only(top: LuminSpacing.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          style: TextButton.styleFrom(
            foregroundColor: colour,
            padding: const EdgeInsets.symmetric(
              horizontal: LuminSpacing.sm,
              vertical: 4,
            ),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () {
            final navigator = Navigator.of(context);
            onNavigate?.call();
            navigator.push(
              MaterialPageRoute<void>(builder: (_) => build()),
            );
          },
          child: Text(
            '$label  →',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
