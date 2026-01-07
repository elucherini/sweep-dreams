import 'dart:async';
import 'dart:developer';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/parking_response.dart';
import '../models/schedule_response.dart';
import '../services/api_service.dart'
    show ApiService, SubscriptionLimitException;
import '../services/subscription_state.dart';
import '../theme/app_theme.dart';
import 'notification_confirmation.dart';
import 'reminder_picker.dart';

class ParkingRegulationCard extends StatefulWidget {
  final ParkingRegulation regulation;
  final bool isSelected;
  final VoidCallback onTap;
  final RequestPoint requestPoint;

  /// ISO datetime string for the move deadline (used for reminder picker)
  final String? moveDeadlineIso;

  const ParkingRegulationCard({
    super.key,
    required this.regulation,
    required this.isSelected,
    required this.onTap,
    required this.requestPoint,
    this.moveDeadlineIso,
  });

  @override
  State<ParkingRegulationCard> createState() => _ParkingRegulationCardState();
}

class _ParkingRegulationCardState extends State<ParkingRegulationCard> {
  static final Map<int, ReminderSelection> _subscribedRegulations =
      <int, ReminderSelection>{};
  static const String _webPushCertificateKeyPair = String.fromEnvironment(
    'WEB_PUSH_CERTIFICATE_KEY_PAIR',
  );

  bool _isRequestingToken = false;
  ReminderSelection? _selectedPreset;

  @override
  void initState() {
    super.initState();
    _selectedPreset = _subscribedRegulations[widget.regulation.id];
  }

