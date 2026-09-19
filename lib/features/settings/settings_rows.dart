/// The Menu's row and section widgets, shared by the root Menu and the
/// drill-down hubs it opens.
///
/// Extracted from `settings_page.dart` on 2026-09-19 when the Menu gained
/// nested pages (handoff §29). Both the root list and the hubs have to look
/// like the same control surface — a second, near-identical private `_Row` in
/// each hub is the drift this codebase has paid for under several names, and
/// it shows up the first time somebody adjusts a padding in one of them.
library;

import 'package:flutter/material.dart';

import '../../shared/tokens.dart';
import '../../shared/widgets/lumin_card.dart';

/// A labelled group of [SettingsRow]s.
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: LuminSpacing.sm,
              bottom: LuminSpacing.sm,
            ),
            child: Text(
              title,
              style: const TextStyle(
                color: LuminColors.textMuted,
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          LuminCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (int i = 0; i < rows.length; i++) ...[
                  rows[i],
                  if (i < rows.length - 1)
                    const Divider(
                      color: LuminColors.cardBorder,
                      height: 1,
                      indent: 56,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One tappable settings row: icon, label, one-line description, chevron.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  /// Sign-out and delete-account. Colours the icon and label with the loss
  /// accent so an irreversible row is never one careless tap away from
  /// looking like `Profile`.
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final fg = destructive ? LuminColors.loss : LuminColors.accent;
    return InkWell(
      onTap: onTap,
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
                color: fg.withOpacity(0.10),
                borderRadius: BorderRadius.circular(LuminRadii.sm),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: fg, size: 18),
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
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: LuminColors.textSecondary,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: LuminColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}
