import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'services/api_service.dart';
import 'theme/app_theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

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
      ],
      child: MaterialApp(
        title: 'Sweep Dreams',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const HomeScreen(),
      ),
    );
  }
}
