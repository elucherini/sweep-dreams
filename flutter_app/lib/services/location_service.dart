import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class LocationService {
  Future<Position> getCurrentLocation() async {
    try {
      if (kIsWeb) {
        return await _getWebLocation();
      }

      return await _getMobileLocation();
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

  Future<Position> _getMobileLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled. Please enable them in settings.');
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
        'Location permissions are permanently denied. Please enable them in system settings.',
      );
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } on PermissionDeniedException {
      rethrow;
    }
  }

  Future<Position> _getWebLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled. Please enable them in settings.');
    }

    permission = await Geolocator.checkPermission();

    // Safari can report deniedForever before showing a prompt; treat it as denied so we can re-ask.
    if (permission == LocationPermission.deniedForever) {
      permission = LocationPermission.denied;
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      // The web permission API is unreliable on iOS Safari; request but ignore the result.
      await Geolocator.requestPermission();
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 20),
      );
    } on PermissionDeniedException {
      // Some browsers can throw after the first prompt; try once more to surface a new prompt.
      await Geolocator.requestPermission();
      try {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 20),
        );
      } on PermissionDeniedException {
        throw Exception(
          'Location access was denied or blocked. '
          'Please enable location services for this site in your browser settings.',
        );
      }
    }
  }
}
