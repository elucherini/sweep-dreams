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

      // Check for location permissions
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception(
            kIsWeb
                ? 'Location permission was denied. Please allow location access when prompted by your browser.'
                : 'Location permission was denied.',
          );
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception(
          kIsWeb
              ? 'Location permissions are blocked. Please check your browser settings:\n'
                  '• Safari: Settings > Safari > Location > Allow\n'
                  '• Chrome: Site settings > Permissions > Location'
              : 'Location permissions are permanently denied. '
                  'Please enable them in system settings.',
        );
      }

      // Get the current position
      // For web, use medium accuracy which is more reliable on iOS
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: kIsWeb ? LocationAccuracy.medium : LocationAccuracy.high,
        timeLimit: Duration(seconds: kIsWeb ? 15 : 10),
      );
    } catch (e) {
      // Handle specific error codes
      if (e.toString().contains('kCLErrorDomain') || 
          e.toString().contains('Error 0') ||
          e.toString().contains('User denied')) {
        throw Exception(
          'Location access was denied or blocked. '
          'Please enable location services in your browser settings.',
        );
      }
      rethrow;
    }
  }
}

