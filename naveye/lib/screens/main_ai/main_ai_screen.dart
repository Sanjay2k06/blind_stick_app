import 'dart:async' show Timer, unawaited;
import 'dart:io';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_routes.dart';
import '../../services/detector_service.dart';
import '../../services/tts_service.dart';
import '../../services/face_recognition_service.dart';
import '../../services/voice_command_service.dart';
import '../../services/shared_stt.dart';
import '../../services/nav_eye_foreground_service.dart';
import '../../services/system_monitor_service.dart';
import '../../services/detection_stabilizer.dart';
import '../../services/navigation_decision_engine.dart';
import '../../services/voice_alert_manager.dart';
import '../../services/currency_recognition_service.dart';
import '../../services/ocr_service.dart';
import '../../services/object_finder_service.dart';
import '../../services/emergency_sos_service.dart';
import '../../services/startup_flow_manager.dart';
import '../startup/calm_startup_overlay.dart';

String formatLocationSummary(double latitude, double longitude, {bool isTamil = true}) {
  if (isTamil) {
    return 'உங்கள் இருப்பிடம் அட்சரேகை ${latitude.toStringAsFixed(3)}, தீர்க்கரேகை ${longitude.toStringAsFixed(3)}.';
  }
  return 'Your location is latitude ${latitude.toStringAsFixed(3)} and longitude ${longitude.toStringAsFixed(3)}.';
}

// ── Fix 1: Top-level YUV→RGB — runs in a background isolate via compute() ───
// Must be top-level (not a method) so Dart can spawn it in a separate isolate.
Map<String, dynamic>? _yuvToRgb(Map<String, dynamic> a) {
  try {
    final yB = a['y'] as Uint8List, uB = a['u'] as Uint8List,
          vB = a['v'] as Uint8List;
    final w = a['w'] as int, h = a['h'] as int;
    final yBpr = a['yBpr'] as int, uBpr = a['uBpr'] as int,
          uBpp = a['uBpp'] as int, rot = a['rot'] as int;

    final rgb = Uint8List(w * h * 3);
    int i = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final yv = yB[y * yBpr + x];
        final idx = (y ~/ 2) * uBpr + (x ~/ 2) * uBpp;
        // BUG-37 FIX: bounds check — some Android cameras use non-standard
        // plane strides (e.g. semi-planar NV12/NV21) where idx can exceed the
        // U/V buffer length. Skip silently rather than crash.
        if (idx >= uB.length || idx >= vB.length) { i += 3; continue; }
        final u = uB[idx], v = vB[idx];
        rgb[i++] = (yv + 1.370705 * (v - 128)).clamp(0, 255).toInt();
        rgb[i++] = (yv - 0.337633 * (u - 128) - 0.698001 * (v-128)).clamp(0,255).toInt();
        rgb[i++] = (yv + 1.732446 * (u - 128)).clamp(0, 255).toInt();
      }
    }

    int outW = w, outH = h;
    Uint8List out = rgb;
    if (rot == 90 || rot == 270) {
      final r = Uint8List(w * h * 3);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final s = (y * w + x) * 3;
          final d = rot == 90 ? (x * h + (h - 1 - y)) * 3
                              : ((w - 1 - x) * h + y) * 3;
          r[d] = rgb[s]; r[d+1] = rgb[s+1]; r[d+2] = rgb[s+2];
        }
      }
      outW = h; outH = w; out = r;
    } else if (rot == 180) {
      final r = Uint8List(w * h * 3);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final s = (y * w + x) * 3;
          final d = ((h-1-y) * w + (w-1-x)) * 3;
          r[d] = rgb[s]; r[d+1] = rgb[s+1]; r[d+2] = rgb[s+2];
        }
      }
      out = r;
    }
    return {'bytes': out, 'w': outW, 'h': outH};
  } catch (_) { return null; }
}

class MainAIScreen extends StatefulWidget {
  const MainAIScreen({super.key});
  @override
  State<MainAIScreen> createState() => _MainAIScreenState();
}

class _MainAIScreenState extends State<MainAIScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {

  // ── Camera ────────────────────────────────────────────────────────────────
  CameraController? _cam;
  List<CameraDescription> _cameras = [];
  int _sensorOrientation = 0;
  bool _cameraReady      = false;

  // ── State ─────────────────────────────────────────────────────────────────
  bool _isDetecting   = false;
  bool _isStreaming    = false;
  bool _modelReady    = false;
  bool _voiceActive   = false;

  String _statusText  = 'Initializing...';
  String _detLabel    = '';
  String _direction   = 'CENTRE';
  String _distance    = '';
  double _distanceM   = 100.0;
  NavigationState _currentNavState = NavigationState.clear;
  NavigationAction _currentNavAction = NavigationAction.clear;

  bool _torchActive = false;
  bool _finderModeActive = false;
  final List<DateTime> _recentTapTimestamps = [];

  void _recordTapAndCheckSos() {
    final now = DateTime.now();
    _recentTapTimestamps.add(now);
    _recentTapTimestamps.removeWhere((t) => now.difference(t).inMilliseconds > 1200);
    if (_recentTapTimestamps.length >= 3) {
      _recentTapTimestamps.clear();
      _handleCmd(VoiceCommand.emergencySOS);
    }
  }

  bool get _isStopAction =>
      _currentNavAction == NavigationAction.stop ||
      _distanceM < 1.2 ||
      _currentNavState == NavigationState.criticalStop ||
      _currentNavState == NavigationState.knownPersonVeryClose;

  String get _navigationStatusHeader {
    if (_currentNavState == NavigationState.clear || _currentNavAction == NavigationAction.clear) {
      return 'முன்னால் பாதை தெளிவாக உள்ளது';
    }
    if (_isStopAction) {
      return 'முன்னால் தடை உள்ளது';
    }
    if (_currentNavState == NavigationState.obstacleLeft) {
      return 'இடப்பக்கம் தடையுள்ளது';
    }
    if (_currentNavState == NavigationState.obstacleRight) {
      return 'வலப்பக்கம் தடையுள்ளது';
    }
    if (_currentNavState == NavigationState.knownPersonLeft) {
      return 'லோகி இடப்பக்கத்தில் உள்ளார்';
    }
    if (_currentNavState == NavigationState.knownPersonRight) {
      return 'லோகி வலப்பக்கத்தில் உள்ளார்';
    }
    if (_currentNavState == NavigationState.knownPersonCenter) {
      return 'லோகி முன்னால் உள்ளார்';
    }
    return 'முன்னால் தடை உள்ளது';
  }

  String get _navigationActionDirective {
    if (_isStopAction) {
      return 'நிறுத்தவும்';
    }
    if (_currentNavAction == NavigationAction.goLeft) {
      return 'இடப்பக்கம் செல்லவும்';
    }
    if (_currentNavAction == NavigationAction.goRight) {
      return 'வலப்பக்கம் செல்லவும்';
    }
    return 'செல்லலாம்';
  }

  IconData get _navigationActionIcon {
    if (_isStopAction) {
      return Icons.pan_tool;
    }
    if (_currentNavAction == NavigationAction.goLeft) {
      return Icons.arrow_back;
    }
    if (_currentNavAction == NavigationAction.goRight) {
      return Icons.arrow_forward;
    }
    return Icons.arrow_upward;
  }

  // ── Services ──────────────────────────────────────────────────────────────
  final DetectorService     _detector = DetectorService();
  final TtsService          _tts      = TtsService();
  final VoiceCommandService _voice    = VoiceCommandService();
  final DetectionStabilizer _stabilizer = DetectionStabilizer(
    stabilityThresholdMs: 350,
    confidenceThreshold: 0.50,
  );
  final NavigationDecisionEngine _decisionEngine = NavigationDecisionEngine();
  late final VoiceAlertManager _voiceAlert;
  bool _debugModeEnabled = false;
  SystemMonitorService?     _monitor;   // battery + connectivity alerts
  bool _serviceActive = false;          // true when foreground service is running

