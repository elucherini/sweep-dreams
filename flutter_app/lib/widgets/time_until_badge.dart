import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/time_format.dart';

/// A pill-shaped badge showing the time until an event.
/// Uses the ScheduleCard styling with color-coded background.
class TimeUntilBadge extends StatelessWidget {
  final String startIso;
  final String prefix;
  final Color? accentColor;
  final IconData? icon;

  const TimeUntilBadge({
    super.key,
    required this.startIso,
    this.prefix = 'sweeping',
    this.accentColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = accentColor ?? AppTheme.accent;
    final badgeIcon = icon ?? Icons.cleaning_services_outlined;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: accent.withValues(alpha: 0.25),
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
              badgeIcon,
              color: accent,
              size: 20,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                formatTimeUntil(startIso, prefix: prefix),
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
