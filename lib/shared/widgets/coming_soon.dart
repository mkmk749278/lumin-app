import 'package:flutter/material.dart';
import '../tokens.dart';
import 'lumin_card.dart';

class ComingSoon extends StatelessWidget {
  const ComingSoon({super.key, required this.title, required this.icon, required this.description});

  final String title;
  final IconData icon;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(LuminSpacing.lg),
      child: LuminCard(
        padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.xl, vertical: LuminSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: LuminColors.accent),
            const SizedBox(height: LuminSpacing.lg),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: LuminSpacing.sm),
            Text(description, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: LuminSpacing.lg),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.md, vertical: LuminSpacing.xs),
              decoration: BoxDecoration(
                color: LuminColors.bgElevated,
                borderRadius: BorderRadius.circular(LuminRadii.pill),
                border: Border.all(color: LuminColors.cardBorder),
              ),
              child: const Text(
                'Coming soon',
                style: TextStyle(color: LuminColors.textSecondary, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
