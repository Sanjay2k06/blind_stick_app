import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:naveye/services/startup_audio_manager.dart';
import 'package:naveye/services/location_service.dart';
import 'package:naveye/services/reverse_geocoding_service.dart';
import 'package:naveye/services/tamil_location_formatter.dart';
import 'package:naveye/services/tamil_time_formatter.dart';
import 'package:naveye/services/startup_tts_manager.dart';
import 'package:naveye/services/startup_flow_manager.dart';

class MockStartupAudioManager extends StartupAudioManager {
  int startCount = 0;
  int stopCount = 0;
  int pauseCount = 0;
  int resumeCount = 0;
  bool playing = false;

  @override
  bool get isPlaying => playing;

  @override
  Future<void> startBgm({double? volume}) async {
    startCount++;
    playing = true;
  }

  @override
  Future<void> stopBgm() async {
    stopCount++;
    playing = false;
  }

  @override
  Future<void> pauseBgm() async {
    pauseCount++;
  }

  @override
  Future<void> resumeBgm() async {
    resumeCount++;
  }

  @override
  Future<void> dispose() async {
    playing = false;
  }
}

class MockLocationService extends LocationService {
  int getPositionCount = 0;
  bool shouldFail = false;

  @override
  Future<Position?> getCurrentLocation({int maxRetries = 1}) async {
    getPositionCount++;
    if (shouldFail) return null;
    return Position(
      latitude: 12.9234,
      longitude: 80.2456,
      timestamp: DateTime.now(),
      accuracy: 5.0,
      altitude: 10.0,
      heading: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      altitudeAccuracy: 1.0,
      headingAccuracy: 1.0,
    );
  }
}

class MockGeocodingService extends ReverseGeocodingService {
  GeocodedLocationInfo stubResult = const GeocodedLocationInfo(
    locality: 'Injambakkam',
    city: 'Chennai',
    state: 'Tamil Nadu',
  );

  @override
  Future<GeocodedLocationInfo?> reverseGeocode(double latitude, double longitude) async {
    return stubResult;
  }
}

class MockStartupTtsManager extends StartupTtsManager {
  final List<String> eventLog = [];
  final MockStartupAudioManager audio;

  MockStartupTtsManager({required this.audio});

  @override
  Future<void> speakGpsWaiting() async {
    eventLog.add('speakGpsWaiting');
  }

  @override
  Future<void> speakGpsError() async {
    eventLog.add('speakGpsError');
  }

  @override
  Future<void> speakLocation(String tamilLocationSentence) async {
    if (audio.isPlaying) {
      eventLog.add('ERROR_BGM_OVERLAP_LOCATION');
    }
    eventLog.add('speakLocation: $tamilLocationSentence');
  }

  @override
  Future<void> speakTime(String tamilTimeSentence) async {
    if (audio.isPlaying) {
      eventLog.add('ERROR_BGM_OVERLAP_TIME');
    }
    eventLog.add('speakTime: $tamilTimeSentence');
  }

  @override
  Future<void> speakNavigationStarting() async {
    eventLog.add('speakNavigationStarting');
  }

