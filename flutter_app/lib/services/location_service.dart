import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class LocationService {
  Future<Position> getCurrentLocation() async {
    try {
      bool serviceEnabled;
      LocationPermission permission;

      // Check if location services are enabled
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled. Please enable them in settings.');
      }

      if (kIsWeb) {
        // On web/Safari, requestPermission does not always persist; call it every tap but still fall through to getCurrentPosition to trigger the prompt.
        permission = await Geolocator.requestPermission();

        if (permission == LocationPermission.deniedForever) {
          throw Exception(
            'Location permissions are blocked. Please check your browser settings:\n'
            '• Safari: Settings > Privacy & Security > Location Services > Safari Websites > Allow\n'
            '• Chrome: Site settings > Permissions > Location',
          );
        }

        // Attempt to get the position even if permission returns denied, so the browser can re-prompt.
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 20),
        );
      } else {
        // Native platforms
        permission = await Geolocator.checkPermission();

        if (permission == LocationPermission.denied ||
            permission == LocationPermission.unableToDetermine) {
          permission = await Geolocator.requestPermission();
          if (permission == LocationPermission.denied) {
            throw Exception('Location permission was denied.');
          }
        }

        if (permission == LocationPermission.deniedForever) {
          throw Exception(
            'Location permissions are permanently denied. Please enable them in system settings.',
          );
        }

        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
      }
    } catch (e) {
      // Handle specific error codes
      if (e.toString().contains('kCLErrorDomain') || 
          e.toString().contains('Error 0') ||
          e.toString().contains('User denied')) {
        throw Exception(
          'Location access was denied or blocked. '
          'Please enable location services in your browser settings. '
          'Safari: Settings > Privacy & Security > Location Services > Safari Websites.',
        );
      }
      rethrow;
    }
  }
}
