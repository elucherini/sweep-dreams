import 'package:flutter/material.dart';

import '../models/schedule_response.dart';
import '../theme/app_theme.dart';

class BlockSelectionPage extends StatelessWidget {
  final ScheduleResponse scheduleResponse;
  final String selectedCorridor;
  final void Function(String block) onBlockSelected;
  final VoidCallback onBack;

  const BlockSelectionPage({
    super.key,
    required this.scheduleResponse,
    required this.selectedCorridor,
    required this.onBlockSelected,
    required this.onBack,
  });

  /// Get unique blocks (limits) for the selected corridor, preserving order
  List<String> get _blocks {
    final seen = <String>{};
    final blocks = <String>[];
    for (final entry in scheduleResponse.schedules) {
      if (entry.corridor == selectedCorridor && seen.add(entry.limits)) {
        blocks.add(entry.limits);
      }
    }
    return blocks;
  }

  /// Get the closest distance for a given block within the selected corridor
  String? _closestDistanceForBlock(String block) {
    String? closestDistance;
    double? closestMeters;
    for (final entry in scheduleResponse.schedules) {
      if (entry.corridor == selectedCorridor &&
          entry.limits == block &&
          entry.distance != null) {
        final meters = _parseDistanceToMeters(entry.distance!);
        if (meters != null &&
            (closestMeters == null || meters < closestMeters)) {
          closestMeters = meters;
          closestDistance = entry.distance;
        }
      }
    }
    return closestDistance;
  }

  /// Parse a distance string like "50 ft" or "0.3 mi" to meters for comparison
  double? _parseDistanceToMeters(String distance) {
    final parts = distance.split(' ');
    if (parts.length != 2) return null;
    final value = double.tryParse(parts[0]);
    if (value == null) return null;
    final unit = parts[1].toLowerCase();
    if (unit == 'ft') {
      return value * 0.3048;
    } else if (unit == 'mi') {
      return value * 1609.34;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final blocks = _blocks;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.screenPadding),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppTheme.maxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BackButton(onTap: onBack),
                const SizedBox(height: 16),
                _buildBlockSelection(context, blocks),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBlockSelection(BuildContext context, List<String> blocks) {
    final hasMultipleOptions = blocks.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Which block?',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          selectedCorridor,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textMuted,
              ),
        ),
        const SizedBox(height: 12),
        ...blocks.asMap().entries.expand((entry) {
          final index = entry.key;
          final block = entry.value;
          final isClosest = index == 0;
          final optionWidget = _SelectionOption(
            label: block,
            isClosest: isClosest,
            showBadge: isClosest && hasMultipleOptions,
            distance: _closestDistanceForBlock(block),
            onTap: () => onBlockSelected(block),
          );
          if (index == 1 && hasMultipleOptions) {
            return [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Other nearby blocks:',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textMuted,
                      ),
                ),
              ),
              optionWidget,
            ];
          }
          return [optionWidget];
        }),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chevron_left,
              color: AppTheme.primaryColor,
              size: 20,
            ),
            Text(
              'Back',
              style: TextStyle(
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionOption extends StatefulWidget {
  final String label;
  final bool isClosest;
  final bool showBadge;
  final String? distance;
  final VoidCallback onTap;

  const _SelectionOption({
    required this.label,
    required this.isClosest,
    required this.showBadge,
    this.distance,
    required this.onTap,
  });

  @override
  State<_SelectionOption> createState() => _SelectionOptionState();
}

class _SelectionOptionState extends State<_SelectionOption> with RouteAware {
  double _opacity = 1.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reset opacity when returning to this page
    final route = ModalRoute.of(context);
    if (route != null && route.isCurrent && _opacity != 1.0) {
      setState(() => _opacity = 1.0);
    }
  }

  void _handleTap() {
    setState(() => _opacity = 0.5);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final unselectedColor = AppTheme.surfaceSoft.withValues(
      alpha: AppTheme.paperInGlassOpacity,
    );
    final borderColor = colors.outlineVariant.withValues(alpha: 0.32);
    final labelColor = AppTheme.textPrimary;
    final mutedColor = AppTheme.textMuted;

    return Padding(
      padding: EdgeInsets.only(bottom: widget.isClosest ? 16 : 6),
      child: GestureDetector(
        onTap: _handleTap,
        child: AnimatedOpacity(
          opacity: _opacity,
          duration: const Duration(milliseconds: 100),
          child: Container(
            decoration: BoxDecoration(
              color: unselectedColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: borderColor,
                width: 0.9,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: Colors.transparent,
                  width: 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: labelColor,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (widget.distance != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          widget.distance!,
                          style: TextStyle(
                            fontSize: 13,
                            color: mutedColor,
                          ),
                        ),
                      ),
                    if (widget.isClosest && widget.showBadge)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: colors.outlineVariant.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Closest',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: mutedColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
