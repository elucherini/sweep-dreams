import 'dart:developer';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/schedule_response.dart';
import '../services/api_service.dart';
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
  static final Set<int> _subscribedBlockIds = <int>{};
  static const String _webPushCertificateKeyPair = String.fromEnvironment(
    'WEB_PUSH_CERTIFICATE_KEY_PAIR',
    defaultValue: 'BIwuhQLU2Zgt2g6cgCj26JhJHJj3iR7i4QcObqEIBljkDMGTud7iHbYQhdHeuqln1b_CzxHspJZ8U8T1Qr7uNFA',
  );

  bool _isRequestingToken = false;
  String? _token;
  bool _subscriptionSaved = false;

  @override
  void initState() {
    super.initState();
    _subscriptionSaved =
        _subscribedBlockIds.contains(widget.scheduleEntry.blockSweepId);
  }

  @override
  void didUpdateWidget(covariant ScheduleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scheduleEntry.blockSweepId !=
        widget.scheduleEntry.blockSweepId) {
      _subscriptionSaved =
          _subscribedBlockIds.contains(widget.scheduleEntry.blockSweepId);
    }
  }

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

  Future<void> _requestPermissionAndGetToken() async {
    setState(() => _isRequestingToken = true);

    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        log('Notification permission denied');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification permission denied')),
        );
        return;
      }

      if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        log('Notification permission not determined');
        return;
      }

      if (kIsWeb && _webPushCertificateKeyPair.isEmpty) {
        log('Missing WEB_PUSH_CERTIFICATE_KEY_PAIR for web push setup');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Add WEB_PUSH_CERTIFICATE_KEY_PAIR to enable web notifications.'),
          ),
        );
        return;
      }

      final vapidKey = kIsWeb && _webPushCertificateKeyPair.isNotEmpty
          ? _webPushCertificateKeyPair
          : null;

      final token = await messaging.getToken(
        vapidKey: vapidKey,
      );

      if (token == null) {
        log('Failed to get FCM token');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to get FCM token')),
        );
        return;
      }

      log('FCM token: $token');
      if (!mounted) return;

      setState(() {
        _token = token;
      });

      await _subscribeDevice(token);
    } catch (e, st) {
      log('Error getting FCM token: $e', stackTrace: st);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isRequestingToken = false);
      }
    }
  }

  Future<void> _subscribeDevice(String token) async {
    final api = context.read<ApiService>();

    try {
      await api.subscribeToSchedule(
        deviceToken: token,
        scheduleBlockSweepId: widget.scheduleEntry.blockSweepId,
        latitude: widget.requestPoint.latitude,
        longitude: widget.requestPoint.longitude,
      );

      if (!mounted) return;

      setState(() {
        _subscriptionSaved = true;
      });
      _subscribedBlockIds.add(widget.scheduleEntry.blockSweepId);
    } catch (e, st) {
      log('Failed to save subscription: $e', stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save subscription: $e')),
      );
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
              const SizedBox(height: 20),
              _buildNotificationSection(),
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
                Text(_formatTimeUntil(widget.scheduleEntry.nextSweepStart),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryColor,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatNextSweepWindow(
                    widget.scheduleEntry.nextSweepStart,
                    widget.scheduleEntry.nextSweepEnd,
                  ),
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

  Widget _buildNotificationSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft.withOpacity(0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.notifications_active_outlined,
                  color: AppTheme.primaryColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Parked here? Get notified before street cleaning',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_subscriptionSaved)
            Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppTheme.primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Notifications enabled!',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            )
          else
            FilledButton.icon(
              onPressed: _isRequestingToken ? null : _requestPermissionAndGetToken,
              icon: _isRequestingToken
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.key_rounded),
              label: Text(
                _isRequestingToken
                    ? 'Requesting permission...'
                    : (_token != null
                        ? 'Retry enabling notifications'
                        : 'Send me a reminder an hour earlier'),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
