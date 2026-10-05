import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naveye/services/detector_service.dart';
import 'package:naveye/services/detection_stabilizer.dart';
import 'package:naveye/services/navigation_decision_engine.dart';
import 'package:naveye/services/voice_alert_manager.dart';

DetectionResult createRawDetection({
  required String label,
  required double xCenter,
  required double xMin,
  required double xMax,
  required double yMin,
  required double yMax,
  double confidence = 0.90,
  double distanceM = 1.8,
  bool isWall = false,
}) {
  return DetectionResult(
    label: label,
    rawLabel: label.toLowerCase(),
    confidence: confidence,
    direction: xCenter < 0.35 ? 'left' : xCenter > 0.65 ? 'right' : 'centre',
    distance: '${distanceM.toStringAsFixed(1)}m',
    distanceM: distanceM,
    xCenter: xCenter,
    xMin: xMin,
    xMax: xMax,
    yMin: yMin,
    yMax: yMax,
    isWallHeuristic: isWall,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (MethodCall methodCall) async {
        return 1;
      },
    );
  });

  late DetectionStabilizer stabilizer;
  late NavigationDecisionEngine engine;
  late VoiceAlertManager voiceAlert;

  setUp(() {
    stabilizer = DetectionStabilizer(
      stabilityThresholdMs: 300,
      minStableFrames: 2,
      confidenceThreshold: 0.50,
    );
    engine = NavigationDecisionEngine(
      leftThreshold: 0.35,
      rightThreshold: 0.65,
      actionGuidanceMode: true,
    );
    voiceAlert = VoiceAlertManager();
    voiceAlert.reset();
  });

  group('Actionable Navigation Narration Tests ([OBJECT] + [POSITION] + [ACTION])', () {
    test('Example: Laptop directly ahead + left clear -> "Laptop ahead. Move left."', () {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      final rawCenter = createRawDetection(
        label: 'laptop',
        xCenter: 0.50,
        xMin: 0.35,
        xMax: 0.65,
        yMin: 0.35,
        yMax: 0.65,
      );

      // Frame 1
      var stable = stabilizer.processFrame([rawCenter], timestamp: t0);
      expect(stable.isEmpty, isTrue);

      // Frame 2 at 350ms
      final t1 = t0.add(const Duration(milliseconds: 350));
      stable = stabilizer.processFrame([rawCenter], timestamp: t1);
      expect(stable.length, equals(1));

      final alert = engine.evaluate(stable, timestamp: t1);
      expect(alert, isNotNull);
      expect(alert!.spokenTextEn, equals('Laptop ahead. Move left.'));
    });

    test('Example: Laptop directly ahead + right clear (left blocked) -> "Laptop ahead. Move left."', () {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      final rawCenter = createRawDetection(
        label: 'laptop',
        xCenter: 0.50,
        xMin: 0.35,
        xMax: 0.65,
        yMin: 0.35,
        yMax: 0.65,
      );
      final rawLeft = createRawDetection(
        label: 'chair',
        xCenter: 0.20,
        xMin: 0.10,
        xMax: 0.30,
        yMin: 0.30,
        yMax: 0.70,
      );

      stabilizer.processFrame([rawCenter, rawLeft], timestamp: t0);
      final t1 = t0.add(const Duration(milliseconds: 350));
      final stable = stabilizer.processFrame([rawCenter, rawLeft], timestamp: t1);
      expect(stable.length, equals(2));

      final alert = engine.evaluate(stable, timestamp: t1);
      expect(alert, isNotNull);
      expect(alert!.spokenTextEn, equals('Laptop ahead. Move left.'));
    });

    test('Example: Obstacle on the left -> "Chair on your left. Move right."', () {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      final rawLeft = createRawDetection(
        label: 'chair',
        xCenter: 0.20,
        xMin: 0.10,
        xMax: 0.30,
        yMin: 0.20,
        yMax: 0.80,
      );

      stabilizer.processFrame([rawLeft], timestamp: t0);
      final t1 = t0.add(const Duration(milliseconds: 350));
      final stable = stabilizer.processFrame([rawLeft], timestamp: t1);
      expect(stable.length, equals(1));

      final alert = engine.evaluate(stable, timestamp: t1);
      expect(alert, isNotNull);
      expect(alert!.spokenTextEn, equals('Chair on your left. Move right.'));
    });

    test('Example: Obstacle on the right -> "Person on your right. Move left."', () {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      final rawRight = createRawDetection(
        label: 'person',
        xCenter: 0.80,
        xMin: 0.70,
        xMax: 0.90,
        yMin: 0.20,
        yMax: 0.80,
      );

      stabilizer.processFrame([rawRight], timestamp: t0);
      final t1 = t0.add(const Duration(milliseconds: 350));
      final stable = stabilizer.processFrame([rawRight], timestamp: t1);
      expect(stable.length, equals(1));

      final alert = engine.evaluate(stable, timestamp: t1);
      expect(alert, isNotNull);
      expect(alert!.spokenTextEn, equals('Person on your right. Move left.'));
    });

    test('Example: Obstacle directly ahead + both sides blocked -> "Obstacle ahead. Stop and wait."', () {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      final rawCenter = createRawDetection(label: 'obstacle', xCenter: 0.50, xMin: 0.40, xMax: 0.60, yMin: 0.3, yMax: 0.7);
      final rawLeft = createRawDetection(label: 'chair', xCenter: 0.20, xMin: 0.10, xMax: 0.30, yMin: 0.3, yMax: 0.7);
      final rawRight = createRawDetection(label: 'table', xCenter: 0.80, xMin: 0.70, xMax: 0.90, yMin: 0.3, yMax: 0.7);

      stabilizer.processFrame([rawCenter, rawLeft, rawRight], timestamp: t0);
      final t1 = t0.add(const Duration(milliseconds: 350));
      final stable = stabilizer.processFrame([rawCenter, rawLeft, rawRight], timestamp: t1);
      expect(stable.length, equals(3));

      final alert = engine.evaluate(stable, timestamp: t1);
      expect(alert, isNotNull);
      expect(alert!.spokenTextEn, equals('Obstacle ahead. Stop and wait.'));
      expect(alert.action, equals(NavigationAction.stop));
    });

    test('Example: Very close obstacle -> "Obstacle very close ahead. Stop and wait."', () {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      final rawClose = createRawDetection(
        label: 'wall',
        xCenter: 0.50,
        xMin: 0.20,
        xMax: 0.80,
        yMin: 0.10,
        yMax: 0.90,
        distanceM: 0.6,
        isWall: true,
      );

      final stable = stabilizer.processFrame([rawClose], timestamp: t0);
      final alert = engine.evaluate(stable, timestamp: t0);
      expect(alert, isNotNull);
      expect(alert!.spokenTextEn, equals('Obstacle very close ahead. Stop and wait.'));
      expect(alert.priority, equals(AlertPriority.criticalObstacle));
    });

    test('Continuous Detection: Stationary laptop speaks ONCE, then SILENCE while continuing detection', () async {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      final rawCenter = createRawDetection(
        label: 'laptop',
        xCenter: 0.50,
        xMin: 0.40,
        xMax: 0.60,
        yMin: 0.30,
        yMax: 0.70,
      );

      stabilizer.processFrame([rawCenter], timestamp: t0);
      final t1 = t0.add(const Duration(milliseconds: 350));
      final stable1 = stabilizer.processFrame([rawCenter], timestamp: t1);
      final alert1 = engine.evaluate(stable1, timestamp: t1);
      expect(alert1!.spokenTextEn, equals('Laptop ahead. Move left.'));

      // Speaks first time
      await voiceAlert.processAlert(alert1, timestamp: t1);
      expect(voiceAlert.currentDebugInfo.announcement, equals('முன்னால் தடையுள்ளது. இடப்பக்கம் செல்லுங்கள்.'));

      // Continuous detection frames over next 30 seconds
      for (int sec = 1; sec <= 5; sec++) {
        final t = t1.add(Duration(seconds: sec));
        final stable = stabilizer.processFrame([rawCenter], timestamp: t);
        final alert = engine.evaluate(stable, timestamp: t);
        await voiceAlert.processAlert(alert, timestamp: t);

        // SILENT: MONITORING SILENTLY state active, duplicate voice suppressed
        expect(voiceAlert.currentDebugInfo.cooldownActive, isTrue);
        expect(voiceAlert.currentDebugInfo.voiceState, equals('MONITORING SILENTLY'));
      }
    });

    test('State Change: Laptop center -> moves left -> moves right triggers new announcements', () async {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      // 1. Center -> "முன்னால் தடையுள்ளது. இடப்பக்கம் செல்லுங்கள்."
      final rawCenter = createRawDetection(label: 'laptop', xCenter: 0.50, xMin: 0.40, xMax: 0.60, yMin: 0.3, yMax: 0.6);
      stabilizer.processFrame([rawCenter], timestamp: t0);
      var stable = stabilizer.processFrame([rawCenter], timestamp: t0.add(const Duration(milliseconds: 350)));
      var alert = engine.evaluate(stable, timestamp: t0.add(const Duration(milliseconds: 350)));
      expect(alert!.spokenTextEn, equals('Laptop ahead. Move left.'));
      await voiceAlert.processAlert(alert, timestamp: t0.add(const Duration(milliseconds: 350)));
      expect(voiceAlert.currentDebugInfo.announcement, equals('முன்னால் தடையுள்ளது. இடப்பக்கம் செல்லுங்கள்.'));

      // 2. Moves LEFT -> "இடப்பக்கம் தடையுள்ளது. வலப்பக்கம் செல்லுங்கள்."
      final tLeft1 = t0.add(const Duration(seconds: 3));
      final rawLeft = createRawDetection(label: 'laptop', xCenter: 0.20, xMin: 0.10, xMax: 0.30, yMin: 0.3, yMax: 0.6);
      stabilizer.processFrame([rawLeft], timestamp: tLeft1);
      final tLeft2 = tLeft1.add(const Duration(milliseconds: 400));
      stable = stabilizer.processFrame([rawLeft], timestamp: tLeft2);
      alert = engine.evaluate(stable, timestamp: tLeft2);
      expect(alert!.spokenTextEn, equals('Laptop on your left. Move right.'));
      await voiceAlert.processAlert(alert, timestamp: tLeft2);
      expect(voiceAlert.currentDebugInfo.announcement, equals('இடப்பக்கம் தடையுள்ளது. வலப்பக்கம் செல்லுங்கள்.'));

      // 3. Moves RIGHT -> "வலப்பக்கம் தடையுள்ளது. இடப்பக்கம் செல்லுங்கள்."
      final tRight1 = tLeft2.add(const Duration(seconds: 3));
      final rawRight = createRawDetection(label: 'laptop', xCenter: 0.80, xMin: 0.70, xMax: 0.90, yMin: 0.3, yMax: 0.6);
      stabilizer.processFrame([rawRight], timestamp: tRight1);
      final tRight2 = tRight1.add(const Duration(milliseconds: 400));
      stable = stabilizer.processFrame([rawRight], timestamp: tRight2);
      alert = engine.evaluate(stable, timestamp: tRight2);
      expect(alert!.spokenTextEn, equals('Laptop on your right. Move left.'));
      await voiceAlert.processAlert(alert, timestamp: tRight2);
      expect(voiceAlert.currentDebugInfo.announcement, equals('வலப்பக்கம் தடையுள்ளது. இடப்பக்கம் செல்லுங்கள்.'));
    });

    test('Priority Preemption: Critical Stop immediately interrupts outdated instruction', () async {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      final moveLeftAlert = NavigationAlert(
        trackingId: 1,
        rawLabel: 'laptop',
        label: 'Laptop',
        direction: ObjectDirection.center,
        action: NavigationAction.goLeft,
        proximity: ObjectProximity.near,
        priority: AlertPriority.obstacleAhead,
        spokenTextEn: 'Laptop ahead. Move left.',
        spokenTextTa: 'முன்னால் தடையுள்ளது. இடப்பக்கம் செல்லுங்கள்.',
        confidence: 0.90,
        relativeArea: 0.08,
        distanceM: 1.8,
        generatedAt: t0,
      );

      final t1 = t0.add(const Duration(milliseconds: 50));
      final stopAlert = NavigationAlert(
        trackingId: 2,
        rawLabel: 'obstacle',
        label: 'Obstacle',
        direction: ObjectDirection.center,
        action: NavigationAction.stop,
        proximity: ObjectProximity.veryNear,
        priority: AlertPriority.criticalObstacle,
        spokenTextEn: 'Obstacle very close ahead. Stop and wait.',
        spokenTextTa: 'முன்னால் தடையுள்ளது. நின்றுவிடுங்கள்.',
        confidence: 0.95,
        relativeArea: 0.25,
        distanceM: 0.5,
        generatedAt: t1,
      );

      await voiceAlert.processAlert(moveLeftAlert, timestamp: t0);
      expect(voiceAlert.currentDebugInfo.announcement, equals('முன்னால் தடையுள்ளது. இடப்பக்கம் செல்லுங்கள்.'));

      // Preempts with Stop immediately
      await voiceAlert.processAlert(stopAlert, timestamp: t1);
      expect(voiceAlert.currentDebugInfo.announcement, equals('முன்னால் தடையுள்ளது. நின்றுவிடுங்கள்.'));
      expect(voiceAlert.currentDebugInfo.priority, equals('criticalObstacle'));
    });
  });

  group('Section 21: Mandatory Blind User Tamil Navigation Test Suite', () {
    test('1. CLEAR state: Expected "முன்னால் பாதை தெளிவாக உள்ளது. செல்லலாம்."', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final clearAlert = engine.createClearAlert(now);
      expect(clearAlert.navState, equals(NavigationState.clear));
      expect(clearAlert.spokenTextTa, equals('முன்னால் பாதை தெளிவாக உள்ளது. செல்லலாம்.'));
    });

    test('2. LEFT obstacle: Expected "இடப்பக்கம் தடையுள்ளது. வலப்பக்கம் செல்லுங்கள்."', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final rawLeft = createRawDetection(label: 'obstacle', xCenter: 0.20, xMin: 0.10, xMax: 0.30, yMin: 0.2, yMax: 0.8);
      stabilizer.processFrame([rawLeft], timestamp: now);
      final stable = stabilizer.processFrame([rawLeft], timestamp: now.add(const Duration(milliseconds: 350)));
      final alert = engine.evaluate(stable, timestamp: now.add(const Duration(milliseconds: 350)));
      expect(alert, isNotNull);
      expect(alert!.spokenTextTa, equals('இடப்பக்கம் தடையுள்ளது. வலப்பக்கம் செல்லுங்கள்.'));
      expect(alert.action, equals(NavigationAction.goRight));
    });

    test('3. RIGHT obstacle: Expected "வலப்பக்கம் தடையுள்ளது. இடப்பக்கம் செல்லுங்கள்."', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final rawRight = createRawDetection(label: 'obstacle', xCenter: 0.80, xMin: 0.70, xMax: 0.90, yMin: 0.2, yMax: 0.8);
      stabilizer.processFrame([rawRight], timestamp: now);
      final stable = stabilizer.processFrame([rawRight], timestamp: now.add(const Duration(milliseconds: 350)));
      final alert = engine.evaluate(stable, timestamp: now.add(const Duration(milliseconds: 350)));
      expect(alert, isNotNull);
      expect(alert!.spokenTextTa, equals('வலப்பக்கம் தடையுள்ளது. இடப்பக்கம் செல்லுங்கள்.'));
      expect(alert.action, equals(NavigationAction.goLeft));
    });

    test('4. CENTER + LEFT CLEAR: Expected "முன்னால் தடையுள்ளது. இடப்பக்கம் செல்லுங்கள்."', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final rawCenter = createRawDetection(label: 'obstacle', xCenter: 0.50, xMin: 0.40, xMax: 0.60, yMin: 0.3, yMax: 0.7);
      final rawRight = createRawDetection(label: 'chair', xCenter: 0.80, xMin: 0.70, xMax: 0.90, yMin: 0.3, yMax: 0.7);
      stabilizer.processFrame([rawCenter, rawRight], timestamp: now);
      final stable = stabilizer.processFrame([rawCenter, rawRight], timestamp: now.add(const Duration(milliseconds: 350)));
      final alert = engine.evaluate(stable, timestamp: now.add(const Duration(milliseconds: 350)));
      expect(alert, isNotNull);
      expect(alert!.spokenTextTa, equals('முன்னால் தடையுள்ளது. இடப்பக்கம் செல்லுங்கள்.'));
      expect(alert.action, equals(NavigationAction.goLeft));
    });

    test('5. CENTER obstacle: Expected "முன்னால் தடையுள்ளது. இடப்பக்கம் செல்லுங்கள்."', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final rawCenter = createRawDetection(label: 'obstacle', xCenter: 0.50, xMin: 0.40, xMax: 0.60, yMin: 0.3, yMax: 0.7);
      final rawLeft = createRawDetection(label: 'chair', xCenter: 0.20, xMin: 0.10, xMax: 0.30, yMin: 0.3, yMax: 0.7);
      stabilizer.processFrame([rawCenter, rawLeft], timestamp: now);
      final stable = stabilizer.processFrame([rawCenter, rawLeft], timestamp: now.add(const Duration(milliseconds: 350)));
      final alert = engine.evaluate(stable, timestamp: now.add(const Duration(milliseconds: 350)));
      expect(alert, isNotNull);
      expect(alert!.spokenTextTa, equals('முன்னால் தடையுள்ளது. இடப்பக்கம் செல்லுங்கள்.'));
      expect(alert.action, equals(NavigationAction.goLeft));
    });

    test('6. CENTER + BOTH BLOCKED: Expected "முன்னால் தடையுள்ளது. நின்றுவிடுங்கள்."', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final rawCenter = createRawDetection(label: 'obstacle', xCenter: 0.50, xMin: 0.40, xMax: 0.60, yMin: 0.3, yMax: 0.7);
      final rawLeft = createRawDetection(label: 'chair', xCenter: 0.20, xMin: 0.10, xMax: 0.30, yMin: 0.3, yMax: 0.7);
      final rawRight = createRawDetection(label: 'table', xCenter: 0.80, xMin: 0.70, xMax: 0.90, yMin: 0.3, yMax: 0.7);
      stabilizer.processFrame([rawCenter, rawLeft, rawRight], timestamp: now);
      final stable = stabilizer.processFrame([rawCenter, rawLeft, rawRight], timestamp: now.add(const Duration(milliseconds: 350)));
      final alert = engine.evaluate(stable, timestamp: now.add(const Duration(milliseconds: 350)));
      expect(alert, isNotNull);
      expect(alert!.spokenTextTa, equals('முன்னால் தடையுள்ளது. நின்றுவிடுங்கள்.'));
      expect(alert.action, equals(NavigationAction.stop));
    });

    test('7. CRITICAL distance: Expected "முன்னால் தடையுள்ளது. நின்றுவிடுங்கள்."', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final rawClose = createRawDetection(
        label: 'wall',
        xCenter: 0.50,
        xMin: 0.20,
        xMax: 0.80,
        yMin: 0.10,
        yMax: 0.90,
        distanceM: 0.6, // < 0.9m
        isWall: true,
      );
      final stable = stabilizer.processFrame([rawClose], timestamp: now);
      final alert = engine.evaluate(stable, timestamp: now);
      expect(alert, isNotNull);
      expect(alert!.spokenTextTa, equals('முன்னால் தடையுள்ளது. நின்றுவிடுங்கள்.'));
      expect(alert.action, equals(NavigationAction.stop));
    });

    test('8. Same CLEAR state: Must NOT repeatedly speak every frame; speaks on 10s heartbeat', () async {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      final clearAlert = engine.createClearAlert(t0);

      // Frame 1: Speaks clear confirmation
      await voiceAlert.processAlert(clearAlert, timestamp: t0);
      expect(voiceAlert.currentDebugInfo.announcement, equals('முன்னால் பாதை தெளிவாக உள்ளது. செல்லலாம்.'));

      // Next frames within 9 seconds: must NOT repeat
      for (int sec = 1; sec <= 9; sec++) {
        final t = t0.add(Duration(seconds: sec));
        await voiceAlert.processAlert(clearAlert, timestamp: t);
        expect(voiceAlert.currentDebugInfo.voiceState, equals('MONITORING SILENTLY'));
      }

      // At 10 seconds: heartbeat confirmation fires
      final t10 = t0.add(const Duration(seconds: 10));
      await voiceAlert.processAlert(clearAlert, timestamp: t10);
      expect(voiceAlert.currentDebugInfo.voiceState, equals('ANNOUNCED'));
      expect(voiceAlert.currentDebugInfo.announcement, equals('முன்னால் பாதை தெளிவாக உள்ளது. செல்லலாம்.'));
    });

    test('9. Same obstacle state: Must NOT repeatedly speak', () async {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      final rawLeft = createRawDetection(label: 'obstacle', xCenter: 0.20, xMin: 0.10, xMax: 0.30, yMin: 0.2, yMax: 0.8);
      stabilizer.processFrame([rawLeft], timestamp: t0);
      final stable = stabilizer.processFrame([rawLeft], timestamp: t0.add(const Duration(milliseconds: 350)));
      final alert = engine.evaluate(stable, timestamp: t0.add(const Duration(milliseconds: 350)));

      // First time: speaks
      final t1 = t0.add(const Duration(milliseconds: 350));
      await voiceAlert.processAlert(alert, timestamp: t1);
      expect(voiceAlert.currentDebugInfo.announcement, equals('இடப்பக்கம் தடையுள்ளது. வலப்பக்கம் செல்லுங்கள்.'));

      // Subsequent identical frames: SILENT
      for (int sec = 1; sec <= 5; sec++) {
        final t = t1.add(Duration(seconds: sec));
        await voiceAlert.processAlert(alert, timestamp: t);
        expect(voiceAlert.currentDebugInfo.voiceState, equals('MONITORING SILENTLY'));
      }
    });

    test('10. Direction change: Must speak new direction', () async {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      final rawLeft = createRawDetection(label: 'obstacle', xCenter: 0.20, xMin: 0.10, xMax: 0.30, yMin: 0.2, yMax: 0.8);
      stabilizer.processFrame([rawLeft], timestamp: t0);
      final stableLeft = stabilizer.processFrame([rawLeft], timestamp: t0.add(const Duration(milliseconds: 350)));
      final alertLeft = engine.evaluate(stableLeft, timestamp: t0.add(const Duration(milliseconds: 350)));
      await voiceAlert.processAlert(alertLeft, timestamp: t0.add(const Duration(milliseconds: 350)));
      expect(voiceAlert.currentDebugInfo.announcement, equals('இடப்பக்கம் தடையுள்ளது. வலப்பக்கம் செல்லுங்கள்.'));

      // Moves to right
      final tRight = t0.add(const Duration(seconds: 4));
      final rawRight = createRawDetection(label: 'obstacle', xCenter: 0.80, xMin: 0.70, xMax: 0.90, yMin: 0.2, yMax: 0.8);
      stabilizer.processFrame([rawRight], timestamp: tRight);
      final stableRight = stabilizer.processFrame([rawRight], timestamp: tRight.add(const Duration(milliseconds: 400)));
      final alertRight = engine.evaluate(stableRight, timestamp: tRight.add(const Duration(milliseconds: 400)));
      await voiceAlert.processAlert(alertRight, timestamp: tRight.add(const Duration(milliseconds: 400)));
      expect(voiceAlert.currentDebugInfo.announcement, equals('வலப்பக்கம் தடையுள்ளது. இடப்பக்கம் செல்லுங்கள்.'));
    });

    test('11. Obstacle disappears: After stabilization grace period, announce clear path', () async {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      final rawCenter = createRawDetection(label: 'obstacle', xCenter: 0.50, xMin: 0.40, xMax: 0.60, yMin: 0.3, yMax: 0.7);
      stabilizer.processFrame([rawCenter], timestamp: t0);
      final stable = stabilizer.processFrame([rawCenter], timestamp: t0.add(const Duration(milliseconds: 350)));
      final alert = engine.evaluate(stable, timestamp: t0.add(const Duration(milliseconds: 350)));
      await voiceAlert.processAlert(alert, timestamp: t0.add(const Duration(milliseconds: 350)));

      // Obstacle disappears for 500ms (within 1500ms grace period) -> null (no oscillation)
      final tDropped = t0.add(const Duration(milliseconds: 850));
      final alertDropped = engine.evaluate([], timestamp: tDropped);
      expect(alertDropped, isNull);

      // Obstacle remains absent past 1500ms grace period and TTS speech watchdog -> announces CLEAR PATH!
      final tClear = t0.add(const Duration(milliseconds: 2500));
      final alertClear = engine.evaluate([], timestamp: tClear);
      expect(alertClear, isNotNull);
      expect(alertClear!.navState, equals(NavigationState.clear));
      expect(alertClear.spokenTextTa, equals('முன்னால் பாதை தெளிவாக உள்ளது. செல்லலாம்.'));

      await voiceAlert.processAlert(alertClear, timestamp: tClear);
      expect(voiceAlert.currentDebugInfo.announcement, equals('முன்னால் பாதை தெளிவாக உள்ளது. செல்லலாம்.'));
    });

    test('12. TTS engine prefers ta-IN and provides startup/stop Tamil voice', () async {
      await voiceAlert.speakStartup();
      await voiceAlert.speakStop();
    });

    test('13. No English navigation strings anywhere in the voice message layer', () {
      final alertClear = engine.createClearAlert(DateTime.now());
      expect(alertClear.spokenTextTa.contains(RegExp(r'[a-zA-Z]')), isFalse);

      final rawObj = createRawDetection(label: 'obstacle', xCenter: 0.50, xMin: 0.40, xMax: 0.60, yMin: 0.3, yMax: 0.7);
      final stable = stabilizer.processFrame([rawObj], timestamp: DateTime.now());
      final alertObj = engine.evaluate(stable, timestamp: DateTime.now());
      if (alertObj != null) {
        expect(alertObj.spokenTextTa.contains(RegExp(r'[a-zA-Z]')), isFalse);
      }
    });

    test('Loki Known Person Tamil guidance (Section 7)', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final lokiObj = StabilizedObject(
        trackingId: 99,
        rawLabel: 'person_Loki',
        label: 'Loki',
        confidence: 0.95,
        xCenter: 0.50,
        yCenter: 0.50,
        xMin: 0.40,
        yMin: 0.20,
        xMax: 0.60,
        yMax: 0.80,
        relativeArea: 0.12,
        distanceM: 1.8,
        isWallHeuristic: false,
        isVehicle: false,
        firstSeen: now,
        lastSeen: now,
        consecutiveFrames: 3,
      );

      final alertAhead = engine.evaluate([lokiObj], timestamp: now);
      expect(alertAhead!.spokenTextTa, equals('லோகி முன்னால் இருக்கிறார். இடப்பக்கம் செல்லுங்கள்.'));

      final alertLeft = engine.evaluate([lokiObj.copyWith(trackingId: 100, xCenter: 0.20, xMin: 0.10, xMax: 0.30)], timestamp: now);
      expect(alertLeft!.spokenTextTa, equals('லோகி இடப்பக்கத்தில் இருக்கிறார். வலப்பக்கம் செல்லுங்கள்.'));

      final alertRight = engine.evaluate([lokiObj.copyWith(trackingId: 101, xCenter: 0.80, xMin: 0.70, xMax: 0.90)], timestamp: now);
      expect(alertRight!.spokenTextTa, equals('லோகி வலப்பக்கத்தில் இருக்கிறார். இடப்பக்கம் செல்லுங்கள்.'));

      final alertClose = engine.evaluate([lokiObj.copyWith(trackingId: 102, distanceM: 0.5, relativeArea: 0.25)], timestamp: now);
      expect(alertClose!.spokenTextTa, equals('லோகி மிகவும் அருகில் இருக்கிறார். நின்றுவிடுங்கள்.'));
    });
  });
}
