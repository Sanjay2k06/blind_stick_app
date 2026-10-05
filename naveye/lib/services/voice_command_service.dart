import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'shared_stt.dart';

enum VoiceCommand {
  start,
  stop,
  repeat,
  whoIsThis,
  openSettings,
  openPeople,
  help,
  whereAmI,
  detectObjects,
  switchCamera,
  changeLanguage,
  addPerson,
  cancel,
  goBack,
  identifyCurrency,
  readText,
  findObject,
  emergencySOS,
  toggleTorch,
  fasterSpeed,
  slowerSpeed,
  time,
  whatIsInFront,
  unknown
}

class VoiceCommandService {
  bool _listening = false;
  bool get isListening => _listening;
  String lastQuery = '';

  /// Lazy-init: call this to warm up STT when convenient (e.g. after the first
  /// tap). Intentionally avoided at app start on Samsung devices because calling
  /// initialize() triggers Samsung's speech service warm-up (200 ms STT cycles).
  Future<bool> init() => SharedStt.instance.init();

  Future<void> startListening(void Function(VoiceCommand) onCommand) async {
    // Lazy-init — only initialise STT the first time the user triggers voice.
    // This avoids Samsung's automatic speech-service warm-up at startup.
    final available = await SharedStt.instance.init();
    if (!available) {
      debugPrint('VoiceCmd: STT not available after lazy init');
      onCommand(VoiceCommand.unknown);
      return;
    }

    // Stop anything currently listening
    if (SharedStt.instance.isListening) {
      await SharedStt.instance.stop();
      await Future.delayed(const Duration(milliseconds: 300));
    }

    _listening = true;
    // Samsung Galaxy A30 (Android 10): on-device STT model is often missing or
    // blocked by Bixby → silent fail within 200 ms.
    // Cloud STT is significantly more reliable on Samsung; use it as PRIMARY.
    // onDevice=false still works offline on some Samsungs but falls back
    // gracefully when no network — the error handler retries with onDevice=true.
    await _doListen(onCommand, retryLeft: 2, onDevice: false);
  }

