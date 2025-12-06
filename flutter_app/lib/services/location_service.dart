import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<Position> getCurrentLocation() async {
    try {
      return await _getLocation();
    } catch (e) {
      final errorString = e.toString();
      
      // Map common permission errors to clearer messages.
      if (kIsWeb) {
        if (errorString.contains('denied') ||
            errorString.contains('PERMISSION_DENIED')) {
          throw Exception(
            'Location access was denied or blocked. '
            'Please enable location services for this site in your browser settings. '
            'Safari: Settings > Privacy & Security > Location Services > Safari Websites.',
          );
        }
      } else {
        if (errorString.contains('kCLErrorDomain') ||
            errorString.contains('Error 0') ||
            errorString.contains('User denied')) {
          throw Exception(
            'Location access was denied or blocked. '
            'Please enable location services in your system settings.',
          );
        }
      }
      rethrow;
    }
  }

  Future<Position> _getLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception(
        kIsWeb
            ? 'Location services are disabled. Please enable them in your browser settings.'
            : 'Location services are disabled. Please enable them in settings.',
      );
    }

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
        kIsWeb
            ? 'Location permissions are permanently denied. Please enable them in browser settings.'
            : 'Location permissions are permanently denied. Please enable them in system settings.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: kIsWeb ? 20 : 10),
      ),
    );
  }
}
