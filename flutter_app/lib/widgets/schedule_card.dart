import 'dart:async';
import 'dart:developer';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/schedule_response.dart';
import '../services/api_service.dart'
    show ApiService, SubscriptionLimitException;
import '../services/subscription_state.dart';
import '../theme/app_theme.dart';
import '../utils/time_format.dart';
import 'base_card.dart';
import 'reminder_picker.dart';
import 'time_until_badge.dart';

class ScheduleCard extends StatefulWidget {
  final ScheduleEntry scheduleEntry;
  final String timezone;
  final RequestPoint requestPoint;
  final List<String?>? sides;
  final String? selectedSide;
  final void Function(String?)? onSideChanged;

  const ScheduleCard({
    super.key,
    required this.scheduleEntry,
    required this.timezone,
    required this.requestPoint,
    this.sides,
    this.selectedSide,
    this.onSideChanged,
  });

  @override
  State<ScheduleCard> createState() => _ScheduleCardState();
}

class _ScheduleCardState extends State<ScheduleCard> {
  static final Map<int, ReminderSelection> _subscribedBlocks =
      <int, ReminderSelection>{};
  static const String _webPushCertificateKeyPair = String.fromEnvironment(
    'WEB_PUSH_CERTIFICATE_KEY_PAIR',
  );

