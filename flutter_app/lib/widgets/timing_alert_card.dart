import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/time_format.dart';
import 'base_card.dart';
import 'time_until_badge.dart';

/// A card for displaying a timing/parking regulation subscription.
/// Shows time-limited parking information and next move deadline.
class TimingAlertCard extends StatelessWidget {
  final String regulation;
  final int hourLimit;
  final String days;
  final String fromTime;
  final String toTime;
  final String nextMoveDeadline;
  final int leadMinutes;
  final VoidCallback? onDelete;

  const TimingAlertCard({
    super.key,
    required this.regulation,
    required this.hourLimit,
    required this.days,
    required this.fromTime,
    required this.toTime,
    required this.nextMoveDeadline,
    required this.leadMinutes,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TimeUntilBadge(
                startIso: nextMoveDeadline,
                prefix: '',
                accentColor: AppTheme.accentParking,
                icon: Icons.timer_outlined,
              ),
            ),
            if (onDelete != null) ...[
              const SizedBox(width: 8),
              DeleteButton(onTap: onDelete!),
            ],
          ],
        ),
        const SizedBox(height: 10),
        BaseCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$hourLimit-hour parking limit',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$days, $fromTime–$toTime',
                style: const TextStyle(
                  fontSize: 15,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Move by: ${_formatDeadline(nextMoveDeadline)}',
                style: const TextStyle(
                  fontSize: 15,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.alarm,
                    color: AppTheme.textMuted.withValues(alpha: 0.6),
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "We'll notify you ${formatLeadTime(leadMinutes, sweepStartIso: nextMoveDeadline)}",
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Format the deadline as a human-readable date and time.
  String _formatDeadline(String isoString) {
    try {
      final dateTime = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      final deadlineDate =
          DateTime(dateTime.year, dateTime.month, dateTime.day);

      String dayPart;
      if (deadlineDate == today) {
        dayPart = 'Today';
      } else if (deadlineDate == tomorrow) {
        dayPart = 'Tomorrow';
      } else {
        dayPart =
            '${_weekdayName(dateTime.weekday)}, ${_monthName(dateTime.month)} ${dateTime.day}';
      }

      final hour = dateTime.hour;
      final minute = dateTime.minute;
      final period = hour >= 12 ? 'pm' : 'am';
      final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      final timePart = minute == 0
          ? '$hour12$period'
          : '$hour12:${minute.toString().padLeft(2, '0')}$period';

      return '$dayPart at $timePart';
    } catch (_) {
      return isoString;
    }
  }

  String _weekdayName(int weekday) {
    const names = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[weekday];
  }

  String _monthName(int month) {
    const names = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return names[month];
  }
}
