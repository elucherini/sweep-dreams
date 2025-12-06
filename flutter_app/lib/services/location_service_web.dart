import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<Position> getCurrentLocation() async {
    try {
      return await _getWebLocation();
    } catch (e) {
      // Map common web permission errors to a clearer message.
      if (e.toString().contains('denied') ||
          e.toString().contains('PERMISSION_DENIED')) {
        throw Exception(
          'Location access was denied or blocked. '
          'Please enable location services for this site in your browser settings. '
          'Safari: Settings > Privacy & Security > Location Services > Safari Websites.',
        );
      }
      rethrow;
    }
  }

  Future<Position> _getWebLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception(
        'Location services are disabled. Please enable them in your browser settings.',
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
        'Location permissions are permanently denied. Please enable them in browser settings.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
  }
}

