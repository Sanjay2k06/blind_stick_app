import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';

/// Data structure containing meaningful human-readable location fields.
class GeocodedLocationInfo {
  final String? locality; // Neighbourhood / suburb / area (e.g. Injambakkam, Adyar)
  final String? city;     // City / Town / District (e.g. Chennai)
  final String? state;    // State (e.g. Tamil Nadu)

  const GeocodedLocationInfo({
    this.locality,
    this.city,
    this.state,
  });

  bool get isEmpty =>
      (locality == null || locality!.trim().isEmpty) &&
      (city == null || city!.trim().isEmpty) &&
      (state == null || state!.trim().isEmpty);

  @override
  String toString() =>
      'GeocodedLocationInfo(locality: $locality, city: $city, state: $state)';
}

/// Service to resolve GPS latitude/longitude into human-readable area names.
///
/// Section 7 of MASTER PROMPT:
/// - Extracts locality, city, state.
/// - Never exposes raw coordinates to speech.
class ReverseGeocodingService {
  final Geocoding? _customGeocoding;

  ReverseGeocodingService({Geocoding? geocoding})
      : _customGeocoding = geocoding;

  Future<GeocodedLocationInfo?> reverseGeocode(
    double latitude,
    double longitude,
  ) async {
    try {
      final geocoding = _customGeocoding ?? Geocoding();
      final List<Placemark> placemarks = await geocoding.placemarkFromCoordinates(
        latitude,
        longitude,
      );

      if (placemarks.isEmpty) return null;

      // Find the most detailed placemark with meaningful locality data
      for (final p in placemarks) {
        String? locality = p.subLocality?.trim();
        if (locality == null || locality.isEmpty) {
          locality = p.locality?.trim();
        }

        String? city = p.locality?.trim();
        if (city == null || city.isEmpty || city == locality) {
          city = p.subAdministrativeArea?.trim();
        }

        String? state = p.administrativeArea?.trim();

        // If locality is identical to city, avoid repeating it
        if (locality != null && city != null && locality.toLowerCase() == city.toLowerCase()) {
          locality = null;
        }

        final info = GeocodedLocationInfo(
          locality: (locality != null && locality.isNotEmpty) ? locality : null,
          city: (city != null && city.isNotEmpty) ? city : null,
          state: (state != null && state.isNotEmpty) ? state : null,
        );

        if (!info.isEmpty) {
          debugPrint('ReverseGeocodingService: Resolved location: $info');
          return info;
        }
      }

      return null;
    } catch (e) {
      debugPrint('ReverseGeocodingService: Geocoding error: $e');
      return null;
    }
  }
}
