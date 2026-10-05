import 'dart:math' as math;
import 'detector_service.dart';

/// Available movement recommendations
enum SafeDirection {
  straight,
  moveLeft,
  moveRight,
  stop,
  pathUnclear,
}

/// Evaluation result for a frame's directional zones
class PathGuidanceDecision {
  final SafeDirection direction;
  final String spokenDirectiveEn;
  final String spokenDirectiveTa;
  final bool isImmediateStop;
  final bool leftBlocked;
  final bool centerBlocked;
  final bool rightBlocked;
  final double? closestObstacleDist;
  final String? primaryObstacleLabel;

  const PathGuidanceDecision({
    required this.direction,
    required this.spokenDirectiveEn,
    required this.spokenDirectiveTa,
    required this.isImmediateStop,
    required this.leftBlocked,
    required this.centerBlocked,
    required this.rightBlocked,
    this.closestObstacleDist,
    this.primaryObstacleLabel,
  });

  String spokenDirective({bool isTamil = false}) =>
      isTamil ? spokenDirectiveTa : spokenDirectiveEn;
}

/// Intelligent Real-Time Path Guidance Service
/// Divides path into LEFT, CENTER, RIGHT corridors and determines
/// safe movement vectors with multi-obstacle spatial awareness.
class PathGuidanceService {
  SafeDirection? _lastDirection;
  DateTime _lastDirectiveTime = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastSpokenEn = '';

  // Minimum gap between non-emergency repeated voice directives
  static const int _guidanceRepeatCooldownMs = 3500;

