import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/schedule_response.dart';
import '../theme/app_theme.dart';

class ScheduleCard extends StatelessWidget {
  final ScheduleEntry scheduleEntry;
  final String timezone;

  const ScheduleCard({
    super.key,
    required this.scheduleEntry,
    required this.timezone,
  });

  String _formatDateTime(String isoString) {
    try {
      final dateTime = DateTime.parse(isoString);
      final formatter = DateFormat('EEEE, MMMM d, y \'at\' h:mm a');
      return formatter.format(dateTime.toLocal());
    } catch (e) {
      return isoString;
    }
  }

  String _formatTime(String isoString) {
    try {
      final dateTime = DateTime.parse(isoString);
      final formatter = DateFormat('h:mm a');
      return formatter.format(dateTime.toLocal());
    } catch (e) {
      return isoString;
    }
  }

  @override
  Widget build(BuildContext context) {
    final schedule = scheduleEntry.schedule;
    
    return Card(
      elevation: 10,
      shadowColor: AppTheme.textPrimary.withOpacity(0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              schedule.label,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _buildNextSweepInfo(),
            const SizedBox(height: 16),
            _buildScheduleChip(schedule.fullName ?? 'Unknown schedule'),
            const SizedBox(height: 20),
            _buildDetailsGrid(),
          ],
        ),
      ),
    );
  }

  Widget _buildNextSweepInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.event_available,
            color: AppTheme.primaryColor,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Next sweep window',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDateTime(scheduleEntry.nextSweepStart),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '→ ${_formatTime(scheduleEntry.nextSweepEnd)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppTheme.primaryColor,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildDetailsGrid() {
    final schedule = scheduleEntry.schedule;
    
    return Column(
      children: [
        _buildDetailRow(
          'Limits',
          schedule.limits ?? schedule.corridor ?? 'N/A',
        ),
        const SizedBox(height: 16),
        _buildDetailRow(
          'Block side',
          schedule.blockSide ?? schedule.cnnRightLeft ?? 'Not specified',
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildDetailRow(
                'Hours',
                '${schedule.fromHour ?? '?'}:00 → ${schedule.toHour ?? '?'}:00',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDetailRow(
                'Weekday',
                schedule.weekDay ?? 'N/A',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
            fontSize: 13,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

