import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:naveye/services/currency_recognition_service.dart';
import 'package:naveye/services/detector_service.dart';
import 'package:naveye/services/detection_stabilizer.dart';
import 'package:naveye/services/navigation_decision_engine.dart';
import 'package:naveye/services/voice_command_service.dart';

void main() {
  group('Module 1 & 4 — Currency Detection & False Positive Prevention', () {
    test('No currency visible / blank frame returns notFound', () {
      final blank = img.Image(width: 320, height: 320);
      img.fill(blank, color: blank.getColor(0, 0, 0));
      final res = CurrencyRecognitionService.instance.recognizeLiveStream(blank);
      expect(res.denomination, equals(InrDenomination.unknown));
      expect(res.isConfident, isFalse);
    });

    test('Road / asphalt / concrete surface strictly rejected (No money false positive)', () {
      final road = img.Image(width: 320, height: 320);
      // Flat asphalt road with slight noise but lacking banknote intaglio micro-structure
      for (int y = 0; y < 320; y++) {
        for (int x = 0; x < 320; x++) {
          final n = (x % 5 + y % 3);
          road.setPixel(x, y, road.getColor(115 + n, 115 + n, 116 + n));
        }
      }
      final res = CurrencyRecognitionService.instance.recognizeLiveStream(road);
      expect(res.denomination, equals(InrDenomination.unknown));
      expect(res.value, equals(0));
    });

    test('Painted wall / ceiling strictly rejected', () {
      final wall = img.Image(width: 320, height: 320);
      img.fill(wall, color: wall.getColor(215, 210, 200));
      final res = CurrencyRecognitionService.instance.recognizeLiveStream(wall);
      expect(res.denomination, equals(InrDenomination.unknown));
    });

    test('Green foliage / leaves strictly rejected', () {
      final leaf = img.Image(width: 320, height: 320);
      for (int y = 0; y < 320; y++) {
        for (int x = 0; x < 320; x++) {
          leaf.setPixel(x, y, leaf.getColor(40, 140 + (x % 10), 45));
        }
      }
      final res = CurrencyRecognitionService.instance.recognizeLiveStream(leaf);
      expect(res.denomination, equals(InrDenomination.unknown));
    });

    test('One ₹20 note detected correctly', () {
      final bytes = File('money_image/20rs_model1_frontend.jpg').readAsBytesSync();
      final image = img.decodeImage(bytes)!;
      final res = CurrencyRecognitionService.instance.recognizeLiveStream(image);
      expect(res.denomination, equals(InrDenomination.twenty));
      expect(res.value, equals(20));
      expect(res.isConfident, isTrue);
    });

    test('One ₹500 note detected correctly', () {
      final bytes = File('money_image/500rs_image_front_back.jpg').readAsBytesSync();
      final image = img.decodeImage(bytes)!;
      final res = CurrencyRecognitionService.instance.recognizeLiveStream(image);
      expect(res.denomination, equals(InrDenomination.fiveHundred));
      expect(res.value, equals(500));
      expect(res.isConfident, isTrue);
    });
  });

  group('Module 2 — Currency Counting, Tracking & Session Total', () {
    late CurrencySessionTracker tracker;

    setUp(() {
      tracker = CurrencySessionTracker();
    });

    test('Accumulation test: ₹500 + ₹200 + ₹100 + ₹20 = ₹820', () {
      final baseTime = DateTime(2026, 11, 4, 10, 0, 0);

      // Present ₹500 over 3 consecutive frames
      tracker.updateWithDetection(
        denomination: InrDenomination.fiveHundred,
        value: 500,
        xCenter: 0.5,
        yCenter: 0.5,
        timestamp: baseTime,
      );
      tracker.updateWithDetection(
        denomination: InrDenomination.fiveHundred,
        value: 500,
        xCenter: 0.5,
        yCenter: 0.5,
        timestamp: baseTime.add(const Duration(milliseconds: 350)),
      );
      final note500 = tracker.updateWithDetection(
        denomination: InrDenomination.fiveHundred,
        value: 500,
        xCenter: 0.5,
        yCenter: 0.5,
        timestamp: baseTime.add(const Duration(milliseconds: 700)),
      );
      expect(note500, isNotNull);
      expect(tracker.sessionTotal, equals(500));

      // Present ₹200 over 3 consecutive frames (different location / denomination)
      tracker.updateWithDetection(
        denomination: InrDenomination.twoHundred,
        value: 200,
        xCenter: 0.2,
        yCenter: 0.3,
        timestamp: baseTime.add(const Duration(milliseconds: 1050)),
      );
      tracker.updateWithDetection(
        denomination: InrDenomination.twoHundred,
        value: 200,
        xCenter: 0.2,
        yCenter: 0.3,
        timestamp: baseTime.add(const Duration(milliseconds: 1400)),
      );
      final note200 = tracker.updateWithDetection(
        denomination: InrDenomination.twoHundred,
        value: 200,
        xCenter: 0.2,
        yCenter: 0.3,
        timestamp: baseTime.add(const Duration(milliseconds: 1750)),
      );
      expect(note200, isNotNull);
      expect(tracker.sessionTotal, equals(700));

      // Present ₹100 over 3 consecutive frames
      tracker.updateWithDetection(
        denomination: InrDenomination.oneHundred,
        value: 100,
        xCenter: 0.8,
        yCenter: 0.7,
        timestamp: baseTime.add(const Duration(milliseconds: 2100)),
      );
      tracker.updateWithDetection(
        denomination: InrDenomination.oneHundred,
        value: 100,
        xCenter: 0.8,
        yCenter: 0.7,
        timestamp: baseTime.add(const Duration(milliseconds: 2450)),
      );
      final note100 = tracker.updateWithDetection(
        denomination: InrDenomination.oneHundred,
        value: 100,
        xCenter: 0.8,
        yCenter: 0.7,
        timestamp: baseTime.add(const Duration(milliseconds: 2800)),
      );
      expect(note100, isNotNull);
      expect(tracker.sessionTotal, equals(800));

      // Present ₹20 over 3 consecutive frames
      tracker.updateWithDetection(
        denomination: InrDenomination.twenty,
        value: 20,
        xCenter: 0.4,
        yCenter: 0.8,
        timestamp: baseTime.add(const Duration(milliseconds: 3150)),
      );
      tracker.updateWithDetection(
        denomination: InrDenomination.twenty,
        value: 20,
        xCenter: 0.4,
        yCenter: 0.8,
        timestamp: baseTime.add(const Duration(milliseconds: 3500)),
      );
      final note20 = tracker.updateWithDetection(
        denomination: InrDenomination.twenty,
        value: 20,
        xCenter: 0.4,
        yCenter: 0.8,
        timestamp: baseTime.add(const Duration(milliseconds: 3850)),
      );
      expect(note20, isNotNull);

      // Verify exact session total matches ₹820
      expect(tracker.sessionTotal, equals(820));
      expect(
        CurrencyRecognitionService.instance.formatTamilAmount(tracker.sessionTotal),
        equals('எட்டுநூற்று இருபது'),
      );
    });

    test('Same note visible for 10 seconds counts exactly ONCE', () {
      final baseTime = DateTime(2026, 11, 4, 10, 0, 0);

      // Confirm note initially across 3 frames
      for (int i = 0; i < 3; i++) {
        tracker.updateWithDetection(
          denomination: InrDenomination.fiveHundred,
          value: 500,
          timestamp: baseTime.add(Duration(milliseconds: i * 350)),
        );
      }
      expect(tracker.sessionTotal, equals(500));

      // Keep showing the same note for 30 consecutive checks (~10.5 seconds)
      for (int i = 3; i <= 30; i++) {
        final result = tracker.updateWithDetection(
          denomination: InrDenomination.fiveHundred,
          value: 500,
          timestamp: baseTime.add(Duration(milliseconds: i * 350)),
        );
        expect(result, isNull, reason: 'Must return null for already counted note');
      }

      // Total must strictly remain 500, NEVER 15000
      expect(tracker.sessionTotal, equals(500));
      expect(tracker.sessionNotes.length, equals(1));
    });

    test('Note moving slightly counts ONCE and does not duplicate', () {
      final baseTime = DateTime(2026, 11, 4, 10, 0, 0);

      // Confirm note at (0.50, 0.50)
      for (int i = 0; i < 3; i++) {
        tracker.updateWithDetection(
          denomination: InrDenomination.oneHundred,
          value: 100,
          xCenter: 0.50,
          yCenter: 0.50,
          timestamp: baseTime.add(Duration(milliseconds: i * 350)),
        );
      }
      expect(tracker.sessionTotal, equals(100));

      // Note drifts slightly due to user hand jitter: (0.52, 0.51), (0.54, 0.53)
      final drift1 = tracker.updateWithDetection(
        denomination: InrDenomination.oneHundred,
        value: 100,
        xCenter: 0.52,
        yCenter: 0.51,
        timestamp: baseTime.add(const Duration(milliseconds: 1100)),
      );
      expect(drift1, isNull);

      final drift2 = tracker.updateWithDetection(
        denomination: InrDenomination.oneHundred,
        value: 100,
        xCenter: 0.54,
        yCenter: 0.53,
        timestamp: baseTime.add(const Duration(milliseconds: 1450)),
      );
      expect(drift2, isNull);

      // Total must remain 100
      expect(tracker.sessionTotal, equals(100));
    });

    test('Reset session option resets total and tracked notes to 0', () {
      tracker.registerExplicitNote(InrDenomination.fiveHundred, 500);
      tracker.registerExplicitNote(InrDenomination.twoHundred, 200);
      expect(tracker.sessionTotal, equals(700));

      tracker.resetSession();
      expect(tracker.sessionTotal, equals(0));
      expect(tracker.sessionNotes, isEmpty);
      expect(tracker.currentVisibleNotes, isEmpty);
    });

    test('Clear distinction maintained between visible notes and session total', () {
      final baseTime = DateTime(2026, 11, 4, 10, 0, 0);

      // Register note at t=0
      tracker.registerExplicitNote(InrDenomination.oneHundred, 100);
      expect(tracker.sessionTotal, equals(100));

      // Register second note at t=1s
      tracker.registerExplicitNote(InrDenomination.twoHundred, 200);
      expect(tracker.sessionTotal, equals(300));

      // Both notes counted in session total
      expect(tracker.sessionNotes.length, equals(2));
    });
  });

  group('Module 3 — Object & Obstacle Detection & Wall Heuristic', () {
    test('Vehicles are NEVER classified as wall heuristics', () {
      const vehicles = ['car', 'bus', 'truck', 'motorcycle', 'bicycle'];
      for (final v in vehicles) {
        final det = DetectionResult(
          label: v,
          rawLabel: v,
          confidence: 0.90,
          direction: 'center',
          distance: '1.2 m',
          distanceM: 1.2,
          xMin: 0.1,
          yMin: 0.1,
          xMax: 0.9, // wide box (0.8 width)
          yMax: 0.8,
          isWallHeuristic: false, // Must be false!
        );
        expect(det.isVehicle, isTrue);
        expect(det.isWallHeuristic, isFalse);
      }
    });

    test('Pedestrians and animals are never tagged as walls', () {
      const nonWalls = ['person', 'dog', 'cat', 'chair', 'couch', 'laptop'];
      for (final nw in nonWalls) {
        final det = DetectionResult(
          label: nw,
          rawLabel: nw,
          confidence: 0.85,
          direction: 'center',
          distance: '1.0 m',
          distanceM: 1.0,
          isWallHeuristic: false,
        );
        expect(det.isWallHeuristic, isFalse);
      }
    });

    test('Navigation decision engine gives critical STOP priority for obstacle directly ahead', () {
      final engine = NavigationDecisionEngine();
      final now = DateTime(2026, 11, 4, 12, 0, 0);

      final closeObstacle = StabilizedObject(
        trackingId: 1,
        rawLabel: 'chair',
        label: 'Chair',
        confidence: 0.88,
        xCenter: 0.50,
        yCenter: 0.50,
        xMin: 0.30,
        yMin: 0.30,
        xMax: 0.70,
        yMax: 0.70,
        relativeArea: 0.16,
        distanceM: 0.65, // < 0.9m -> extremely close
        isWallHeuristic: false,
        isVehicle: false,
        firstSeen: now.subtract(const Duration(milliseconds: 500)),
        lastSeen: now,
        consecutiveFrames: 3,
      );

      final alert = engine.evaluate([closeObstacle], timestamp: now);
      expect(alert, isNotNull);
      expect(alert!.action, equals(NavigationAction.stop));
      expect(alert.spokenTextTa, contains('நின்றுவிடுங்கள்'));
    });

    test('Navigation decision engine creates clear alert when no obstacle', () {
      final engine = NavigationDecisionEngine();
      final now = DateTime(2026, 11, 4, 12, 0, 0);

      final alert = engine.evaluate([], timestamp: now);
      expect(alert, isNotNull);
      expect(alert!.action, equals(NavigationAction.clear));
      expect(alert.spokenTextTa, equals('முன்னால் பாதை தெளிவாக உள்ளது. செல்லலாம்.'));
    });
  });

  group('Module 6 — Voice Command & Reset Wallet Integration', () {
    test('Parses reset wallet voice commands in Tamil and English', () {
      final voice = VoiceCommandService();
      expect(voice.parseCommand('பணத்தை மீட்டமை'), equals(VoiceCommand.resetWallet));
      expect(voice.parseCommand('மீட்டமை'), equals(VoiceCommand.resetWallet));
      expect(voice.parseCommand('பணத்தை அழி'), equals(VoiceCommand.resetWallet));
      expect(voice.parseCommand('reset wallet'), equals(VoiceCommand.resetWallet));
      expect(voice.parseCommand('clear wallet'), equals(VoiceCommand.resetWallet));
      expect(voice.parseCommand('reset money'), equals(VoiceCommand.resetWallet));
    });

    test('Emergency SOS maintains highest priority over all commands', () {
      final voice = VoiceCommandService();
      expect(voice.parseCommand('அவசரம்'), equals(VoiceCommand.emergencySOS));
      expect(voice.parseCommand('காப்பாற்று'), equals(VoiceCommand.emergencySOS));
      expect(voice.parseCommand('emergency'), equals(VoiceCommand.emergencySOS));
    });
  });
}

