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
  final Schedule schedule;
  final String nextSweepStart;
  final String nextSweepEnd;

  ScheduleEntry({
    required this.schedule,
    required this.nextSweepStart,
    required this.nextSweepEnd,
  });

  factory ScheduleEntry.fromJson(Map<String, dynamic> json) {
    return ScheduleEntry(
      schedule: Schedule.fromJson(json['schedule']),
      nextSweepStart: json['next_sweep_start'],
      nextSweepEnd: json['next_sweep_end'],
    );
  }
}

class Schedule {
  final String? fullName;
  final String? blockSide;
  final String? cnnRightLeft;
  final String? corridor;
  final String? limits;
  final int? fromHour;
  final int? toHour;
  final String? weekDay;

  Schedule({
    this.fullName,
    this.blockSide,
    this.cnnRightLeft,
    this.corridor,
    this.limits,
    this.fromHour,
    this.toHour,
    this.weekDay,
  });

  factory Schedule.fromJson(Map<String, dynamic> json) {
    return Schedule(
      fullName: json['full_name'],
      blockSide: json['block_side'],
      cnnRightLeft: json['cnn_right_left'],
      corridor: json['corridor'],
      limits: json['limits'],
      fromHour: json['from_hour'],
      toHour: json['to_hour'],
      weekDay: json['week_day'],
    );
  }

  String get label =>
      blockSide ?? cnnRightLeft ?? corridor ?? 'Schedule';
}

