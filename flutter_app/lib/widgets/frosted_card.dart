import 'dart:ui';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class FrostedCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double blurSigma;
  final Color fillColor;
  final double fillOpacity;
  final double innerStrokeOpacity;
  final double outerStrokeOpacity;
  final double shadowOpacity;
  final bool enableBlur;
  final bool enableInternalFalloff;
  final bool enableEdgeVignette;
  final double topHighlightOpacity;
  final double bottomShadeOpacity;

  const FrostedCard({
    super.key,
    required this.child,
    this.borderRadius = AppTheme.glassRadius, // target ≈ 16–24 (≈20)
    this.blurSigma = AppTheme.glassBlurSigma, // target ≈ 16–18
    this.fillColor = AppTheme.glassBase, // cool gray, not white
    this.fillOpacity = AppTheme.glassOpacity, // target ≈ 0.72–0.78
    this.innerStrokeOpacity =
        AppTheme.glassInnerStrokeOpacity, // target ≈ 0.25–0.30
    this.outerStrokeOpacity = AppTheme.glassOuterStrokeOpacity,
    this.shadowOpacity = AppTheme.glassShadowOpacity, // target ≈ 0.06
    this.enableBlur = true,
    this.enableInternalFalloff = true,
    this.enableEdgeVignette = false,
    this.topHighlightOpacity = AppTheme.glassTopHighlightOpacity,
    this.bottomShadeOpacity = AppTheme.glassBottomShadeOpacity,
  });

  @override
  Widget build(BuildContext context) {
    final innerRadius = (borderRadius - AppTheme.glassInnerStrokeInset)
        .clamp(0.0, double.infinity)
        .toDouble();
    // Center should be clearer than edges so distortion reads (and the sheet doesn't look gray).
    final fillCenter = (fillOpacity - 0.14).clamp(0.0, 1.0);
    final fillMid = fillOpacity.clamp(0.0, 1.0);
    final fillEdge = (fillOpacity + 0.06).clamp(0.0, 1.0);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: shadowOpacity),
            blurRadius: AppTheme.glassShadowBlurRadius,
            offset: AppTheme.glassShadowOffset,
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

            // Glass fill (cool gray tint; keep it calm—no glossy gradients).
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.0, -0.15),
                    radius: 1.12,
                    colors: [
                      fillColor.withValues(alpha: fillCenter),
                      fillColor.withValues(alpha: fillMid),
                      fillColor.withValues(alpha: fillEdge),
                    ],
                    stops: const [0.0, 0.62, 1.0],
                  ),
                  borderRadius: BorderRadius.circular(borderRadius),
                  border: Border.all(
                    // Light edge definition reads as a sheet without adding "gray".
                    color: Colors.white.withValues(alpha: outerStrokeOpacity),
                    width: AppTheme.glassOuterStrokeWidth,
                  ),
                ),
              ),
            ),

            // Subtle internal light falloff to read as a material sheet.
            // This is NOT a glossy sheen; it’s gentle thickness/lighting.
            if (enableInternalFalloff)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(borderRadius),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: topHighlightOpacity),
                          Colors.transparent,
                          Colors.black.withValues(alpha: bottomShadeOpacity),
                        ],
                        stops: const [0.0, 0.58, 1.0],
                      ),
                    ),
                  ),
                ),
              ),

            // Crisp top edge highlight (thin) — helps the sheet read on bright backgrounds.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: 1.25,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.0),
                        Colors.white.withValues(
                          alpha: (innerStrokeOpacity + 0.10).clamp(0.0, 1.0),
                        ),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // Very subtle edge vignette helps the sheet separate from a bright background
            // without adding more drop shadow.
            if (enableEdgeVignette)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(borderRadius),
                      gradient: RadialGradient(
                        center: const Alignment(0.0, -0.08),
                        radius: 1.08,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(
                            alpha: AppTheme.glassEdgeVignetteOpacity,
                          ),
                        ],
                        stops: const [0.72, 1.0],
                      ),
                    ),
                  ),
                ),
              ),

            // Subtle 1px inner stroke (white @ ~0.25–0.30 opacity).
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.glassInnerStrokeInset),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color:
                            Colors.white.withValues(alpha: innerStrokeOpacity),
                        width: AppTheme.glassInnerStrokeWidth,
                      ),
                      borderRadius: BorderRadius.circular(innerRadius),
                    ),
                  ),
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
