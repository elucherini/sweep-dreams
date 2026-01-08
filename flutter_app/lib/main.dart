import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'screens/map_home_screen.dart';
import 'services/api_service.dart';
import 'services/subscription_state.dart';
import 'theme/app_theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

const String _mapboxToken = String.fromEnvironment('MAPBOX_TOKEN');
const String _webPushCertificateKeyPair = String.fromEnvironment(
  'WEB_PUSH_CERTIFICATE_KEY_PAIR',
);

/// Whether Firebase/notifications are enabled on this platform.
bool get _notificationsEnabled =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.android;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_notificationsEnabled) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  // MapBox SDK has a bug where it uses bool.fromEnvironment in non-const
  // context for debug logging setup, which fails on web in debug mode.
  // Wrap in try-catch to handle gracefully.
  try {
    MapboxOptions.setAccessToken(_mapboxToken);
  } catch (e) {
    debugPrint('MapBox initialization error (expected on web debug): $e');
  }

  runApp(const SweepDreamsApp());
}

class SweepDreamsApp extends StatefulWidget {
  const SweepDreamsApp({super.key});

  @override
  State<SweepDreamsApp> createState() => _SweepDreamsAppState();
}

class _SweepDreamsAppState extends State<SweepDreamsApp> {
  @override
  void initState() {
    super.initState();

    // Listen for foreground messages (only when notifications are enabled)
    if (_notificationsEnabled) {
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint(
            'onMessage: ${message.notification?.title} / ${message.data}');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiService>(
          create: (_) => ApiService(),
        ),
        ChangeNotifierProvider<SubscriptionState>(
          create: (_) => SubscriptionState(),
        ),
      ],
      child: MaterialApp(
        title: 'Sweep Dreams',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const _SubscriptionsBootstrapper(
          child: MapHomeScreen(),
        ),
      ),
    );
  }
}

class _SubscriptionsBootstrapper extends StatefulWidget {
  final Widget child;

  const _SubscriptionsBootstrapper({required this.child});

  @override
  State<_SubscriptionsBootstrapper> createState() =>
      _SubscriptionsBootstrapperState();
}

class _SubscriptionsBootstrapperState
    extends State<_SubscriptionsBootstrapper> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hydrateSubscriptions();
    });
  }

  Future<String?> _getDeviceTokenIfAuthorized() async {
    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        return null;
      }

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        String? apnsToken = await messaging.getAPNSToken();
        var retries = 0;
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

      // If web push isn't configured, skip (avoids surfacing misleading counts).
      if (kIsWeb && vapidKey == null) return null;

      return await messaging.getToken(vapidKey: vapidKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> _hydrateSubscriptions() async {
    if (!_notificationsEnabled) return;

    final token = await _getDeviceTokenIfAuthorized();
    if (!mounted) return;

    final subscriptionState = context.read<SubscriptionState>();
    if (token == null) {
      subscriptionState.clear();
      return;
    }

    try {
      final api = context.read<ApiService>();
      final subscriptions = await api.getSubscriptions(token);
      if (!mounted) return;

      if (subscriptions == null) {
        subscriptionState.clear();
        return;
      }

      subscriptionState.setSubscriptions(
        subscriptions.subscriptions.map((s) => s.scheduleBlockSweepId),
      );
      subscriptionState.setActiveAlertsCount(
        subscriptions.validSubscriptions.length,
      );
    } catch (_) {
      // Keep any existing state; badge will update next time we successfully load.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
