class ScheduleResponse {
  final RequestPoint requestPoint;
  final List<ScheduleEntry> schedules;
  final String timezone;

  ScheduleResponse({
    required this.requestPoint,
    required this.schedules,
    required this.timezone,
  });

  factory ScheduleResponse.fromJson(Map<String, dynamic> json) {
    return ScheduleResponse(
      requestPoint: RequestPoint.fromJson(json['request_point']),
      schedules: (json['schedules'] as List)
          .map((s) => ScheduleEntry.fromJson(s))
          .toList(),
      timezone: json['timezone'] ?? 'America/Los_Angeles',
    );
  }
}

class RequestPoint {
  final double latitude;
  final double longitude;

  RequestPoint({required this.latitude, required this.longitude});

  factory RequestPoint.fromJson(Map<String, dynamic> json) {
    return RequestPoint(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }
}

class ScheduleEntry {
  final int blockSweepId;
  final String corridor;
  final String limits;
  final String? blockSide;
  final List<String> humanRules;
  final String nextSweepStart;
  final String nextSweepEnd;
  final String? distance;
  final bool isUserSide;
  final List<Map<String, dynamic>> sideGeometries;

  ScheduleEntry({
    required this.blockSweepId,
    required this.corridor,
    required this.limits,
    this.blockSide,
    required this.humanRules,
    required this.nextSweepStart,
    required this.nextSweepEnd,
    this.distance,
    required this.isUserSide,
    required this.sideGeometries,
  });

  factory ScheduleEntry.fromJson(Map<String, dynamic> json) {
    return ScheduleEntry(
      blockSweepId: json['block_sweep_id'] as int,
      corridor: json['corridor'] as String,
      limits: json['limits'] as String,
      blockSide: json['block_side'] as String?,
      humanRules:
          (json['human_rules'] as List?)?.map((r) => r as String).toList() ??
              [],
      nextSweepStart: json['next_sweep_start'],
      nextSweepEnd: json['next_sweep_end'],
      distance: json['distance'] as String?,
      isUserSide: json['is_user_side'] as bool,
      sideGeometries: (json['side_geometries'] as List)
          .map((g) => g as Map<String, dynamic>)
          .toList(),
    );
  }
}
