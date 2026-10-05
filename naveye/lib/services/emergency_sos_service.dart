import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibration/vibration.dart';

class SosPayload {
  final double latitude;
  final double longitude;
  final int batteryLevel;
  final String emergencyContact;
  final String messageTa;
  final String mapUrl;

  const SosPayload({
    required this.latitude,
    required this.longitude,
    required this.batteryLevel,
    required this.emergencyContact,
    required this.messageTa,
    required this.mapUrl,
  });
}

class EmergencySosService {
  EmergencySosService._();
  static final EmergencySosService instance = EmergencySosService._();

  final Battery _battery = Battery();

  /// Trigger full Emergency SOS procedure
  Future<SosPayload> triggerSos() async {
    debugPrint('EmergencySOS: Triggered!');

    // 1. Heavy SOS haptic pattern: 3 short, 3 long, 3 short (SOS in morse)
    try {
      final hasVib = await Vibration.hasVibrator();
      if (hasVib == true) {
        Vibration.vibrate(
          pattern: [0, 200, 100, 200, 100, 200, 200, 500, 100, 500, 100, 500, 200, 200, 100, 200],
        );
      }
    } catch (_) {}

    // 2. Fetch battery level
    int batteryLevel = 50;
    try {
      batteryLevel = await _battery.batteryLevel;
    } catch (e) {
      debugPrint('EmergencySOS battery error: $e');
    }

    // 3. Fetch GPS position
    double lat = 13.0827; // Chennai fallback
    double lng = 80.2707;
    try {
      final hasPerm = await Geolocator.checkPermission();
      if (hasPerm == LocationPermission.always || hasPerm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 4),
          ),
        );
        lat = pos.latitude;
        lng = pos.longitude;
      }
    } catch (e) {
      debugPrint('EmergencySOS geolocator error: $e');
    }

    // 4. Retrieve emergency contact number
    final prefs = await SharedPreferences.getInstance();
    final emergencyContact = prefs.getString('user_emergency') ??
        prefs.getString('emergency_phone') ??
        '';

    final mapUrl = 'https://maps.google.com/?q=${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';
    final messageTa = 'அவசர உதவி தேவை! நாவ்ஐ பயனாளர் அவசர உதவி கோருகிறார்.\n'
        'இருப்பிடம்: $mapUrl\n'
        'பேட்டரி: $batteryLevel%';

    final payload = SosPayload(
      latitude: lat,
      longitude: lng,
      batteryLevel: batteryLevel,
      emergencyContact: emergencyContact,
      messageTa: messageTa,
      mapUrl: mapUrl,
    );

    // 5. If contact phone exists, launch SMS intent
    if (emergencyContact.isNotEmpty) {
      final cleanPhone = emergencyContact.replaceAll(RegExp(r'[^0-9+]'), '');
      final smsUri = Uri(
        scheme: 'sms',
        path: cleanPhone,
        queryParameters: {'body': messageTa},
      );
      try {
        if (await canLaunchUrl(smsUri)) {
          await launchUrl(smsUri, mode: LaunchMode.externalApplication);
        }
      } catch (e) {
        debugPrint('EmergencySOS SMS launch error: $e');
      }
    }

    return payload;
  }
}
