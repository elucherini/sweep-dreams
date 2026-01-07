import 'schedule_response.dart';

class ParkingRegulation {
  final int id;
  final String regulation;
  final int? hourLimit;
  final String? days;
  final String? fromTime;
  final String? toTime;
  final String? rppArea;
  final String? exceptions;
  final String? neighborhood;
  final String distance;
  final double distanceMeters;
  final Map<String, dynamic>? line;
  final String? nextMoveDeadlineIso;

  ParkingRegulation({
    required this.id,
    required this.regulation,
    this.hourLimit,
    this.days,
    this.fromTime,
    this.toTime,
    this.rppArea,
    this.exceptions,
    this.neighborhood,
    required this.distance,
    required this.distanceMeters,
    this.line,
    this.nextMoveDeadlineIso,
  });

  factory ParkingRegulation.fromJson(Map<String, dynamic> json) {
    return ParkingRegulation(
      id: json['id'] as int,
      regulation: json['regulation'] as String,
      hourLimit: json['hour_limit'] as int?,
      days: json['days'] as String?,
      fromTime: json['from_time'] as String?,
      toTime: json['to_time'] as String?,
      rppArea: json['rpp_area'] as String?,
      exceptions: json['exceptions'] as String?,
      neighborhood: json['neighborhood'] as String?,
      distance: json['distance'] as String,
      distanceMeters: (json['distance_meters'] as num).toDouble(),
      line: json['line'] as Map<String, dynamic>?,
      nextMoveDeadlineIso: json['next_move_deadline_iso'] as String?,
    );
  }
}

class ParkingResponse {
  final RequestPoint requestPoint;
  final List<ParkingRegulation> regulations;
  final String timezone;

  ParkingResponse({
    required this.requestPoint,
    required this.regulations,
    required this.timezone,
  });

  factory ParkingResponse.fromJson(Map<String, dynamic> json) {
    return ParkingResponse(
      requestPoint: RequestPoint.fromJson(json['request_point']),
      regulations: (json['regulations'] as List)
          .map((r) => ParkingRegulation.fromJson(r))
          .toList(),
      timezone: json['timezone'] ?? 'America/Los_Angeles',
    );
  }
}
