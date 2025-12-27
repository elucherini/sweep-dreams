import 'dart:developer';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/subscription_response.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  AlertsScreenState createState() => AlertsScreenState();
}

class AlertsScreenState extends State<AlertsScreen> {
  static const String _webPushCertificateKeyPair = String.fromEnvironment(
    'WEB_PUSH_CERTIFICATE_KEY_PAIR',
    defaultValue:
        'BIwuhQLU2Zgt2g6cgCj26JhJHJj3iR7i4QcObqEIBljkDMGTud7iHbYQhdHeuqln1b_CzxHspJZ8U8T1Qr7uNFA',
  );

  bool _isLoading = false;
  String? _errorMessage;
  SubscriptionResponse? _subscription;
  String? _deviceToken;

  @override
  void initState() {
    super.initState();
    _loadSubscription();
  }

  /// Public method to refresh the subscription data
  void refresh() {
    _loadSubscription();
  }

  Future<String?> _getDeviceToken() async {
    try {
      final messaging = FirebaseMessaging.instance;

      // Check notification permission first
      final settings = await messaging.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        return null;
      }

      // On iOS, wait for the APNs token
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        String? apnsToken = await messaging.getAPNSToken();
        int retries = 0;
        while (apnsToken == null && retries < 5) {
          await Future.delayed(const Duration(milliseconds: 300));
          apnsToken = await messaging.getAPNSToken();
          retries++;
        }
        if (apnsToken == null) {
          return null;
        }
      }

      final vapidKey = kIsWeb && _webPushCertificateKeyPair.isNotEmpty
          ? _webPushCertificateKeyPair
          : null;

      return await messaging.getToken(vapidKey: vapidKey);
    } catch (e) {
      log('Error getting device token: $e');
      return null;
    }
  }

  Future<void> _loadSubscription() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final token = await _getDeviceToken();
      if (token == null) {
        setState(() {
          _isLoading = false;
          _deviceToken = null;
          _subscription = null;
        });
        return;
      }

      _deviceToken = token;

      if (!mounted) return;
      final api = context.read<ApiService>();
      final subscription = await api.getSubscription(token);

      setState(() {
        _subscription = subscription;
        _isLoading = false;
      });
    } catch (e) {
      log('Error loading subscription: $e');
      setState(() {
        _isLoading = false;
        // 404 means no subscription, which is not an error
        if (!e.toString().contains('404')) {
          _errorMessage = 'Failed to load alerts';
        }
      });
    }
  }

  Future<void> _deleteSubscription() async {
    if (_deviceToken == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Alert'),
        content: const Text('Are you sure you want to remove this alert?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      if (!mounted) return;
      final api = context.read<ApiService>();
      await api.deleteSubscription(_deviceToken!);

      setState(() {
        _subscription = null;
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alert removed')),
        );
      }
    } catch (e) {
      log('Error deleting subscription: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to remove alert';
      });
    }
  }

  String _formatNextSweepWindow(String startIso, String endIso) {
    try {
      final startDateTime = DateTime.parse(startIso);
      final endDateTime = DateTime.parse(endIso);

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
      return '$startIso-$endIso';
    }
  }

  String _formatTimeUntil(String startIso) {
    try {
      final startDateTime = DateTime.parse(startIso).toLocal();
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
    return SelectionArea(
      child: Container(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height,
        ),
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.7, -0.8),
            radius: 1.2,
            colors: [
              Color(0xFFFEF3C7), // warm streetlight glow
              AppTheme.background,
            ],
          ),
        ),
        child: Stack(
          children: [
            // Subtle ambient glow effect
            Positioned(
              top: -100,
              right: -100,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppTheme.accent.withValues(alpha: 0.1),
                      AppTheme.accent.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 32),
                          _buildContent(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ALERTS',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your notification subscriptions',
          style: Theme.of(context).textTheme.displayMedium,
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return Card(
        elevation: 20,
        shadowColor: AppTheme.primaryColor.withValues(alpha: 0.15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: AppTheme.border.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: const Padding(
          padding: EdgeInsets.all(48.0),
          child: Center(
            child: CircularProgressIndicator(
              color: AppTheme.primaryColor,
            ),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Card(
        elevation: 20,
        shadowColor: AppTheme.primaryColor.withValues(alpha: 0.15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: AppTheme.border.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const Icon(
                Icons.error_outline,
                color: AppTheme.error,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppTheme.error,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadSubscription,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // No device token means notifications not enabled
    if (_deviceToken == null) {
      return _buildEmptyState(
        icon: Icons.notifications_off_outlined,
        title: 'Notifications not enabled',
        message:
            'Enable notifications on the Home screen to get alerts before street sweeping.',
      );
    }

    // No subscription
    if (_subscription == null) {
      return _buildEmptyState(
        icon: Icons.notifications_none_outlined,
        title: 'No alerts yet',
        message:
            'Go to the Home screen and tap "Turn on reminders" for a street to get notified before sweeping.',
      );
    }

    // Show subscription
    return _buildSubscriptionCard(_subscription!);
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Card(
      elevation: 20,
      shadowColor: AppTheme.primaryColor.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: AppTheme.border.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppTheme.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: AppTheme.primaryColor.withValues(alpha: 0.7),
                size: 48,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppTheme.textPrimary,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textMuted,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionCard(SubscriptionResponse subscription) {
    return Card(
      elevation: 20,
      shadowColor: AppTheme.primaryColor.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: AppTheme.border.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.notifications_active,
                    color: AppTheme.primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Active Alert',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppTheme.textPrimary,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.primarySoft,
                    AppTheme.primarySoft.withValues(alpha: 0.5),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: AppTheme.border.withValues(alpha: 0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Time until sweep
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(
                          color: AppTheme.primaryColor.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.access_time_outlined,
                              color: AppTheme.primaryColor,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatTimeUntil(subscription.nextSweepStart),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primaryColor,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Next sweep window
                    const Text(
                      'Next sweep window',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatNextSweepWindow(
                        subscription.nextSweepStart,
                        subscription.nextSweepEnd,
                      ),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Reminder timing
                    Row(
                      children: [
                        Icon(
                          Icons.alarm,
                          color: AppTheme.textMuted.withValues(alpha: 0.7),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Reminder ${subscription.leadMinutes} minutes before',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textMuted.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Delete button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _deleteSubscription,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove alert'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.error,
                  side:
                      BorderSide(color: AppTheme.error.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