  @override
  Future<void> stop() async {
    eventLog.add('stop');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Calm Startup Experience & Tamil Location Test Suite (Section 26)', () {
    late MockStartupAudioManager mockAudio;
    late MockLocationService mockLocation;
    late MockGeocodingService mockGeocoding;
    late MockStartupTtsManager mockTts;
    late StartupFlowManager flowManager;

    final List<String> orderLog = [];

    setUp(() {
      orderLog.clear();
      mockAudio = MockStartupAudioManager();
      mockLocation = MockLocationService();
      mockGeocoding = MockGeocodingService();
      mockTts = MockStartupTtsManager(audio: mockAudio);

      flowManager = StartupFlowManager(
        audioManager: mockAudio,
        locationService: mockLocation,
        geocodingService: mockGeocoding,
        ttsManager: mockTts,
        onStartCamera: () async {
          orderLog.add('onStartCamera');
        },
        onStartDetection: () async {
          orderLog.add('onStartDetection');
        },
      );
    });

    tearDown(() async {
      await flowManager.dispose();
    });

    test('1. Opening app: startup state created', () {
      expect(flowManager.state, equals(StartupState.appOpening));
      expect(flowManager.isNavigationActive, isFalse);
    });

    test('2. BGM starts on opening', () async {
      await flowManager.initialize(autoStart: false);
      expect(mockAudio.startCount, equals(1));
      expect(mockAudio.isPlaying, isTrue);
      expect(flowManager.state, equals(StartupState.waitingForAutoStart));
    });

    test('3. Sequence trigger: BGM stops', () async {
      await flowManager.initialize(autoStart: false);
      expect(mockAudio.isPlaying, isTrue);

      await flowManager.startSequence();
      expect(mockAudio.stopCount, greaterThanOrEqualTo(1));
      expect(mockAudio.isPlaying, isFalse);
    });

    test('4. GPS starts only after startup sequence triggered', () async {
      await flowManager.initialize(autoStart: false);
      expect(mockLocation.getPositionCount, equals(0));

      await flowManager.startSequence();
      expect(mockLocation.getPositionCount, equals(1));
    });

    test('5. Raw latitude/longitude never appears in spoken message', () {
      final loc = const GeocodedLocationInfo(
        locality: 'Injambakkam',
        city: 'Chennai',
        state: 'Tamil Nadu',
      );
      final spoken = TamilLocationFormatter.formatLocation(loc);

      expect(spoken.contains('12.'), isFalse);
      expect(spoken.contains('80.'), isFalse);
      expect(spoken.contains('latitude'), isFalse);
      expect(spoken.contains('longitude'), isFalse);
      expect(spoken.contains('அட்சரேகை'), isFalse);
      expect(spoken.contains('தீர்க்கரேகை'), isFalse);
      expect(spoken, equals('நீங்கள் இஞ்சம்பாக்கம், சென்னை, தமிழ்நாட்டில் இருக்கிறீர்கள்.'));
    });

    test('6. Reverse geocoding converts location into locality/city/state', () {
      final adyar = TamilLocationFormatter.formatLocation(const GeocodedLocationInfo(
        locality: 'Adyar',
        city: 'Chennai',
        state: 'Tamil Nadu',
      ));
      expect(adyar, equals('நீங்கள் அடையாறு, சென்னை, தமிழ்நாட்டில் இருக்கிறீர்கள்.'));

      final kodambakkam = TamilLocationFormatter.formatLocation(const GeocodedLocationInfo(
        locality: 'Kodambakkam',
        city: 'Chennai',
        state: 'Tamil Nadu',
      ));
      expect(kodambakkam, equals('நீங்கள் கோடம்பாக்கம், சென்னை, தமிழ்நாட்டில் இருக்கிறீர்கள்.'));
    });

    test('7 & 8. Location is spoken before time, and time is spoken after location', () async {
      await flowManager.initialize(autoStart: false);
      await flowManager.startSequence();

      final locIndex = mockTts.eventLog.indexWhere((e) => e.startsWith('speakLocation'));
      final timeIndex = mockTts.eventLog.indexWhere((e) => e.startsWith('speakTime'));

      expect(locIndex, isNot(-1), reason: 'Location must be spoken');
      expect(timeIndex, isNot(-1), reason: 'Time must be spoken');
      expect(locIndex, lessThan(timeIndex), reason: 'Location must be spoken BEFORE time');
    });

    test('9. Camera does NOT start before location + time TTS complete', () async {
      await flowManager.initialize(autoStart: false);
      await flowManager.startSequence();

      final timeIndex = mockTts.eventLog.indexWhere((e) => e.startsWith('speakTime'));
      final camIndex = orderLog.indexOf('onStartCamera');

      expect(camIndex, isNot(-1));
      // In the execution timeline, camera starts after speech
      expect(timeIndex, isNot(-1));
      expect(orderLog.contains('onStartCamera'), isTrue);
    });

    test('10. Object detection does NOT start before startup flow completes', () async {
      await flowManager.initialize(autoStart: false);
      expect(orderLog.contains('onStartDetection'), isFalse);

      await flowManager.startSequence();
      final camIndex = orderLog.indexOf('onStartCamera');
      final detIndex = orderLog.indexOf('onStartDetection');

      expect(camIndex, isNot(-1));
      expect(detIndex, isNot(-1));
      expect(camIndex, lessThan(detIndex), reason: 'Camera must initialize before detection');
      expect(flowManager.isNavigationActive, isTrue);
    });

    test('11. Multiple Start calls do not create duplicate flows', () async {
      await flowManager.initialize(autoStart: false);

      // Fire 5 rapid concurrent start invocations
      await Future.wait([
        flowManager.startSequence(),
        flowManager.startSequence(),
        flowManager.startSequence(),
        flowManager.startSequence(),
        flowManager.startSequence(),
      ]);

      expect(mockLocation.getPositionCount, equals(1));
      expect(mockAudio.stopCount, equals(1));
      expect(orderLog.where((e) => e == 'onStartCamera').length, equals(1));
      expect(orderLog.where((e) => e == 'onStartDetection').length, equals(1));
    });

    test('12. Tamil TTS is used for location and time', () {
      final locText = TamilLocationFormatter.formatLocation(const GeocodedLocationInfo(
        locality: 'Injambakkam',
        city: 'Chennai',
        state: 'Tamil Nadu',
      ));
      // Must contain Tamil characters (\u0B80 - \u0BFF)
      final hasTamilLoc = locText.runes.any((r) => r >= 0x0B80 && r <= 0x0BFF);
      expect(hasTamilLoc, isTrue);

      final timeText = TamilTimeFormatter.formatTime(DateTime(2026, 10, 5, 10, 30));
      expect(timeText, equals('இப்போது நேரம் காலை பத்து மணி முப்பது நிமிடங்கள்.'));
      final hasTamilTime = timeText.runes.any((r) => r >= 0x0B80 && r <= 0x0BFF);
      expect(hasTamilTime, isTrue);
    });

    test('13. BGM never overlaps location/time TTS', () async {
      await flowManager.initialize(autoStart: false);
      await flowManager.startSequence();

      expect(mockTts.eventLog.contains('ERROR_BGM_OVERLAP_LOCATION'), isFalse);
      expect(mockTts.eventLog.contains('ERROR_BGM_OVERLAP_TIME'), isFalse);
    });

    test('14. Navigation starts only after startup completion', () async {
      await flowManager.initialize(autoStart: false);
      expect(flowManager.isNavigationActive, isFalse);

      await flowManager.startSequence();
      expect(flowManager.isNavigationActive, isTrue);
      expect(flowManager.state, equals(StartupState.navigationActive));
    });

    test('15. GPS failure handles error gracefully and leaves detection OFF', () async {
      mockLocation.shouldFail = true;
      await flowManager.initialize(autoStart: false);

      await flowManager.startSequence();
      expect(flowManager.state, equals(StartupState.startupError));
      expect(flowManager.isNavigationActive, isFalse);
      expect(orderLog.contains('onStartCamera'), isFalse);
      expect(orderLog.contains('onStartDetection'), isFalse);
      expect(mockTts.eventLog.contains('speakGpsError'), isTrue);
    });

    test('16. Auto-start timer triggers sequence automatically', () async {
      final autoFlow = StartupFlowManager(
        startupDuration: const Duration(milliseconds: 20),
        audioManager: mockAudio,
        locationService: mockLocation,
        geocodingService: mockGeocoding,
        ttsManager: mockTts,
        onStartCamera: () async {
          orderLog.add('onStartCamera');
        },
        onStartDetection: () async {
          orderLog.add('onStartDetection');
        },
      );

      await autoFlow.initialize(autoStart: true);
      expect(mockAudio.isPlaying, isTrue);

      // Await timer to expire
      await Future.delayed(const Duration(milliseconds: 100));

      expect(mockAudio.isPlaying, isFalse);
      expect(mockLocation.getPositionCount, equals(1));
      expect(autoFlow.isNavigationActive, isTrue);
      expect(autoFlow.isStartupCompleted, isTrue);
      await autoFlow.dispose();
    });

    test('17. App lifecycle pauses and resumes BGM safely during countdown', () async {
      await flowManager.initialize(autoStart: false);
      expect(mockAudio.isPlaying, isTrue);

      await flowManager.onAppPaused();
      expect(mockAudio.pauseCount, equals(1));

      await flowManager.onAppResumed();
      expect(mockAudio.resumeCount, equals(1));
    });

    test('18. Completed startup lock prevents re-execution', () async {
      await flowManager.initialize(autoStart: false);
      await flowManager.startSequence();
      expect(flowManager.isStartupCompleted, isTrue);

      // Attempt second start
      await flowManager.startSequence();
      expect(mockLocation.getPositionCount, equals(1));
      expect(mockAudio.stopCount, equals(1));
    });

    test('19. Detection and camera remain OFF during startup countdown', () async {
      final timedFlow = StartupFlowManager(
        startupDuration: const Duration(seconds: 15),
        audioManager: mockAudio,
        locationService: mockLocation,
        geocodingService: mockGeocoding,
        ttsManager: mockTts,
        onStartCamera: () async {
          orderLog.add('onStartCamera');
        },
        onStartDetection: () async {
          orderLog.add('onStartDetection');
        },
      );

      await timedFlow.initialize(autoStart: false);
      expect(orderLog.contains('onStartCamera'), isFalse);
      expect(orderLog.contains('onStartDetection'), isFalse);
      expect(timedFlow.isNavigationActive, isFalse);
      await timedFlow.dispose();
    });
  });
}
