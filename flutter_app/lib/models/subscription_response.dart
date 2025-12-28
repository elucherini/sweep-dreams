/// Represents a single subscription/alert for a schedule
class SubscriptionItem {
  final int scheduleBlockSweepId;
  final int leadMinutes;
  final String? corridor;
  final String? limits;
  final String? blockSide;
  final String? nextSweepStart;
  final String? nextSweepEnd;
  final String? error;

  SubscriptionItem({
    required this.scheduleBlockSweepId,
    required this.leadMinutes,
    this.corridor,
    this.limits,
    this.blockSide,
    this.nextSweepStart,
    this.nextSweepEnd,
    this.error,
  });

  factory SubscriptionItem.fromJson(Map<String, dynamic> json) {
    return SubscriptionItem(
      scheduleBlockSweepId: json['schedule_block_sweep_id'] as int,
      leadMinutes: json['lead_minutes'] as int,
      corridor: json['corridor'] as String?,
      limits: json['limits'] as String?,
      blockSide: json['block_side'] as String?,
      nextSweepStart: json['next_sweep_start'] as String?,
      nextSweepEnd: json['next_sweep_end'] as String?,
      error: json['error'] as String?,
    );
  }

  /// Returns true if this subscription has valid schedule data
  bool get hasScheduleData => corridor != null && error == null;
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

  /// Returns subscriptions that have valid schedule data
  List<SubscriptionItem> get validSubscriptions =>
      subscriptions.where((s) => s.hasScheduleData).toList();
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
