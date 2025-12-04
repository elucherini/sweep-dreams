import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../models/schedule_response.dart';

class ApiService {
  final String baseUrl;

  ApiService({String? baseUrl})
      : baseUrl = baseUrl ??
            const String.fromEnvironment(
              'API_URL',
              defaultValue: 'http://localhost:8000',
            );

  Future<ScheduleResponse> checkLocation(double latitude, double longitude) async {
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
      throw Exception('Failed to fetch schedule: ${response.statusCode} - ${response.body}');
    }
  }

  Future<void> subscribeToSchedule({
    required String deviceToken,
    required int scheduleBlockSweepId,
    required double latitude,
    required double longitude,
    int leadMinutes = 60,
  }) async {
    final uri = Uri.parse('$baseUrl/subscriptions');
    final payload = {
      'device_token': deviceToken,
      'platform': _platform(),
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

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to save subscription: ${response.statusCode} - ${response.body}',
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
