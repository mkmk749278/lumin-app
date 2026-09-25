/// A small ⓘ that opens a screen's explanation in a bottom sheet.
///
/// Owner, 2026-09-24: *"don't keep all that brief there, keep i icon over there
/// to know that's it, keep everything simple … that's like production."* The
/// paragraphs that used to sit under a figure are still true and still
/// reachable — one tap on the ⓘ beside the thing they explain — but they no
/// longer stand between the reader and the number.
///
/// Two rules, both carried over from the text this replaces:
///
/// * **The sheet shows the same sentences, not a summary of them.** The track
///   record's assumptions (size, fee, UTC, "not a back-test", "your results
///   will differ") are conditions on reading its figures, and the tests pin
///   them *inside the sheet*, so an edit that thins them out still fails.
/// * **Nothing money-relevant hides behind the icon alone.** A screen that
///   shows performance figures keeps its one-line "past performance" caption
///   in view; the ⓘ carries the detail, not the only warning.
import 'package:flutter/material.dart';

import '../tokens.dart';

/// Opens [paragraphs] under [title] in a bottom sheet.
Future<void> showInfoSheet(
  BuildContext context, {
  required String title,
  required List<String> paragraphs,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _InfoSheet(title: title, paragraphs: paragraphs),
  );
}

/// The ⓘ itself. [title] names the sheet and is also the button's tooltip and
/// screen-reader label, so it should read as one ("About this track record").
class InfoButton extends StatelessWidget {
  const InfoButton({
    super.key,
    required this.title,
    required this.paragraphs,
    this.size = 18,
    this.color = LuminColors.textMuted,
  });

  final String title;
  final List<String> paragraphs;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: () =>
            showInfoSheet(context, title: title, paragraphs: paragraphs),
        icon: Icon(Icons.info_outline, size: size, color: color),
        tooltip: title,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        // A 32px target, not 48: this sits inside a card header beside a
        // figure, and the default would push the figure off a small phone.
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        splashRadius: 18,
      );
}

class _InfoSheet extends StatelessWidget {
  const _InfoSheet({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.8;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        decoration: const BoxDecoration(
          color: LuminColors.bgCard,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(LuminRadii.lg)),
          border: Border(top: BorderSide(color: LuminColors.cardBorder)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                LuminSpacing.xl, LuminSpacing.md, LuminSpacing.xl, LuminSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: LuminColors.textMuted.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(LuminRadii.pill),
                    ),
                  ),
                ),
                const SizedBox(height: LuminSpacing.lg),
                Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 18, color: LuminColors.accent),
                    const SizedBox(width: LuminSpacing.sm),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: LuminColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: LuminSpacing.md),
                for (final p in paragraphs) ...[
                  Text(
                    p,
                    style: const TextStyle(
                      color: LuminColors.textSecondary,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: LuminSpacing.sm),
                ],
                const SizedBox(height: LuminSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: LuminColors.accent,
                      backgroundColor: LuminColors.bgElevated,
                      padding: const EdgeInsets.symmetric(vertical: LuminSpacing.md),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(LuminRadii.md),
                      ),
                    ),
                    child: const Text(
                      'Got it',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
