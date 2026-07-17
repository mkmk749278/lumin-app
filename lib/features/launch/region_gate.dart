/// Region gate — Play Store launch A6 (2026-05-20).
///
/// Wraps any auto-trade-touching surface (Binance connect form,
/// Auto-trade settings, etc.) and replaces it with a polite
/// "not available in your region" card when the server-side
/// region check reports the user is in a blocked jurisdiction.
///
/// **Doctrine — soft-fail open.**
///
/// * While the region fetch is in flight: render the child as-is.
///   We never block the UI on a slow network round-trip.
/// * On fetch success + ``is_blocked == false``: render the child.
///   Includes the ``country_code == "unknown"`` case — better to
///   show the feature to a user we can't identify than to block a
///   user in a permitted region.
/// * On fetch success + ``is_blocked == true``: replace the child
///   with [_RegionBlockedCard].  The server-side endpoint reads
///   CDN headers (Cloudflare's ``CF-IPCountry``), so this branch
///   only fires when the request demonstrably originated from a
///   blocked country.
/// * On fetch failure (network / 5xx): the [HttpRepository] soft-
///   falls to ``unknown`` + not-blocked.  Same as the in-flight
///   case from the user's POV.
///
/// Server-side dispatch ALSO enforces region restrictions via the
/// connect-time validator + per-user allowlist.  This widget is the
/// UX layer.  If a user somehow bypasses this gate (rooted device
/// replays a stale unblocked response, etc.) they still cannot
/// actually trade — they just see a more confusing error.
library;

import 'package:flutter/material.dart';

import '../../data/app_config.dart';
import '../../data/repository.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/lumin_card.dart';

class RegionGate extends StatefulWidget {
  const RegionGate({super.key, required this.child});

  /// The surface to gate — typically the Binance connect form or
  /// the Auto-trade settings card.  Rendered unchanged when the
  /// user's region is permitted (or unknown).
  final Widget child;

  @override
  State<RegionGate> createState() => _RegionGateState();
}

class _RegionGateState extends State<RegionGate> {
  Future<RegionInfo>? _fetch;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Kick the fetch on first attach.  Subsequent rebuilds reuse
    // the same future — region doesn't change while the user is
    // sitting on a page, and we don't want to re-fetch on every
    // setState.
    _fetch ??= AppConfigScope.of(context).repo.fetchRegion();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RegionInfo>(
      future: _fetch,
      builder: (context, snap) {
        // In-flight: render the child immediately.  Region check is
        // a UX nicety, not a hard gate; we don't add latency for it.
        if (snap.connectionState != ConnectionState.done) {
          return widget.child;
        }
        // Error → repo soft-fails to unblocked-unknown; this branch
        // is defensive.  Show child rather than an error banner.
        if (snap.hasError || snap.data == null) {
          return widget.child;
        }
        final region = snap.data!;
        if (!region.isBlocked) {
          return widget.child;
        }
        return _RegionBlockedCard(region: region);
      },
    );
  }
}

class _RegionBlockedCard extends StatelessWidget {
  const _RegionBlockedCard({required this.region});

  final RegionInfo region;

  @override
  Widget build(BuildContext context) {
    final blockedList = region.blockedRegions.isEmpty
        ? 'restricted regions'
        : region.blockedRegions.join(' / ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.public_off_outlined,
                  color: LuminColors.warn,
                  size: 20,
                ),
                SizedBox(width: LuminSpacing.sm),
                Text(
                  'Not available in your region',
                  style: TextStyle(
                    color: LuminColors.warn,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.md),
            Text(
              'Auto-trade is currently not available in $blockedList. '
              'Your region is detected as ${region.countryCode}.',
              style: const TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: LuminSpacing.sm),
            const Text(
              'You can still browse every signal and its analysis in '
              'the app. Automated order placement is disabled to '
              'comply with local regulations.',
              style: TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
