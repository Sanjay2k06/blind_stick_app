import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Service responsible for fetching current GPS position safely.
///
/// Section 6 & 11 of MASTER PROMPT:
/// - Fetches GPS location only after Start is pressed.
/// - Never exposes raw coordinates or technical numbers to speech.
/// - Handles timeouts and permission gracefully.
class LocationService {
  final Duration timeout;

  LocationService({this.timeout = const Duration(seconds: 4)});

  /// Checks if location permission is granted, requests if needed.
  Future<bool> ensurePermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('LocationService: Location service is disabled on device');
      return false;
    }

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

    return true;
  }

  /// Attempts to acquire current position with fast cache-first fallback and bounded timeout.
  Future<Position?> getCurrentLocation({int maxRetries = 1}) async {
    final hasPermission = await ensurePermission();
    if (!hasPermission) return null;

    // Fast check: if recent cached position exists (< 10 minutes), use it immediately
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        final age = DateTime.now().difference(lastKnown.timestamp);
        if (age.inMinutes < 10) {
          debugPrint('LocationService: Using fresh cached position (${age.inSeconds}s old)');
          return lastKnown;
        }
      }
    } catch (_) {}

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: timeout,
          ),
        );
        return position;
      } catch (e) {
        debugPrint('LocationService: Attempt $attempt failed to acquire GPS: $e');
        // Fallback to last known position if current satellite lock timed out
        try {
          final lastKnown = await Geolocator.getLastKnownPosition();
          if (lastKnown != null) {
            debugPrint('LocationService: Utilizing last known position as fallback');
            return lastKnown;
          }
        } catch (_) {}

        if (attempt == maxRetries) {
          return null;
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    return null;
  }
}