  @override
  void didUpdateWidget(covariant ParkingRegulationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.regulation.id != widget.regulation.id) {
      _selectedPreset = _subscribedRegulations[widget.regulation.id];
    }
  }

  String _formatTimeRange() {
    final from = widget.regulation.fromTime;
    final to = widget.regulation.toTime;
    if (from == null || to == null) return '';
    return '$from - $to';
  }

  String _formatScheduleDescription() {
    final parts = <String>[];
    if (widget.regulation.days != null) {
      parts.add(widget.regulation.days!);
    }
    final timeRange = _formatTimeRange();
    if (timeRange.isNotEmpty) {
      parts.add(timeRange);
    }
    return parts.join('  ·  ');
  }

  Future<void> _showReminderPickerAndSubscribe() async {
    // Need a deadline to show the reminder picker
    final deadlineIso = widget.moveDeadlineIso;
    if (deadlineIso == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Cannot set reminder: no deadline available')),
      );
      return;
    }

    final selection = await showReminderPicker(
      context: context,
      streetName: widget.regulation.regulation,
      scheduleDescription: _formatScheduleDescription(),
      sweepStartIso: deadlineIso,
      selected: _selectedPreset,
      forTiming: true,
    );

    if (selection == null || !mounted) return;

    await _requestPermissionAndGetToken(selection, deadlineIso);
  }

  Future<void> _requestPermissionAndGetToken(
      ReminderSelection selection, String deadlineIso) async {
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
        if (!mounted) return;
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
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Add WEB_PUSH_CERTIFICATE_KEY_PAIR to enable web notifications.'),
          ),
        );
        return;
      }

      final vapidKey = kIsWeb && _webPushCertificateKeyPair.isNotEmpty
          ? _webPushCertificateKeyPair
          : null;

      // On iOS, wait for the APNs token to be available before getting FCM token
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        String? apnsToken = await messaging.getAPNSToken();
        int retries = 0;
        while (apnsToken == null && retries < 10) {
          await Future.delayed(const Duration(milliseconds: 500));
          apnsToken = await messaging.getAPNSToken();
          retries++;
        }
        if (apnsToken == null) {
          log('Failed to get APNs token after $retries retries');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Failed to register for push notifications')),
          );
          return;
        }
        log('APNs token received after $retries retries');
      }

      final token = await messaging.getToken(
        vapidKey: vapidKey,
      );

      if (token == null) {
        log('Failed to get FCM token');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to get FCM token')),
        );
        return;
      }
      if (!mounted) return;

      await _subscribeDevice(token, selection, deadlineIso);
    } catch (e, st) {
      log('Error getting FCM token: $e', stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isRequestingToken = false);
      }
    }
  }

  Future<void> _subscribeDevice(
      String token, ReminderSelection selection, String deadlineIso) async {
    final api = context.read<ApiService>();

    try {
      await api.subscribeToSchedule(
        deviceToken: token,
        scheduleBlockSweepId: widget.regulation.id,
        latitude: widget.requestPoint.latitude,
        longitude: widget.requestPoint.longitude,
        leadMinutes: selection.leadMinutesFor(deadlineIso),
        subscriptionType: 'timing',
      );

      if (!mounted) return;

      setState(() {
        _selectedPreset = selection;
      });
      _subscribedRegulations[widget.regulation.id] = selection;

      // Update shared subscription state
      if (mounted) {
        context.read<SubscriptionState>().addSubscription(widget.regulation.id);
      }
    } on SubscriptionLimitException {
      log('Subscription limit reached');
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Alert limit reached'),
          content: const Text(
            'You\'ve reached the maximum number of alerts. Go to the Alerts tab to remove one before adding another.',
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
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
    final colors = Theme.of(context).colorScheme;
    final reg = widget.regulation;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color:
              (widget.isSelected ? AppTheme.primarySoft : AppTheme.surfaceSoft)
                  .withValues(alpha: AppTheme.paperInGlassOpacity),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: widget.isSelected
                ? colors.primary.withValues(alpha: 0.22)
                : colors.outlineVariant.withValues(alpha: 0.28),
            width: widget.isSelected ? 1.1 : 0.8,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: regulation title + distance badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      reg.regulation,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _DistanceBadge(distance: reg.distance),
                ],
              ),
              // Hour limit if applicable
              if (reg.hourLimit != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${reg.hourLimit}-hour parking limit',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
              // Days and time range
              if (reg.days != null || reg.fromTime != null) ...[
                const SizedBox(height: 4),
                Text(
                  _formatScheduleDescription(),
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
              // RPP area info
              if (reg.rppArea != null) ...[
                const SizedBox(height: 4),
                Text(
                  'RPP Area ${reg.rppArea} exempt',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
              // Exceptions
              if (reg.exceptions != null && reg.exceptions!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  reg.exceptions!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
              // Notification button/confirmation
              const SizedBox(height: 12),
              _buildNotificationSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationSection() {
    // Check shared subscription state first (source of truth)
    final subscriptionState = context.watch<SubscriptionState>();
    final isSubscribed = subscriptionState.isSubscribed(widget.regulation.id);

    // If no longer subscribed, clear local state
    if (!isSubscribed && _selectedPreset != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _selectedPreset = null;
            _subscribedRegulations.remove(widget.regulation.id);
          });
        }
      });
    }

    // Check if subscribed in current session with known preset
    if (isSubscribed &&
        _selectedPreset != null &&
        widget.moveDeadlineIso != null) {
      final leadMinutes =
          _selectedPreset!.leadMinutesFor(widget.moveDeadlineIso!);
      final message = leadMinutes == 0
          ? "You'll be notified when it's time to move your car"
          : "You'll be notified $leadMinutes min before";
      return NotificationConfirmation(message: message);
    }

    // Check if already subscribed via shared state (from backend)
    if (isSubscribed) {
      return const NotificationConfirmation(
        message: "You'll be notified before the deadline",
        subtitle:
            'To change, delete your alert from the Alerts screen, then come back.',
      );
    }

    // Not subscribed - show the button
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isRequestingToken ? null : _showReminderPickerAndSubscribe,
        child: _isRequestingToken
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Requesting...',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            : const Text('Turn on reminders'),
      ),
    );
  }
}

class _DistanceBadge extends StatelessWidget {
  final String distance;

  const _DistanceBadge({required this.distance});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        distance,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppTheme.textMuted,
        ),
      ),
    );
  }
}
