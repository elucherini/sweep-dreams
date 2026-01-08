import 'package:flutter/foundation.dart';

/// Shared state for tracking which schedule blocks have active subscriptions.
/// Used to show appropriate UI for already-subscribed blocks.
class SubscriptionState extends ChangeNotifier {
  final Set<int> _subscribedBlockSweepIds = {};

  /// Returns true if the given blockSweepId has an active subscription.
  bool isSubscribed(int blockSweepId) {
    return _subscribedBlockSweepIds.contains(blockSweepId);
  }

  /// Add a subscription for the given blockSweepId.
  void addSubscription(int blockSweepId) {
    if (_subscribedBlockSweepIds.add(blockSweepId)) {
      notifyListeners();
    }
  }

  /// Remove a subscription for the given blockSweepId.
  void removeSubscription(int blockSweepId) {
    if (_subscribedBlockSweepIds.remove(blockSweepId)) {
      notifyListeners();
    }
  }

  /// Replace all subscriptions with the given set of blockSweepIds.
  void setSubscriptions(Iterable<int> blockSweepIds) {
    _subscribedBlockSweepIds.clear();
    _subscribedBlockSweepIds.addAll(blockSweepIds);
    notifyListeners();
  }

  /// Clear all subscriptions.
  void clear() {
    if (_subscribedBlockSweepIds.isNotEmpty) {
      _subscribedBlockSweepIds.clear();
      notifyListeners();
    }
  }
}
