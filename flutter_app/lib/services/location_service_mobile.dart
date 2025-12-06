import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<Position> getCurrentLocation() async {
    try {
      return await _getMobileLocation();
    } catch (e) {
      // Map common platform-specific permission errors to a clearer message.
      if (e.toString().contains('kCLErrorDomain') ||
          e.toString().contains('Error 0') ||
          e.toString().contains('User denied')) {
        throw Exception(
          'Location access was denied or blocked. '
          'Please enable location services in your system settings.',
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

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
  }
}

