import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/schedule_response.dart';

class ApiService {
  // Default to localhost for development
  // In production, you'd want to configure this via environment variables
  // or use a proper configuration system
  final String baseUrl;

  ApiService({this.baseUrl = 'http://localhost:8000'});

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
}

