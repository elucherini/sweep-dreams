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
import 'base_card.dart';
import 'notification_confirmation.dart';
import 'reminder_picker.dart';

class ParkingRegulationCard extends StatefulWidget {
  final ParkingRegulation regulation;
  final bool isSelected;
  final VoidCallback? onTap;
  final RequestPoint requestPoint;

  /// ISO datetime string for the move deadline (used for reminder picker)
  final String? moveDeadlineIso;

  const ParkingRegulationCard({
    super.key,
    required this.regulation,
    required this.isSelected,
    this.onTap,
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
    return '$from–$to';
  }

  String? _formatScheduleLine() {
    final parts = <String>[];
    if (widget.regulation.days != null && widget.regulation.days!.isNotEmpty) {
      parts.add(widget.regulation.days!);
    }
    final timeRange = _formatTimeRange();
    if (timeRange.isNotEmpty) {
      parts.add(timeRange);
    }
    if (parts.isEmpty) return null;
    return parts.join('  ·  ');
  }

  int? _parseTimeToMinutes(String value) {
    final normalized = value.trim().toLowerCase();

    if (normalized == 'midnight') return 0;
    if (normalized == 'noon') return 12 * 60;

    final match12 =
        RegExp(r'^(\d{1,2})(?::(\d{2}))?\s*([ap]m)$').firstMatch(normalized);
    if (match12 != null) {
      final hour = int.tryParse(match12.group(1)!);
      final minute = int.tryParse(match12.group(2) ?? '0') ?? 0;
      final period = match12.group(3)!;
      if (hour == null || hour < 1 || hour > 12 || minute < 0 || minute > 59) {
        return null;
      }
      var hour24 = hour % 12;
      if (period == 'pm') hour24 += 12;
      return hour24 * 60 + minute;
    }

    final match24 = RegExp(r'^(\d{1,2})(?::(\d{2}))?$').firstMatch(normalized);
    if (match24 != null) {
      final hour = int.tryParse(match24.group(1)!);
      final minute = int.tryParse(match24.group(2) ?? '0') ?? 0;
      if (hour == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
        return null;
      }
      return hour * 60 + minute;
    }

    return null;
  }

  Set<int>? _parseWeekdays(String days) {
    final normalized = days.trim().toLowerCase().replaceAll('.', '');
    final withHyphen = normalized.replaceAll('–', '-').replaceAll('—', '-');

    if (withHyphen == 'daily' ||
        withHyphen == 'every day' ||
        withHyphen == 'everyday') {
      return {1, 2, 3, 4, 5, 6, 7};
    }

    if (withHyphen.contains('weekdays')) return {1, 2, 3, 4, 5};
    if (withHyphen.contains('weekends')) return {6, 7};

    const dayMap = <String, int>{
      'mon': 1,
      'monday': 1,
      'tue': 2,
      'tues': 2,
      'tuesday': 2,
      'wed': 3,
      'weds': 3,
      'wednesday': 3,
      'thu': 4,
      'thur': 4,
      'thurs': 4,
      'thursday': 4,
      'fri': 5,
      'friday': 5,
      'sat': 6,
      'saturday': 6,
      'sun': 7,
      'sunday': 7,
      // Common short forms from backend parsing.
      'm': 1,
      'sa': 6,
      'su': 7,
      'f': 5,
    };

    final matchRange = RegExp(r'^(\w+)\s*-\s*(\w+)$').firstMatch(withHyphen);
    if (matchRange != null) {
      final start = dayMap[matchRange.group(1)!];
      final end = dayMap[matchRange.group(2)!];
      if (start == null || end == null) return null;
      final result = <int>{};
      var current = start;
      for (var i = 0; i < 7; i++) {
        result.add(current);
        if (current == end) break;
        current = current == 7 ? 1 : current + 1;
      }
      return result;
    }

    final tokens = withHyphen
        .split(RegExp(r'[,/\s]+'))
        .where((t) => t.trim().isNotEmpty)
        .toList();
    if (tokens.isEmpty) return null;

    final result = <int>{};
    for (final token in tokens) {
      final day = dayMap[token];
      if (day == null) return null;
      result.add(day);
    }
    return result;
  }

  bool? _isInForceNow() {
    final days = widget.regulation.days;
    final from = widget.regulation.fromTime;
    final to = widget.regulation.toTime;
    if (days == null || from == null || to == null) return null;

    final weekdays = _parseWeekdays(days);
    if (weekdays == null) return null;

    final startMinutes = _parseTimeToMinutes(from);
    final endMinutes = _parseTimeToMinutes(to);
    if (startMinutes == null || endMinutes == null) return null;

    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final today = now.weekday;

    if (startMinutes == endMinutes) {
      return weekdays.contains(today);
    }

    if (startMinutes < endMinutes) {
      if (!weekdays.contains(today)) return false;
      return nowMinutes >= startMinutes && nowMinutes < endMinutes;
    }

    // Overnight window (e.g., 10pm–6am)
    if (nowMinutes >= startMinutes) {
      return weekdays.contains(today);
    }
    final yesterday = today == 1 ? 7 : today - 1;
    return weekdays.contains(yesterday);
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
      scheduleDescription: _formatScheduleLine() ?? '',
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
    final scheduleLine = _formatScheduleLine();
    final inForce = _isInForceNow();

    final statusBadge = _PillBadge(
      icon: inForce == null
          ? Icons.help_outline
          : (inForce ? Icons.schedule_outlined : Icons.schedule),
      label: inForce == null
          ? 'Status unknown'
          : (inForce ? 'In force now' : 'Not in force'),
      backgroundColor: inForce == true
          ? AppTheme.primarySoft.withValues(alpha: 0.92)
          : AppTheme.surfaceSoft.withValues(alpha: 0.92),
      borderColor: inForce == true
          ? colors.primary.withValues(alpha: 0.22)
          : colors.outlineVariant.withValues(alpha: 0.35),
      foregroundColor: inForce == true ? colors.primary : AppTheme.textMuted,
    );

    final card = BaseCard(
      borderColor: widget.isSelected
          ? colors.primary.withValues(alpha: 0.22)
          : colors.outlineVariant.withValues(alpha: 0.28),
      borderWidth: widget.isSelected ? 1.1 : 0.8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PARKING REGULATION',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppTheme.textMuted,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            reg.hourLimit != null
                ? '${reg.hourLimit}-hour parking limit'
                : reg.regulation,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary,
            ),
          ),
          if (scheduleLine != null) ...[
            const SizedBox(height: 2),
            Text(
              scheduleLine,
              style: const TextStyle(
                fontSize: 15,
                color: AppTheme.textMuted,
              ),
            ),
          ],
          if (reg.rppArea != null && reg.rppArea!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'RPP Area ${reg.rppArea} holders exempt',
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textMuted,
              ),
            ),
          ],
          if (reg.neighborhood != null && reg.neighborhood!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              reg.neighborhood!,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textMuted,
              ),
            ),
          ],
          if (reg.exceptions != null && reg.exceptions!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              reg.exceptions!,
              style: const TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: AppTheme.textMuted,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Divider(
            height: 1,
            thickness: 0.8,
            color: colors.outlineVariant.withValues(alpha: 0.28),
          ),
          const SizedBox(height: 14),
          _buildNotificationSection(),
        ],
      ),
    );

    final tappableCard = widget.onTap == null
        ? card
        : Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(14),
              child: card,
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [statusBadge],
        ),
        const SizedBox(height: 10),
        tappableCard,
      ],
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

class _PillBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color borderColor;
  final Color foregroundColor;

  const _PillBadge({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.borderColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: borderColor, width: 0.9),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: foregroundColor),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: foregroundColor,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
