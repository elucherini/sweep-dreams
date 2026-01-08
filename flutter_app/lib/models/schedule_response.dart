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
  final String cnnRightLeft; // 'L' or 'R' - which side of the centerline
  final List<String> humanRules;
  final String nextSweepStart;
  final String nextSweepEnd;
  final String? distance;
  final double? distanceMeters;
  final bool isUserSide;
  final Map<String, dynamic> geometry;

  ScheduleEntry({
    required this.blockSweepId,
    required this.corridor,
    required this.limits,
    this.blockSide,
    required this.cnnRightLeft,
    required this.humanRules,
    required this.nextSweepStart,
    required this.nextSweepEnd,
    this.distance,
    this.distanceMeters,
    required this.isUserSide,
    required this.geometry,
  });

  factory ScheduleEntry.fromJson(Map<String, dynamic> json) {
    return ScheduleEntry(
      blockSweepId: json['block_sweep_id'] as int,
      corridor: json['corridor'] as String,
      limits: json['limits'] as String,
      blockSide: json['block_side'] as String?,
      cnnRightLeft: json['cnn_right_left'] as String? ?? 'R',
      humanRules:
          (json['human_rules'] as List?)?.map((r) => r as String).toList() ??
              [],
      nextSweepStart: json['next_sweep_start'],
      nextSweepEnd: json['next_sweep_end'],
      distance: json['distance'] as String?,
      distanceMeters: (json['distance_meters'] as num?)?.toDouble(),
      isUserSide: (json['is_user_side'] as bool?) ?? false,
      geometry: json['geometry'] as Map<String, dynamic>,
    );
  }
}
