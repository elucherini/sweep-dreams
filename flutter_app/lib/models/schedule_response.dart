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
  final List<String> humanRules;
  final String nextSweepStart;
  final String nextSweepEnd;
  final int? blockSweepId;

  ScheduleEntry({
    required this.schedule,
    required this.humanRules,
    required this.nextSweepStart,
    required this.nextSweepEnd,
    required this.blockSweepId,
  });

  factory ScheduleEntry.fromJson(Map<String, dynamic> json) {
    final schedule = Schedule.fromJson(json['schedule']);
    return ScheduleEntry(
      schedule: schedule,
      blockSweepId: (json['block_sweep_id'] ?? json['schedule']?['block_sweep_id'])
          as int?,
      humanRules: (json['human_rules'] as List?)
          ?.map((r) => r as String)
          .toList() ?? [],
      nextSweepStart: json['next_sweep_start'],
      nextSweepEnd: json['next_sweep_end'],
    );
  }
}

class Schedule {
  final Block block;
  final List<Rule> rules;
  final List<List<double>> line;
  final int? blockSweepId;

  Schedule({
    required this.block,
    required this.rules,
    required this.line,
    required this.blockSweepId,
  });

  factory Schedule.fromJson(Map<String, dynamic> json) {
    return Schedule(
      block: Block.fromJson(json['block']),
      rules: (json['rules'] as List)
          .map((r) => Rule.fromJson(r))
          .toList(),
      line: (json['line'] as List)
          .map((coord) => (coord as List).map((c) => (c as num).toDouble()).toList())
          .toList(),
      blockSweepId: json['block_sweep_id'] as int?,
    );
  }

  String get label => block.blockSide;
}

class Block {
  final int cnn;
  final String corridor;
  final String limits;
  final String cnnRightLeft;
  final String blockSide;

  Block({
    required this.cnn,
    required this.corridor,
    required this.limits,
    required this.cnnRightLeft,
    required this.blockSide,
  });

  factory Block.fromJson(Map<String, dynamic> json) {
    return Block(
      cnn: json['cnn'],
      corridor: json['corridor'],
      limits: json['limits'],
      cnnRightLeft: json['cnn_right_left'],
      blockSide: json['block_side'],
    );
  }
}

class Rule {
  final Pattern pattern;
  final TimeWindow timeWindow;
  final bool skipHolidays;

  Rule({
    required this.pattern,
    required this.timeWindow,
    required this.skipHolidays,
  });

  factory Rule.fromJson(Map<String, dynamic> json) {
    return Rule(
      pattern: Pattern.fromJson(json['pattern']),
      timeWindow: TimeWindow.fromJson(json['time_window']),
      skipHolidays: json['skip_holidays'],
    );
  }
}

class Pattern {
  final List<int> weekdays;
  final List<int> weeksOfMonth;

  Pattern({
    required this.weekdays,
    required this.weeksOfMonth,
  });

  factory Pattern.fromJson(Map<String, dynamic> json) {
    return Pattern(
      weekdays: (json['weekdays'] as List).map((w) => w as int).toList(),
      weeksOfMonth: (json['weeks_of_month'] as List).map((w) => w as int).toList(),
    );
  }
}

class TimeWindow {
  final String start;
  final String end;

  TimeWindow({
    required this.start,
    required this.end,
  });

  factory TimeWindow.fromJson(Map<String, dynamic> json) {
    return TimeWindow(
      start: json['start'],
      end: json['end'],
    );
  }
}