  bool _isRequestingToken = false;
  String? _token;
  ReminderSelection? _selectedPreset;
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    _selectedPreset = _subscribedBlocks[widget.scheduleEntry.blockSweepId];
    _startUpdateTimer();
  }

  @override
  void didUpdateWidget(covariant ScheduleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scheduleEntry.blockSweepId !=
        widget.scheduleEntry.blockSweepId) {
      _selectedPreset = _subscribedBlocks[widget.scheduleEntry.blockSweepId];
      _token = null; // Reset token state for new block
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  void _startUpdateTimer() {
    // Update every minute to recalculate the countdown
    _updateTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        setState(() {
          // Trigger rebuild - formatTimeUntil will recalculate
        });
      }
    });
  }

  String _formatScheduleDescription() {
    try {
      final startDateTime = DateTime.parse(widget.scheduleEntry.nextSweepStart);
      final endDateTime = DateTime.parse(widget.scheduleEntry.nextSweepEnd);

      final dateFormatter = DateFormat('EEE, MMM d');
      final startTimeFormatter = DateFormat('h');
      final endTimeFormatter = DateFormat('ha');

      final datePart = dateFormatter.format(startDateTime.toLocal());
      final startTime = startTimeFormatter.format(startDateTime.toLocal());
      final endTime =
          endTimeFormatter.format(endDateTime.toLocal()).toLowerCase();

      return '$datePart  ·  $startTime–$endTime';
    } catch (e) {
      return '';
    }
  }

  Future<void> _showReminderPickerAndSubscribe() async {
    final selection = await showReminderPicker(
      context: context,
      streetName: widget.scheduleEntry.corridor,
      scheduleDescription: _formatScheduleDescription(),
      sweepStartIso: widget.scheduleEntry.nextSweepStart,
      selected: _selectedPreset,
    );

    if (selection == null || !mounted) return;

    // User selected a reminder option, proceed with notification setup
    await _requestPermissionAndGetToken(selection);
  }

  Future<void> _requestPermissionAndGetToken(
      ReminderSelection selection) async {
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
        // If not available yet, wait and retry a few times
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

      setState(() {
        _token = token;
      });

      await _subscribeDevice(token, selection);
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
      String token, ReminderSelection selection) async {
    final api = context.read<ApiService>();

    try {
      await api.subscribeToSchedule(
        deviceToken: token,
        scheduleBlockSweepId: widget.scheduleEntry.blockSweepId,
        latitude: widget.requestPoint.latitude,
        longitude: widget.requestPoint.longitude,
        leadMinutes:
            selection.leadMinutesFor(widget.scheduleEntry.nextSweepStart),
      );

      if (!mounted) return;

      setState(() {
        _selectedPreset = selection;
      });
      _subscribedBlocks[widget.scheduleEntry.blockSweepId] = selection;

      // Update shared subscription state
      if (mounted) {
        context
            .read<SubscriptionState>()
            .addSubscription(widget.scheduleEntry.blockSweepId);
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
    return _buildCombinedCard();
  }

  Widget _buildSideSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Which side of the street?',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
        ),
        const SizedBox(height: 12),
        Row(
          children: widget.sides!.map((side) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: side == widget.sides!.last ? 0 : 8,
                ),
                child: _SideButton(
                  side: side,
                  isSelected: widget.selectedSide == side,
                  onTap: widget.onSideChanged != null
                      ? () => widget.onSideChanged!(side)
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCombinedCard() {
    final entry = widget.scheduleEntry;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Side selector (if multiple sides available) - outside the card
        if (widget.sides != null && widget.sides!.length > 1) ...[
          _buildSideSelector(),
          const SizedBox(height: 14),
        ],
        // Time until sweep badge - outside the card
        TimeUntilBadge(startIso: widget.scheduleEntry.nextSweepStart),
        const SizedBox(height: 14),
        // The rest of the content in a BaseCard
        BaseCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title: corridor between limits
              Text(
                '${entry.corridor} between ${entry.limits}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
              // Next sweep window
              Text(
                'Next sweep: ${formatSweepWindow(
                  widget.scheduleEntry.nextSweepStart,
                  widget.scheduleEntry.nextSweepEnd,
                )}',
                style: const TextStyle(
                  fontSize: 15,
                  color: AppTheme.textMuted,
                ),
              ),
              // Schedule rules
              const SizedBox(height: 12),
              const Text(
                'Schedule',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              ...widget.scheduleEntry.humanRules.map((humanRule) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '• ',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          humanRule,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        // Notification section - outside the card
        const SizedBox(height: 14),
        _buildNotificationSection(),
      ],
    );
  }

  Widget _buildNotificationSection() {
    // Check shared subscription state first (source of truth)
    final subscriptionState = context.watch<SubscriptionState>();
    final isSubscribed =
        subscriptionState.isSubscribed(widget.scheduleEntry.blockSweepId);

    // If no longer subscribed, clear local state
    if (!isSubscribed && _selectedPreset != null) {
      // Schedule cleanup for after build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _selectedPreset = null;
            _subscribedBlocks.remove(widget.scheduleEntry.blockSweepId);
          });
        }
      });
    }

    // Check if subscribed in current session with known preset
    if (isSubscribed && _selectedPreset != null) {
      return Row(
        children: [
          const Icon(
            Icons.check_circle,
            color: AppTheme.primaryColor,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "You'll be notified ${formatLeadTime(
                _selectedPreset!
                    .leadMinutesFor(widget.scheduleEntry.nextSweepStart),
                sweepStartIso: widget.scheduleEntry.nextSweepStart,
              )}",
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      );
    }

    // Check if already subscribed via shared state (from backend)
    if (isSubscribed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  "You'll be notified before this sweep",
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'To change, delete your alert from the Alerts screen, then come back.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textMuted,
                ),
          ),
        ],
      );
    }

    // Not subscribed - show the button
    return ElevatedButton(
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
          : Text(
              _token != null
                  ? 'Retry enabling notifications'
                  : 'Turn on reminders',
            ),
    );
  }
}

class _SideButton extends StatefulWidget {
  final String? side;
  final bool isSelected;
  final VoidCallback? onTap;

  const _SideButton({
    required this.side,
    required this.isSelected,
    this.onTap,
  });

  @override
  State<_SideButton> createState() => _SideButtonState();
}

class _SideButtonState extends State<_SideButton> {
  double _opacity = 1.0;

  void _handleTap() {
    if (widget.onTap == null) return;
    setState(() => _opacity = 0.5);
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) setState(() => _opacity = 1.0);
    });
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final displayName = widget.side ?? 'Unknown';
    final backgroundColor =
        (widget.isSelected ? AppTheme.primarySoft : AppTheme.surfaceSoft)
            .withValues(alpha: AppTheme.paperInGlassOpacity);
    final borderColor = widget.isSelected
        ? colors.primary.withValues(alpha: 0.22)
        : colors.outlineVariant.withValues(alpha: 0.32);
    final textColor =
        widget.isSelected ? colors.primary : AppTheme.textPrimary;

    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedOpacity(
        opacity: _opacity,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor,
              width: widget.isSelected ? 1.1 : 0.9,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            child: Center(
              child: Text(
                displayName,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: textColor,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