  // ── Timing / throttle ─────────────────────────────────────────────────────
  DateTime   _lastDetection      = DateTime.now();
  String     _lastAnnouncement   = '';
  bool       _vibrationEnabled   = true;
  bool       _busy               = false;              // prevents frame queue buildup

  // ── Fix 11: low-light tracking ───────────────────────────────────────────
  DateTime _lastDarkCheck  = DateTime.fromMillisecondsSinceEpoch(0);

  // ── Last camera frame snapshot ───────────────────────────────────────────
  img.Image?      _lastFrame;


  // ── Bounding box overlay ──────────────────────────────────────────────────
  DetectionResult? _topResult;   // carries box coords for the painter

  // ── Camera init guard — prevents concurrent double-initialisation ─────────
  bool _cameraInitializing   = false;
  bool _cameraPermDenied     = false; // true when user denied camera permission

  // ── Voice timeout ─────────────────────────────────────────────────────────
  Timer? _voiceTimeout;

  // ── Pulse animation ───────────────────────────────────────────────────────
  late AnimationController _pulse;
  late Animation<double>   _pulseAnim;
  late final StartupFlowManager _startupFlowManager;

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.5, end: 1.0)
        .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

    _startupFlowManager = StartupFlowManager(
      onStartCamera: () async {
        await _initCamera();
      },
      onStartDetection: () async {
        if (!_modelReady) {
          await Future.wait([
            _detector.loadModel(),
            _detector.refreshSensitivity(),
            FaceRecognitionService.instance.init(),
          ]);
          if (mounted) {
            setState(() => _modelReady = _detector.isLoaded);
          }
        }
        if (mounted) {
          await _startDetectionSilent();
        }
      },
    );

    _init();
  }

  Future<void> _init() async {
    // ── Preload lightweight services (TTS, background monitor, preferences) ──
    await _tts.init();
    _voiceAlert = VoiceAlertManager(tts: _tts);
    _monitor = SystemMonitorService(_tts);
    unawaited(_monitor!.start().catchError(
        (e) => debugPrint('SystemMonitor start error: $e')));
    final prefs = await SharedPreferences.getInstance();
    _vibrationEnabled = prefs.getBool('vibration') ?? true;

    if (mounted) {
      setState(() {
        _statusText = 'வழிகாட்டுதல் தயாராகிறது...';
      });
    }

    // Initialize Calm Startup Flow: starts Sahara BGM at volume 0.20 and starts 15-second auto-timer
    await _startupFlowManager.initialize();
  }

  Future<void> _initCamera() async {
    // Guard: skip if already initializing to prevent concurrent double-init
    if (_cameraInitializing) return;
    _cameraInitializing = true;
    try {
      // ── Speak before the system permission dialog appears ─────────────────
      // Blind users can't see the dialog; announce so they know to tap Allow.
      final camStatus0 = await Permission.camera.status;
      if (!camStatus0.isGranted) {
        await _tts.speak(
          'கேமரா அனுமதி தேவை. அனுமதி பொத்தானை அழுத்தவும்.');
        await Future.delayed(const Duration(milliseconds: 900));
      }
      // ── Request camera permission before anything else ────────────────────
      final camStatus = await Permission.camera.request();
      if (!camStatus.isGranted) {
        debugPrint('Camera permission denied: $camStatus');
        if (mounted) {
          setState(() {
            _cameraPermDenied = true;
            _statusText = 'கேமரா அனுமதி தேவை';
          });
          await _tts.speakNow(
            'கேமரா அனுமதி மறுக்கப்பட்டது. அமைப்புகளில் கேமரா அனுமதியை இயக்கவும்.');
        }
        return;
      }
      if (mounted) setState(() => _cameraPermDenied = false);

      // Dispose existing controller first if any
      if (_cam != null) {
        if (_isStreaming) {
          try { _cam!.stopImageStream(); } catch (_) {}
          _isStreaming = false;
        }
        try { _cam!.dispose(); } catch (_) {}
        _cam = null;
        if (mounted) setState(() => _cameraReady = false);
      }
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;
      final cam = _cameras.first;
      _sensorOrientation = cam.sensorOrientation;
      // ResolutionPreset.medium (720×480) — good preview quality on screen and
      // enough detail for face recognition at 1–3 m. The stream is only active
      // during detection (stopped on toggle-off) so idle GC pressure is zero.
      _cam = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _cam!.initialize();
      if (mounted) setState(() => _cameraReady = true);

      // Only pre-start the stream if detection is already active (e.g. on
      // lifecycle resume while detecting). On first launch, detection hasn't
      // started yet — starting the stream here just burns GC with idle frames.
      if (_isDetecting) {
        try {
          await _cam!.startImageStream(_processFrame);
          _isStreaming = true;
          debugPrint('Camera: stream pre-started (detection was active)');
        } catch (e) {
          debugPrint('Camera: startImageStream during init failed: $e');
        }
      } else {
        debugPrint('Camera: stream deferred until detection starts');
      }
    } catch (e) {
      debugPrint('Camera init error: $e');
    } finally {
      _cameraInitializing = false;
    }
  }

  // ── Toggle detection ──────────────────────────────────────────────────────
  Future<void> _toggleDetection() async {
    if (!_cameraReady || !_modelReady || _cam == null) return;
    HapticFeedback.mediumImpact();

    if (_isDetecting) {
      // — STOP (Section 16: வழிகாட்டுதல் நிறுத்தப்பட்டது.) —
      setState(() {
        _isDetecting = false;
        _statusText  = 'வழிகாட்டுதல் தொடங்க தட்டவும்';
        _detLabel    = '';
        _distance    = '';
        _distanceM   = 100.0;
        _topResult   = null;
        _currentNavState = NavigationState.clear;
        _currentNavAction = NavigationAction.clear;
      });
      _stabilizer.reset();
      _decisionEngine.reset();
      _voiceAlert.reset();
      _lastFrame           = null;
      _lastAnnouncement    = '';
      _detector.resetConfirmation(); // clear confirmation counters on stop
      await _stopStream(); // stop stream to eliminate idle GC frame-buffer churn
      await NavEyeForegroundService.stop();
      if (mounted) setState(() => _serviceActive = false);
      await _voiceAlert.speakStop();
    } else {
      // — START (Section 16: வழிகாட்டுதல் தொடங்கப்பட்டது. முன்னால் செல்லலாம்.) —
      _stabilizer.reset();
      _decisionEngine.reset();
      _voiceAlert.reset();
      setState(() {
        _isDetecting = true;
        _statusText  = 'வழிகாட்டுதல் செயலில் உள்ளது';
        _detLabel    = '';
        _currentNavState = NavigationState.clear;
        _currentNavAction = NavigationAction.clear;
      });
      await NavEyeForegroundService.start();
      if (mounted) setState(() => _serviceActive = true);
      await _voiceAlert.speakStartup();
      await _startStream();
    }
  }

  Future<void> _startStream() async {
    if (_isStreaming || _cam == null) return;
    try {
      await _cam!.startImageStream(_processFrame);
      _isStreaming = true;
    } catch (e) {
      debugPrint('startImageStream error: $e');
      _isStreaming = false;
      if (mounted) {
        setState(() {
          _isDetecting = false;
          _statusText  = 'Camera error — tap to retry';
        });
      }
    }
  }

  Future<void> _stopStream() async {
    if (!_isStreaming || _cam == null) return;
    try { await _cam!.stopImageStream(); } catch (_) {}
    _isStreaming = false;
  }

  // Fix 5: start detection without playing TTS (used for auto-start on launch)
  Future<void> _startDetectionSilent() async {
    if (!_cameraReady || !_modelReady || _cam == null || _isDetecting) return;
    if (mounted) {
      setState(() {
        _isDetecting = true;
        _statusText  = 'வழிகாட்டுதல் செயலில் உள்ளது';
        _detLabel    = '';
        _currentNavState = NavigationState.clear;
        _currentNavAction = NavigationAction.clear;
      });
    }
    await NavEyeForegroundService.start();
    if (mounted) setState(() => _serviceActive = true);
    // Stream was started during _initCamera (single-configure optimisation).
    // If for any reason it isn't running yet, start it now.
    if (!_isStreaming) await _startStream();
  }

  Future<void> _processFrame(CameraImage frame) async {
    // Drop frames if not detecting or model not ready yet — stream stays warm
    if (!_isDetecting || !_modelReady) return;
    if (_busy) return;
    final now = DateTime.now();
    // Allow frames to stream at ~5 FPS (every 200 ms) so temporal stabilizer works smoothly
    if (now.difference(_lastDetection).inMilliseconds < 200) return;
    _lastDetection = now;
    _busy = true;

    try {
      // YUV conversion off the UI thread
      final raw = await compute(_yuvToRgb, {
        'y': Uint8List.fromList(frame.planes[0].bytes),
        'u': Uint8List.fromList(frame.planes[1].bytes),
        'v': Uint8List.fromList(frame.planes[2].bytes),
        'w': frame.width,   'h': frame.height,
        'yBpr': frame.planes[0].bytesPerRow,
        'uBpr': frame.planes[1].bytesPerRow,
        'uBpp': frame.planes[1].bytesPerPixel ?? 2,
        'rot':  _sensorOrientation,
      });
      if (raw == null || !mounted) return;
      final image = img.Image.fromBytes(
        width:  raw['w'] as int,
        height: raw['h'] as int,
        bytes:  (raw['bytes'] as Uint8List).buffer,
        format: img.Format.uint8,
        numChannels: 3,
      );
      _lastFrame = image;

      // Low-light check (sample centre pixels)
      if (now.difference(_lastDarkCheck).inSeconds >= 5) {
        _lastDarkCheck = now;
        final cx = image.width ~/ 2, cy = image.height ~/ 2;
        int brightness = 0, cnt = 0;
        for (int y = cy - 60; y < cy + 60; y += 6) {
          for (int x = cx - 60; x < cx + 60; x += 6) {
            if (y < 0 || y >= image.height || x < 0 || x >= image.width) continue;
            final p = image.getPixel(x, y);
            brightness += ((p.r + p.g + p.b) ~/ 3);
            cnt++;
          }
        }
        final avg = cnt > 0 ? brightness ~/ cnt : 255;
        if (avg < 38) {
          if (!_torchActive) {
            _torchActive = true;
            try {
              await _cam?.setFlashMode(FlashMode.torch);
              await _voiceAlert.speakDirective(
                  'வெளிச்சம் குறைவாக உள்ளது. டார்ச் ஆன் செய்யப்பட்டது.');
            } catch (e) {
              debugPrint('Auto-torch error: $e');
            }
          }
        } else if (avg >= 60 && _torchActive) {
          _torchActive = false;
          try {
            await _cam?.setFlashMode(FlashMode.off);
            await _voiceAlert.speakDirective(
                'வெளிச்சம் போதுமானது. டார்ச் அணைக்கப்பட்டது.');
          } catch (e) {
            debugPrint('Auto-torch off error: $e');
          }
        }
      }

      final results = await _detector.detect(image);
      if (!mounted) return;

      // ── Object Finder Mode Evaluation ───────────────────────────────────────
      if (_finderModeActive) {
        final feedback = ObjectFinderService.instance.evaluateDetections(results, now);
        if (feedback != null) {
          await _voiceAlert.speakDirective(feedback.spokenTextTa);
          if (feedback.isReachable) {
            HapticFeedback.heavyImpact();
          } else {
            HapticFeedback.mediumImpact();
          }
        }
      }

      // ── Step 1: Temporal Detection Stabilizer ─────────────────────────────
      final stabilizedObjects = _stabilizer.processFrame(results, timestamp: now);

      // ── Continuous Clear-Path Guidance & Heartbeat (Sections 2 & 13) ────────
      if (results.isEmpty || stabilizedObjects.isEmpty) {
        final clearAlert = _decisionEngine.evaluate([], timestamp: now);
        if (clearAlert != null) {
          if (mounted) {
            setState(() {
              _detLabel   = 'முன்னால் பாதை தெளிவாக உள்ளது';
              _direction  = 'முன்னால்';
              _distance   = 'தெளிவு';
              _distanceM  = 100.0;
              _topResult  = null;
              _currentNavState = NavigationState.clear;
              _currentNavAction = NavigationAction.clear;
            });
          }
          await _voiceAlert.processAlert(clearAlert, timestamp: now);
          _lastAnnouncement = clearAlert.spokenTextTa;
          if (_serviceActive) unawaited(NavEyeForegroundService.clearDetection());
        }
        return;
      }

      // ── Step 2: Face recognition enhancement for stabilized persons ───────
      final processedObjects = <StabilizedObject>[];
      for (final obj in stabilizedObjects) {
        if (obj.rawLabel == 'person') {
          final match = await FaceRecognitionService.instance.recogniseInFrame(
            image,
            pxMin: obj.xMin, pyMin: obj.yMin,
            pxMax: obj.xMax, pyMax: obj.yMax,
          );
          if (match != null && match.isConfirmed) {
            processedObjects.add(obj.copyWith(
              rawLabel: 'person_${match.name}',
              label: match.name,
              xCenter: match.faceCenterXRatio,
            ));
          } else {
            // Unconfirmed or unknown person
            processedObjects.add(obj);
          }
        } else {
          processedObjects.add(obj);
        }
      }

      // ── Step 3: Navigation Decision Engine (Spatial reasoning & priority) ─
      final navAlert = _decisionEngine.evaluate(processedObjects, timestamp: now);

      // Find best matching DetectionResult for bounding box painting
      DetectionResult? topMatch;
      if (navAlert != null) {
        for (final r in results) {
          if (r.rawLabel == navAlert.rawLabel || (navAlert.rawLabel.startsWith('person_') && r.rawLabel == 'person')) {
            topMatch = r;
            break;
          }
        }
      }
      topMatch ??= results.isNotEmpty ? results.first : null;

      if (mounted) {
        setState(() {
          if (navAlert != null) {
            _detLabel  = navAlert.label;
            _direction = navAlert.direction.displayName;
            _distance  = navAlert.proximity.displayName;
            _distanceM = navAlert.distanceM;
            _topResult = topMatch;
            _currentNavState = navAlert.navState;
            _currentNavAction = navAlert.action;
          }
        });
      }

      // ── Step 4: Centralized Voice Alert Manager (Cooldown & Priority Queue)
      await _voiceAlert.processAlert(navAlert, timestamp: now);

      if (navAlert != null) {
        _lastAnnouncement = navAlert.spokenTextTa;
        if (_serviceActive) {
          unawaited(NavEyeForegroundService.update(
            label: _detLabel,
            distance: navAlert.proximity.displayName,
          ));
        }

        // Haptic feedback
        if (_vibrationEnabled && await Vibration.hasVibrator() == true) {
          if (navAlert.priority == AlertPriority.criticalObstacle) {
            Vibration.vibrate(pattern: [0, 250, 100, 250, 100, 250]);
          } else if (navAlert.rawLabel == 'person') {
            Vibration.vibrate(pattern: [0, 80, 120, 80]);
          } else if (navAlert.distanceM < 1.2) {
            Vibration.vibrate(pattern: [0, 150, 80, 150]);
          } else {
            Vibration.vibrate(duration: 80);
          }
        }
      }
    } catch (e) {
      debugPrint('Frame error: $e');
    } finally {
      _busy = false;
    }
  }

  // ── Voice commands ────────────────────────────────────────────────────────
  void _resetVoiceState() {
    _voiceTimeout?.cancel();
    _voiceTimeout = null;
    _voice.stopListening(); // stop mic if still open
    _tts.unmute();
    if (mounted) setState(() => _voiceActive = false);
  }

  Future<void> _startVoiceListen() async {
    // Always cancel any pending timeout first to avoid a race where the old
    // timer fires during the new listen session and resets voice state.
    _voiceTimeout?.cancel();
    _voiceTimeout = null;

    // Tap again while active → cancel (toggle off)
    if (_voiceActive) {
      _resetVoiceState();
      await _tts.speakNow('ரத்து செய்யப்பட்டது.');
      return;
    }

    await _tts.stop();
    HapticFeedback.heavyImpact();
    setState(() => _voiceActive = true);

    // ── Audio confirmation ────────────────────────────────────────────────────
    await _tts.speakNow('கேட்கிறது — தொடங்கு, நிறுத்து, அல்லது உதவி எனச் சொல்லுங்கள்');
    await Future.delayed(const Duration(milliseconds: 1300));

    _tts.mute(); // mute obstacle TTS while mic is active

    // Safety: auto-cancel after 12 s if no command received
    _voiceTimeout?.cancel();
    _voiceTimeout = Timer(const Duration(seconds: 12), () {
      _resetVoiceState();
      _tts.speakNow('கட்டளை எதுவும் கேட்கவில்லை.');
    });

    if (!_voiceActive) return; // was cancelled during the delay

    await _voice.startListening((cmd) async {
      _resetVoiceState();
      // Audio feedback on result
      if (cmd != VoiceCommand.unknown) {
        await _tts.speakNow('புரிந்தது.');
      } else {
        await _tts.speakNow('மன்னிக்கவும், சரியாகக் கேட்கவில்லை. மீண்டும் சொல்லவும்.');
      }
      await _handleCmd(cmd);
    });
  }

  Future<void> _handleCmd(VoiceCommand cmd) async {
    switch (cmd) {
      case VoiceCommand.start:
        if (!_isDetecting) await _toggleDetection();
        break;
      case VoiceCommand.stop:
        if (_finderModeActive) {
          _finderModeActive = false;
          ObjectFinderService.instance.cancel();
          await _tts.speakNow('பொருள் தேடுதல் நிறுத்தப்பட்டது.');
        }
        if (_isDetecting) await _toggleDetection();
        break;
      case VoiceCommand.repeat:
        await _tts.speakNow(
          _lastAnnouncement.isNotEmpty ? _lastAnnouncement : 'மீண்டும் சொல்ல எதுவும் இல்லை.');
        break;
      case VoiceCommand.whoIsThis:
        await _tts.speakNow('முன்னால் யார் இருக்கிறார் என்று பார்க்கிறேன்.');

        img.Image? checkFrame = _lastFrame;

        // Fix 6: if detection is stopped, take a single snapshot
        if (checkFrame == null && _cam != null && _cameraReady && !_isStreaming) {
          try {
            final xFile = await _cam!.takePicture();
            final bytes = await File(xFile.path).readAsBytes();
            checkFrame  = img.decodeImage(bytes);
            await File(xFile.path).delete();
          } catch (e) {
            debugPrint('Snapshot error: $e');
          }
        }

        if (checkFrame != null) {
          final match = await FaceRecognitionService.instance
              .recogniseInFrame(checkFrame);
          if (match != null) {
            final nameTa = match.name.toLowerCase() == 'loki' ? 'லோகி' : match.name;
            await _tts.speakNow('அவர் $nameTa.');
          } else {
            await _tts.speakNow(
                'தெரிந்த முகம் எதுவும் இல்லை. இவர் அறியப்படாத நபர்.');
          }
        } else {
          await _tts.speakNow('படம் எடுக்க முடியவில்லை. மீண்டும் முயற்சிக்கவும்.');
        }
        break;
      case VoiceCommand.emergencySOS:
        await _tts.speakNow('அவசர உதவி செயல்படுத்தப்படுகிறது.');
        final payload = await EmergencySosService.instance.triggerSos();
        if (payload.emergencyContact.isNotEmpty) {
          await _tts.speakNow('அவசர செய்தி மற்றும் இருப்பிடம் அனுப்பப்படுகிறது.');
        } else {
          await _tts.speakNow('அவசர தொடர்பு எண் பதிவு செய்யப்படவில்லை. இருப்பிடம் சேமிக்கப்பட்டது.');
        }
        break;
      case VoiceCommand.identifyCurrency:
        await _tts.speakNow('ரூபாய் நோட்டை சரிபார்க்கிறேன்.');
        img.Image? currFrame = _lastFrame;
        if (currFrame == null && _cam != null && _cameraReady && !_isStreaming) {
          try {
            final xFile = await _cam!.takePicture();
            final bytes = await File(xFile.path).readAsBytes();
            currFrame = img.decodeImage(bytes);
            await File(xFile.path).delete();
          } catch (e) {
            debugPrint('Currency capture error: $e');
          }
        }
        if (currFrame != null) {
          String? ocrText;
          try {
            final tmpPath = '${Directory.systemTemp.path}/curr_snap_${DateTime.now().millisecondsSinceEpoch}.jpg';
            final encoded = img.encodeJpg(currFrame, quality: 85);
            final tmpFile = File(tmpPath);
            await tmpFile.writeAsBytes(encoded);
            final ocrRes = await OcrService.instance.processImageFile(tmpPath);
            if (ocrRes.hasText) {
              ocrText = ocrRes.rawText;
            }
            if (await tmpFile.exists()) {
              await tmpFile.delete();
            }
          } catch (e) {
            debugPrint('Currency OCR helper error: $e');
          }

          final currResult = CurrencyRecognitionService.instance.recognize(
            image: currFrame,
            ocrText: ocrText,
          );
          await _tts.speakNow(currResult.spokenTextTa);
        } else {
          await _tts.speakNow('படம் எடுக்க முடியவில்லை. மீண்டும் முயற்சிக்கவும்.');
        }
        break;
      case VoiceCommand.readText:
        await _tts.speakNow('வாசகம் படிக்கப்படுகிறது.');
        String? ocrPath;
        if (_cam != null && _cameraReady) {
          try {
            final xFile = await _cam!.takePicture();
            ocrPath = xFile.path;
          } catch (e) {
            debugPrint('OCR capture error: $e');
          }
        }
        if (ocrPath == null && _lastFrame != null) {
          try {
            ocrPath = '${Directory.systemTemp.path}/ocr_snap_${DateTime.now().millisecondsSinceEpoch}.jpg';
            final encoded = img.encodeJpg(_lastFrame!, quality: 90);
            await File(ocrPath).writeAsBytes(encoded);
          } catch (e) {
            debugPrint('OCR fallback encode error: $e');
          }
        }
        if (ocrPath != null) {
          final ocrResult = await OcrService.instance.processImageFile(ocrPath);
          try {
            final f = File(ocrPath);
            if (await f.exists()) await f.delete();
          } catch (_) {}
          await _tts.speakNow(ocrResult.spokenTextTa);
        } else {
          await _tts.speakNow('படம் எடுக்க முடியவில்லை. மீண்டும் முயற்சிக்கவும்.');
        }
        break;
      case VoiceCommand.findObject:
        final query = _voice.lastQuery;
        final target = ObjectFinderService.instance.setTargetFromQuery(query);
        _finderModeActive = true;
        if (!_isDetecting) {
          await _toggleDetection();
        }
        final targetTa = ObjectFinderService.instance.getTamilName(target ?? query);
        await _tts.speakNow('$targetTa தேடும் முறை இயக்கப்பட்டது. கேமராவை மெதுவாக சுழற்றவும்.');
        break;
      case VoiceCommand.toggleTorch:
        if (_cam != null && _cameraReady) {
          try {
            _torchActive = !_torchActive;
            await _cam!.setFlashMode(_torchActive ? FlashMode.torch : FlashMode.off);
            await _tts.speakNow(_torchActive ? 'டார்ச் ஆன் செய்யப்பட்டது.' : 'டார்ச் அணைக்கப்பட்டது.');
          } catch (e) {
            debugPrint('Torch toggle error: $e');
            await _tts.speakNow('டார்ச் இயக்க முடியவில்லை.');
          }
        } else {
          await _tts.speakNow('கேமரா தயாராகவில்லை.');
        }
        break;
      case VoiceCommand.fasterSpeed:
        final newMultiplier = (_tts.speechRateMultiplier + 0.25).clamp(1.0, 2.0);
        await _tts.setSpeechRateMultiplier(newMultiplier);
        await _tts.speakNow('குரல் வேகம் அதிகரிக்கப்பட்டது.');
        break;
      case VoiceCommand.slowerSpeed:
        final newMultiplier = (_tts.speechRateMultiplier - 0.25).clamp(1.0, 2.0);
        await _tts.setSpeechRateMultiplier(newMultiplier);
        await _tts.speakNow('குரல் வேகம் குறைக்கப்பட்டது.');
        break;
      case VoiceCommand.openSettings:
        await _tts.speakNow('அமைப்புகள் திறக்கப்படுகிறது.');
        if (mounted) {
          await Navigator.pushNamed(context, AppRoutes.settings);
          await _detector.refreshSensitivity();
          await _tts.init();
          final p = await SharedPreferences.getInstance();
          if (mounted) setState(() => _vibrationEnabled = p.getBool('vibration') ?? true);
        }
        break;
      case VoiceCommand.openPeople:
        _showPeopleMenu();
        break;
      case VoiceCommand.help:
        await _tts.speakNow(
          'பயன்படுத்தக்கூடிய கட்டளைகள்: தொடங்கு, நிறுத்து, ரூபாய் நோட்டு, வாசகம் படி, எங்கே இருக்கிறது, அவசரம், டார்ச், வேகமாக பேசு, மெதுவாக பேசு, யார் இது, நபர்கள், அமைப்புகள், உதவி.');
        break;
      case VoiceCommand.whereAmI:
        await _tts.speakNow('உங்கள் இருப்பிடத்தைச் சரிபார்க்கிறது.');
        break;
      case VoiceCommand.detectObjects:
        if (!_isDetecting) await _toggleDetection();
        break;
      case VoiceCommand.switchCamera:
        await _tts.speakNow('கேமரா மாற்றப்படுகிறது.');
        break;
      case VoiceCommand.changeLanguage:
        await _tts.speakNow('மொழி மாற்றப்பட்டது.');
        break;
      case VoiceCommand.addPerson:
        _showPeopleMenu();
        break;
      case VoiceCommand.cancel:
      case VoiceCommand.goBack:
        await _tts.speakNow('ரத்து செய்யப்பட்டது.');
        break;
      case VoiceCommand.unknown:
        await _tts.speakNow('கட்டளை புரியவில்லை. உதவி எனக் கூறவும்.');
        break;
    }
  }

  // ── People menu ───────────────────────────────────────────────────────────
  void _showPeopleMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4,
                decoration: BoxDecoration(
                    color: AppColors.greyDark,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text('நபர்கள்',
                style: TextStyle(color: Colors.white, fontSize: 17,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 18),
            _MenuTile(
              icon: Icons.person_add_alt_1, label: 'புதிய நபரைச் சேர்க்கவும்',
              sub: 'முகத்தை ஸ்கேன் செய்து பதிவு செய்யவும்',
              color: Colors.white,
              onTap: () async {
                Navigator.pop(context);
                // Stop the back-camera stream before the capture screen opens
                // its front camera — prevents dual-camera contention on
                // Samsung devices which causes freezing or slow init.
                await _stopStream();           // BUG-22 FIX: use helper consistently
                if (!mounted) return;
                await Navigator.pushNamed(context, AppRoutes.peopleCapture);
                await FaceRecognitionService.instance.refreshKnownPeople();
                // Restart the stream now that capture is done.
                if (mounted && _isDetecting && _cam != null && !_isStreaming) {
                  await _startStream();
                }
              },
            ),
            const SizedBox(height: 10),
            _MenuTile(
              icon: Icons.people_alt_outlined, label: 'நபர்களைப் பார்க்கவும் / நிர்வகிக்கவும்',
              sub: 'பதிவு செய்யப்பட்ட முகங்களை நிர்வகிக்க',
              color: Colors.white,
              onTap: () async {
                Navigator.pop(context);
                await Navigator.pushNamed(context, AppRoutes.peopleList);
                await FaceRecognitionService.instance.refreshKnownPeople();
              },
            ),
          ]),
        ),
      ),
    );
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  bool _wasPausedByLifecycle = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _startupFlowManager.onAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      _startupFlowManager.onAppResumed();
    }

    if (state == AppLifecycleState.paused) {
      _wasPausedByLifecycle = true;
      // ── If the foreground service is running, keep camera alive ─────────────
      // The service holds the process alive; detection continues in background
      // so a blind user gets TTS alerts even when screen is locked.
      if (_serviceActive) {
        debugPrint('Lifecycle: paused — foreground service active, camera kept alive');
        return;
      }
      // ── No service — dispose camera to free resources ────────────────────
      if (_cam == null) return;
      if (mounted) setState(() => _cameraReady = false);
      if (_isStreaming) {
        try { _cam!.stopImageStream(); } catch (_) {}
        _isStreaming = false;
      }
      try { _cam!.dispose(); } catch (_) {}
      _cam = null;
      _cameraInitializing = false; // allow re-init on resume
    } else if (state == AppLifecycleState.resumed &&
               _wasPausedByLifecycle) {
      _wasPausedByLifecycle = false;
      if (!SharedStt.instance.available) SharedStt.instance.reset();
      if (_cam != null) {
        // Camera was kept alive by the foreground service — just refresh UI
        if (mounted) setState(() => _cameraReady = true);
        debugPrint('Lifecycle: resumed — camera still alive, no re-init needed');
      } else {
        // Camera was disposed — full re-initialise
        _initCamera().then((_) {
          if (_isDetecting && !_isStreaming && mounted) _startStream();
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _startupFlowManager.dispose();
    _voiceTimeout?.cancel();
    _pulse.dispose();
    _monitor?.dispose();
    unawaited(NavEyeForegroundService.stop()); // fire-and-forget stop
    if (_isStreaming) {
      try { _cam?.stopImageStream(); } catch (_) {}
      _isStreaming = false;
    }
    _cam?.dispose();
    _detector.dispose();
    _voiceAlert.stop();
    _tts.dispose();
    _voice.dispose();
    // Do NOT call FaceRecognitionService.instance.dispose() here.
    // The service is a singleton shared by the whole app; disposing it from
    // a screen that can be re-created (e.g. after navigator.pop) would null
    // the ONNX session, causing a crash on the next recogniseInFrame() call.
    // The ONNX session is kept alive for the app's lifetime.
    super.dispose();
  }

  // ── Colour helpers (Strict Black and White) ──────────────────────────────
  Color get _borderColor {
    if (!_isDetecting) return AppColors.greyDark;
    return Colors.white;
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Column(children: [

          // Status bar (Section 18 & 19: வழிகாட்டுதல் செயலில் உள்ளது)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(color: Colors.white, width: 1.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                Icon(
                  _isDetecting ? Icons.radar : Icons.search_outlined,
                  color: _isDetecting ? Colors.white : AppColors.grey, size: 17),
                const SizedBox(width: 8),
                Expanded(child: Text(_statusText,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700))),
                if (_isDetecting)
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, __) => Opacity(
                      opacity: _pulseAnim.value,
                      child: Container(width: 8, height: 8,
                          decoration: const BoxDecoration(
                              color: Colors.white, shape: BoxShape.circle)),
                    ),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    _debugModeEnabled ? Icons.bug_report : Icons.bug_report_outlined,
                    color: _debugModeEnabled ? Colors.white : AppColors.grey,
                    size: 20,
                  ),
                  tooltip: 'Developer Debug Mode',
                  onPressed: () {
                    setState(() {
                      _debugModeEnabled = !_debugModeEnabled;
                    });
                  },
                ),
              ]),
            ),
          ),

          // Tamil TTS availability diagnostic banner
          ValueListenableBuilder<bool>(
            valueListenable: _tts.isTamilAvailableNotifier,
            builder: (context, available, _) {
              if (available) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.black, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'எச்சரிக்கை: தமிழ் குரல் கிடைக்கவில்லை',
                      style: TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              );
            },
          ),

          // Camera area — full gesture control for blind users
          //   Single tap    → toggle detection on / off
          //   Double tap    → activate voice command
          //   Long press    → repeat last announcement
          //   Swipe up      → identify person in front
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GestureDetector(
                onTapDown: (_) => _recordTapAndCheckSos(),
                onTap: _toggleDetection,
                onDoubleTap: () {
                  HapticFeedback.heavyImpact();
                  _startVoiceListen();
                },
                onLongPress: () {
                  HapticFeedback.heavyImpact();
                  final msg = _lastAnnouncement.isNotEmpty
                      ? _lastAnnouncement
                      : 'மீண்டும் சொல்ல எதுவும் இல்லை.';
                  _tts.speakNow(msg);
                },
                onVerticalDragEnd: (details) {
                  // Swipe up (negative velocity = upward)
                  if ((details.primaryVelocity ?? 0) < -400) {
                    HapticFeedback.mediumImpact();
                    _handleCmd(VoiceCommand.whoIsThis);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _borderColor, width: 2.0),
                    boxShadow: _isDetecting && _distanceM < 1.2
                        ? [BoxShadow(
                            color: Colors.white.withValues(alpha: 0.35),
                            blurRadius: 14, spreadRadius: 2)]
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: _cameraReady && _cam != null
                        ? Stack(fit: StackFit.expand, children: [
                            CameraPreview(_cam!),

                            // ── White viewfinder / focus frame ────────────
                            // Always shown while detecting so the user (or a
                            // helper) knows which zone the AI is focusing on.
                            // Fades to a ghost when the detection box is active.
                            if (_isDetecting)
                              CustomPaint(
                                size: Size.infinite,
                                painter: _ViewfinderPainter(
                                    hasDetection: _topResult != null),
                              ),

                            // ── Bounding box overlay ──────────────────────
                            if (_isDetecting && _topResult != null)
                              AnimatedBuilder(
                                animation: _pulseAnim,
                                builder: (_, __) => CustomPaint(
                                  size: Size.infinite,
                                  painter: _DetectionBoxPainter(
                                    result:     _topResult!,
                                    pulseValue: _pulseAnim.value,
                                  ),
                                ),
                              ),

                            // Idle overlay
                            if (!_isDetecting)
                              Container(
                                color: Colors.black54,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 80, height: 80,
                                      decoration: BoxDecoration(
                                        color: Colors.black,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2),
                                      ),
                                      child: const Icon(Icons.touch_app,
                                          color: Colors.white, size: 42),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text('வழிகாட்டுதல் தொடங்க தட்டவும்',
                                        style: TextStyle(color: Colors.white,
                                            fontSize: 20, fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 8),
                                    Text(
                                      _modelReady ? 'AI தயார்' : 'மாதிரி தயாராகவில்லை',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    // Gesture hint cards
                                    _GestureHint(icon: Icons.touch_app,   label: 'தட்டவும்',         hint: 'தொடங்க / நிறுத்த'),
                                    const SizedBox(height: 4),
                                    _GestureHint(icon: Icons.mic,          label: 'இருமுறை தட்டவும்',  hint: 'குரல் கட்டளை'),
                                    const SizedBox(height: 4),
                                    _GestureHint(icon: Icons.replay,       label: 'அழுத்திப் பிடிக்க',  hint: 'மீண்டும் கேட்க'),
                                    const SizedBox(height: 4),
                                    _GestureHint(icon: Icons.swipe_up,     label: 'மேலே ஸ்வைப்',    hint: 'யார் என்று பார்க்க'),
                                  ],
                                ),
                              ),

                            // ── LISTENING overlay ─────────────────────────
                            if (_voiceActive)
                              Positioned(
                                top: 8, left: 0, right: 0,
                                child: Center(
                                  child: AnimatedBuilder(
                                    animation: _pulseAnim,
                                    builder: (_, __) => Opacity(
                                      opacity: 0.78 + 0.22 * _pulseAnim.value,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 18, vertical: 9),
                                        decoration: BoxDecoration(
                                          color: Colors.black,
                                          borderRadius: BorderRadius.circular(26),
                                          border: Border.all(color: Colors.white, width: 2),
                                          boxShadow: [BoxShadow(
                                            color: Colors.white.withValues(alpha: 0.3),
                                            blurRadius: 12, spreadRadius: 1)],
                                        ),
                                        child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                          Icon(Icons.mic,
                                              color: Colors.white, size: 17),
                                          SizedBox(width: 7),
                                          Text('கேட்கிறது...',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 0.6,
                                              )),
                                        ]),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                            if (_isDetecting) ...[
                              // LIVE badge
                              Positioned(
                                top: 12, left: 12,
                                child: AnimatedBuilder(
                                  animation: _pulseAnim,
                                  builder: (_, __) => Opacity(
                                    opacity: 0.7 + 0.3 * _pulseAnim.value,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                          color: Colors.black,
                                          border: Border.all(color: Colors.white, width: 1.5),
                                          borderRadius: BorderRadius.circular(20)),
                                      child: const Row(children: [
                                        Icon(Icons.fiber_manual_record,
                                            color: Colors.white, size: 9),
                                        SizedBox(width: 4),
                                        Text('செயலில்', style: TextStyle(
                                            color: Colors.white, fontSize: 11,
                                            fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                                      ]),
                                    ),
                                  ),
                                ),
                              ),

                              // Very close warning badge (Section 19: நிறுத்தவும்)
                              if (_detLabel.isNotEmpty && _distanceM < 1.2)
                                Positioned(
                                  top: 12, right: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(20)),
                                    child: const Row(children: [
                                      Icon(Icons.warning_amber_rounded,
                                          color: Colors.black, size: 14),
                                      SizedBox(width: 4),
                                      Text('நிறுத்தவும்', style: TextStyle(
                                          color: Colors.black, fontSize: 11,
                                          fontWeight: FontWeight.w900)),
                                    ]),
                                  ),
                                ),

                              // ── Developer Debug HUD ─────────────────────
                              if (_debugModeEnabled) _buildDebugOverlay(),

                              // Detection result overlay (Sections 18 & 19: Accessibility-first Black & White UI)
                              if (_detLabel.isNotEmpty)
                                Positioned(
                                  bottom: 12, left: 12, right: 12,
                                  child: _isStopAction
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: Colors.white, width: 2.5),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  const Icon(Icons.pan_tool, color: Colors.black, size: 28),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      _navigationActionDirective,
                                                      style: const TextStyle(
                                                        color: Colors.black,
                                                        fontSize: 26,
                                                        fontWeight: FontWeight.w900,
                                                        letterSpacing: 0.5,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _navigationStatusHeader,
                                                style: const TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: Colors.black,
                                                      borderRadius: BorderRadius.circular(20),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        const Icon(Icons.straighten, color: Colors.white, size: 13),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          '${_distanceM.toStringAsFixed(1)} மீ${_distance.isNotEmpty ? ' • $_distance' : ''}',
                                                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: Colors.black,
                                                      borderRadius: BorderRadius.circular(20),
                                                    ),
                                                    child: Text(
                                                      _detLabel.isNotEmpty ? _detLabel : 'தடை',
                                                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        )
                                      : Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.92),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: Colors.white, width: 2.0),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(_navigationActionIcon, color: Colors.white, size: 28),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      _navigationActionDirective,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 24,
                                                        fontWeight: FontWeight.w900,
                                                        letterSpacing: 0.5,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _navigationStatusHeader,
                                                style: const TextStyle(
                                                  color: AppColors.greyLight,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: Colors.black,
                                                      borderRadius: BorderRadius.circular(20),
                                                      border: Border.all(color: Colors.white),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        const Icon(Icons.straighten, color: Colors.white, size: 13),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          _currentNavAction == NavigationAction.clear
                                                              ? (_distance.isNotEmpty ? _distance : 'தெளிவு')
                                                              : '${_distanceM.toStringAsFixed(1)} மீ${_distance.isNotEmpty ? ' • $_distance' : ''}',
                                                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: Colors.black,
                                                      borderRadius: BorderRadius.circular(20),
                                                      border: Border.all(color: Colors.white),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          _direction == 'LEFT'
                                                              ? Icons.arrow_back
                                                              : _direction == 'RIGHT'
                                                                  ? Icons.arrow_forward
                                                                  : Icons.arrow_upward,
                                                          color: Colors.white,
                                                          size: 13,
                                                        ),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          _direction == 'LEFT' ? 'இடப்பக்கம்' : (_direction == 'RIGHT' ? 'வலப்பக்கம்' : 'முன்னால்'),
                                                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                ),

                              // Scanning spinner (no detection yet)
                              if (_detLabel.isEmpty)
                                Positioned(
                                  bottom: 12, left: 12, right: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.88),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.white, width: 1.5),
                                    ),
                                    child: const Row(children: [
                                      SizedBox(width: 14, height: 14,
                                          child: CircularProgressIndicator(
                                              color: Colors.white, strokeWidth: 2)),
                                      SizedBox(width: 10),
                                      Text('பாதை கண்காணிக்கப்படுகிறது...',
                                          style: TextStyle(
                                              color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                                    ]),
                                  ),
                                ),
                            ],
                          ])
                        : _cameraPermDenied
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.no_photography_outlined,
                                    color: AppColors.danger, size: 60),
                                const SizedBox(height: 16),
                                const Text('கேமரா அனுமதி தேவை',
                                    style: TextStyle(
                                        color: AppColors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 8),
                                const Text(
                                  'தடைகளைக் கண்டறிய நாவ்ஐ செயலிற்கு\nகேமரா அனுமதி தேவை.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: AppColors.grey, fontSize: 13, height: 1.5)),
                                const SizedBox(height: 20),
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    await openAppSettings();
                                  },
                                  icon: const Icon(Icons.settings, size: 16),
                                  label: const Text('அமைப்புகளைத் திறக்கவும்',
                                      style: TextStyle(fontWeight: FontWeight.w700)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.yellow,
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextButton(
                                  onPressed: () {
                                    setState(() => _cameraPermDenied = false);
                                    _initCamera();
                                  },
                                  child: const Text('மீண்டும் முயற்சிக்கவும்',
                                      style: TextStyle(color: AppColors.grey)),
                                ),
                              ],
                            )
                          : const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(
                                    color: AppColors.yellow, strokeWidth: 2),
                                SizedBox(height: 16),
                                Text('கேமரா தொடங்குகிறது...',
                                    style: TextStyle(
                                        color: AppColors.greyLight, fontSize: 14)),
                              ],
                            ),
                  ),
                ),
              ),
            ),
          ),

          // ── Bottom bar: People | MIC | Settings ────────────────────────────
          // The mic button is centred and large so it is impossible to miss.
          // RED  + pulsing glow + "ON"  label = actively listening
          // GREY + no glow     + "MIC" label = off / ready to tap
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [

              // ── People (Section 17: Black and White) ───────────────────────
              Expanded(
                child: GestureDetector(
                  onTap: _showPeopleMenu,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.people, color: Colors.white, size: 20),
                      SizedBox(height: 4),
                      Text('நபர்கள்', style: TextStyle(
                          color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // ── Microphone (Section 17: Black and White) ────────────────────
              GestureDetector(
                onTap: _startVoiceListen,
                child: AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (_, __) {
                    final active = _voiceActive;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        color: active ? Colors.white : Colors.black,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 3,
                        ),
                        boxShadow: active
                            ? [BoxShadow(
                                color: Colors.white.withValues(
                                    alpha: 0.30 + 0.35 * _pulseAnim.value),
                                blurRadius: 18 + 12 * _pulseAnim.value,
                                spreadRadius: 3)]
                            : null,
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(
                          active ? Icons.mic : Icons.mic_none,
                          color: active ? Colors.black : Colors.white,
                          size: active ? 30 : 26,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          active ? 'நிறுத்து' : 'பேசு',
                          style: TextStyle(
                            color: active ? Colors.black : Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ]),
                    );
                  },
                ),
              ),

              const SizedBox(width: 10),

              // ── Settings (Section 17: Black and White) ──────────────────────
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    await Navigator.pushNamed(context, AppRoutes.settings);
                    await _detector.refreshSensitivity();
                    await _tts.init();
                    final p = await SharedPreferences.getInstance();
                    if (mounted) {
                      setState(() =>
                          _vibrationEnabled = p.getBool('vibration') ?? true);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.settings, color: Colors.white, size: 20),
                      SizedBox(height: 4),
                      Text('அமைப்புகள்', style: TextStyle(
                          color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
      CalmStartupOverlay(flowManager: _startupFlowManager),
    ],
  ),
);
}

  Widget _buildDebugOverlay() {
    return Positioned(
      top: 48,
      left: 12,
      right: 12,
      child: ValueListenableBuilder<VoiceDebugInfo>(
        valueListenable: _voiceAlert.debugNotifier,
        builder: (context, info, _) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.yellow, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(
                  children: [
                    Icon(Icons.bug_report, color: AppColors.yellow, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'DEVELOPER DEBUG MODE',
                      style: TextStyle(
                        color: AppColors.yellow,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const Divider(color: AppColors.greyDark, height: 12),
                _debugRow('Detected object:', info.objectName),
                _debugRow('Confidence:', info.confidence > 0 ? info.confidence.toStringAsFixed(2) : '0.00'),
                _debugRow('Position:', info.position),
                _debugRow('Approximate proximity:', info.proximity),
                _debugRow('Announcement:', '"${info.announcement}"'),
                _debugRow(
                  'Announcement cooldown:',
                  info.cooldownActive ? 'ACTIVE' : 'INACTIVE',
                  valueColor: info.cooldownActive ? AppColors.greyLight : AppColors.white,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _debugRow(String label, String value, {Color valueColor = AppColors.white}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.greyLight, fontSize: 11)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(color: valueColor, fontSize: 11, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Small reusable widgets ────────────────────────────────────────────────────

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String   label, sub;
  final Color    color;
  final VoidCallback onTap;
  const _MenuTile({
    required this.icon, required this.label, required this.sub,
    required this.color, required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.inputBg, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(
                color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(color: AppColors.grey, fontSize: 12)),
          ])),
          const Icon(Icons.chevron_right, color: AppColors.grey, size: 18),
        ]),
      ),
    );
  }
}

// ── Gesture hint row — shown on idle camera overlay ──────────────────────────
class _GestureHint extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   hint;
  const _GestureHint({required this.icon, required this.label, required this.hint});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(children: [
        Icon(icon, color: AppColors.yellow, size: 14),
        const SizedBox(width: 6),
        Text('$label  ', style: const TextStyle(
            color: AppColors.yellow, fontSize: 11, fontWeight: FontWeight.w700)),
        Text(hint, style: const TextStyle(color: AppColors.grey, fontSize: 11)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Detection bounding-box painter
//  Draws:
//    • Spotlight — dark vignette outside the detected object's box
//    • Corner brackets — colour-coded by distance, pulsing when very close
//    • Subtle fill — semi-transparent tint inside the box
//    • Label tag — object name + distance above the box
//  For wall/obstacle heuristics the whole frame gets a pulsing border instead.
// ─────────────────────────────────────────────────────────────────────────────
class _DetectionBoxPainter extends CustomPainter {
  final DetectionResult result;
  final double          pulseValue;  // 0.0 – 1.0 from AnimationController

  const _DetectionBoxPainter({
    required this.result,
    required this.pulseValue,
  });

  // Distance → colour (Strict Black and White Theme)
  Color get _boxColor => Colors.white;

  @override
  void paint(Canvas canvas, Size size) {
    // ── Direct coordinate mapping ────────────────────────────────────────────
    final l = result.xMin * size.width;
    final t = result.yMin * size.height;
    final r = result.xMax * size.width;
    final b = result.yMax * size.height;

    final color     = _boxColor;
    final isClose   = result.isVeryClose;
    final isDanger  = result.distanceM < 0.8;

    // ── Wall / full-frame obstacle → pulsing border, no spotlight ────────────
    if (result.isWallHeuristic) {
      final opacity = isDanger ? 0.55 + 0.45 * pulseValue : 0.70;
      final border  = Paint()
        ..color      = color.withValues(alpha: opacity)
        ..strokeWidth = 5.0 + 3.0 * pulseValue
        ..style       = PaintingStyle.stroke;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(3, 3, size.width - 6, size.height - 6),
          const Radius.circular(14),
        ),
        border,
      );
      _drawLabel(canvas, size, 10, 10, color, size.width - 20);
      return;
    }

    // ── Spotlight — dim everything outside the bounding box ──────────────────
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.45);
    canvas.drawRect(Rect.fromLTRB(0,          0,          size.width, t         ), dim);
    canvas.drawRect(Rect.fromLTRB(0,          b,          size.width, size.height), dim);
    canvas.drawRect(Rect.fromLTRB(0,          t,          l,          b         ), dim);
    canvas.drawRect(Rect.fromLTRB(r,          t,          size.width, b         ), dim);

    // ── Subtle fill ───────────────────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTRB(l, t, r, b),
      Paint()..color = color.withValues(alpha: isDanger ? 0.12 + 0.08 * pulseValue : 0.08),
    );

    // ── Corner brackets ───────────────────────────────────────────────────────
    final boxShort = (r - l) < (b - t) ? (r - l) : (b - t);
    final arm      = (boxShort * 0.22).clamp(14.0, 42.0);
    final sw       = isClose ? 3.2 + 1.8 * pulseValue : 2.8;

    final p = Paint()
      ..color      = Colors.white
      ..strokeWidth = sw
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.round;

    // top-left
    canvas.drawLine(Offset(l, t + arm), Offset(l, t), p);
    canvas.drawLine(Offset(l, t),       Offset(l + arm, t), p);
    // top-right
    canvas.drawLine(Offset(r - arm, t), Offset(r, t), p);
    canvas.drawLine(Offset(r, t),       Offset(r, t + arm), p);
    // bottom-left
    canvas.drawLine(Offset(l, b - arm), Offset(l, b), p);
    canvas.drawLine(Offset(l, b),       Offset(l + arm, b), p);
    // bottom-right
    canvas.drawLine(Offset(r - arm, b), Offset(r, b), p);
    canvas.drawLine(Offset(r, b),       Offset(r, b - arm), p);

    // ── Label tag ─────────────────────────────────────────────────────────────
    _drawLabel(canvas, size, l, t, color, r - l);
  }

  void _drawLabel(Canvas canvas, Size size,
      double l, double t, Color color, double maxW) {
    final text = '${result.label}  •  ${result.distance}';
    final tp   = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color:       Colors.white,
          fontSize:    13,
          fontWeight:  FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxW.clamp(60.0, size.width - l));

    const padX = 10.0, padY = 6.0;
    final tagW   = (tp.width + padX * 2).clamp(0.0, size.width - l);
    final tagH   = tp.height + padY * 2;
    final tagTop  = (t - tagH - 5).clamp(0.0, size.height - tagH);
    final tagLeft = l.clamp(0.0, size.width - tagW);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(tagLeft, tagTop, tagW, tagH),
        const Radius.circular(6),
      ),
      Paint()..color = Colors.black,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(tagLeft, tagTop, tagW, tagH),
        const Radius.circular(6),
      ),
      Paint()..color = Colors.white ..style = PaintingStyle.stroke ..strokeWidth = 1.5,
    );
    tp.paint(canvas, Offset(tagLeft + padX, tagTop + padY));
  }

  @override
  bool shouldRepaint(_DetectionBoxPainter old) =>
      old.result     != result ||
      old.pulseValue != pulseValue;
}

