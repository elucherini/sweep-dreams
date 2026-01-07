/// Base class for subscription items using sealed class hierarchy.
/// Use pattern matching to handle the specific subscription types.
sealed class SubscriptionItem {
  final int scheduleBlockSweepId;
  final int leadMinutes;
  final String? lastNotifiedAt;
  final String? error;

  SubscriptionItem({
    required this.scheduleBlockSweepId,
    required this.leadMinutes,
    this.lastNotifiedAt,
    this.error,
  });

  /// Factory that creates the appropriate subtype based on subscription_type
  factory SubscriptionItem.fromJson(Map<String, dynamic> json) {
    final subscriptionType = json['subscription_type'] as String? ?? 'sweeping';

    if (subscriptionType == 'timing') {
      return TimingSubscription.fromJson(json);
    }
    return SweepingSubscription.fromJson(json);
  }

  /// Returns true if this subscription has valid data (no error)
  bool get hasScheduleData;

  /// Returns true if a notification has already been sent for the current window
  bool get hasBeenNotified;

  /// The deadline datetime string used for notification calculations
  String? get deadlineIso;
}

/// Subscription for street sweeping alerts
class SweepingSubscription extends SubscriptionItem {
  final String corridor;
  final String limits;
  final String? blockSide;
  final String nextSweepStart;
  final String nextSweepEnd;

  SweepingSubscription({
    required super.scheduleBlockSweepId,
    required super.leadMinutes,
    super.lastNotifiedAt,
    super.error,
    required this.corridor,
    required this.limits,
    this.blockSide,
    required this.nextSweepStart,
    required this.nextSweepEnd,
  });

  factory SweepingSubscription.fromJson(Map<String, dynamic> json) {
    return SweepingSubscription(
      scheduleBlockSweepId: json['schedule_block_sweep_id'] as int,
      leadMinutes: json['lead_minutes'] as int,
      lastNotifiedAt: json['last_notified_at'] as String?,
      error: json['error'] as String?,
      corridor: json['corridor'] as String? ?? 'Unknown',
      limits: json['limits'] as String? ?? '',
      blockSide: json['block_side'] as String?,
      nextSweepStart: json['next_sweep_start'] as String? ?? '',
      nextSweepEnd: json['next_sweep_end'] as String? ?? '',
    );
  }

  @override
  bool get hasScheduleData => corridor.isNotEmpty && error == null;

  @override
  String? get deadlineIso => nextSweepStart;

  @override
  bool get hasBeenNotified {
    if (lastNotifiedAt == null || nextSweepStart.isEmpty) {
      return false;
    }
    try {
      final notifiedAt = DateTime.parse(lastNotifiedAt!);
      final sweepStart = DateTime.parse(nextSweepStart);
      final notifyAt = sweepStart.subtract(Duration(minutes: leadMinutes));
      return notifiedAt.isAtSameOrAfter(notifyAt);
    } catch (_) {
      return false;
    }
  }
}

/// Subscription for time-limited parking alerts
class TimingSubscription extends SubscriptionItem {
  final String regulation;
  final int hourLimit;
  final String days;
  final String fromTime;
  final String toTime;
  final String nextMoveDeadline;

  TimingSubscription({
    required super.scheduleBlockSweepId,
    required super.leadMinutes,
    super.lastNotifiedAt,
    super.error,
    required this.regulation,
    required this.hourLimit,
    required this.days,
    required this.fromTime,
    required this.toTime,
    required this.nextMoveDeadline,
  });

  factory TimingSubscription.fromJson(Map<String, dynamic> json) {
    return TimingSubscription(
      scheduleBlockSweepId: json['schedule_block_sweep_id'] as int,
      leadMinutes: json['lead_minutes'] as int,
      lastNotifiedAt: json['last_notified_at'] as String?,
      error: json['error'] as String?,
      regulation: json['regulation'] as String? ?? 'Time limited',
      hourLimit: json['hour_limit'] as int? ?? 0,
      days: json['days'] as String? ?? '',
      fromTime: json['from_time'] as String? ?? '',
      toTime: json['to_time'] as String? ?? '',
      nextMoveDeadline: json['next_move_deadline'] as String? ?? '',
    );
  }

  @override
  bool get hasScheduleData => nextMoveDeadline.isNotEmpty && error == null;

  @override
  String? get deadlineIso => nextMoveDeadline;

  @override
  bool get hasBeenNotified {
    if (lastNotifiedAt == null || nextMoveDeadline.isEmpty) {
      return false;
    }
    try {
      final notifiedAt = DateTime.parse(lastNotifiedAt!);
      final deadline = DateTime.parse(nextMoveDeadline);
      final notifyAt = deadline.subtract(Duration(minutes: leadMinutes));
      return notifiedAt.isAtSameOrAfter(notifyAt);
    } catch (_) {
      return false;
    }
  }
}

extension DateTimeComparison on DateTime {
  bool isAtSameOrAfter(DateTime other) {
    return isAtSameMomentAs(other) || isAfter(other);
  }
}

/// Response from GET /subscriptions/:device_token
/// Contains all subscriptions for a device
class SubscriptionsResponse {
  final String deviceToken;
  final String platform;
  final List<SubscriptionItem> subscriptions;

  SubscriptionsResponse({
    required this.deviceToken,
    required this.platform,
    required this.subscriptions,
  });

  factory SubscriptionsResponse.fromJson(Map<String, dynamic> json) {
    final subscriptionsList = (json['subscriptions'] as List<dynamic>)
        .map((item) => SubscriptionItem.fromJson(item as Map<String, dynamic>))
        .toList();

    return SubscriptionsResponse(
      deviceToken: json['device_token'] as String,
      platform: json['platform'] as String,
      subscriptions: subscriptionsList,
    );
  }

  /// Returns true if there are any subscriptions
  bool get hasSubscriptions => subscriptions.isNotEmpty;

  /// Returns subscriptions that have valid schedule data and haven't been notified yet
  List<SubscriptionItem> get validSubscriptions => subscriptions
      .where((s) => s.hasScheduleData && !s.hasBeenNotified)
      .toList();
}

/// Legacy single subscription response (kept for backwards compatibility)
/// Used by POST /subscriptions response
class SubscriptionResponse {
  final String deviceToken;
  final String platform;
  final int scheduleBlockSweepId;
  final int leadMinutes;
  final String corridor;
  final String limits;
  final String? blockSide;
  final String nextSweepStart;
  final String nextSweepEnd;

  SubscriptionResponse({
    required this.deviceToken,
    required this.platform,
    required this.scheduleBlockSweepId,
    required this.leadMinutes,
    required this.corridor,
    required this.limits,
    this.blockSide,
    required this.nextSweepStart,
    required this.nextSweepEnd,
  });

  factory SubscriptionResponse.fromJson(Map<String, dynamic> json) {
    return SubscriptionResponse(
      deviceToken: json['device_token'] as String,
      platform: json['platform'] as String,
      scheduleBlockSweepId: json['schedule_block_sweep_id'] as int,
      leadMinutes: json['lead_minutes'] as int,
      corridor: json['corridor'] as String,
      limits: json['limits'] as String,
      blockSide: json['block_side'] as String?,
      nextSweepStart: json['next_sweep_start'] as String,
      nextSweepEnd: json['next_sweep_end'] as String,
    );
  }
}
