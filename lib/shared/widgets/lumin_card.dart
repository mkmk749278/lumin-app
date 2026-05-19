import 'package:flutter/material.dart';
import '../tokens.dart';

class LuminCard extends StatelessWidget {
  const LuminCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(LuminSpacing.lg),
    this.onTap,
    this.border,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Optional custom border (e.g. accent-coloured for status cards).
  /// Defaults to the standard ``cardBorder`` when omitted.
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: LuminColors.bgCard,
        borderRadius: BorderRadius.circular(LuminRadii.lg),
        border: border ?? Border.all(color: LuminColors.cardBorder),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(LuminRadii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(LuminRadii.lg),
        onTap: onTap,
        child: card,
      ),
    );
  }
}
