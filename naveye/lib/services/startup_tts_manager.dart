import 'package:flutter/foundation.dart';
import 'tts_service.dart';

/// Coordinates sequential Tamil voice announcements during startup.
///
/// Sections 10, 11, 12, 13, 15 of MASTER PROMPT:
/// - Strictly sequential: BGM stops -> Location -> Time -> "வழிகாட்டுதல் தொடங்குகிறது."
/// - Never overlaps speech.
/// - Never speaks raw coordinates or technical jargon.
class StartupTtsManager {
  final TtsService? _customTts;

  StartupTtsManager({TtsService? tts}) : _customTts = tts;

  TtsService get _tts => _customTts ?? TtsService();

  /// Speaks message when GPS acquisition is delayed/in progress.
  Future<void> speakGpsWaiting() async {
    debugPrint('StartupTtsManager: Speaking GPS waiting');
    await _tts.speakAndWait(
      'உங்கள் இருப்பிடத்தைப் பெறுகிறோம். சிறிது நேரம் காத்திருக்கவும்.',
      timeout: const Duration(seconds: 8),
    );
  }

  /// Speaks message when GPS acquisition fails.
  Future<void> speakGpsError() async {
    debugPrint('StartupTtsManager: Speaking GPS error');
    await _tts.speakAndWait(
      'உங்கள் இருப்பிடத்தைப் பெற முடியவில்லை. தயவுசெய்து இருப்பிட சேவையைச் சரிபார்க்கவும்.',
      timeout: const Duration(seconds: 10),
    );
  }

  /// Speaks the natural resolved Tamil location sentence.
  Future<void> speakLocation(String tamilLocationSentence) async {
    debugPrint('StartupTtsManager: Speaking location: $tamilLocationSentence');
    await _tts.speakAndWait(
      tamilLocationSentence,
      timeout: const Duration(seconds: 12),
    );
  }

  /// Speaks the natural current time sentence in Tamil.
  Future<void> speakTime(String tamilTimeSentence) async {
    debugPrint('StartupTtsManager: Speaking time: $tamilTimeSentence');
    await _tts.speakAndWait(
      tamilTimeSentence,
      timeout: const Duration(seconds: 10),
    );
  }

  /// Speaks the final startup transition message: "வழிகாட்டுதல் தொடங்குகிறது."
  Future<void> speakNavigationStarting() async {
    debugPrint('StartupTtsManager: Speaking navigation starting');
    await _tts.speakAndWait(
      'வழிகாட்டுதல் தொடங்குகிறது.',
      timeout: const Duration(seconds: 6),
    );
  }

  /// Halts any ongoing speech.
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (e) {
      debugPrint('StartupTtsManager: Error stopping TTS: $e');
    }
  }
}
