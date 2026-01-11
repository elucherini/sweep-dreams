import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/time_format.dart';

/// A pill-shaped badge showing the time until an event.
/// Uses the ScheduleCard styling with color-coded background.
/// Can be tapped to toggle visibility of associated map overlay.
class TimeUntilBadge extends StatelessWidget {
  final String startIso;
  final String prefix;
  final Color? accentColor;
  final IconData? icon;

  /// Whether the associated line overlay is visible on the map.
  final bool enabled;

  /// Called when the badge is tapped to toggle visibility.
  final VoidCallback? onToggle;

  const TimeUntilBadge({
    super.key,
    required this.startIso,
    this.prefix = 'sweeping',
    this.accentColor,
    this.icon,
    this.enabled = true,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final baseAccent = accentColor ?? AppTheme.accent;
    final badgeIcon = icon ?? Icons.cleaning_services_outlined;

    // When disabled, use white/off-white colors instead of the accent
    final accent = enabled ? baseAccent : AppTheme.textMuted;
    final backgroundColor =
        enabled ? baseAccent.withValues(alpha: 0.12) : AppTheme.surface;
    final borderColor =
        enabled ? baseAccent.withValues(alpha: 0.25) : AppTheme.border;

    final badge = DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: borderColor),
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
                  color: enabled
                      ? colors.onSecondaryContainer
                      : AppTheme.textMuted,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (onToggle == null) {
      return badge;
    }

    return GestureDetector(
      onTap: onToggle,
      child: badge,
    );
  }
}
