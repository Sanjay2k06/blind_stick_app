import 'dart:async';
import 'package:flutter/foundation.dart';
import 'startup_audio_manager.dart';
import 'location_service.dart';
import 'reverse_geocoding_service.dart';
import 'tamil_location_formatter.dart';
import 'tamil_time_formatter.dart';
import 'startup_tts_manager.dart';

/// Explicit startup state machine states.
///
/// Flow:
/// APP_OPENING
/// → BGM_PLAYING
/// → WAITING_FOR_AUTO_START (15-second calm splash duration)
/// → BGM_STOPPING
/// → FETCHING_LOCATION
/// → LOCATION_RESOLVED
/// → ANNOUNCING_LOCATION
/// → ANNOUNCING_TIME
/// → STARTING_CAMERA
/// → STARTING_DETECTION
/// → NAVIGATION_ACTIVE
/// (or STARTUP_ERROR)
enum StartupState {
  appOpening,
  bgmPlaying,
  waitingForAutoStart,
  bgmStopping,
  fetchingLocation,
  locationResolved,
  announcingLocation,
  announcingTime,
  startingCamera,
  startingDetection,
  navigationActive,
  startupError;

  static const StartupState waitingForUserStart = StartupState.waitingForAutoStart;
}

class StartupFlowManager {
  static const Duration defaultStartupDuration = Duration(seconds: 15);
  final Duration startupDuration;

  final StartupAudioManager audioManager;
  final LocationService locationService;
  final ReverseGeocodingService geocodingService;
  final StartupTtsManager ttsManager;

  final Future<void> Function()? onStartCamera;
  final Future<void> Function()? onStartDetection;

  StartupState _state = StartupState.appOpening;
  final ValueNotifier<StartupState> stateNotifier =
      ValueNotifier<StartupState>(StartupState.appOpening);

  /// Seconds remaining in the 15-second startup countdown.
  final ValueNotifier<int> remainingSecondsNotifier = ValueNotifier<int>(15);

  bool _isStartingLock = false;
  bool _isStartupCompleted = false;
  bool _isPaused = false;
  Timer? _countdownTimer;
  int _secondsLeft = 15;

  StartupFlowManager({
    this.startupDuration = defaultStartupDuration,
    StartupAudioManager? audioManager,
    LocationService? locationService,
    ReverseGeocodingService? geocodingService,
    StartupTtsManager? ttsManager,
    this.onStartCamera,
    this.onStartDetection,
  })  : audioManager = audioManager ?? StartupAudioManager(),
        locationService = locationService ?? LocationService(),
        geocodingService = geocodingService ?? ReverseGeocodingService(),
        ttsManager = ttsManager ?? StartupTtsManager() {
    _secondsLeft = startupDuration.inSeconds;
    remainingSecondsNotifier.value = _secondsLeft;
  }

  StartupState get state => _state;
  bool get isNavigationActive => _state == StartupState.navigationActive;
  bool get isWaitingForAutoStart => _state == StartupState.waitingForAutoStart;
  bool get isWaitingForUserStart => isWaitingForAutoStart;
  bool get isError => _state == StartupState.startupError;
  bool get isLocked => _isStartingLock;
  bool get isStartupCompleted => _isStartupCompleted;

  void _setState(StartupState newState) {
    debugPrint('StartupFlowManager: Transition state [$_state] → [$newState]');
    _state = newState;
    stateNotifier.value = newState;
  }

  /// Called upon application launch:
  /// APP_OPENING → BGM_PLAYING → WAITING_FOR_AUTO_START
  /// Starts Sahara BGM at volume 0.20 and begins the 15-second countdown.
  Future<void> initialize({bool autoStart = true}) async {
    if (_isStartupCompleted || _isStartingLock) return;

    _setState(StartupState.appOpening);
    await audioManager.startBgm();
    _setState(StartupState.bgmPlaying);
    _setState(StartupState.waitingForAutoStart);

    if (autoStart) {
      _startAutoTimer();
    }
  }

