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
    return BaseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time until deadline badge + delete button
          Row(
            children: [
              Expanded(
                child: TimeUntilBadge(
                  startIso: nextMoveDeadline,
                  label: 'Move car',
                ),
              ),
              if (onDelete != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onDelete,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.delete_outline,
                      color: AppTheme.error.withValues(alpha: 0.7),
                      size: 18,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          // Title: regulation type with hour limit
          Text(
            '$hourLimit-hour parking limit',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          // Days and hours
          Text(
            '$days, $fromTime–$toTime',
            style: const TextStyle(
              fontSize: 15,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          // Next move deadline
          Text(
            'Move by: ${_formatDeadline(nextMoveDeadline)}',
            style: const TextStyle(
              fontSize: 15,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          // Reminder timing
          Row(
            children: [
              Icon(
                Icons.alarm,
                color: AppTheme.textMuted.withValues(alpha: 0.6),
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                "We'll notify you ${formatLeadTime(leadMinutes, sweepStartIso: nextMoveDeadline)}",
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMuted.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Format the deadline as a human-readable date and time.
  String _formatDeadline(String isoString) {
    try {
      final dateTime = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      final deadlineDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

      String dayPart;
      if (deadlineDate == today) {
        dayPart = 'Today';
      } else if (deadlineDate == tomorrow) {
        dayPart = 'Tomorrow';
      } else {
        dayPart = '${_weekdayName(dateTime.weekday)}, ${_monthName(dateTime.month)} ${dateTime.day}';
      }

      final hour = dateTime.hour;
      final minute = dateTime.minute;
      final period = hour >= 12 ? 'pm' : 'am';
      final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      final timePart = minute == 0 ? '$hour12$period' : '$hour12:${minute.toString().padLeft(2, '0')}$period';

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
    const names = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return names[month];
  }
}
