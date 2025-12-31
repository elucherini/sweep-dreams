import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Cool-neutral editorial backdrop intended to make frosted materials read
/// (distortion needs a visually active layer behind the glass).
///
/// Spec:
/// - Vertical gradient: #F6F7FB → #E7EAF2
/// - 1–2 blurred blobs: large (≈360–420px), σ≈60, opacity≈0.28–0.35
/// - Optional subtle grain overlay (~3–4% opacity)
class EditorialBackground extends StatelessWidget {
  final Widget child;
  final bool enableBlobs;
  final bool enableFocusField;
  final bool enableGrain;

  const EditorialBackground({
    super.key,
    required this.child,
    this.enableBlobs = true,
    this.enableFocusField = true,
    this.enableGrain = true,
  });

  @override
  Widget build(BuildContext context) {
    final mediaSize = MediaQuery.of(context).size;
    // Bias slightly smaller within the 360–420px range so color stays concentrated
    // enough to create mid-scale contrast for σ≈18 glass blur to read.
    final blobSize = (mediaSize.shortestSide * 0.9).clamp(360.0, 420.0);
    final w = mediaSize.width;
    final h = mediaSize.height;

    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(gradient: AppTheme.backgroundGradient),
        ),
        if (enableBlobs) ...[
          // Place blob centers roughly behind where the primary frosted card lives
          // (mid-screen), so BackdropFilter has something to distort.
          Positioned(
            left: (w * 0.82) - (blobSize * 0.5),
            top: (h * 0.52) - (blobSize * 0.5),
            child: _BlurredBlob(
              size: blobSize,
              blurSigma: AppTheme.backgroundBlobBlurSigma,
              color: AppTheme.backgroundBlobPeriwinkle,
              opacity: AppTheme.backgroundBlobOpacityA,
            ),
          ),
          Positioned(
            left: (w * 0.18) - ((blobSize * 0.9) * 0.5),
            top: (h * 0.84) - ((blobSize * 0.9) * 0.5),
            child: _BlurredBlob(
              size: blobSize * 0.9,
              blurSigma: AppTheme.backgroundBlobBlurSigma,
              color: AppTheme.backgroundBlobSky,
              opacity: AppTheme.backgroundBlobOpacityB,
            ),
          ),
        ],
        if (enableFocusField)
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: AppTheme.backgroundFocusFieldAlignment,
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: AppTheme.backgroundFocusFieldBlurSigma,
                    sigmaY: AppTheme.backgroundFocusFieldBlurSigma,
                  ),
                  child: Container(
                    width: w * AppTheme.backgroundFocusFieldWidthFactor,
                    height: h * AppTheme.backgroundFocusFieldHeightFactor,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      // Use a radial valley (not a flat fill) so it never reads as a patch.
                      gradient: RadialGradient(
                        center: const Alignment(0.0, -0.05),
                        radius: 0.95,
                        colors: [
                          Colors.black.withValues(
                            alpha: AppTheme.backgroundFocusFieldOpacity,
                          ),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (enableGrain)
          const Positioned.fill(
            child: IgnorePointer(
              child: _GrainOverlay(opacity: AppTheme.backgroundGrainOpacity),
            ),
          ),
        child,
      ],
    );
  }
}

class _BlurredBlob extends StatelessWidget {
  final double size;
  final double blurSigma;
  final Color color;
  final double opacity;

  const _BlurredBlob({
    required this.size,
    required this.blurSigma,
    required this.color,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Base wash (very soft, per spec).
          ImageFiltered(
            imageFilter:
                ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
            child: _BlobPaint(
              color: color,
              opacity: opacity,
              primaryCenter: const Alignment(-0.22, -0.18),
              primaryRadius: 0.92,
              secondaryCenter: const Alignment(0.55, 0.28),
              secondaryRadius: 0.88,
              secondaryOpacityScale: 0.55,
            ),
          ),
          // Detail component (lower blur, very low opacity).
          // This gives the glass blur (σ≈16–18) something to visibly soften.
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: AppTheme.backgroundBlobDetailBlurSigma,
              sigmaY: AppTheme.backgroundBlobDetailBlurSigma,
            ),
            child: _BlobPaint(
              color: color,
              opacity: opacity * AppTheme.backgroundBlobDetailOpacityScale,
              primaryCenter: const Alignment(-0.10, -0.06),
              primaryRadius: 0.78,
              secondaryCenter: const Alignment(0.35, 0.12),
              secondaryRadius: 0.72,
              secondaryOpacityScale: 0.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _BlobPaint extends StatelessWidget {
  final Color color;
  final double opacity;
  final Alignment primaryCenter;
  final double primaryRadius;
  final Alignment secondaryCenter;
  final double secondaryRadius;
  final double secondaryOpacityScale;

  const _BlobPaint({
    required this.color,
    required this.opacity,
    required this.primaryCenter,
    required this.primaryRadius,
    required this.secondaryCenter,
    required this.secondaryRadius,
    required this.secondaryOpacityScale,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: primaryCenter,
              radius: primaryRadius,
              colors: [
                color.withValues(alpha: opacity),
                color.withValues(alpha: opacity * 0.62),
                color.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: secondaryCenter,
              radius: secondaryRadius,
              colors: [
                color.withValues(alpha: opacity * secondaryOpacityScale),
                color.withValues(alpha: opacity * secondaryOpacityScale * 0.48),
                color.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

class _GrainOverlay extends StatelessWidget {
  final double opacity;

  const _GrainOverlay({required this.opacity});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _GrainPainter(opacity: opacity),
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  final double opacity;
  static const int _seed = 13;

  const _GrainPainter({required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    if (size.isEmpty) return;

    final rnd = Random(_seed);
    final area = size.width * size.height;

    // Subtle film grain: a sparse 1px point field, rendered once (no animation).
    // Density tuned to read at ~3–4% overall opacity without looking speckled.
    final count = (area / 55).clamp(1500, 12000).toInt();

    final dark = <Offset>[];
    final light = <Offset>[];
    for (var i = 0; i < count; i++) {
      final p = Offset(
        rnd.nextDouble() * size.width,
        rnd.nextDouble() * size.height,
      );
      (i.isEven ? dark : light).add(p);
    }

    final paintDark = Paint()
      ..color = Colors.black.withValues(alpha: opacity)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.square;

    final paintLight = Paint()
      ..color = Colors.white.withValues(alpha: opacity * 0.65)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.square;

    canvas.drawPoints(ui.PointMode.points, dark, paintDark);
    canvas.drawPoints(ui.PointMode.points, light, paintLight);
  }

  @override
  bool shouldRepaint(covariant _GrainPainter oldDelegate) {
    return oldDelegate.opacity != opacity;
  }
}


