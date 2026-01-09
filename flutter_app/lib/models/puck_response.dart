import 'parking_response.dart';
import 'schedule_response.dart';

class PuckErrors {
  final String? schedule;
  final String? regulation;

  const PuckErrors({this.schedule, this.regulation});

  factory PuckErrors.fromJson(Map<String, dynamic> json) {
    return PuckErrors(
      schedule: json['schedule'] as String?,
      regulation: json['regulation'] as String?,
    );
  }
}

class PuckResponse {
  final RequestPoint requestPoint;
  final ScheduleEntry? schedule;
  final ParkingRegulation? regulation;
  final String timezone;
  final PuckErrors? errors;

  PuckResponse({
    required this.requestPoint,
    required this.schedule,
    required this.regulation,
    required this.timezone,
    required this.errors,
  });

  factory PuckResponse.fromJson(Map<String, dynamic> json) {
    final parsedRegulation = json['regulation'] == null
        ? null
        : ParkingRegulation.fromJson(json['regulation']);

    return PuckResponse(
      requestPoint: RequestPoint.fromJson(json['request_point']),
      schedule: json['schedule'] == null
          ? null
          : ScheduleEntry.fromJson(json['schedule']),
      regulation: parsedRegulation?.isTimingLimited == true
          ? parsedRegulation
          : null,
      timezone: json['timezone'] ?? 'America/Los_Angeles',
      errors:
          json['errors'] == null ? null : PuckErrors.fromJson(json['errors']),
    );
  }
}
