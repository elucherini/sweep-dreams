import 'dart:ui';
import 'package:flutter/material.dart';

class FrostedCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double blurSigma;
  final bool enableBlur;

  const FrostedCard({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.blurSigma = 28, // usually higher than you think
    this.enableBlur = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            if (enableBlur)
              Positioned.fill(
                child: BackdropFilter(
                  filter:
                      ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                  child: const SizedBox(),
                ),
              ),

            // Glass fill: gradient (top more opaque).
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      cs.surface.withValues(alpha: 0.28),
                      cs.surface.withValues(alpha: 0.18),
                    ],
                  ),
                ),
              ),
            ),

            // Border stroke (1px-ish) + your edge lighting if desired.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(borderRadius),
                ),
              ),
            ),

            // Content
            child,
          ],
        ),
      ),
    );
  }
}
