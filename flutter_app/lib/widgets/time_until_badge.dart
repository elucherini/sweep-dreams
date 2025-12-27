import 'package:flutter/material.dart';

import '../utils/time_format.dart';

/// A pill-shaped badge showing the time until a sweep starts.
/// Uses the ScheduleCard styling with gradient background.
class TimeUntilBadge extends StatelessWidget {
  final String startIso;

  const TimeUntilBadge({
    super.key,
    required this.startIso,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.9),
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
            Icon(
              Icons.access_time_outlined,
              color: colors.onSecondaryContainer,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              formatTimeUntil(startIso),
              style: TextStyle(
                fontSize: 16,
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
