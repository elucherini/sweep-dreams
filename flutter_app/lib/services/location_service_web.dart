// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<Position> getCurrentLocation() async {
    final geolocation = html.window.navigator.geolocation;
    // ignore: unnecessary_null_comparison
    if (geolocation == null) {
      throw Exception('Geolocation is not supported by this browser.');
    }

    try {
      final position = await geolocation.getCurrentPosition(
        enableHighAccuracy: true,
        timeout: const Duration(seconds: 20),
        maximumAge: Duration.zero,
      );

      final coords = position.coords;
      final data = <String, dynamic>{
        'latitude': coords?.latitude ?? 0.0,
        'longitude': coords?.longitude ?? 0.0,
        'timestamp': position.timestamp ?? DateTime.now(),
        'accuracy': (coords?.accuracy ?? 0).toDouble(),
        'altitude': (coords?.altitude ?? 0).toDouble(),
        'heading': (coords?.heading ?? 0).toDouble(),
        'speed': (coords?.speed ?? 0).toDouble(),
        'speedAccuracy': 0.0,
      };

      return Position.fromMap(data);
    } catch (e) {
      if (e is html.PositionError &&
          e.code == html.PositionError.PERMISSION_DENIED) {
        throw Exception(
          'Location access was denied or blocked. '
          'Please enable location services for this site in your browser settings. '
          'Safari: Settings > Privacy & Security > Location Services > Safari Websites.',
        );
      }

      throw Exception(
        e.toString().isEmpty ? 'Failed to get current location.' : e.toString(),
      );
    }
  }
}
