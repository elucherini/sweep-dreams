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
import '../widgets/editorial_background.dart';
import '../widgets/timing_alert_card.dart';

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
  bool _notificationsAuthorized = false;

  @override
  void initState() {
    super.initState();
    _loadSubscription();
  }

  /// Public method to refresh the subscription data
  void refresh() {
    _loadSubscription();
  }

  Future<({String? token, bool authorized})>
      _getDeviceTokenAndAuthorization() async {
    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.getNotificationSettings();
      final authorized =
          settings.authorizationStatus == AuthorizationStatus.authorized;

      // On iOS, wait for the APNs token
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        String? apnsToken = await messaging.getAPNSToken();
        int retries = 0;
        while (apnsToken == null && retries < 5) {
          await Future.delayed(const Duration(milliseconds: 300));
          apnsToken = await messaging.getAPNSToken();
          retries++;
        }
      }

      final vapidKey = kIsWeb && _webPushCertificateKeyPair.isNotEmpty
          ? _webPushCertificateKeyPair
          : null;

      // If web push isn't configured, skip token retrieval.
      if (kIsWeb && vapidKey == null) return (token: null, authorized: false);

      final token = await messaging.getToken(vapidKey: vapidKey);
      return (token: token, authorized: authorized);
    } catch (e) {
      log('Error getting device token: $e');
      return (token: null, authorized: false);
    }
  }

  Future<void> _requestEnableNotifications() async {
    try {
      final messaging = FirebaseMessaging.instance;

      if (kIsWeb && _webPushCertificateKeyPair.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Missing WEB_PUSH_CERTIFICATE_KEY_PAIR for web notifications.',
            ),
          ),
        );
        return;
      }

      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      final authorized =
          settings.authorizationStatus == AuthorizationStatus.authorized;
      if (!mounted) return;

      setState(() => _notificationsAuthorized = authorized);
      context.read<SubscriptionState>().setNotificationsAuthorized(authorized);

      if (authorized) {
        await _loadSubscription();
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enable notifications in system settings to get alerts.'),
        ),
      );
    } catch (e) {
      log('Error requesting notification permission: $e');
    }
  }

  Future<void> _loadSubscription() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _getDeviceTokenAndAuthorization();
      final token = result.token;
      final authorized = result.authorized;
      _notificationsAuthorized = authorized;

      if (mounted) {
        context
            .read<SubscriptionState>()
            .setNotificationsAuthorized(authorized);
      }

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
          subscriptionState
              .setActiveAlertsCount(subscriptions.validSubscriptions.length);
        } else {
          subscriptionState.setSubscriptions(const []);
          subscriptionState.setActiveAlertsCount(0);
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

  DateTime? _notifyAtFor(SubscriptionItem sub) {
    final deadlineIso = sub.deadlineIso;
    if (deadlineIso == null || deadlineIso.isEmpty) return null;

    try {
      final deadline = DateTime.parse(deadlineIso);
      return deadline.subtract(Duration(minutes: sub.leadMinutes));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _AlertsContent(
      header: _buildHeader(),
      body: _buildContent(),
    );

    // If we're rendered outside the main tab shell, provide our own scaffold +
    // background so this screen doesn't appear on a black/transparent route.
    if (Scaffold.maybeOf(context) == null) {
      return Scaffold(
        body: EditorialBackground(
          child: content,
        ),
      );
    }

    return content;
  }

  Widget _buildHeader() {
    final canPop = Navigator.of(context).canPop();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canPop) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.chevron_left, size: 20),
              label: const Text('Map'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
        ],
        const SizedBox(height: 6),
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
      return const Padding(
        padding: EdgeInsets.all(48.0),
        child: Center(
          child: CircularProgressIndicator(
            color: AppTheme.primaryColor,
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Padding(
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
      );
    }

    // No device token means notifications not enabled
    if (_deviceToken == null) {
      return _buildEmptyState(
        icon: Icons.notifications_off_outlined,
        title: 'Notifications not enabled',
        message:
            'Enable notifications to get alerts before street sweeping and parking restrictions.',
        action: ElevatedButton(
          onPressed: _requestEnableNotifications,
          child: const Text('Enable notifications'),
        ),
      );
    }

    // No subscriptions (or all have been notified)
    if (_subscriptions == null || _subscriptions!.validSubscriptions.isEmpty) {
      return _buildEmptyState(
        icon: Icons.notifications_none_outlined,
        title: 'No alerts yet',
        message:
            'Tap “Turn on reminders” on a street or regulation to get notified.',
      );
    }

    // Show subscriptions
    return _buildSubscriptionsCard(_subscriptions!);
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    return Padding(
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
          if (action != null) ...[
            const SizedBox(height: 16),
            action,
          ],
        ],
      ),
    );
  }

  Widget _buildSubscriptionsCard(SubscriptionsResponse subscriptions) {
    final validSubs = [...subscriptions.validSubscriptions];
    validSubs.sort((a, b) {
      final aNotifyAt = _notifyAtFor(a);
      final bNotifyAt = _notifyAtFor(b);

      if (aNotifyAt == null && bNotifyAt == null) {
        // Prefer street sweeping in ties/unknowns.
        if (a is SweepingSubscription && b is TimingSubscription) return -1;
        if (a is TimingSubscription && b is SweepingSubscription) return 1;
        return 0;
      }
      if (aNotifyAt == null) return 1;
      if (bNotifyAt == null) return -1;

      final cmp = aNotifyAt.compareTo(bNotifyAt);
      if (cmp != 0) return cmp;

      if (a is SweepingSubscription && b is TimingSubscription) return -1;
      if (a is TimingSubscription && b is SweepingSubscription) return 1;
      return 0;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_notificationsAuthorized) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.errorBackground.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.error.withValues(alpha: 0.22),
                width: 0.9,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.notification_important_outlined,
                  color: AppTheme.error.withValues(alpha: 0.8),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Notifications are off',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "You'll still see your alerts here, but you won't get reminders until notifications are enabled.",
                        style: TextStyle(
                          color: AppTheme.textMuted.withValues(alpha: 0.95),
                          fontSize: 13,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ElevatedButton(
                          onPressed: _requestEnableNotifications,
                          child: const Text('Enable notifications'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
        Text(
          validSubs.length == 1
              ? 'Active alert'
              : 'Active alerts (${validSubs.length})',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppTheme.textMuted,
              ),
        ),
        const SizedBox(height: 20),
        ...validSubs.asMap().entries.map((entry) {
          final index = entry.key;
          final sub = entry.value;
          return Column(
            children: [
              if (index > 0) const SizedBox(height: 12),
              _buildAlertCard(sub),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildAlertCard(SubscriptionItem sub) {
    return switch (sub) {
      SweepingSubscription s => SweepingAlertCard(
          corridor: s.corridor,
          limits: s.limits,
          blockSide: s.blockSide,
          nextSweepStart: s.nextSweepStart,
          nextSweepEnd: s.nextSweepEnd,
          leadMinutes: s.leadMinutes,
          onDelete: () => _deleteSubscription(s.scheduleBlockSweepId),
        ),
      TimingSubscription t => TimingAlertCard(
          regulation: t.regulation,
          hourLimit: t.hourLimit,
          days: t.days,
          fromTime: t.fromTime,
          toTime: t.toTime,
          nextMoveDeadline: t.nextMoveDeadline,
          leadMinutes: t.leadMinutes,
          onDelete: () => _deleteSubscription(t.scheduleBlockSweepId),
        ),
    };
  }
}

class _AlertsContent extends StatelessWidget {
  final Widget header;
  final Widget body;

  const _AlertsContent({
    required this.header,
    required this.body,
  });

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
                      constraints: const BoxConstraints(
                        maxWidth: AppTheme.maxContentWidth,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          header,
                          const SizedBox(height: 32),
                          body,
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
}
