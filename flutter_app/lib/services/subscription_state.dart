import 'package:flutter/foundation.dart';

/// Shared state for tracking which schedule blocks have active subscriptions.
/// Used to show appropriate UI for already-subscribed blocks.
class SubscriptionState extends ChangeNotifier {
  final Set<int> _subscribedBlockSweepIds = {};
  int _activeAlertsCount = 0;

  int get subscribedCount => _subscribedBlockSweepIds.length;
  int get activeAlertsCount => _activeAlertsCount;

  /// Returns true if the given blockSweepId has an active subscription.
  bool isSubscribed(int blockSweepId) {
    return _subscribedBlockSweepIds.contains(blockSweepId);
  }

  /// Add a subscription for the given blockSweepId.
  void addSubscription(int blockSweepId) {
    if (_subscribedBlockSweepIds.add(blockSweepId)) {
      _activeAlertsCount += 1;
      notifyListeners();
    }
  }

  /// Remove a subscription for the given blockSweepId.
  void removeSubscription(int blockSweepId) {
    if (_subscribedBlockSweepIds.remove(blockSweepId)) {
      if (_activeAlertsCount > 0) _activeAlertsCount -= 1;
      notifyListeners();
    }
  }

  /// Replace all subscriptions with the given set of blockSweepIds.
  void setSubscriptions(Iterable<int> blockSweepIds) {
    _subscribedBlockSweepIds.clear();
    _subscribedBlockSweepIds.addAll(blockSweepIds);
    notifyListeners();
  }

  void setActiveAlertsCount(int count) {
    final next = count < 0 ? 0 : count;
    if (next == _activeAlertsCount) return;
    _activeAlertsCount = next;
    notifyListeners();
  }

  /// Clear all subscriptions.
  void clear() {
    if (_subscribedBlockSweepIds.isNotEmpty || _activeAlertsCount != 0) {
      _subscribedBlockSweepIds.clear();
      _activeAlertsCount = 0;
      notifyListeners();
    }
  }
}
