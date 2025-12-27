class SubscriptionResponse {
  final String deviceToken;
  final String platform;
  final int scheduleBlockSweepId;
  final int leadMinutes;
  final String nextSweepStart;
  final String nextSweepEnd;

  SubscriptionResponse({
    required this.deviceToken,
    required this.platform,
    required this.scheduleBlockSweepId,
    required this.leadMinutes,
    required this.nextSweepStart,
    required this.nextSweepEnd,
  });

  factory SubscriptionResponse.fromJson(Map<String, dynamic> json) {
    return SubscriptionResponse(
      deviceToken: json['device_token'] as String,
      platform: json['platform'] as String,
      scheduleBlockSweepId: json['schedule_block_sweep_id'] as int,
      leadMinutes: json['lead_minutes'] as int,
      nextSweepStart: json['next_sweep_start'] as String,
      nextSweepEnd: json['next_sweep_end'] as String,
    );
  }
}
