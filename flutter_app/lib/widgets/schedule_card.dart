import 'dart:async';
import 'dart:developer';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/schedule_response.dart';
import '../services/api_service.dart';
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
  static final Map<int, ReminderPreset> _subscribedBlocks =
      <int, ReminderPreset>{};
  static const String _webPushCertificateKeyPair = String.fromEnvironment(
    'WEB_PUSH_CERTIFICATE_KEY_PAIR',
    defaultValue:
        'BIwuhQLU2Zgt2g6cgCj26JhJHJj3iR7i4QcObqEIBljkDMGTud7iHbYQhdHeuqln1b_CzxHspJZ8U8T1Qr7uNFA',
  );

  bool _isRequestingToken = false;
  String? _token;
  ReminderPreset? _selectedPreset;
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
    final preset = await showReminderPicker(
      context: context,
      streetName: widget.scheduleEntry.corridor,
      scheduleDescription: _formatScheduleDescription(),
    );

    if (preset == null || !mounted) return;

    // User selected a reminder preset, proceed with notification setup
    await _requestPermissionAndGetToken(preset);
  }

  Future<void> _requestPermissionAndGetToken(ReminderPreset preset) async {
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

      await _subscribeDevice(token, preset);
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

  Future<void> _subscribeDevice(String token, ReminderPreset preset) async {
    final api = context.read<ApiService>();

    try {
      await api.subscribeToSchedule(
        deviceToken: token,
        scheduleBlockSweepId: widget.scheduleEntry.blockSweepId,
        latitude: widget.requestPoint.latitude,
        longitude: widget.requestPoint.longitude,
        leadMinutes: preset.leadMinutesFor(widget.scheduleEntry.nextSweepStart),
      );

      if (!mounted) return;

      setState(() {
        _selectedPreset = preset;
      });
      _subscribedBlocks[widget.scheduleEntry.blockSweepId] = preset;
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
    final colors = Theme.of(context).colorScheme;

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
            final isSelected = widget.selectedSide == side;
            final displayName = side ?? 'Unknown';
            const baseColor = Color(0xFFFEFCF7); // warmer white
            final borderColor = isSelected
                ? colors.primary.withValues(alpha: 0.35)
                : colors.outlineVariant.withValues(alpha: 0.28);
            final textColor =
                isSelected ? colors.primary : AppTheme.textPrimary;

            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: side == widget.sides!.last ? 0 : 8,
                ),
                child: GestureDetector(
                  onTap: widget.onSideChanged != null
                      ? () => widget.onSideChanged!(side)
                      : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: baseColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: borderColor,
                        width: isSelected ? 1.1 : 0.9,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.055),
                          blurRadius: isSelected ? 14 : 11,
                          offset: const Offset(0, 5),
                        ),
                        if (isSelected)
                          BoxShadow(
                            color: colors.primary.withValues(alpha: 0.1),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                      ],
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
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCombinedCard() {
    final entry = widget.scheduleEntry;

    return BaseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Side selector (if multiple sides available)
          if (widget.sides != null && widget.sides!.length > 1) ...[
            _buildSideSelector(),
            const SizedBox(height: 14),
          ],
          // Time until sweep badge
          TimeUntilBadge(startIso: widget.scheduleEntry.nextSweepStart),
          const SizedBox(height: 14),
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
          // Notification section
          const SizedBox(height: 12),
          if (_selectedPreset != null)
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
                    "You'll be notified ${formatLeadTime(
                      _selectedPreset!.leadMinutesFor(widget.scheduleEntry.nextSweepStart),
                      sweepStartIso: widget.scheduleEntry.nextSweepStart,
                    )}",
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            )
          else
            ElevatedButton(
              onPressed:
                  _isRequestingToken ? null : _showReminderPickerAndSubscribe,
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              ),
              child: _isRequestingToken
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
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
            ),
        ],
      ),
    );
  }
}
