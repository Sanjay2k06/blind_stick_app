import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Service responsible for fetching current GPS position safely across all Android & iOS devices.
///
/// Section 6 & 11 of MASTER PROMPT:
/// - Fetches GPS location only after Start is pressed.
/// - Never exposes raw coordinates or technical numbers to speech.
/// - Handles timeouts, permission, non-Google devices, and indoor GPS drops gracefully.
class LocationService {
  final Duration timeout;

  LocationService({this.timeout = const Duration(seconds: 5)});

  /// Checks if location permission is granted, requests if needed.
  Future<bool> ensurePermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('LocationService: Location permission denied');
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('LocationService: Location permission permanently denied');
        return false;
      }

      // Check if location hardware services are enabled on device
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('LocationService: Location service toggle is disabled on device');
        // Note: Even if service toggle is disabled, cached location might still exist
      }

      return true;
    } catch (e) {
      debugPrint('LocationService: ensurePermission error: $e');
      return false;
    }
  }

  /// Attempts to acquire current position with multi-layered fallbacks:
  /// 1. Fresh cached position if < 5 minutes old
  /// 2. Fused location provider / medium accuracy
  /// 3. Native Android LocationManager (cell/Wi-Fi network provider, works indoors & on non-Google devices)
  /// 4. Historical last known position fallback
  Future<Position?> getCurrentLocation({int maxRetries = 2}) async {
    final hasPermission = await ensurePermission();
    if (!hasPermission) return null;

    // Fast check: if recent cached position exists (< 5 minutes), use it immediately
    Position? fallbackCached;
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        fallbackCached = lastKnown;
        final age = DateTime.now().difference(lastKnown.timestamp);
        if (age.inMinutes < 5) {
          debugPrint('LocationService: Using fresh cached position (${age.inSeconds}s old)');
          return lastKnown;
        }
      }
    } catch (_) {}

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        LocationSettings settings;
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          if (attempt == 1) {
            // First attempt: Fused Location Provider with medium accuracy
            settings = AndroidSettings(
              accuracy: LocationAccuracy.medium,
              forceLocationManager: false,
              timeLimit: timeout,
            );
          } else {
            // Second attempt: Native Android LocationManager with low accuracy
            // (Uses cell tower and Wi-Fi networks; works indoors and on devices without GMS)
            settings = AndroidSettings(
              accuracy: LocationAccuracy.low,
              forceLocationManager: true,
              timeLimit: const Duration(seconds: 4),
            );
          }
        } else {
          settings = LocationSettings(
            accuracy: attempt == 1 ? LocationAccuracy.medium : LocationAccuracy.low,
            timeLimit: timeout,
          );
        }

        final position = await Geolocator.getCurrentPosition(locationSettings: settings);
        return position;
      } catch (e) {
        debugPrint('LocationService: Attempt $attempt failed to acquire GPS: $e');

        // Immediate fallback check to last known position
        try {
          final lastKnown = await Geolocator.getLastKnownPosition();
          if (lastKnown != null) {
            debugPrint('LocationService: Utilizing last known position as fallback');
            return lastKnown;
          }
        } catch (_) {}

        if (attempt == maxRetries) {
          if (fallbackCached != null) {
            debugPrint('LocationService: Returning cached fallback position after retries');
            return fallbackCached;
          }
          return null;
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }

    return fallbackCached;
  }
}
