import 'package:flutter/material.dart';

import '../models/schedule_response.dart';
import '../theme/app_theme.dart';
import '../widgets/frosted_card.dart';

class StreetSelectionPage extends StatelessWidget {
  final ScheduleResponse scheduleResponse;
  final void Function(String corridor) onCorridorSelected;
  final VoidCallback onBack;

  const StreetSelectionPage({
    super.key,
    required this.scheduleResponse,
    required this.onCorridorSelected,
    required this.onBack,
  });

  /// Get unique corridors from schedules, preserving order (closest first from API)
  List<String> get _corridors {
    final seen = <String>{};
    final corridors = <String>[];
    for (final entry in scheduleResponse.schedules) {
      final corridor = entry.corridor;
      if (seen.add(corridor)) {
        corridors.add(corridor);
      }
    }
    return corridors;
  }

  /// Get the closest distance for a given corridor (minimum across all its schedules)
  String? _closestDistanceForCorridor(String corridor) {
    String? closestDistance;
    double? closestMeters;
    for (final entry in scheduleResponse.schedules) {
      if (entry.corridor == corridor && entry.distance != null) {
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
    final corridors = _corridors;

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
                FrostedCard(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTheme.cardPadding),
                    child: _buildCorridorSelection(context, corridors),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCorridorSelection(BuildContext context, List<String> corridors) {
    if (corridors.isEmpty) {
      return _buildEmptyState(context);
    }

    final hasMultipleOptions = corridors.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Which street are you parked on?',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
        ),
        const SizedBox(height: 12),
        ...corridors.asMap().entries.expand((entry) {
          final index = entry.key;
          final corridor = entry.value;
          final isClosest = index == 0;
          final optionWidget = _SelectionOption(
            label: corridor,
            isClosest: isClosest,
            showBadge: isClosest && hasMultipleOptions,
            distance: _closestDistanceForCorridor(corridor),
            onTap: () => onCorridorSelected(corridor),
          );
          if (index == 1 && hasMultipleOptions) {
            return [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Other nearby streets:',
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

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.border.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: AppTheme.primaryColor.withValues(alpha: 0.7),
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No sweeping schedules found. This app only works in San Francisco!',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textMuted,
                  ),
            ),
          ),
        ],
      ),
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

class _SelectionOption extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final unselectedColor = AppTheme.surfaceSoft.withValues(
      alpha: AppTheme.paperInGlassOpacity,
    );
    final borderColor = colors.outlineVariant.withValues(alpha: 0.32);
    final labelColor = AppTheme.textPrimary;
    final mutedColor = AppTheme.textMuted;

    return Padding(
      padding: EdgeInsets.only(bottom: isClosest ? 16 : 6),
      child: GestureDetector(
        onTap: onTap,
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
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: labelColor,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (distance != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        distance!,
                        style: TextStyle(
                          fontSize: 13,
                          color: mutedColor,
                        ),
                      ),
                    ),
                  if (isClosest && showBadge)
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
    );
  }
}
