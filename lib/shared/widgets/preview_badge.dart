/// Preview banner — flags settings surfaces whose toggles aren't yet wired
/// to the live engine.
///
/// Backend wiring shipped in v0.0.7 for Signals / Pulse / Trade and v0.0.9
/// for the per-agent drill-down — those surfaces are now driven from
/// `https://api.luminapp.org`.  This badge remains on the settings
/// drill-downs (Agents toggles, Risk gates, Pre-TP, Auto-trade, API keys)
/// where the controls are still illustrative pending a future tier.
import 'package:flutter/material.dart';
import '../tokens.dart';

class PreviewBadge extends StatelessWidget {
  const PreviewBadge({super.key, this.message});

  /// Optional override copy.  When null, falls back to the settings-context
  /// wording.  Live-data surfaces gate the badge on `!repo.isLive` so the
  /// default wording is correct for both the offline-mock and
  /// settings-drill-down surfaces.
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        LuminSpacing.lg,
        LuminSpacing.sm,
        LuminSpacing.lg,
        LuminSpacing.md,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: LuminSpacing.md,
        vertical: LuminSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: LuminColors.warn.withOpacity(0.10),
        borderRadius: BorderRadius.circular(LuminRadii.sm),
        border: Border.all(color: LuminColors.warn.withOpacity(0.30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: LuminColors.warn, size: 16),
          const SizedBox(width: LuminSpacing.sm),
          Expanded(
            child: Text(
              message ??
                  'Preview — these controls are illustrative.  Live wiring ships in a future release.',
              style: const TextStyle(
                color: LuminColors.warn,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
