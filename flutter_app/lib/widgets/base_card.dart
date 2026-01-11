import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A cool-neutral "paper" surface for content nested inside frosted glass.
/// Intentionally avoids elevation shadows to keep the glass hierarchy clean.
class BaseCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final double? borderWidth;

  const BaseCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.backgroundColor,
    this.borderColor,
    this.borderWidth,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final resolvedBorderColor =
        borderColor ?? colors.outlineVariant.withValues(alpha: 0.28);

    return Container(
      decoration: BoxDecoration(
        color: (backgroundColor ?? AppTheme.surfaceSoft)
            .withValues(alpha: AppTheme.paperInGlassOpacity),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: resolvedBorderColor,
          width: borderWidth ?? 0.8,
        ),
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

/// A small circular delete button with an error-colored trash icon.
/// Used consistently across alert cards.
class DeleteButton extends StatelessWidget {
  final VoidCallback onTap;

  const DeleteButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.delete_outline,
          color: AppTheme.error.withValues(alpha: 0.7),
          size: 18,
        ),
      ),
    );
  }
}
