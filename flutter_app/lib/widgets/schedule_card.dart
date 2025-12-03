import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/schedule_response.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

class ScheduleCard extends StatefulWidget {
  final ScheduleEntry scheduleEntry;
  final String timezone;
  final RequestPoint requestPoint;

  const ScheduleCard({
    super.key,
    required this.scheduleEntry,
    required this.timezone,
    required this.requestPoint,
  });

  @override
  State<ScheduleCard> createState() => _ScheduleCardState();
}

class _ScheduleCardState extends State<ScheduleCard> {
  bool _isSubscribing = false;

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

  String _formatTimeUntil(String startIso) {
    try {
      final startDateTime = DateTime.parse(startIso).toLocal();
      final now = DateTime.now();
      final difference = startDateTime.difference(now);

      if (difference.isNegative) {
        return '';
      }

      final totalHours = difference.inHours;
      final totalMinutes = difference.inMinutes;

      if (totalHours >= 48) {
        // More than 48 hours: show "in x days"
        final days = difference.inDays + 1;
        return 'in $days ${days == 1 ? 'day' : 'days'}';
      } else if (totalHours >= 24) {
        // Between 48 and 24 hours: show "in x days and y hours"
        final days = difference.inDays;
        final hours = totalHours - (days * 24);
        return 'in $days ${days == 1 ? 'day' : 'days'} and $hours ${hours == 1 ? 'hour' : 'hours'}';
      } else if (totalHours >= 6) {
        // Between 24 and 6 hours: show "in x hours"
        return 'in $totalHours ${totalHours == 1 ? 'hour' : 'hours'}';
      } else if (totalHours >= 1) {
        // Between 6 hours and 1 hour: show "in x hours and y minutes"
        final hours = totalHours;
        final minutes = totalMinutes - (hours * 60);
        return 'in $hours ${hours == 1 ? 'hour' : 'hours'} and $minutes ${minutes == 1 ? 'minute' : 'minutes'}';
      } else {
        // Under 1 hour: show "in x minutes"
        return 'in $totalMinutes ${totalMinutes == 1 ? 'minute' : 'minutes'}';
      }
    } catch (e) {
      return '';
    }
  }


  @override
  Widget build(BuildContext context) {
    final schedule = widget.scheduleEntry.schedule;
    
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
              const SizedBox(height: 24),
              _buildSubscribeButton(context),
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
                    widget.scheduleEntry.nextSweepStart,
                    widget.scheduleEntry.nextSweepEnd,
                  ),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryColor,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTimeUntil(widget.scheduleEntry.nextSweepStart),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted.withValues(alpha: 0.8),
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
    final schedule = widget.scheduleEntry.schedule;

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
        ...widget.scheduleEntry.humanRules.asMap().entries.map((entry) {
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

  Widget _buildSubscribeButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isSubscribing ? null : () => _handleSubscribe(context),
        icon: _isSubscribing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.directions_car),
        label: Text(_isSubscribing ? 'Saving...' : 'I parked here'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Future<void> _handleSubscribe(BuildContext context) async {
    final blockSweepId = widget.scheduleEntry.blockSweepId ?? widget.scheduleEntry.schedule.blockSweepId;
    if (blockSweepId == null) {
      _showSnack(context, 'No schedule id available for this block yet.');
      return;
    }

    final confirm = await _showConfirmationDialog(context);
    if (confirm != true) return;

    setState(() {
      _isSubscribing = true;
    });

    try {
      final notificationService = context.read<NotificationService>();
      final apiService = context.read<ApiService>();

      final token = await notificationService.requestPermissionAndToken();
      if (token == null) {
        _showSnack(context, 'Notifications are blocked or permissions were denied.');
        return;
      }

      await apiService.subscribeToSchedule(
        deviceToken: token,
        platform: notificationService.platformLabel,
        scheduleBlockSweepId: blockSweepId,
        latitude: widget.requestPoint.latitude,
        longitude: widget.requestPoint.longitude,
      );

      _showSnack(context, 'Notifications set for this block.');
    } catch (e) {
      _showSnack(context, 'Could not enable notifications: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSubscribing = false;
        });
      }
    }
  }

  Future<bool?> _showConfirmationDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enable reminders?'),
        content: const Text(
          'We will remind you 1 hour before the next sweep window for this block. Allow notifications to continue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No, thanks'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes, notify me'),
          ),
        ],
      ),
    );
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
