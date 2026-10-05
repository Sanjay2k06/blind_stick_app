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

  LocationService({this.timeout = const Duration(seconds: 10)});

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

  /// Attempts to acquire current position with timeout and fallback.
  Future<Position?> getCurrentLocation({int maxRetries = 1}) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final hasPermission = await ensurePermission();
        if (!hasPermission) return null;

        final position = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: timeout,
          ),
        );
        return position;
      } catch (e) {
        debugPrint('LocationService: Attempt $attempt failed to acquire GPS: $e');
        if (attempt == maxRetries) {
          // As a fallback, try to get the last known position
          try {
            final lastKnown = await Geolocator.getLastKnownPosition();
            if (lastKnown != null) {
              debugPrint('LocationService: Utilizing last known position as fallback');
              return lastKnown;
            }
          } catch (_) {}
          return null;
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    return null;
  }
}
