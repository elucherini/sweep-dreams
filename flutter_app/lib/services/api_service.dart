import 'dart:convert';
import 'dart:collection';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../models/subscription_response.dart';
import '../models/puck_response.dart';

/// Exception thrown when the user has reached the maximum number of subscriptions.
class SubscriptionLimitException implements Exception {
  final String message;
  SubscriptionLimitException(
      [this.message = 'Maximum subscriptions limit reached']);

  @override
  String toString() => message;
}

class _CacheEntry<T> {
  final T value;
  final DateTime expiresAt;

  const _CacheEntry({required this.value, required this.expiresAt});

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class ApiService {
  final String baseUrl;

  static const int _puckCoordPrecision = 4;
  static const Duration _puckCacheTtl = Duration(seconds: 15);
  static const int _puckCacheMaxEntries = 200;

  final LinkedHashMap<String, _CacheEntry<PuckResponse>> _puckCache =
      LinkedHashMap();
  final Map<String, Future<PuckResponse>> _puckInFlight = {};

  ApiService({String? baseUrl})
      : baseUrl = baseUrl ??
            const String.fromEnvironment(
              'API_URL',
              defaultValue: 'http://localhost:8787',
            );

  Future<PuckResponse> checkPuck(
    double latitude,
    double longitude, {
    int radius = 10,
  }) async {
    final qLat = latitude.toStringAsFixed(_puckCoordPrecision);
    final qLon = longitude.toStringAsFixed(_puckCoordPrecision);
    final cacheKey = 'puck:$qLat,$qLon:r=$radius';

    final cached = _puckCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      _puckCache.remove(cacheKey);
      _puckCache[cacheKey] = cached;
      return cached.value;
    }

    final inFlight = _puckInFlight[cacheKey];
    if (inFlight != null) {
      return await inFlight;
    }

    final uri = Uri.parse('$baseUrl/api/check-puck').replace(
      queryParameters: {
        'latitude': qLat,
        'longitude': qLon,
        'radius': radius.toString(),
      },
    );

    final future = http.get(uri).then((response) {
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return PuckResponse.fromJson(json);
      }

      throw Exception(
        'Failed to fetch puck data: ${response.statusCode} - ${response.body}',
      );
    });
    _puckInFlight[cacheKey] = future;

    try {
      final result = await future;
      _puckCache[cacheKey] = _CacheEntry(
        value: result,
        expiresAt: DateTime.now().add(_puckCacheTtl),
      );
      while (_puckCache.length > _puckCacheMaxEntries) {
        _puckCache.remove(_puckCache.keys.first);
      }
      return result;
    } finally {
      _puckInFlight.remove(cacheKey);
    }
  }

  Future<void> subscribeToSchedule({
    required String deviceToken,
    required int scheduleBlockSweepId,
    required double latitude,
    required double longitude,
    int leadMinutes = 60,
    String subscriptionType = 'sweeping',
  }) async {
    final uri = Uri.parse('$baseUrl/subscriptions');
    final payload = {
      'device_token': deviceToken,
      'platform': _platform(),
      'subscription_type': subscriptionType,
      'schedule_block_sweep_id': scheduleBlockSweepId,
      'latitude': latitude,
      'longitude': longitude,
      'lead_minutes': leadMinutes,
    };

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode == 409) {
      throw SubscriptionLimitException();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to save subscription: ${response.statusCode} - ${response.body}',
      );
    }
  }

  /// Get all subscriptions for a device token
  Future<SubscriptionsResponse?> getSubscriptions(String deviceToken) async {
    final uri =
        Uri.parse('$baseUrl/subscriptions/${Uri.encodeComponent(deviceToken)}');

    final response = await http.get(uri);

    if (response.statusCode == 404) {
      return null;
    }

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return SubscriptionsResponse.fromJson(json);
    } else {
      throw Exception(
        'Failed to fetch subscriptions: ${response.statusCode} - ${response.body}',
      );
    }
  }

  /// Delete a specific subscription by device token and schedule ID
  Future<void> deleteSubscription(
    String deviceToken,
    int scheduleBlockSweepId,
  ) async {
    final uri = Uri.parse(
      '$baseUrl/subscriptions/${Uri.encodeComponent(deviceToken)}/$scheduleBlockSweepId',
    );

    final response = await http.delete(uri);

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception(
        'Failed to delete subscription: ${response.statusCode} - ${response.body}',
      );
    }
  }

  String _platform() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      default:
        return 'web';
    }
  }
}
