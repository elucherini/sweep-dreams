import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A translucent, frosted glass card with backdrop blur and soft elevation.
/// Inspired by iOS system blur materials.
class FrostedCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double blurSigma;
  final bool enableBlur;

  const FrostedCard({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.blurSigma = 20,
    this.enableBlur = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
            spreadRadius: 0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final innerDecoration = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppTheme.primarySoft.withValues(alpha: 0.4),
          Colors.white.withValues(alpha: 0.2),
        ],
      ),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.5),
        width: 1,
      ),
    );

    if (enableBlur) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          decoration: innerDecoration,
          child: child,
        ),
      );
    }

    // Without blur, use a more opaque background for better visibility
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primarySoft.withValues(alpha: 0.6),
            Colors.white.withValues(alpha: 0.4),
          ],
        ),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
      child: child,
    );
  }
}
