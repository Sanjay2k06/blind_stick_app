import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Text-to-Speech service — always English (en-US).
///
/// BUG-8 FIX: Converted to a singleton via Dart factory constructor.
/// Previously every screen created `final TtsService _tts = TtsService()`,
/// each creating a separate FlutterTts engine.  Multiple engines compete on
/// the single Android TTS channel — calling stop() on one does NOT stop
/// another engine's speech, causing overlapping / echoing audio.
/// The factory constructor means `TtsService()` always returns the same instance.
class TtsService {
  // ── Singleton ─────────────────────────────────────────────────────────────
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  final FlutterTts _tts = FlutterTts();
  bool   _isSpeaking = false;
  bool   _muted      = false;
  String _lastSpoken = '';
  String _languageCode = 'ta-IN';
  bool   _isTamilAvailable = true;

  final ValueNotifier<bool> isTamilAvailableNotifier = ValueNotifier<bool>(true);

  // BUG-6 FIX: use Timer so it can be cancelled when dispose() is called.
  Timer? _speakTimer;

  double _speechRate = 0.45;
  double get speechRateMultiplier => _speechRate / 0.45;

  bool get isSpeaking => _isSpeaking;
  bool get isTamilAvailable => _isTamilAvailable;
  void mute()   => _muted = true;
  void unmute() => _muted = false;

  Future<void> setSpeechRateMultiplier(double multiplier) async {
    final clamped = multiplier.clamp(0.8, 2.0);
    _speechRate = (0.45 * clamped).clamp(0.35, 0.95);
    await _tts.setSpeechRate(_speechRate);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('speech_rate_multiplier', clamped);
  }

  /// Register a one-shot callback fired when the current speech finishes.
  void setOnComplete(VoidCallback cb) {
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
      cb();
    });
  }

  /// Speaks text and waits until completion or timeout.
  /// Guarantees that subsequent startup steps never overlap in speech.
  Future<void> speakAndWait(String text, {Duration timeout = const Duration(seconds: 12)}) async {
    if (!_isTamilAvailable || text.trim().isEmpty) return;

    final completer = Completer<void>();
    Timer? timeoutTimer;

    _lastSpoken = text;
    _isSpeaking = true;
    _speakTimer?.cancel();

    void onDone() {
      timeoutTimer?.cancel();
      _isSpeaking = false;
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    _tts.setCompletionHandler(onDone);
    _tts.setErrorHandler((_) => onDone());
    _tts.setCancelHandler(onDone);

    timeoutTimer = Timer(timeout, () {
      debugPrint('TTS speakAndWait: Timed out after ${timeout.inSeconds}s');
      onDone();
    });

    try {
      await _tts.stop();
      await _tts.speak(text);
      await completer.future;
    } catch (e) {
      debugPrint('TTS speakAndWait error: $e');
      onDone();
    } finally {
      timeoutTimer.cancel();
      // Restore default completion handlers
      _tts.setCompletionHandler(() => _isSpeaking = false);
      _tts.setErrorHandler((_) => _isSpeaking = false);
      _tts.setCancelHandler(() => _isSpeaking = false);
    }

    // Brief inter-utterance pause so next speech doesn't blend
    await Future.delayed(const Duration(milliseconds: 300));
  }

  bool get isTamil => true;
  String get languageCode => _languageCode;

  Future<void> setPreferredLanguage(String language) async {
    _languageCode = 'ta-IN';
    await _tts.setLanguage('ta-IN');
  }

  Future<void> init() async {
    final prefs  = await SharedPreferences.getInstance();
    final volume = prefs.getString('voice_volume') ?? 'Medium';

    _languageCode = 'ta-IN';
    try {
      final available = await _tts.isLanguageAvailable('ta-IN');
      _isTamilAvailable = available == true || available == 1;
      if (!_isTamilAvailable) {
        debugPrint('TTS Diagnostic: Tamil voice (ta-IN) is not available on this device engine.');
      }
    } catch (e) {
      debugPrint('TTS isLanguageAvailable error: $e');
      _isTamilAvailable = true;
    }
    isTamilAvailableNotifier.value = _isTamilAvailable;

    await _tts.setLanguage('ta-IN');
    try {
      final dynamic voices = await _tts.getVoices;
      if (voices is List) {
        for (final v in voices) {
          if (v is Map) {
            final locale = (v['locale'] ?? '').toString().toLowerCase();
            if (locale.contains('ta') || locale.contains('tam')) {
              await _tts.setVoice({
                'name': v['name'].toString(),
                'locale': v['locale'].toString(),
              });
              debugPrint('TTS Diagnostic: Selected installed Tamil voice: ${v['name']} (${v['locale']})');
              break;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('TTS getVoices error: $e');
    }

    final multiplier = prefs.getDouble('speech_rate_multiplier') ?? 1.0;
    _speechRate = (0.45 * multiplier).clamp(0.35, 0.95);
    await _tts.setSpeechRate(_speechRate);
    await _tts.setVolume(volume == 'High' ? 1.0 : volume == 'Low' ? 0.35 : 0.85);
    await _tts.setPitch(1.0);

    // Restore default handlers (setOnComplete may have overridden completion)
    _tts.setCompletionHandler(() => _isSpeaking = false);
    _tts.setErrorHandler((_)    => _isSpeaking = false);
    _tts.setCancelHandler(()    => _isSpeaking = false);
  }

  /// Obstacle announcement — skipped if muted, duplicate, or Tamil unavailable.
  Future<void> announce(String text) async {
    if (_muted || !_isTamilAvailable) return;
    if (_isSpeaking && text == _lastSpoken) return;
    _lastSpoken = text;
    _isSpeaking = true;
    await _tts.stop();
    await _tts.speak(text);
    _armTimeout();
  }

  /// General speech — respects mute + deduplication.
  Future<void> speak(String text) async {
    if (_muted || !_isTamilAvailable) return;
    if (_isSpeaking && text == _lastSpoken) return;
    _lastSpoken = text;
    _isSpeaking = true;
    await _tts.stop();
    await _tts.speak(text);
    _armTimeout();
  }

  /// Always speaks immediately — interrupts current speech, ignores mute.
  Future<void> speakNow(String text) async {
    if (!_isTamilAvailable) {
      debugPrint('TTS: Speech suppressed because Tamil voice is unavailable.');
      return;
    }
    _lastSpoken = text;
    _isSpeaking = true;
    await _tts.stop();
    await _tts.speak(text);
    _armTimeout();
  }

  void _armTimeout() {
    _speakTimer?.cancel();
    _speakTimer = Timer(
      const Duration(seconds: 25),
      () => _isSpeaking = false,
    );
  }

  Future<void> stop() async {
    _speakTimer?.cancel();
    await _tts.stop();
    _isSpeaking = false;
  }

  /// No-op in singleton context — the engine is kept alive for the app lifetime.
  /// Calling stop() is still safe and will halt current speech.
  void dispose() {
    _speakTimer?.cancel();
    _tts.stop();
  }
}
