import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/time_format.dart';

/// A pill-shaped badge showing the time until an event.
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
              Icons.cleaning_services_outlined,
              color: AppTheme.textMuted,
              size: 20,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                formatTimeUntil(startIso),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: colors.onSecondaryContainer,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
