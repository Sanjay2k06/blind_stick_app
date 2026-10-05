import 'package:flutter_test/flutter_test.dart';
import 'package:naveye/services/detector_service.dart';
import 'package:naveye/services/path_guidance_service.dart';

DetectionResult createObstacle({
  required String label,
  required double xCenter,
  required double xMin,
  required double xMax,
  required double distanceM,
}) {
  return DetectionResult(
    label: label,
    rawLabel: label.toLowerCase(),
    confidence: 0.90,
    direction: xCenter < 0.35 ? 'left' : xCenter > 0.65 ? 'right' : 'centre',
    distance: '${distanceM.toStringAsFixed(1)}m',
    distanceM: distanceM,
    xCenter: xCenter,
    xMin: xMin,
    xMax: xMax,
  );
}

void main() {
  late PathGuidanceService guidanceService;

  setUp(() {
    guidanceService = PathGuidanceService();
  });

  group('PathGuidanceService — Directional Logic & Safety Rules', () {
    test('Rule 1: All zones clear -> GO STRAIGHT', () {
      final decision = guidanceService.evaluatePath([]);
      expect(decision.direction, SafeDirection.straight);
      expect(decision.isImmediateStop, isFalse);
      expect(decision.spokenDirectiveEn, contains('GO STRAIGHT'));
      expect(decision.spokenDirectiveTa, contains('நேராகச் செல்லுங்கள்'));
      expect(decision.leftBlocked, isFalse);
      expect(decision.centerBlocked, isFalse);
      expect(decision.rightBlocked, isFalse);
    });

    test('Rule 2: Center clear, obstacle on left -> GO STRAIGHT with left warning', () {
      final leftObstacle = createObstacle(
        label: 'chair',
        xCenter: 0.20,
        xMin: 0.10,
        xMax: 0.28,
        distanceM: 2.5,
      );

      final decision = guidanceService.evaluatePath([leftObstacle]);
      expect(decision.direction, SafeDirection.straight);
      expect(decision.leftBlocked, isTrue);
      expect(decision.centerBlocked, isFalse);
      expect(decision.rightBlocked, isFalse);
      expect(decision.spokenDirectiveEn, contains('OBSTACLE ON LEFT. GO STRAIGHT.'));
      expect(decision.spokenDirectiveTa, contains('இடதுபுறம் தடை. நேராகச் செல்லுங்கள்.'));
    });

    test('Rule 3: Center clear, obstacle on right -> GO STRAIGHT with right warning', () {
      final rightObstacle = createObstacle(
        label: 'bench',
        xCenter: 0.80,
        xMin: 0.72,
        xMax: 0.88,
        distanceM: 2.0,
      );

      final decision = guidanceService.evaluatePath([rightObstacle]);
      expect(decision.direction, SafeDirection.straight);
      expect(decision.leftBlocked, isFalse);
      expect(decision.centerBlocked, isFalse);
      expect(decision.rightBlocked, isTrue);
      expect(decision.spokenDirectiveEn, contains('OBSTACLE ON RIGHT. GO STRAIGHT.'));
      expect(decision.spokenDirectiveTa, contains('வலதுபுறம் தடை. நேராகச் செல்லுங்கள்.'));
    });

    test('Rule 4: Center clear, obstacles on both left and right -> NARROW PATH', () {
      final leftObs = createObstacle(
        label: 'chair',
        xCenter: 0.18,
        xMin: 0.10,
        xMax: 0.26,
        distanceM: 2.0,
      );
      final rightObs = createObstacle(
        label: 'table',
        xCenter: 0.82,
        xMin: 0.74,
        xMax: 0.90,
        distanceM: 2.2,
      );

      final decision = guidanceService.evaluatePath([leftObs, rightObs]);
      expect(decision.direction, SafeDirection.straight);
      expect(decision.leftBlocked, isTrue);
      expect(decision.centerBlocked, isFalse);
      expect(decision.rightBlocked, isTrue);
      expect(decision.spokenDirectiveEn, contains('NARROW PATH. GO STRAIGHT CAREFULLY.'));
      expect(decision.spokenDirectiveTa, contains('குறுகிய பாதை'));
    });

    test('Rule 5: Center blocked & Right blocked & Left clear -> MOVE LEFT', () {
      final centerObs = createObstacle(
        label: 'person',
        xCenter: 0.50,
        xMin: 0.40,
        xMax: 0.60,
        distanceM: 1.8,
      );
      final rightObs = createObstacle(
        label: 'wall',
        xCenter: 0.85,
        xMin: 0.70,
        xMax: 0.98,
        distanceM: 1.5,
      );

      final decision = guidanceService.evaluatePath([centerObs, rightObs]);
      expect(decision.direction, SafeDirection.moveLeft);
      expect(decision.leftBlocked, isFalse);
      expect(decision.centerBlocked, isTrue);
      expect(decision.rightBlocked, isTrue);
      expect(decision.spokenDirectiveEn, contains('MOVE LEFT'));
      expect(decision.spokenDirectiveTa, contains('இடதுபுறம் செல்லுங்கள்'));
    });

    test('Rule 6: Center blocked & Left blocked & Right clear -> MOVE RIGHT', () {
      final centerObs = createObstacle(
        label: 'person',
        xCenter: 0.50,
        xMin: 0.38,
        xMax: 0.62,
        distanceM: 1.9,
      );
      final leftObs = createObstacle(
        label: 'bicycle',
        xCenter: 0.18,
        xMin: 0.05,
        xMax: 0.30,
        distanceM: 1.6,
      );

      final decision = guidanceService.evaluatePath([centerObs, leftObs]);
      expect(decision.direction, SafeDirection.moveRight);
      expect(decision.leftBlocked, isTrue);
      expect(decision.centerBlocked, isTrue);
      expect(decision.rightBlocked, isFalse);
      expect(decision.spokenDirectiveEn, contains('MOVE RIGHT'));
      expect(decision.spokenDirectiveTa, contains('வலதுபுறம் செல்லுங்கள்'));
    });

    test('Rule 7: Immediate danger (< 0.8m) -> STOP. OBSTACLE AHEAD', () {
      final dangerObs = createObstacle(
        label: 'chair',
        xCenter: 0.50,
        xMin: 0.35,
        xMax: 0.65,
        distanceM: 0.65, // < 0.8m
      );

      final decision = guidanceService.evaluatePath([dangerObs]);
      expect(decision.direction, SafeDirection.stop);
      expect(decision.isImmediateStop, isTrue);
      expect(decision.spokenDirectiveEn, contains('STOP'));
      expect(decision.spokenDirectiveTa, contains('நில்லுங்கள்'));
    });

    test('Rule 8: All corridors blocked -> STOP. PATH COMPLETELY BLOCKED', () {
      final obsLeft = createObstacle(label: 'wall', xCenter: 0.15, xMin: 0.0, xMax: 0.34, distanceM: 1.5);
      final obsCenter = createObstacle(label: 'gate', xCenter: 0.50, xMin: 0.35, xMax: 0.65, distanceM: 1.4);
      final obsRight = createObstacle(label: 'wall', xCenter: 0.85, xMin: 0.66, xMax: 1.0, distanceM: 1.6);

      final decision = guidanceService.evaluatePath([obsLeft, obsCenter, obsRight]);
      expect(decision.direction, SafeDirection.stop);
      expect(decision.isImmediateStop, isTrue);
      expect(decision.spokenDirectiveEn, contains('PATH COMPLETELY BLOCKED'));
      expect(decision.spokenDirectiveTa, contains('பாதை முழுமையாக அடைக்கப்பட்டுள்ளது'));
    });

    test('Rule 9: Center blocked with both Left and Right clear -> steers to clear side opposite bias', () {
      final obstacleLeaningRight = createObstacle(
        label: 'person',
        xCenter: 0.58, // leans right
        xMin: 0.45,
        xMax: 0.68,
        distanceM: 2.0,
      );

      final decision1 = guidanceService.evaluatePath([obstacleLeaningRight]);
      expect(decision1.direction, SafeDirection.moveLeft);

      final obstacleLeaningLeft = createObstacle(
        label: 'person',
        xCenter: 0.42, // leans left
        xMin: 0.32,
        xMax: 0.52,
        distanceM: 2.0,
      );

      final decision2 = guidanceService.evaluatePath([obstacleLeaningLeft]);
      expect(decision2.direction, SafeDirection.moveRight);
    });
  });

  group('PathGuidanceService — Announcement Throttling', () {
    test('Immediate stop always announces immediately', () {
      final now = DateTime.now();
      final stopDecision = guidanceService.evaluatePath([
        createObstacle(label: 'barrier', xCenter: 0.5, xMin: 0.3, xMax: 0.7, distanceM: 0.5),
      ]);

      expect(guidanceService.shouldAnnounce(stopDecision, now), isTrue);
    });

    test('Direction transition announces immediately without waiting for cooldown', () {
      final now = DateTime.now();
      // First announcement: Straight
      final straightDecision = guidanceService.evaluatePath([]);
      expect(guidanceService.shouldAnnounce(straightDecision, now), isTrue);

      // 500 ms later: Center blocked, must Move Left -> should announce immediately
      final moveLeftDecision = guidanceService.evaluatePath([
        createObstacle(label: 'box', xCenter: 0.5, xMin: 0.35, xMax: 0.65, distanceM: 1.5),
        createObstacle(label: 'wall', xCenter: 0.85, xMin: 0.7, xMax: 1.0, distanceM: 1.5),
      ]);
      expect(guidanceService.shouldAnnounce(moveLeftDecision, now.add(const Duration(milliseconds: 500))), isTrue);

      // Same direction within cooldown should NOT announce
      expect(guidanceService.shouldAnnounce(moveLeftDecision, now.add(const Duration(milliseconds: 1000))), isFalse);
    });
  });
}
