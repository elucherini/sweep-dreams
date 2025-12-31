import 'dart:developer';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/subscription_response.dart';
import '../services/api_service.dart';
import '../services/subscription_state.dart';
import '../theme/app_theme.dart';
import '../widgets/alert_card.dart';
import '../widgets/frosted_card.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  AlertsScreenState createState() => AlertsScreenState();
}

class AlertsScreenState extends State<AlertsScreen> {
  static const String _webPushCertificateKeyPair = String.fromEnvironment(
    'WEB_PUSH_CERTIFICATE_KEY_PAIR',
  );

  bool _isLoading = false;
  String? _errorMessage;
  SubscriptionsResponse? _subscriptions;
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
          _subscriptions = null;
        });
        return;
      }

      _deviceToken = token;

      if (!mounted) return;
      final api = context.read<ApiService>();
      final subscriptions = await api.getSubscriptions(token);

      // Update shared subscription state
      if (mounted) {
        final subscriptionState = context.read<SubscriptionState>();
        if (subscriptions != null) {
          subscriptionState.setSubscriptions(
            subscriptions.subscriptions.map((s) => s.scheduleBlockSweepId),
          );
        } else {
          subscriptionState.clear();
        }
      }

      setState(() {
        _subscriptions = subscriptions;
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

  Future<void> _deleteSubscription(int scheduleBlockSweepId) async {
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
      await api.deleteSubscription(_deviceToken!, scheduleBlockSweepId);

      // Remove from shared subscription state
      if (mounted) {
        context
            .read<SubscriptionState>()
            .removeSubscription(scheduleBlockSweepId);
      }

      // Remove the deleted subscription from local state
      setState(() {
        if (_subscriptions != null) {
          _subscriptions = SubscriptionsResponse(
            deviceToken: _subscriptions!.deviceToken,
            platform: _subscriptions!.platform,
            subscriptions: _subscriptions!.subscriptions
                .where((s) => s.scheduleBlockSweepId != scheduleBlockSweepId)
                .toList(),
          );
          // Clear subscriptions if none left
          if (_subscriptions!.subscriptions.isEmpty) {
            _subscriptions = null;
          }
        }
        _isLoading = false;
      });
    } catch (e) {
      log('Error deleting subscription: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to remove alert';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.screenPadding),
                  child: Center(
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: AppTheme.maxContentWidth),
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
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          'Alerts',
          style: Theme.of(context).textTheme.displayMedium,
        ),
        const SizedBox(height: 8),
        Text(
          "Manage the street sweeping alerts you've subscribed to.\nWe'll send reminders before the next sweep.",
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.normal,
              ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const FrostedCard(
        child: Padding(
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
      return FrostedCard(
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

    // No subscriptions (or all have been notified)
    if (_subscriptions == null || _subscriptions!.validSubscriptions.isEmpty) {
      return _buildEmptyState(
        icon: Icons.notifications_none_outlined,
        title: 'No alerts yet',
        message:
            'Go to the Home screen and tap "Turn on reminders" for a street to get notified before sweeping.',
      );
    }

    // Show subscriptions
    return _buildSubscriptionsCard(_subscriptions!);
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return FrostedCard(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primarySoft.withValues(alpha: 0.8),
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

  Widget _buildSubscriptionsCard(SubscriptionsResponse subscriptions) {
    final validSubs = subscriptions.validSubscriptions;

    return FrostedCard(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    validSubs.length == 1
                        ? 'Active alert'
                        : 'Active alerts (${validSubs.length})',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppTheme.textMuted,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Build a card for each subscription
            ...validSubs.asMap().entries.map((entry) {
              final index = entry.key;
              final sub = entry.value;
              return Column(
                children: [
                  if (index > 0) const SizedBox(height: 12),
                  AlertCard(
                    corridor: sub.corridor ?? 'Unknown',
                    limits: sub.limits ?? '',
                    blockSide: sub.blockSide,
                    nextSweepStart: sub.nextSweepStart ?? '',
                    nextSweepEnd: sub.nextSweepEnd ?? '',
                    leadMinutes: sub.leadMinutes,
                    onDelete: () =>
                        _deleteSubscription(sub.scheduleBlockSweepId),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}
