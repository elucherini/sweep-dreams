// Lightweight Firebase options holder. Replace the placeholder values with your
// project config or supply them via --dart-define at build time.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

const String _defaultApiKey =
    String.fromEnvironment('FIREBASE_API_KEY', defaultValue: 'AIzaSyBPCgA3KnxhLOuwXcW-1tmUqpXQq3eh5gc');
const String _defaultAppId =
    String.fromEnvironment('FIREBASE_APP_ID', defaultValue: '1:625444034450:web:0502cc539a212a26f5934b');
const String _defaultMessagingSenderId = String.fromEnvironment(
  'FIREBASE_MESSAGING_SENDER_ID',
  defaultValue: '625444034450',
);
const String _defaultProjectId =
    String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'sweep-dreams');
const String _defaultStorageBucket = String.fromEnvironment(
  'FIREBASE_STORAGE_BUCKET',
  defaultValue: 'sweep-dreams.firebasestorage.app',
);
const String defaultVapidKey = String.fromEnvironment(
  'FCM_VAPID_KEY',
  // Public web push key provided by the user.
  defaultValue:
      'BIwuhQLU2Zgt2g6cgCj26JhJHJj3iR7i4QcObqEIBljkDMGTud7iHbYQhdHeuqln1b_CzxHspJZ8U8T1Qr7uNFA',
);

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return FirebaseOptions(
        apiKey: const String.fromEnvironment('FIREBASE_API_KEY_WEB', defaultValue: _defaultApiKey),
        appId: const String.fromEnvironment('FIREBASE_APP_ID_WEB', defaultValue: _defaultAppId),
        messagingSenderId: const String.fromEnvironment(
          'FIREBASE_MESSAGING_SENDER_ID_WEB',
          defaultValue: _defaultMessagingSenderId,
        ),
        projectId: const String.fromEnvironment(
          'FIREBASE_PROJECT_ID_WEB',
          defaultValue: _defaultProjectId,
        ),
        storageBucket: const String.fromEnvironment(
          'FIREBASE_STORAGE_BUCKET_WEB',
          defaultValue: _defaultStorageBucket,
        ),
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return FirebaseOptions(
          apiKey: const String.fromEnvironment('FIREBASE_API_KEY_ANDROID', defaultValue: _defaultApiKey),
          appId: const String.fromEnvironment('FIREBASE_APP_ID_ANDROID', defaultValue: _defaultAppId),
          messagingSenderId: const String.fromEnvironment(
            'FIREBASE_MESSAGING_SENDER_ID_ANDROID',
            defaultValue: _defaultMessagingSenderId,
          ),
          projectId: const String.fromEnvironment(
            'FIREBASE_PROJECT_ID_ANDROID',
            defaultValue: _defaultProjectId,
          ),
          storageBucket: const String.fromEnvironment(
            'FIREBASE_STORAGE_BUCKET_ANDROID',
            defaultValue: _defaultStorageBucket,
          ),
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return FirebaseOptions(
          apiKey: const String.fromEnvironment('FIREBASE_API_KEY_IOS', defaultValue: _defaultApiKey),
          appId: const String.fromEnvironment('FIREBASE_APP_ID_IOS', defaultValue: _defaultAppId),
          messagingSenderId: const String.fromEnvironment(
            'FIREBASE_MESSAGING_SENDER_ID_IOS',
            defaultValue: _defaultMessagingSenderId,
          ),
          projectId: const String.fromEnvironment(
            'FIREBASE_PROJECT_ID_IOS',
            defaultValue: _defaultProjectId,
          ),
          storageBucket: const String.fromEnvironment(
            'FIREBASE_STORAGE_BUCKET_IOS',
            defaultValue: _defaultStorageBucket,
          ),
          iosBundleId: const String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID', defaultValue: ''),
        );
      default:
        return FirebaseOptions(
          apiKey: _defaultApiKey,
          appId: _defaultAppId,
          messagingSenderId: _defaultMessagingSenderId,
          projectId: _defaultProjectId,
          storageBucket: _defaultStorageBucket,
        );
    }
  }
}