// ─────────────────────────────────────────────────────────────────────────────
//  White viewfinder / focus-frame painter
//  Draws:
//    • Light vignette outside the focus zone
//    • White corner-bracket crosshairs inside the zone
//    • "FOCUS" label at top-left corner
//  The focus zone is the centre 65 % width × 62 % height of the frame.
//  Objects inside this zone are the primary announcement target.
// ─────────────────────────────────────────────────────────────────────────────
class _ViewfinderPainter extends CustomPainter {
  final bool hasDetection; // dims the viewfinder when an object box is active
  const _ViewfinderPainter({this.hasDetection = false});

  @override
  void paint(Canvas canvas, Size size) {
    // Focus zone rect — centred, 65 % wide × 62 % tall
    const hPad = 0.175; // (1 - 0.65) / 2
    const vPad = 0.190; // (1 - 0.62) / 2
    final l = size.width  * hPad;
    final t = size.height * vPad;
    final r = size.width  * (1 - hPad);
    final b = size.height * (1 - vPad);
    final rect = Rect.fromLTRB(l, t, r, b);

    // Vignette — dim outside
    if (!hasDetection) {
      final vignette = Paint()..color = Colors.black.withValues(alpha: 0.30);
      canvas.drawRect(Rect.fromLTRB(0, 0, size.width, t), vignette);
      canvas.drawRect(Rect.fromLTRB(0, b, size.width, size.height), vignette);
      canvas.drawRect(Rect.fromLTRB(0, t, l, b), vignette);
      canvas.drawRect(Rect.fromLTRB(r, t, size.width, b), vignette);
    }

    // Corner arm length — adaptive
    final armLen = (rect.shortestSide * 0.14).clamp(18.0, 44.0);

    final paint = Paint()
      ..color      = hasDetection
          ? Colors.white.withValues(alpha: 0.35) // fade when box overlay is active
          : Colors.white.withValues(alpha: 0.90)
      ..strokeWidth = hasDetection ? 1.8 : 2.6
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.round;

    // Top-left
    canvas.drawLine(Offset(l, t + armLen), Offset(l, t), paint);
    canvas.drawLine(Offset(l, t), Offset(l + armLen, t), paint);
    // Top-right
    canvas.drawLine(Offset(r - armLen, t), Offset(r, t), paint);
    canvas.drawLine(Offset(r, t), Offset(r, t + armLen), paint);
    // Bottom-left
    canvas.drawLine(Offset(l, b - armLen), Offset(l, b), paint);
    canvas.drawLine(Offset(l, b), Offset(l + armLen, b), paint);
    // Bottom-right
    canvas.drawLine(Offset(r - armLen, b), Offset(r, b), paint);
    canvas.drawLine(Offset(r, b), Offset(r, b - armLen), paint);

    // Small centre crosshair
    if (!hasDetection) {
      final cx = (l + r) / 2, cy = (t + b) / 2;
      const ch = 10.0;
      final cp = Paint()
        ..color      = Colors.white.withValues(alpha: 0.55)
        ..strokeWidth = 1.5
        ..style       = PaintingStyle.stroke
        ..strokeCap   = StrokeCap.round;
      canvas.drawLine(Offset(cx - ch, cy), Offset(cx + ch, cy), cp);
      canvas.drawLine(Offset(cx, cy - ch), Offset(cx, cy + ch), cp);
    }

    // "FOCUS" label tag — top-left corner of the frame
    if (!hasDetection) {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'FOCUS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      const padX = 7.0, padY = 4.0;
      final tagW = tp.width + padX * 2;
      final tagH = tp.height + padY * 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(l, t - tagH - 4, tagW, tagH),
          const Radius.circular(4),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.20),
      );
      tp.paint(canvas, Offset(l + padX, t - tagH - 4 + padY));
    }
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) =>
      old.hasDetection != hasDetection;
}