  void _startAutoTimer() {
    _countdownTimer?.cancel();
    _secondsLeft = startupDuration.inSeconds;
    remainingSecondsNotifier.value = _secondsLeft;

    if (startupDuration <= Duration.zero) {
      unawaited(startSequence());
      return;
    }

    if (startupDuration < const Duration(seconds: 1)) {
      _countdownTimer = Timer(startupDuration, () {
        _secondsLeft = 0;
        remainingSecondsNotifier.value = 0;
        unawaited(startSequence());
      });
      return;
    }

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isPaused) return;

      _secondsLeft--;
      remainingSecondsNotifier.value = _secondsLeft;

      if (_secondsLeft <= 0) {
        timer.cancel();
        _countdownTimer = null;
        unawaited(startSequence());
      }
    });
  }

  /// Executes the strict sequential startup flow:
  /// 1. Immediately stops BGM
  /// 2. Fetches GPS location
  /// 3. Reverse geocodes coordinates to Tamil locality
  /// 4. Speaks natural Tamil location
  /// 5. Speaks current Tamil time
  /// 6. Speaks transition "வழிகாட்டுதல் தொடங்குகிறது."
  /// 7. Starts camera
  /// 8. Starts object detection & navigation engine
  /// 9. Sets navigation active
  Future<void> startSequence() async {
    if (_isStartingLock || _isStartupCompleted || _state == StartupState.navigationActive) {
      debugPrint('StartupFlowManager: Execution blocked by startup lock or already active');
      return;
    }

    _isStartingLock = true;
    _countdownTimer?.cancel();
    _countdownTimer = null;

    try {
      // 1. Immediately stop BGM
      _setState(StartupState.bgmStopping);
      await audioManager.stopBgm();

      // 2. Fetch GPS location
      _setState(StartupState.fetchingLocation);
      final position = await locationService.getCurrentLocation(maxRetries: 2);

      if (position == null) {
        debugPrint('StartupFlowManager: GPS acquisition failed');
        _setState(StartupState.startupError);
        await ttsManager.speakGpsError();
        _isStartingLock = false; // Allow user to tap retry ("மீண்டும் முயற்சிக்கவும்")
        return;
      }

      // 3. Reverse geocode location
      final geocoded = await geocodingService.reverseGeocode(
        position.latitude,
        position.longitude,
      );
      final locationSentence = TamilLocationFormatter.formatLocation(geocoded);
      _setState(StartupState.locationResolved);

      // 4. Announce natural location
      _setState(StartupState.announcingLocation);
      await ttsManager.speakLocation(locationSentence);

      // 5. Announce current local time
      _setState(StartupState.announcingTime);
      final timeSentence = TamilTimeFormatter.formatTime(DateTime.now());
      await ttsManager.speakTime(timeSentence);

      // 6. Short Tamil transition message
      await ttsManager.speakNavigationStarting();

      // 7. Initialize camera
      _setState(StartupState.startingCamera);
      if (onStartCamera != null) {
        await onStartCamera!();
      }

      // 8. Start object detection & navigation engine
      _setState(StartupState.startingDetection);
      if (onStartDetection != null) {
        await onStartDetection!();
      }

      // 9. Fully active navigation
      _isStartupCompleted = true;
      _setState(StartupState.navigationActive);
      debugPrint('StartupFlowManager: Navigation active!');
    } catch (e, st) {
      debugPrint('StartupFlowManager: Exception in startup sequence: $e\n$st');
      _setState(StartupState.startupError);
      _isStartingLock = false;
    }
  }

  /// Retry action when GPS acquisition fails.
  Future<void> retry() async {
    if (_isStartingLock || _isStartupCompleted) return;
    await startSequence();
  }

  /// App lifecycle: pause BGM if app goes to background during startup.
  Future<void> onAppPaused() async {
    _isPaused = true;
    if (_state == StartupState.bgmPlaying || _state == StartupState.waitingForAutoStart) {
      await audioManager.pauseBgm();
    }
  }

  /// App lifecycle: resume BGM if returning to foreground before sequence started.
  Future<void> onAppResumed() async {
    _isPaused = false;
    if (_state == StartupState.waitingForAutoStart && !_isStartupCompleted && !_isStartingLock) {
      await audioManager.resumeBgm();
    }
  }

  /// Dispose all resources.
  Future<void> dispose() async {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    await audioManager.dispose();
    await ttsManager.stop();
  }
}