  Future<void> _doListen(
    void Function(VoiceCommand) onCommand, {
    required int retryLeft,
    bool onDevice = true,
  }) async {
    bool done = false;

    void finish(String words) async {
      if (done) return;
      done = true;
      _listening = false;
      lastQuery = words;
      SharedStt.instance.clearListeners();
      await SharedStt.instance.stop();
      debugPrint('VoiceCmd recognised: "$words"');
      onCommand(_parse(words));
    }

    void abort() {
      if (done) return;
      done = true;
      _listening = false;
      SharedStt.instance.clearListeners();
      onCommand(VoiceCommand.unknown);
    }

    // FIX-2: Status listener — catches silent STT stops (e.g. the engine
    // transitions to "notListening" after pauseFor timeout without firing a
    // finalResult). Without this the 12-second _voiceTimeout is the only
    // recovery, leaving the user waiting with no feedback.
    SharedStt.instance.setStatusListener((String status) {
      debugPrint('VoiceCmd status: $status  done=$done');
      if ((status == 'notListening' || status == 'done') && !done) {
        // STT ended without a result — treat as no command heard.
        // Small delay so any in-flight onResult callback fires first.
        Future.delayed(const Duration(milliseconds: 200), () {
          if (!done) abort();
        });
      }
    });

    // Register error listener — fires when network/audio error occurs mid-listen
    SharedStt.instance.setErrorListener((SpeechRecognitionError error) async {
      if (done) return;
      final msg = error.errorMsg;
      debugPrint('VoiceCmd error: $msg  retryLeft=$retryLeft  onDevice=$onDevice');

      // error_busy           = mic in use → abort, don't fight it
      // error_speech_timeout = user didn't speak → abort gracefully
      // error_no_match       = no speech detected → abort gracefully
      // error_network        = transient connectivity → retry
      // error_language_not_supported / error_client = on-device model missing
      //   → fall back to cloud STT (onDevice=false)
      final isNetworkRetry   = msg.contains('error_network') && retryLeft > 0;
      final isOnDeviceFailed = onDevice &&
          (msg.contains('error_language_not_supported') ||
           msg.contains('error_client') ||
           msg.contains('error_not_supported'));

      if (isNetworkRetry) {
        done = true;
        SharedStt.instance.clearListeners();
        try { await SharedStt.instance.stop(); } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 800));
        if (_listening) {
          debugPrint('VoiceCmd retrying network… ($retryLeft left)');
          await _doListen(onCommand, retryLeft: retryLeft - 1, onDevice: onDevice);
        }
      } else if (isOnDeviceFailed) {
        // On-device model unavailable — retry with cloud STT.
        // Use retryLeft - 1 so the total attempts across both modes is bounded.
        done = true;
        SharedStt.instance.clearListeners();
        try { await SharedStt.instance.stop(); } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 500));
        if (_listening && retryLeft > 0) {
          debugPrint('VoiceCmd: on-device unavailable, switching to cloud STT (retryLeft=${retryLeft - 1})');
          await _doListen(onCommand, retryLeft: retryLeft - 1, onDevice: false);
        } else if (_listening) {
          debugPrint('VoiceCmd: on-device unavailable, no retries left — aborting');
          abort();
        }
      } else {
        // All other errors: stop cleanly and return unknown command
        abort();
      }
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final lang = (prefs.getString('language') ?? 'Tamil').toLowerCase();
      final localeId = lang.contains('english') ? 'en_US' : 'ta_IN';
      debugPrint('STT listen ← VoiceCommandService (localeId=$localeId onDevice=$onDevice retryLeft=$retryLeft)');
      await SharedStt.instance.raw.listen(
        onResult: (result) {
          final words = result.recognizedWords.toLowerCase().trim();
          if (words.isEmpty) return;
          if (result.finalResult) {
            finish(words);
            return;
          }
          // Fire immediately on partial if command is already clear
          final cmd = _parse(words);
          if (cmd != VoiceCommand.unknown) finish(words);
        },
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          cancelOnError: false,
          partialResults: true,
          onDevice: onDevice,
          listenFor: const Duration(seconds: 10),
          pauseFor: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('VoiceCmd listen error: $e');
      abort();
    }
  }

  Future<void> stopListening() async {
    _listening = false;
    SharedStt.instance.clearListeners();
    await SharedStt.instance.stop();
  }

  /// Parses transcribed words into a VoiceCommand (public for testing and offline fallback)
  VoiceCommand parseCommand(String words) => _parse(words);

  VoiceCommand _parse(String words) {
    if (words.isEmpty) { return VoiceCommand.unknown; }
    final lower = words.toLowerCase().trim();

    // Help instructions (distinguish from emergency distress cry)
    if (_has(lower, ['help', 'commands', 'assist', 'guide', 'instructions', 'what can', 'வழிமுறைகள்', 'உதவிக்குறிப்பு', 'கட்டளைகள்', 'உதவிக்குறிப்புகள்'])) {
      return VoiceCommand.help;
    }

    // 1. Emergency SOS has the absolute highest priority
    if (_has(lower, ['அவசரம்', 'காப்பாற்று', 'ஆபத்து', 'sos', 'emergency', 'distress', 'அவசர உதவி', 'உதவி'])) {
      return VoiceCommand.emergencySOS;
    }
    // 2. Start / Stop controls
    if (_has(lower, ['start', 'begin', 'go', 'detect', 'scan', 'activate', 'தொடங்கு', 'ஆரம்பி'])) {
      return VoiceCommand.start;
    }
    if (_has(lower, ['stop', 'end', 'off', 'pause', 'halt', 'cancel', 'finish', 'deactivate', 'நிறுத்து', 'முடி'])) {
      return VoiceCommand.stop;
    }
    if (_has(lower, ['repeat', 'again', 'say again', 'what was that', 'pardon', 'what did', 'மீண்டும்', 'திரும்ப'])) {
      return VoiceCommand.repeat;
    }
    // 3. Assistive Utilities
    if (_has(lower, ['பணம்', 'ரூபாய்', 'நோட்டு', 'காசு', 'currency', 'money', 'rupee', 'banknote', 'cash'])) {
      return VoiceCommand.identifyCurrency;
    }
    if (_has(lower, ['படி', 'எழுத்து', 'பலகை', 'வாசி', 'அறிவிப்பு', 'read', 'text', 'signboard', 'sign', 'ocr'])) {
      return VoiceCommand.readText;
    }
    // Object Finder (e.g. "சாவி எங்கே", "பாட்டில் எங்கே", "find keys")
    if (_has(lower, ['சாவி', 'பாட்டில்', 'கப்', 'find', 'where is', 'search', 'நாற்காலி', 'தேடு']) ||
        (lower.contains('எங்கே') && !lower.contains('நான்') && !lower.contains('இருப்பிடம்'))) {
      return VoiceCommand.findObject;
    }
    // Torch / Flashlight
    if (_has(lower, ['டார்ச்', 'வெளிச்சம்', 'விளக்கு', 'torch', 'flashlight', 'light'])) {
      return VoiceCommand.toggleTorch;
    }
    // Speech Rate
    if (_has(lower, ['வேகமாக', 'வேகம்', 'faster', 'speed up'])) {
      return VoiceCommand.fasterSpeed;
    }
    if (_has(lower, ['மெதுவாக', 'slower', 'slow down', 'normal speed'])) {
      return VoiceCommand.slowerSpeed;
    }
    // Location / Person
    if (_has(lower, ['who', 'identify', 'name', 'face', 'recognize', 'recognise', 'யார்', 'முகம்'])) {
      return VoiceCommand.whoIsThis;
    }
    if (_has(lower, ['where am i', 'where am i now', 'current location', 'my location', 'location', 'நான் எங்கே', 'இருப்பிடம்', 'இடம்', 'என் இருப்பிடம்', 'எங்கே இருக்கிறேன்', 'என் இடம்', 'தற்போதைய இருப்பிடம்'])) {
      return VoiceCommand.whereAmI;
    }
    if (_has(lower, [
      'முன்னாடி என்ன இருக்கு',
      'முன்னாடி என்ன இருக்கிறது',
      'முன்னாடி என்ன இருக்குது',
      'முன்னாடி என்ன',
      'முன்னாடி',
      'முன்னால் என்ன இருக்கிறது',
      'முன்னால் என்ன இருக்கு',
      'முன்னால் என்ன',
      'முன்னே என்ன இருக்கிறது',
      'முன்னே என்ன இருக்கு',
      'முன்னே என்ன',
      'எதிரே என்ன இருக்கிறது',
      'எதிரில் என்ன இருக்கு',
      'என்ன இருக்கு',
      'what is in front',
      'what is ahead',
      'what\'s in front',
      'what is ahead of me',
      'what is in front of me',
      'front',
      'ahead',
      'obstacles',
      'detect object',
      'detect objects',
      'scan around',
      'look around',
      'தடை',
      'பார்',
    ])) {
      return VoiceCommand.whatIsInFront;
    }
    if (_has(lower, [
      'time',
      'what time',
      'what time is it',
      'current time',
      'what is the time',
      'tell me the time',
      'நேரம்',
      'என்ன நேரம்',
      'மணி என்ன',
      'இப்போது மணி என்ன',
      'இப்போ மணி என்ன',
    ])) {
      return VoiceCommand.time;
    }
    if (_has(lower, ['front camera', 'selfie camera', 'front camera switch', 'rear camera', 'back camera', 'switch camera', 'camera', 'கேமரா'])) {
      return VoiceCommand.switchCamera;
    }
    if (_has(lower, ['change language', 'switch language', 'language to', 'english', 'tamil', 'sinhala', 'மொழி', 'தமிழ்', 'ஆங்கிலம்'])) {
      return VoiceCommand.changeLanguage;
    }
    if (_has(lower, ['add person', 'new person', 'save person', 'register person', 'நபரை சேர்'])) {
      return VoiceCommand.addPerson;
    }
    if (_has(lower, ['settings', 'setting', 'configure', 'options', 'preferences', 'config', 'அமைப்பு', 'அமைப்புகள்'])) {
      return VoiceCommand.openSettings;
    }
    if (_has(lower, ['people', 'persons', 'faces', 'contacts', 'manage', 'நபர்கள்', 'மனிதர்கள்'])) {
      return VoiceCommand.openPeople;
    }
    if (_has(lower, ['cancel', 'close', 'dismiss', 'stop listening', 'ரத்து'])) {
      return VoiceCommand.cancel;
    }
    if (_has(lower, ['go back', 'back', 'return', 'பின்னால்'])) {
      return VoiceCommand.goBack;
    }
    return VoiceCommand.unknown;
  }

  bool _has(String words, List<String> kw) => kw.any((k) => words.contains(k));

  void dispose() {
    _listening = false;
    SharedStt.instance.clearListeners();
    SharedStt.instance.stop();
  }
}
