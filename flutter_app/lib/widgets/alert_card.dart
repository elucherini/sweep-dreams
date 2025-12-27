import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/time_format.dart';
import 'base_card.dart';
import 'time_until_badge.dart';

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

  @override
  Widget build(BuildContext context) {
    return BaseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time until sweep badge + delete button
          Row(
            children: [
              Expanded(
                child: TimeUntilBadge(startIso: nextSweepStart),
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
            'Next sweep: ${formatSweepWindow(nextSweepStart, nextSweepEnd)}',
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
                'We\'ll notify you $leadMinutes min earlier',
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
}
