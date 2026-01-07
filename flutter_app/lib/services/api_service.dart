import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../models/schedule_response.dart';
import '../models/subscription_response.dart';
import '../models/parking_response.dart';

/// Exception thrown when the user has reached the maximum number of subscriptions.
class SubscriptionLimitException implements Exception {
  final String message;
  SubscriptionLimitException(
      [this.message = 'Maximum subscriptions limit reached']);

  @override
  String toString() => message;
}

class ApiService {
  final String baseUrl;

  ApiService({String? baseUrl})
      : baseUrl = baseUrl ??
            const String.fromEnvironment(
              'API_URL',
              defaultValue: 'http://localhost:8787',
            );

  Future<ScheduleResponse> checkLocation(
      double latitude, double longitude) async {
    final uri = Uri.parse('$baseUrl/api/check-location').replace(
      queryParameters: {
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
      },
    );

    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return ScheduleResponse.fromJson(json);
    } else {
      throw Exception(
          'Failed to fetch schedule: ${response.statusCode} - ${response.body}');
    }
  }

  Future<ParkingResponse> checkParking(
    double latitude,
    double longitude, {
    int radius = 25,
  }) async {
    final uri = Uri.parse('$baseUrl/api/check-parking').replace(
      queryParameters: {
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'radius': radius.toString(),
      },
    );

    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return ParkingResponse.fromJson(json);
    } else {
      throw Exception(
          'Failed to fetch parking regulations: ${response.statusCode} - ${response.body}');
    }
  }

  Future<void> subscribeToSchedule({
    required String deviceToken,
    required int scheduleBlockSweepId,
    required double latitude,
    required double longitude,
    int leadMinutes = 60,
    String subscriptionType = 'sweeping',
  }) async {
    final uri = Uri.parse('$baseUrl/subscriptions');
    final payload = {
      'device_token': deviceToken,
      'platform': _platform(),
      'subscription_type': subscriptionType,
      'schedule_block_sweep_id': scheduleBlockSweepId,
      'latitude': latitude,
      'longitude': longitude,
      'lead_minutes': leadMinutes,
    };

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode == 409) {
      throw SubscriptionLimitException();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to save subscription: ${response.statusCode} - ${response.body}',
      );
    }
  }

  /// Get all subscriptions for a device token
  Future<SubscriptionsResponse?> getSubscriptions(String deviceToken) async {
    final uri =
        Uri.parse('$baseUrl/subscriptions/${Uri.encodeComponent(deviceToken)}');

    final response = await http.get(uri);

    if (response.statusCode == 404) {
      return null;
    }

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return SubscriptionsResponse.fromJson(json);
    } else {
      throw Exception(
        'Failed to fetch subscriptions: ${response.statusCode} - ${response.body}',
      );
    }
  }

  /// Delete a specific subscription by device token and schedule ID
  Future<void> deleteSubscription(
    String deviceToken,
    int scheduleBlockSweepId,
  ) async {
    final uri = Uri.parse(
      '$baseUrl/subscriptions/${Uri.encodeComponent(deviceToken)}/$scheduleBlockSweepId',
    );

    final response = await http.delete(uri);

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception(
        'Failed to delete subscription: ${response.statusCode} - ${response.body}',
      );
    }
  }

  /// Delete all subscriptions for a device token
  Future<void> deleteAllSubscriptions(String deviceToken) async {
    final uri =
        Uri.parse('$baseUrl/subscriptions/${Uri.encodeComponent(deviceToken)}');

    final response = await http.delete(uri);

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception(
        'Failed to delete subscriptions: ${response.statusCode} - ${response.body}',
      );
    }
  }

  String _platform() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      default:
        return 'web';
    }
  }
}
