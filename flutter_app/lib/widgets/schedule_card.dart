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

  String _formatNextSweepWindow(String startIso, String endIso) {
    try {
      final startDateTime = DateTime.parse(startIso);
      final endDateTime = DateTime.parse(endIso);

      // Format: "Fri Dec 5, 2025 at 2am->6am"
      final dateFormatter = DateFormat('EEE MMM d, y');
      final startTimeFormatter = DateFormat('ha');
      final endTimeFormatter = DateFormat('ha');

      final datePart = dateFormatter.format(startDateTime.toLocal());
      final startTime = startTimeFormatter.format(startDateTime.toLocal()).toLowerCase();
      final endTime = endTimeFormatter.format(endDateTime.toLocal()).toLowerCase();

      return '$datePart at $startTime->$endTime';
    } catch (e) {
      return '$startIso -> $endIso';
    }
  }


  @override
  Widget build(BuildContext context) {
    final schedule = scheduleEntry.schedule;
    
    return Card(
      elevation: 12,
      shadowColor: AppTheme.primaryColor.withOpacity(0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppTheme.border.withOpacity(0.5)),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.surface,
              AppTheme.surface.withOpacity(0.98),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.cleaning_services,
                      color: AppTheme.primaryColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      schedule.label,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildNextSweepInfo(),
              const SizedBox(height: 20),
              _buildDetailsGrid(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNextSweepInfo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primarySoft,
            AppTheme.primarySoft.withOpacity(0.5),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.schedule,
              color: AppTheme.primaryColor,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
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
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatNextSweepWindow(
                    scheduleEntry.nextSweepStart,
                    scheduleEntry.nextSweepEnd,
                  ),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryColor,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsGrid() {
    final schedule = scheduleEntry.schedule;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Schedule',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
            fontSize: 13,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        ...scheduleEntry.humanRules.asMap().entries.map((entry) {
          final index = entry.key;
          final humanRule = entry.value;
          final rule = index < schedule.rules.length ? schedule.rules[index] : null;
          final holidayText = rule != null
              ? (rule.skipHolidays ? ', except holidays' : ', including holidays')
              : '';

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    '• ',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 15,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '$humanRule$holidayText',
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}


