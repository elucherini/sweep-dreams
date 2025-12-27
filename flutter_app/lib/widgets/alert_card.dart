import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

/// A white elevated card for displaying an alert/subscription.
/// Designed to be nested inside a FrostedCard container.
class AlertCard extends StatelessWidget {
  final String corridor;
  final String limits;
  final String? blockSide;
  final String nextSweepStart;
  final String nextSweepEnd;
  final int leadMinutes;
  final VoidCallback? onDelete;

  const AlertCard({
    super.key,
    required this.corridor,
    required this.limits,
    this.blockSide,
    required this.nextSweepStart,
    required this.nextSweepEnd,
    required this.leadMinutes,
    this.onDelete,
  });

  String _formatNextSweepWindow() {
    try {
      final startDateTime = DateTime.parse(nextSweepStart);
      final endDateTime = DateTime.parse(nextSweepEnd);

      final dateFormatter = DateFormat('EEE, MMM d');
      final startTimeFormatter = DateFormat('ha');
      final endTimeFormatter = DateFormat('ha');

      final datePart = dateFormatter.format(startDateTime.toLocal());
      final startTime =
          startTimeFormatter.format(startDateTime.toLocal()).toLowerCase();
      final endTime =
          endTimeFormatter.format(endDateTime.toLocal()).toLowerCase();

      return '$datePart $startTime-$endTime';
    } catch (e) {
      return '$nextSweepStart-$nextSweepEnd';
    }
  }

  String _formatTimeUntil() {
    try {
      final startDateTime = DateTime.parse(nextSweepStart).toLocal();
      final now = DateTime.now();
      final difference = startDateTime.difference(now);

      if (difference.isNegative) {
        return 'now';
      }

      final totalHours = difference.inHours;

      if (totalHours >= 48) {
        final days = difference.inDays + 1;
        return 'in $days ${days == 1 ? 'day' : 'days'}';
      } else if (totalHours >= 24) {
        final days = difference.inDays;
        final hours = totalHours - (days * 24);
        return 'in $days ${days == 1 ? 'day' : 'days'} and $hours ${hours == 1 ? 'hour' : 'hours'}';
      } else if (totalHours >= 1) {
        return 'in $totalHours ${totalHours == 1 ? 'hour' : 'hours'}';
      } else {
        final totalMinutes = difference.inMinutes;
        return 'in $totalMinutes ${totalMinutes == 1 ? 'minute' : 'minutes'}';
      }
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Time until sweep badge + delete button
            Row(
              children: [
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.access_time_outlined,
                            color: AppTheme.primaryColor,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _formatTimeUntil(),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
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
            // Title: corridor between limits
            Text(
              '$corridor between $limits',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPrimary,
              ),
            ),
            // Block side
            if (blockSide != null) ...[
              const SizedBox(height: 2),
              Text(
                '($blockSide Side)',
                style: const TextStyle(
                  fontSize: 15,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
            const SizedBox(height: 4),
            // Next sweep
            Text(
              'Next sweep: ${_formatNextSweepWindow()}',
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
                  '$leadMinutes min reminder',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
