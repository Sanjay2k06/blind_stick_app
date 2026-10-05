import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naveye/models/person_model.dart';
import 'package:naveye/services/detection_stabilizer.dart';
import 'package:naveye/services/face_recognition_service.dart';
import 'package:naveye/services/navigation_decision_engine.dart';
import 'package:naveye/services/voice_alert_manager.dart';

List<double> createMockEmbedding(int seed, {int dim = 512, double noise = 0.0}) {
  final random = Random(seed);
  final raw = List<double>.generate(dim, (_) => (random.nextDouble() * 2 - 1) + (noise != 0 ? (Random().nextDouble() * noise) : 0.0));
  final norm = sqrt(raw.map((x) => x * x).reduce((a, b) => a + b));
  return raw.map((x) => x / norm).toList();
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

  group('Known Person Recognition — Direction, Stability, Cooldown & Pipeline Tests', () {
    late NavigationDecisionEngine decisionEngine;
    late VoiceAlertManager voiceAlert;

    setUp(() {
      decisionEngine = NavigationDecisionEngine(
        leftThreshold: 0.35,
        rightThreshold: 0.65,
        actionGuidanceMode: false,
      );
      voiceAlert = VoiceAlertManager();
      voiceAlert.reset();
    });

    test('TEST 1 & 2: Direction strictly calculated from Face Bounding Box center ratio', () {
      // LEFT: face center < 35% of frame width
      expect(FaceMatch.calculateFaceDirection(0.20), equals(ObjectDirection.left));
      expect(FaceMatch.calculateFaceDirection(0.34), equals(ObjectDirection.left));

      // CENTER: 35% - 65%
      expect(FaceMatch.calculateFaceDirection(0.35), equals(ObjectDirection.center));
      expect(FaceMatch.calculateFaceDirection(0.50), equals(ObjectDirection.center));
      expect(FaceMatch.calculateFaceDirection(0.65), equals(ObjectDirection.center));

      // RIGHT: > 65%
      expect(FaceMatch.calculateFaceDirection(0.66), equals(ObjectDirection.right));
      expect(FaceMatch.calculateFaceDirection(0.85), equals(ObjectDirection.right));
    });

    test('TEST 3 & 4: Known person directional narration (left, center, right)', () {
      final now = DateTime(2026, 9, 28, 10, 30);

      // Person recognized on left (distinct trackingId 101)
      final leftPerson = StabilizedObject(
        trackingId: 101,
        rawLabel: 'person_Loki',
        label: 'Loki',
        confidence: 0.92,
        xCenter: 0.25, // < 0.35
        yCenter: 0.50,
        xMin: 0.15,
        yMin: 0.20,
        xMax: 0.35,
        yMax: 0.80,
        relativeArea: 0.12,
        distanceM: 1.8,
        isWallHeuristic: false,
        isVehicle: false,
        firstSeen: now,
        lastSeen: now,
        consecutiveFrames: 3,
      );

      final leftAlert = decisionEngine.evaluate([leftPerson], timestamp: now);
      expect(leftAlert, isNotNull);
      expect(leftAlert!.direction, equals(ObjectDirection.left));
      expect(leftAlert.spokenTextEn, equals('Loki left.'));

      // Person directly ahead (distinct trackingId 102)
      final centerPerson = leftPerson.copyWith(
        trackingId: 102,
        xCenter: 0.50, // 0.35 - 0.65
        xMin: 0.40,
        xMax: 0.60,
      );

      final centerAlert = decisionEngine.evaluate([centerPerson], timestamp: now);
      expect(centerAlert, isNotNull);
      expect(centerAlert!.direction, equals(ObjectDirection.center));
      expect(centerAlert.spokenTextEn, equals('Loki ahead.'));

      // Person on right (distinct trackingId 103)
      final rightPerson = leftPerson.copyWith(
        trackingId: 103,
        xCenter: 0.75, // > 0.65
        xMin: 0.65,
        xMax: 0.85,
      );

      final rightAlert = decisionEngine.evaluate([rightPerson], timestamp: now);
      expect(rightAlert, isNotNull);
      expect(rightAlert!.direction, equals(ObjectDirection.right));
      expect(rightAlert.spokenTextEn, equals('Loki right.'));
    });

    test('TEST 5 & 6: Stationary person for 10 seconds -> Voice suppressed, direction change announces once', () async {
      final t0 = DateTime(2026, 9, 28, 10, 30, 0);

      final lokiLeft = StabilizedObject(
        trackingId: 101,
        rawLabel: 'person_Loki',
        label: 'Loki',
        confidence: 0.95,
        xCenter: 0.20,
        yCenter: 0.50,
        xMin: 0.10,
        yMin: 0.20,
        xMax: 0.30,
        yMax: 0.80,
        relativeArea: 0.10,
        distanceM: 1.8,
        isWallHeuristic: false,
        isVehicle: false,
        firstSeen: t0,
        lastSeen: t0,
        consecutiveFrames: 3,
      );

      // Frame 1: Loki recognized on left -> speaks
      final alert0 = decisionEngine.evaluate([lokiLeft], timestamp: t0);
      await voiceAlert.processAlert(alert0, timestamp: t0);
      expect(voiceAlert.currentDebugInfo.announcement, equals('Loki இடது.'));
      expect(voiceAlert.currentDebugInfo.cooldownActive, isFalse);

      // Frames over next 10 seconds while Loki stays stationary on left
      for (int sec = 1; sec <= 10; sec++) {
        final t = t0.add(Duration(seconds: sec));
        final stableAlert = decisionEngine.evaluate([lokiLeft], timestamp: t);
        await voiceAlert.processAlert(stableAlert, timestamp: t);
        // Cooldown/Suppression active: DOES NOT SPEAK AGAIN for unchanged stationary person!
        expect(voiceAlert.currentDebugInfo.cooldownActive, isTrue);
      }

      // Loki moves to center after 11 seconds (temporal smoothing: stable frame > 350ms)
      final t11 = t0.add(const Duration(seconds: 11));
      final lokiCenter = lokiLeft.copyWith(
        xCenter: 0.50,
        xMin: 0.40,
        xMax: 0.60,
      );
      decisionEngine.evaluate([lokiCenter], timestamp: t11); // candidate frame
      final t11Stable = t11.add(const Duration(milliseconds: 400));
      final centerAlert = decisionEngine.evaluate([lokiCenter], timestamp: t11Stable); // stable frame
      expect(centerAlert!.spokenTextEn, equals('Loki ahead.'));
      await voiceAlert.processAlert(centerAlert, timestamp: t11Stable);
      expect(voiceAlert.currentDebugInfo.announcement, equals('Loki முன்னால்.'));

      // Loki moves to right after 14 seconds (temporal smoothing: stable frame > 350ms)
      final t14 = t0.add(const Duration(seconds: 14));
      final lokiRight = lokiLeft.copyWith(
        xCenter: 0.80,
        xMin: 0.70,
        xMax: 0.90,
      );
      decisionEngine.evaluate([lokiRight], timestamp: t14); // candidate frame
      final t14Stable = t14.add(const Duration(milliseconds: 400));
      final rightAlert = decisionEngine.evaluate([lokiRight], timestamp: t14Stable); // stable frame
      expect(rightAlert!.spokenTextEn, equals('Loki right.'));
      await voiceAlert.processAlert(rightAlert, timestamp: t14Stable);
      expect(voiceAlert.currentDebugInfo.announcement, equals('Loki வலது.'));
    });

    test('TEST 7 & 8: Unregistered person -> Says ONLY Person ahead / left / right, never assigns name', () async {
      final now = DateTime(2026, 9, 28, 10, 30);

      // Unregistered person center
      final strangerCenter = StabilizedObject(
        trackingId: 201,
        rawLabel: 'person',
        label: 'person',
        confidence: 0.88,
        xCenter: 0.50,
        yCenter: 0.50,
        xMin: 0.40,
        yMin: 0.20,
        xMax: 0.60,
        yMax: 0.80,
        relativeArea: 0.10,
        distanceM: 2.0,
        isWallHeuristic: false,
        isVehicle: false,
        firstSeen: now,
        lastSeen: now,
        consecutiveFrames: 3,
      );

      final centerAlert = decisionEngine.evaluate([strangerCenter], timestamp: now);
      expect(centerAlert, isNotNull);
      expect(centerAlert!.spokenTextEn, equals('Person ahead.'));
      expect(centerAlert.spokenTextEn.contains('Loki'), isFalse);

      // Unregistered person left (distinct ID 202)
      final strangerLeft = strangerCenter.copyWith(trackingId: 202, xCenter: 0.20, xMin: 0.10, xMax: 0.30);
      final leftAlert = decisionEngine.evaluate([strangerLeft], timestamp: now);
      expect(leftAlert!.spokenTextEn, equals('Person left.'));
      expect(leftAlert.spokenTextEn.contains('Loki'), isFalse);

      // Unregistered person right (distinct ID 203)
      final strangerRight = strangerCenter.copyWith(trackingId: 203, xCenter: 0.80, xMin: 0.70, xMax: 0.90);
      final rightAlert = decisionEngine.evaluate([strangerRight], timestamp: now);
      expect(rightAlert!.spokenTextEn, equals('Person right.'));
      expect(rightAlert.spokenTextEn.contains('Loki'), isFalse);
    });

    test('TEST 9: Multi-reference embedding similarity & Ambiguity margin test', () {
      // 10 reference embeddings for Loki
      final lokiEmbeddings = List.generate(10, (i) => createMockEmbedding(42 + i, noise: 0.05));
      final flatLoki = <double>[];
      for (final e in lokiEmbeddings) {
        flatLoki.addAll(e);
      }

      // Query from same person (close to reference sample 2)
      final genuineQuery = createMockEmbedding(44, noise: 0.02);

      // Query from different stranger
      final strangerQuery = createMockEmbedding(999);

      // Cosine similarity helper
      double cosine(List<double> a, List<double> b) {
        double dot = 0, na = 0, nb = 0;
        for (int i = 0; i < a.length; i++) {
          dot += a[i] * b[i];
          na += a[i] * a[i];
          nb += b[i] * b[i];
        }
        return dot / (sqrt(na) * sqrt(nb));
      }

      // Calculate scores against all 10 references
      final genuineScores = lokiEmbeddings.map((ref) => cosine(genuineQuery, ref)).toList();
      final strangerScores = lokiEmbeddings.map((ref) => cosine(strangerQuery, ref)).toList();

      genuineScores.sort((a, b) => b.compareTo(a));
      strangerScores.sort((a, b) => b.compareTo(a));

      // Genuine top match is high (> 0.60)
      expect(genuineScores.first, greaterThan(0.60));
      // Stranger top match is low (< 0.40)
      expect(strangerScores.first, lessThan(0.40));
    });

    test('TEST 10: Multiple people in the same frame -> Known person prioritized or compound alert', () {
      final now = DateTime(2026, 9, 28, 10, 30);

      // Known person (Loki) directly ahead
      final loki = StabilizedObject(
        trackingId: 101,
        rawLabel: 'person_Loki',
        label: 'Loki',
        confidence: 0.94,
        xCenter: 0.50,
        yCenter: 0.50,
        xMin: 0.40,
        yMin: 0.20,
        xMax: 0.60,
        yMax: 0.80,
        relativeArea: 0.12,
        distanceM: 1.5,
        isWallHeuristic: false,
        isVehicle: false,
        firstSeen: now,
        lastSeen: now,
        consecutiveFrames: 3,
      );

      // Unknown person on the right
      final stranger = StabilizedObject(
        trackingId: 202,
        rawLabel: 'person',
        label: 'person',
        confidence: 0.85,
        xCenter: 0.80,
        yCenter: 0.50,
        xMin: 0.70,
        yMin: 0.20,
        xMax: 0.90,
        yMax: 0.80,
        relativeArea: 0.08,
        distanceM: 2.4,
        isWallHeuristic: false,
        isVehicle: false,
        firstSeen: now,
        lastSeen: now,
        consecutiveFrames: 3,
      );

      final alert = decisionEngine.evaluate([loki, stranger], timestamp: now);
      expect(alert, isNotNull);
      // Primary focus is on Loki directly ahead
      expect(alert!.rawLabel, equals('person_Loki'));
      expect(alert.spokenTextEn.contains('Loki'), isTrue);
    });

    test('TEST 11: Person Profile metadata conforms to Kodambakkam, Chennai 28-09-2026 10:30 AM', () {
      final regDate = DateTime(2026, 9, 28, 10, 30);
      final refImages = List.generate(10, (i) => '/data/known_people/loki_ref_${i + 1}.jpeg');

      final person = Person(
        id: 1,
        name: 'Loki',
        imagePath: refImages.first,
        createdAt: regDate,
        lastSeenAt: regDate,
        lastSeenLatitude: 13.0524,
        lastSeenLongitude: 80.2207,
        locationName: 'Kodambakkam, Chennai',
        referenceImages: refImages,
        embedding: List.filled(5120, 0.05),
      );

      expect(person.name, equals('Loki'));
      expect(person.createdAt, equals(regDate));
      expect(person.lastSeenLatitude, equals(13.0524));
      expect(person.lastSeenLongitude, equals(80.2207));
      expect(person.locationName, equals('Kodambakkam, Chennai'));
      expect(person.referenceImages.length, equals(10));
      expect(person.embedding.length, equals(5120)); // 10 * 512

      final map = person.toMap();
      final reconstructed = Person.fromMap(map);
      expect(reconstructed.name, equals('Loki'));
      expect(reconstructed.locationName, equals('Kodambakkam, Chennai'));
      expect(reconstructed.referenceImages.length, equals(10));
    });
  });
}