  /// Evaluates all detected objects and determines the safest immediate movement.
  PathGuidanceDecision evaluatePath(List<DetectionResult> detections) {
    if (detections.isEmpty) {
      return const PathGuidanceDecision(
        direction: SafeDirection.straight,
        spokenDirectiveEn: 'PATH CLEAR. GO STRAIGHT.',
        spokenDirectiveTa: 'பாதை தெளிவாக உள்ளது. நேராகச் செல்லுங்கள்.',
        isImmediateStop: false,
        leftBlocked: false,
        centerBlocked: false,
        rightBlocked: false,
      );
    }

    // Filter relevant obstacles within path relevance range (<= 3.5 metres)
    // Small carried objects that don't block walking are excluded from path-blocking
    final obstacles = detections.where((d) {
      if (d.distanceM > 3.5) return false;
      final raw = d.rawLabel.toLowerCase();
      // Items that don't block the path on ground
      if (const {'cell phone', 'remote', 'clock', 'fork', 'knife', 'spoon', 'book'}.contains(raw)) {
        return false;
      }
      return true;
    }).toList();

    if (obstacles.isEmpty) {
      return const PathGuidanceDecision(
        direction: SafeDirection.straight,
        spokenDirectiveEn: 'PATH CLEAR. GO STRAIGHT.',
        spokenDirectiveTa: 'பாதை தெளிவாக உள்ளது. நேராகச் செல்லுங்கள்.',
        isImmediateStop: false,
        leftBlocked: false,
        centerBlocked: false,
        rightBlocked: false,
      );
    }

    // Zone clearance tracking:
    // Left zone:   0.00 <= x < 0.35
    // Center zone: 0.30 <= x <= 0.70 (corridor)
    // Right zone:  0.65 < x <= 1.00
    bool leftBlocked = false;
    bool centerBlocked = false;
    bool rightBlocked = false;

    double closestDist = 100.0;
    DetectionResult? closestObstacle;

    double closestLeftDist = 100.0;
    double closestCenterDist = 100.0;
    double closestRightDist = 100.0;

    for (final obs in obstacles) {
      final d = obs.distanceM;
      if (d < closestDist) {
        closestDist = d;
        closestObstacle = obs;
      }

      // Check which zones this obstacle spans
      final spansLeft = obs.xMin < 0.35 || obs.xCenter < 0.35;
      final spansCenter = (obs.xMin <= 0.65 && obs.xMax >= 0.35) ||
          (obs.xCenter >= 0.30 && obs.xCenter <= 0.70);
      final spansRight = obs.xMax > 0.65 || obs.xCenter > 0.65;

      if (spansLeft) {
        leftBlocked = true;
        closestLeftDist = math.min(closestLeftDist, d);
      }
      if (spansCenter) {
        centerBlocked = true;
        closestCenterDist = math.min(closestCenterDist, d);
      }
      if (spansRight) {
        rightBlocked = true;
        closestRightDist = math.min(closestRightDist, d);
      }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // SAFETY RULE 1: Immediate danger (< 0.8 m) in or near center corridor
    // ──────────────────────────────────────────────────────────────────────────
    if (closestDist < 0.8) {
      final label = closestObstacle?.label ?? 'Obstacle';
      return PathGuidanceDecision(
        direction: SafeDirection.stop,
        spokenDirectiveEn: 'STOP. $label AHEAD.',
        spokenDirectiveTa: 'நில்லுங்கள்! முன்னால் தடை உள்ளது.',
        isImmediateStop: true,
        leftBlocked: leftBlocked,
        centerBlocked: centerBlocked,
        rightBlocked: rightBlocked,
        closestObstacleDist: closestDist,
        primaryObstacleLabel: label,
      );
    }

    // ──────────────────────────────────────────────────────────────────────────
    // SAFETY RULE 2: ALL corridors blocked
    // ──────────────────────────────────────────────────────────────────────────
    if (leftBlocked && centerBlocked && rightBlocked) {
      return PathGuidanceDecision(
        direction: SafeDirection.stop,
        spokenDirectiveEn: 'STOP. PATH COMPLETELY BLOCKED.',
        spokenDirectiveTa: 'நில்லுங்கள்! பாதை முழுமையாக அடைக்கப்பட்டுள்ளது.',
        isImmediateStop: true,
        leftBlocked: true,
        centerBlocked: true,
        rightBlocked: true,
        closestObstacleDist: closestDist,
        primaryObstacleLabel: closestObstacle?.label,
      );
    }

    // ──────────────────────────────────────────────────────────────────────────
    // CASE A: CENTER is clear
    // ──────────────────────────────────────────────────────────────────────────
    if (!centerBlocked) {
      if (leftBlocked && !rightBlocked) {
        // Obstacle on left, right and center are clear
        return PathGuidanceDecision(
          direction: SafeDirection.straight,
          spokenDirectiveEn: 'OBSTACLE ON LEFT. GO STRAIGHT.',
          spokenDirectiveTa: 'இடதுபுறம் தடை. நேராகச் செல்லுங்கள்.',
          isImmediateStop: false,
          leftBlocked: true,
          centerBlocked: false,
          rightBlocked: false,
          closestObstacleDist: closestLeftDist,
          primaryObstacleLabel: closestObstacle?.label,
        );
      } else if (rightBlocked && !leftBlocked) {
        // Obstacle on right, left and center are clear
        return PathGuidanceDecision(
          direction: SafeDirection.straight,
          spokenDirectiveEn: 'OBSTACLE ON RIGHT. GO STRAIGHT.',
          spokenDirectiveTa: 'வலதுபுறம் தடை. நேராகச் செல்லுங்கள்.',
          isImmediateStop: false,
          leftBlocked: false,
          centerBlocked: false,
          rightBlocked: true,
          closestObstacleDist: closestRightDist,
          primaryObstacleLabel: closestObstacle?.label,
        );
      } else if (leftBlocked && rightBlocked) {
        // Narrow channel: both left and right have obstacles, center is open
        return PathGuidanceDecision(
          direction: SafeDirection.straight,
          spokenDirectiveEn: 'NARROW PATH. GO STRAIGHT CAREFULLY.',
          spokenDirectiveTa: 'குறுகிய பாதை. கவனமாக நேராகச் செல்லுங்கள்.',
          isImmediateStop: false,
          leftBlocked: true,
          centerBlocked: false,
          rightBlocked: true,
          closestObstacleDist: closestDist,
          primaryObstacleLabel: closestObstacle?.label,
        );
      }

      // Completely clear
      return const PathGuidanceDecision(
        direction: SafeDirection.straight,
        spokenDirectiveEn: 'PATH CLEAR. GO STRAIGHT.',
        spokenDirectiveTa: 'பாதை தெளிவாக உள்ளது. நேராகச் செல்லுங்கள்.',
        isImmediateStop: false,
        leftBlocked: false,
        centerBlocked: false,
        rightBlocked: false,
      );
    }

    // ──────────────────────────────────────────────────────────────────────────
    // CASE B: CENTER is blocked
    // ──────────────────────────────────────────────────────────────────────────
    // Subcase B1: CENTER blocked + LEFT clear + RIGHT blocked
    if (!leftBlocked && rightBlocked) {
      return PathGuidanceDecision(
        direction: SafeDirection.moveLeft,
        spokenDirectiveEn: 'OBSTACLE AHEAD. MOVE LEFT.',
        spokenDirectiveTa: 'முன்னால் தடை. இடதுபுறம் செல்லுங்கள்.',
        isImmediateStop: false,
        leftBlocked: false,
        centerBlocked: true,
        rightBlocked: true,
        closestObstacleDist: closestCenterDist,
        primaryObstacleLabel: closestObstacle?.label,
      );
    }

    // Subcase B2: CENTER blocked + RIGHT clear + LEFT blocked
    if (!rightBlocked && leftBlocked) {
      return PathGuidanceDecision(
        direction: SafeDirection.moveRight,
        spokenDirectiveEn: 'OBSTACLE AHEAD. MOVE RIGHT.',
        spokenDirectiveTa: 'முன்னால் தடை. வலதுபுறம் செல்லுங்கள்.',
        isImmediateStop: false,
        leftBlocked: true,
        centerBlocked: true,
        rightBlocked: false,
        closestObstacleDist: closestCenterDist,
        primaryObstacleLabel: closestObstacle?.label,
      );
    }

    // Subcase B3: CENTER blocked + BOTH LEFT and RIGHT are clear
    if (!leftBlocked && !rightBlocked) {
      // Pick the side with wider clearance or opposite to obstacle bias
      final centerBias = closestObstacle?.xCenter ?? 0.5;
      if (centerBias > 0.5) {
        // Obstacle leans slightly right → prefer LEFT
        return PathGuidanceDecision(
          direction: SafeDirection.moveLeft,
          spokenDirectiveEn: 'OBSTACLE AHEAD. MOVE LEFT.',
          spokenDirectiveTa: 'முன்னால் தடை. இடதுபுறம் செல்லுங்கள்.',
          isImmediateStop: false,
          leftBlocked: false,
          centerBlocked: true,
          rightBlocked: false,
          closestObstacleDist: closestCenterDist,
          primaryObstacleLabel: closestObstacle?.label,
        );
      } else {
        // Obstacle leans slightly left or center → prefer RIGHT
        return PathGuidanceDecision(
          direction: SafeDirection.moveRight,
          spokenDirectiveEn: 'OBSTACLE AHEAD. MOVE RIGHT.',
          spokenDirectiveTa: 'முன்னால் தடை. வலதுபுறம் செல்லுங்கள்.',
          isImmediateStop: false,
          leftBlocked: false,
          centerBlocked: true,
          rightBlocked: false,
          closestObstacleDist: closestCenterDist,
          primaryObstacleLabel: closestObstacle?.label,
        );
      }
    }

    // Fallback: Safety first
    return const PathGuidanceDecision(
      direction: SafeDirection.pathUnclear,
      spokenDirectiveEn: 'PATH UNCLEAR. STOP.',
      spokenDirectiveTa: 'பாதை தெளிவாக இல்லை. நில்லுங்கள்.',
      isImmediateStop: true,
      leftBlocked: true,
      centerBlocked: true,
      rightBlocked: true,
    );
  }

  /// Determines whether the new decision should trigger a spoken announcement.
  /// Enforces state-change detection and cooldown to avoid audio spamming.
  bool shouldAnnounce(PathGuidanceDecision decision, DateTime now) {
    // Immediate danger stops always announce immediately
    if (decision.isImmediateStop) {
      final sinceLast = now.difference(_lastDirectiveTime).inMilliseconds;
      if (sinceLast >= 2000 || _lastDirection != SafeDirection.stop) {
        _recordAnnouncement(decision, now);
        return true;
      }
      return false;
    }

    // Direction changed (e.g. was Straight, now Move Left)
    if (_lastDirection != decision.direction) {
      _recordAnnouncement(decision, now);
      return true;
    }

    // Same direction: only repeat if cooldown has elapsed and spoken text changed
    final sinceLast = now.difference(_lastDirectiveTime).inMilliseconds;
    if (sinceLast >= _guidanceRepeatCooldownMs && _lastSpokenEn != decision.spokenDirectiveEn) {
      _recordAnnouncement(decision, now);
      return true;
    }

    return false;
  }

  void _recordAnnouncement(PathGuidanceDecision decision, DateTime now) {
    _lastDirection = decision.direction;
    _lastDirectiveTime = now;
    _lastSpokenEn = decision.spokenDirectiveEn;
  }

  void reset() {
    _lastDirection = null;
    _lastDirectiveTime = DateTime.fromMillisecondsSinceEpoch(0);
    _lastSpokenEn = '';
  }
}
