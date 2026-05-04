/// Preview banner — sits at the top of any tab showing mocked data.
///
/// Honest framing: clearly tells the user this is sample data while the
/// FastAPI backend wires up.  Without this badge a user could mistake
/// the mocked numbers for real engine state.
import 'package:flutter/material.dart';
import '../tokens.dart';

class PreviewBadge extends StatelessWidget {
  const PreviewBadge({super.key});

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
        children: const [
          Icon(Icons.info_outline, color: LuminColors.warn, size: 16),
          SizedBox(width: LuminSpacing.sm),
          Expanded(
            child: Text(
              'Preview — sample data.  Live engine data lands when the backend wires up.',
              style: TextStyle(
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
