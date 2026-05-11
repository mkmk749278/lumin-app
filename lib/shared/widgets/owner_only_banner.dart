/// Owner-only banner — surfaces on tier-gated settings pages when the
/// current JWT's tier is not ``owner``.  Engine PR #355 enforces 403 on
/// PUT/POST to the gated endpoints; this banner is the app-side companion
/// that tells subscribers WHY the Save action is missing and the form
/// fields are read-only.
///
/// The Save button on the page is hidden (not just disabled) per the
/// design-first rule: a greyed-out button signals "exists but I can't
/// use it"; an absent button + this banner signals "this isn't for
/// your tier" — the honest answer.
import 'package:flutter/material.dart';
import '../tokens.dart';

class OwnerOnlyBanner extends StatelessWidget {
  const OwnerOnlyBanner({super.key, this.message});

  /// Optional override copy.  Defaults to the generic settings wording.
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
        color: LuminColors.accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(LuminRadii.sm),
        border: Border.all(color: LuminColors.accent.withOpacity(0.30)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.admin_panel_settings_outlined,
            color: LuminColors.accent,
            size: 16,
          ),
          const SizedBox(width: LuminSpacing.sm),
          Expanded(
            child: Text(
              message ??
                  'Read-only — only the engine owner can change these settings.',
              style: const TextStyle(
                color: LuminColors.accent,
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
