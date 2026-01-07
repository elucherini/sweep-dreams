import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/time_format.dart';

/// A pill-shaped badge showing the time until an event.
/// Uses the ScheduleCard styling with gradient background.
class TimeUntilBadge extends StatelessWidget {
  final String startIso;

  /// Optional label to prefix the time (e.g., "Move car" → "Move car in 2 hours")
  final String? label;

  const TimeUntilBadge({
    super.key,
    required this.startIso,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 8,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.access_time_outlined,
              color: AppTheme.textMuted,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              label != null
                  ? '$label ${formatTimeUntil(startIso)}'
                  : formatTimeUntil(startIso),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colors.onSecondaryContainer,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
