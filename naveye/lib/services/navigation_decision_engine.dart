// ignore_for_file: constant_identifier_names

import 'detection_stabilizer.dart';

/// Horizontal direction classification for detected objects.
enum ObjectDirection {
  left,
  center,
  right;

  String get displayName {
    switch (this) {
      case ObjectDirection.left:
        return 'LEFT';
      case ObjectDirection.center:
        return 'CENTER';
      case ObjectDirection.right:
        return 'RIGHT';
    }
  }
}

/// Proximity tier based on relative bounding-box area and distance estimation.
enum ObjectProximity {
  far,
  near,
  veryNear;

  String get displayName {
    switch (this) {
      case ObjectProximity.far:
        return 'FAR';
      case ObjectProximity.near:
        return 'NEAR';
      case ObjectProximity.veryNear:
        return 'VERY NEAR';
    }
  }
}

/// Navigation directive recommendations: Action / Direction
/// Formatted according to: [OBJECT] + [POSITION] + [ACTION]
enum NavigationAction {
  stop,
  goLeft,
  goRight,
  clear;

  String get commandEn {
    switch (this) {
      case NavigationAction.stop:
        return 'Stop and wait.';
      case NavigationAction.goLeft:
        return 'Move left.';
      case NavigationAction.goRight:
        return 'Move right.';
      case NavigationAction.clear:
        return 'Path clear.';
    }
  }

  String get commandTa {
    switch (this) {
      case NavigationAction.stop:
        return 'நின்றுவிடுங்கள்.';
      case NavigationAction.goLeft:
        return 'இடப்பக்கம் செல்லுங்கள்.';
      case NavigationAction.goRight:
        return 'வலப்பக்கம் செல்லுங்கள்.';
      case NavigationAction.clear:
        return 'முன்னால் பாதை தெளிவாக உள்ளது. செல்லலாம்.';
    }
  }
}

/// Navigation States for the State Machine (Section 8)
enum NavigationState {
  clear,
  obstacleLeft,
  obstacleCenterLeftClear,
  obstacleCenterRightClear,
  obstacleRight,
  criticalStop,
  knownPersonLeft,
  knownPersonCenter,
  knownPersonRight,
  knownPersonVeryClose,
  unknownPerson,
  transition;

  String get displayNameTa {
    switch (this) {
      case NavigationState.clear:
        return 'முன்னால் பாதை தெளிவாக உள்ளது';
      case NavigationState.obstacleLeft:
        return 'இடப்பக்கம் தடையுள்ளது';
      case NavigationState.obstacleRight:
        return 'வலப்பக்கம் தடையுள்ளது';
      case NavigationState.obstacleCenterLeftClear:
      case NavigationState.obstacleCenterRightClear:
      case NavigationState.unknownPerson:
        return 'முன்னால் தடை உள்ளது';
      case NavigationState.criticalStop:
      case NavigationState.knownPersonVeryClose:
        return 'நிறுத்தவும்';
      case NavigationState.knownPersonLeft:
        return 'லோகி இடப்பக்கத்தில் உள்ளார்';
      case NavigationState.knownPersonCenter:
        return 'லோகி முன்னால் உள்ளார்';
      case NavigationState.knownPersonRight:
        return 'லோகி வலப்பக்கத்தில் உள்ளார்';
      case NavigationState.transition:
        return 'வழிகாட்டுதல் செயலில் உள்ளது';
    }
  }

  String get guidanceActionTa {
    switch (this) {
      case NavigationState.clear:
        return 'செல்லலாம்';
      case NavigationState.obstacleLeft:
      case NavigationState.obstacleCenterRightClear:
      case NavigationState.knownPersonLeft:
        return 'வலப்பக்கம் செல்லவும்';
      case NavigationState.obstacleRight:
      case NavigationState.obstacleCenterLeftClear:
      case NavigationState.knownPersonRight:
        return 'இடப்பக்கம் செல்லவும்';
      case NavigationState.criticalStop:
      case NavigationState.knownPersonVeryClose:
        return 'நிறுத்தவும்';
      default:
        return 'செல்லலாம்';
    }
  }
}

/// Priority tier for voice announcements:
/// Priority 0: Critical Stop
/// Priority 1: Obstacle Ahead / Evasive Action
/// Priority 2: Known Person
/// Priority 3: Normal Informational Object
/// Priority 4: Clear Path Heartbeat
enum AlertPriority {
  criticalObstacle, // Level 0: Immediate STOP
  obstacleAhead,    // Level 1: GO LEFT / GO RIGHT
  knownPerson,      // Level 2: Known Person (Loki)
  normalObject,     // Level 3: Normal object / informational
  clearPath;        // Level 4: Clear path heartbeat

  int get level {
    switch (this) {
      case AlertPriority.criticalObstacle:
        return 0;
      case AlertPriority.obstacleAhead:
        return 1;
      case AlertPriority.knownPerson:
        return 2;
      case AlertPriority.normalObject:
        return 3;
      case AlertPriority.clearPath:
        return 4;
    }
  }

  bool isHigherOrEqual(AlertPriority other) => level <= other.level;
  bool isStrictlyHigher(AlertPriority other) => level < other.level;

  static const stop = AlertPriority.criticalObstacle;
  static const navigationAction = AlertPriority.obstacleAhead;
  static const informational = AlertPriority.normalObject;
}

/// A fully synthesized navigation alert ready for VoiceAlertManager.
class NavigationAlert {
  final int trackingId;
  final String rawLabel;
  final String label;
  final ObjectDirection direction;
  final NavigationAction action;
  final NavigationState navState;
  final ObjectProximity proximity;
  final AlertPriority priority;
  final String spokenTextEn;
  final String spokenTextTa;
  final double confidence;
  final double relativeArea;
  final double distanceM;
  final DateTime generatedAt;

  const NavigationAlert({
    required this.trackingId,
    required this.rawLabel,
    required this.label,
    required this.direction,
    this.action = NavigationAction.clear,
    this.navState = NavigationState.clear,
    required this.proximity,
    required this.priority,
    required this.spokenTextEn,
    required this.spokenTextTa,
    required this.confidence,
    required this.relativeArea,
    required this.distanceM,
    required this.generatedAt,
  });

  /// Navigation state signature for state change comparison:
  /// Voice speaks ONLY when the spoken Tamil instruction changes.
  String get stateKey => spokenTextTa;
}

/// Spatial reasoning and navigation decision engine.
/// Computes horizontal corridors, obstacle avoidance vectors, free-space analysis,
/// temporal smoothing (300-500ms), and natural action narration:
/// [OBJECT] + [POSITION] + [ACTION]
/// e.g. "Laptop ahead. Move left."
///      "Person on your right. Move left."
///      "Obstacle very close ahead. Stop and wait."
class NavigationDecisionEngine {
  /// Direction threshold between Left and Center (< 0.35 -> LEFT).
  double leftThreshold;

  /// Direction threshold between Center and Right (> 0.65 -> RIGHT).
  double rightThreshold;

  /// Boundary hysteresis band to prevent micro-jitter toggling across boundaries (default: 0.04).
  double directionHysteresis;

  /// Proximity threshold for NEAR (relative bounding box area, default: 0.045).
  double nearAreaThreshold;

  /// Proximity threshold for VERY NEAR (relative bounding box area, default: 0.18).
  double veryNearAreaThreshold;

  /// Minimum duration an action/direction must persist before changing state (300–500 ms, default: 350 ms).
  int directionChangeStabilityMs;

  /// When true, voice commands follow [OBJECT] + [POSITION] + [ACTION].
  /// When false, voice commands are descriptive ("Laptop ahead.", etc.).
  bool actionGuidanceMode;

  // Track per-object direction history with 2-second grace period
  final Map<int, ObjectDirection> _activeDirections = {};
  final Map<int, ObjectDirection> _candidateDirections = {};
  final Map<int, DateTime> _candidateDirectionStart = {};
  final Map<int, DateTime> _lastSeenDirections = {};

  // Global navigation action state machine
  NavigationAction? _activeAction;
  NavigationAction? _candidateAction;
  DateTime? _candidateActionStart;
  DateTime? _lastActionEvaluationTime;

  NavigationDecisionEngine({
    this.leftThreshold = 0.35,
    this.rightThreshold = 0.65,
    this.directionHysteresis = 0.04,
    this.nearAreaThreshold = 0.045,
    this.veryNearAreaThreshold = 0.18,
    this.directionChangeStabilityMs = 350,
    this.actionGuidanceMode = true,
  });

  // Temporal grace tracker for obstacle disappearance
  DateTime? _lastObstacleSeenTime;

  /// Creates a standardized CLEAR alert
  NavigationAlert createClearAlert(DateTime now) {
    return NavigationAlert(
      trackingId: 0,
      rawLabel: 'clear',
      label: 'பாதை தெளிவாக உள்ளது',
      direction: ObjectDirection.center,
      action: NavigationAction.clear,
      navState: NavigationState.clear,
      proximity: ObjectProximity.far,
      priority: AlertPriority.clearPath,
      spokenTextEn: 'Path ahead is clear. You may proceed.',
      spokenTextTa: 'முன்னால் பாதை தெளிவாக உள்ளது. செல்லலாம்.',
      confidence: 1.0,
      relativeArea: 0.0,
      distanceM: 100.0,
      generatedAt: now,
    );
  }

  /// Evaluates stabilized objects and determines the single active navigation instruction.
  NavigationAlert? evaluate(
    List<StabilizedObject> objects, {
    DateTime? timestamp,
    bool isTamil = true,
  }) {
    final now = timestamp ?? DateTime.now();

    if (objects.isEmpty) {
      // Temporal grace period (Section 14): do not transition to clear on a momentary dropped frame
      if (_lastObstacleSeenTime != null && now.difference(_lastObstacleSeenTime!).inMilliseconds < 1500) {
        return null;
      }
      _activeAction = NavigationAction.clear;
      _candidateAction = null;
      return createClearAlert(now);
    }

    _lastObstacleSeenTime = now;

    // 1. Maintain direction cache with 2-second grace period
    final previousSeenMap = Map<int, DateTime>.from(_lastSeenDirections);
    for (final obj in objects) {
      _lastSeenDirections[obj.trackingId] = now;
    }
    _activeDirections.removeWhere((id, _) => now.difference(_lastSeenDirections[id] ?? now).inMilliseconds > 2000);
    _candidateDirections.removeWhere((id, _) => now.difference(_lastSeenDirections[id] ?? now).inMilliseconds > 2000);
    _candidateDirectionStart.removeWhere((id, _) => now.difference(_lastSeenDirections[id] ?? now).inMilliseconds > 2000);
    _lastSeenDirections.removeWhere((_, time) => now.difference(time).inMilliseconds > 2000);

    // 2. Classify individual objects and assess corridor blockages
    final candidates = <_EvaluatedCandidate>[];
    bool leftBlocked = false;
    bool centerBlocked = false;
    bool rightBlocked = false;
    bool isExtremelyClose = false;

    for (final obj in objects) {
      final direction = _resolveDirection(
        obj.trackingId,
        obj.xCenter,
        now,
        previousSeen: previousSeenMap[obj.trackingId],
      );
      final proximity = _resolveProximity(obj.relativeArea, obj.distanceM);
      final priority = _resolvePriority(obj, direction, proximity);

      candidates.add(_EvaluatedCandidate(
        object: obj,
        direction: direction,
        proximity: proximity,
        priority: priority,
      ));

      // Spatial corridor blockage analysis
      final spansLeft = obj.xMin < leftThreshold || obj.xCenter < leftThreshold;
      final spansCenter = (obj.xMin <= rightThreshold && obj.xMax >= leftThreshold) ||
          (obj.xCenter >= (leftThreshold - directionHysteresis) &&
              obj.xCenter <= (rightThreshold + directionHysteresis));
      final spansRight = obj.xMax > rightThreshold || obj.xCenter > rightThreshold;

      if (spansLeft) leftBlocked = true;
      if (spansCenter) centerBlocked = true;
      if (spansRight) rightBlocked = true;

      // Obstacle very close directly ahead (< 0.9m, or relativeArea >= 0.18, or wall heuristic)
      if (spansCenter &&
          (obj.distanceM < 0.9 ||
              obj.relativeArea >= veryNearAreaThreshold ||
              obj.isWallHeuristic ||
              (obj.isVehicle && obj.distanceM < 2.0))) {
        isExtremelyClose = true;
      }
    }

    if (candidates.isEmpty) return null;

    // Pick primary object
    candidates.sort((a, b) {
      final pDiff = a.priority.level.compareTo(b.priority.level);
      if (pDiff != 0) return pDiff;

      final aIsCenter = a.direction == ObjectDirection.center;
      final bIsCenter = b.direction == ObjectDirection.center;
      if (aIsCenter && !bIsCenter) return -1;
      if (!aIsCenter && bIsCenter) return 1;

      final proxDiff = b.proximity.index.compareTo(a.proximity.index);
      if (proxDiff != 0) return proxDiff;

      final distDiff = a.object.distanceM.compareTo(b.object.distanceM);
      if (distDiff != 0) return distDiff;

      return b.object.confidence.compareTo(a.object.confidence);
    });

    final primary = candidates.first;

    // 3. Navigation Decision Logic:
    // Rule 1: OBJECT ON LEFT -> Move right.
    // Rule 2: OBJECT ON RIGHT -> Move left.
    // Rule 3: OBJECT IN CENTER:
    //         - Extremely close -> Stop and wait.
    //         - Left clear -> Move left.
    //         - Left blocked, right clear -> Move right.
    //         - Both sides blocked -> Stop and wait.
    NavigationAction rawAction;
    AlertPriority decisionPriority;

    if (isExtremelyClose || (centerBlocked && leftBlocked && rightBlocked)) {
      rawAction = NavigationAction.stop;
      decisionPriority = AlertPriority.criticalObstacle;
    } else if (centerBlocked || primary.direction == ObjectDirection.center) {
      // CENTER OBSTACLE:
      // Always guide LEFT as the default safe navigation instruction.
      // Do NOT dynamically switch between left and right for a center obstacle.
      rawAction = NavigationAction.goLeft;
      decisionPriority = AlertPriority.obstacleAhead;
    } else {
      // Center is clear! Check side obstacles
      if (leftBlocked && !rightBlocked) {
        rawAction = NavigationAction.goRight;
        decisionPriority = AlertPriority.obstacleAhead;
      } else if (rightBlocked && !leftBlocked) {
        rawAction = NavigationAction.goLeft;
        decisionPriority = AlertPriority.obstacleAhead;
      } else if (primary.direction == ObjectDirection.left) {
        rawAction = NavigationAction.goRight;
        decisionPriority = AlertPriority.obstacleAhead;
      } else if (primary.direction == ObjectDirection.right) {
        rawAction = NavigationAction.goLeft;
        decisionPriority = AlertPriority.obstacleAhead;
      } else {
        rawAction = NavigationAction.clear;
        decisionPriority = AlertPriority.normalObject;
      }
    }

    // 4. Direction / Action Stability (300–500 ms)
    NavigationAction stableAction;
    if (rawAction == NavigationAction.stop) {
      // Emergency STOP triggers immediately for safety!
      _activeAction = NavigationAction.stop;
      _candidateAction = null;
      _candidateActionStart = null;
      stableAction = NavigationAction.stop;
    } else {
      final lastActionEval = _lastActionEvaluationTime;
      _lastActionEvaluationTime = now;
      if (lastActionEval != null && now.difference(lastActionEval).inMilliseconds > 1000) {
        _activeAction = rawAction;
        _candidateAction = null;
        _candidateActionStart = null;
        stableAction = rawAction;
      } else if (_activeAction == null) {
        _activeAction = rawAction;
        _candidateAction = null;
        _candidateActionStart = null;
        stableAction = rawAction;
      } else if (rawAction == _activeAction) {
        _candidateAction = null;
        _candidateActionStart = null;
        stableAction = _activeAction!;
      } else {
        // Candidate action differs from active action: require stability
        if (_candidateAction != rawAction) {
          _candidateAction = rawAction;
          _candidateActionStart = now;
          stableAction = _activeAction!;
        } else {
          final elapsed = now.difference(_candidateActionStart!).inMilliseconds;
          if (elapsed >= directionChangeStabilityMs) {
            _activeAction = rawAction;
            _candidateAction = null;
            _candidateActionStart = null;
            stableAction = rawAction;
          } else {
            stableAction = _activeAction!;
          }
        }
      }
    }

    // 5. Determine Navigation State
    final isKnownPerson = primary.object.rawLabel.startsWith('person_') ||
        primary.object.rawLabel.startsWith('known_') ||
        primary.object.label.toLowerCase() == 'loki';
    final isUnknownPerson = !isKnownPerson && primary.object.rawLabel == 'person';

    NavigationState navState;
    if (stableAction == NavigationAction.stop || isExtremelyClose) {
      if (isKnownPerson) {
        navState = NavigationState.knownPersonVeryClose;
      } else {
        navState = NavigationState.criticalStop;
      }
    } else if (isKnownPerson) {
      switch (primary.direction) {
        case ObjectDirection.left:
          navState = NavigationState.knownPersonLeft;
          break;
        case ObjectDirection.right:
          navState = NavigationState.knownPersonRight;
          break;
        case ObjectDirection.center:
          navState = NavigationState.knownPersonCenter;
          break;
      }
    } else if (isUnknownPerson) {
      navState = NavigationState.unknownPerson;
    } else {
      if (centerBlocked || primary.direction == ObjectDirection.center) {
        if (stableAction == NavigationAction.stop) {
          navState = NavigationState.criticalStop;
        } else {
          navState = NavigationState.obstacleCenterLeftClear;
        }
      } else if (primary.direction == ObjectDirection.left || (leftBlocked && !rightBlocked)) {
        navState = NavigationState.obstacleLeft;
      } else if (primary.direction == ObjectDirection.right || (rightBlocked && !leftBlocked)) {
        navState = NavigationState.obstacleRight;
      } else {
        navState = NavigationState.transition;
      }
    }

    // 6. Narration Selection: [OBJECT] + [POSITION] + [ACTION]
    String spokenEn;
    String spokenTa;

    if (actionGuidanceMode) {
      spokenEn = _buildNarrationEn(
        object: primary.object,
        direction: primary.direction,
        action: stableAction,
        isVeryClose: isExtremelyClose,
      );
      spokenTa = _buildNarrationTa(
        object: primary.object,
        direction: primary.direction,
        action: stableAction,
        isVeryClose: isExtremelyClose,
        navState: navState,
      );
    } else {
      spokenEn = _formatNarrationEn(primary);
      spokenTa = _formatNarrationTa(primary);
    }

    return NavigationAlert(
      trackingId: primary.object.trackingId,
      rawLabel: primary.object.rawLabel,
      label: primary.object.label,
      direction: primary.direction,
      action: stableAction,
      navState: navState,
      proximity: primary.proximity,
      priority: stableAction == NavigationAction.stop
          ? AlertPriority.criticalObstacle
          : (actionGuidanceMode ? decisionPriority : primary.priority),
      spokenTextEn: spokenEn,
      spokenTextTa: spokenTa,
      confidence: primary.object.confidence,
      relativeArea: primary.object.relativeArea,
      distanceM: primary.object.distanceM,
      generatedAt: now,
    );
  }

  /// Builds natural navigation sentences: [OBJECT] + [POSITION] + [ACTION]
  /// Examples:
  /// - "Laptop ahead. Move left."
  /// - "Person on your right. Move left."
  /// - "Chair on your left. Move right."
  /// - "Obstacle ahead. Move left."
  /// - "Obstacle very close ahead. Stop and wait."
  String _buildNarrationEn({
    required StabilizedObject object,
    required ObjectDirection direction,
    required NavigationAction action,
    required bool isVeryClose,
  }) {
    final isObstacle = object.rawLabel == 'obstacle' ||
        object.rawLabel == 'wall' ||
        object.isWallHeuristic;
    final label = isObstacle ? 'Obstacle' : _capitalize(object.label);

    String positionStr;
    if (isVeryClose) {
      positionStr = 'very close ahead';
    } else {
      switch (direction) {
        case ObjectDirection.left:
          positionStr = 'on your left';
          break;
        case ObjectDirection.center:
          positionStr = 'ahead';
          break;
        case ObjectDirection.right:
          positionStr = 'on your right';
          break;
      }
    }

    final actionStr = action.commandEn; // "Move left.", "Move right.", "Stop and wait."
    return '$label $positionStr. $actionStr';
  }

  /// Builds natural Tamil navigation sentences:
  /// - CENTER OBSTACLE: "முன்னால் தடையுள்ளது. இடப்பக்கம் செல்லுங்கள்."
  /// - LEFT OBSTACLE: "இடப்பக்கம் தடையுள்ளது. வலப்பக்கம் செல்லுங்கள்."
  /// - RIGHT OBSTACLE: "வலப்பக்கம் தடையுள்ளது. இடப்பக்கம் செல்லுங்கள்."
  /// - CLEAR PATH: "முன்னால் பாதை தெளிவாக உள்ளது. செல்லலாம்."
  /// - CRITICAL / VERY CLOSE OBSTACLE: "முன்னால் தடையுள்ளது. நின்றுவிடுங்கள்."
  String _buildNarrationTa({
    required StabilizedObject object,
    required ObjectDirection direction,
    required NavigationAction action,
    required bool isVeryClose,
    required NavigationState navState,
  }) {
    final isKnownPerson = object.rawLabel.startsWith('person_') ||
        object.rawLabel.startsWith('known_') ||
        object.label.toLowerCase() == 'loki';
    final isUnknownPerson = !isKnownPerson && object.rawLabel == 'person';

    if (isKnownPerson) {
      final name = object.label.toLowerCase() == 'loki' ? 'லோகி' : _capitalize(object.label);
      if (isVeryClose || action == NavigationAction.stop) {
        return '$name மிகவும் அருகில் இருக்கிறார். நின்றுவிடுங்கள்.';
      }
      switch (direction) {
        case ObjectDirection.left:
          return '$name இடப்பக்கத்தில் இருக்கிறார். வலப்பக்கம் செல்லுங்கள்.';
        case ObjectDirection.right:
          return '$name வலப்பக்கத்தில் இருக்கிறார். இடப்பக்கம் செல்லுங்கள்.';
        case ObjectDirection.center:
          return '$name முன்னால் இருக்கிறார். இடப்பக்கம் செல்லுங்கள்.';
      }
    }

    if (isUnknownPerson) {
      if (isVeryClose || action == NavigationAction.stop) {
        return 'முன்னால் தடையுள்ளது. நின்றுவிடுங்கள்.';
      }
      switch (direction) {
        case ObjectDirection.left:
          return 'இடப்பக்கம் தடையுள்ளது. வலப்பக்கம் செல்லுங்கள்.';
        case ObjectDirection.right:
          return 'வலப்பக்கம் தடையுள்ளது. இடப்பக்கம் செல்லுங்கள்.';
        case ObjectDirection.center:
          return 'முன்னால் தடையுள்ளது. இடப்பக்கம் செல்லுங்கள்.';
      }
    }

    // General Obstacle / Object guidance
    if (isVeryClose || action == NavigationAction.stop) {
      return 'முன்னால் தடையுள்ளது. நின்றுவிடுங்கள்.';
    }

    if (direction == ObjectDirection.center ||
        navState == NavigationState.obstacleCenterLeftClear ||
        navState == NavigationState.obstacleCenterRightClear) {
      return 'முன்னால் தடையுள்ளது. இடப்பக்கம் செல்லுங்கள்.';
    }

    if (navState == NavigationState.obstacleLeft || direction == ObjectDirection.left) {
      return 'இடப்பக்கம் தடையுள்ளது. வலப்பக்கம் செல்லுங்கள்.';
    }

    if (navState == NavigationState.obstacleRight || direction == ObjectDirection.right) {
      return 'வலப்பக்கம் தடையுள்ளது. இடப்பக்கம் செல்லுங்கள்.';
    }

    return 'முன்னால் தடையுள்ளது. இடப்பக்கம் செல்லுங்கள்.';
  }

  /// Calculates horizontal direction with hysteresis and temporal smoothing (300–500 ms).
  ObjectDirection _resolveDirection(int id, double xCenter, DateTime now, {DateTime? previousSeen}) {
    final current = _activeDirections[id];

    // Compute target direction with hysteresis bands
    ObjectDirection target;
    if (current == null) {
      if (xCenter < leftThreshold) {
        target = ObjectDirection.left;
      } else if (xCenter > rightThreshold) {
        target = ObjectDirection.right;
      } else {
        target = ObjectDirection.center;
      }
      _activeDirections[id] = target;
      return target;
    }

    // Apply hysteresis around 0.35 and 0.65 to prevent boundary toggling
    switch (current) {
      case ObjectDirection.center:
        if (xCenter < (leftThreshold - directionHysteresis)) {
          target = ObjectDirection.left;
        } else if (xCenter > (rightThreshold + directionHysteresis)) {
          target = ObjectDirection.right;
        } else {
          target = ObjectDirection.center;
        }
        break;
      case ObjectDirection.left:
        if (xCenter >= (leftThreshold + directionHysteresis)) {
          target = xCenter > rightThreshold ? ObjectDirection.right : ObjectDirection.center;
        } else {
          target = ObjectDirection.left;
        }
        break;
      case ObjectDirection.right:
        if (xCenter <= (rightThreshold - directionHysteresis)) {
          target = xCenter < leftThreshold ? ObjectDirection.left : ObjectDirection.center;
        } else {
          target = ObjectDirection.right;
        }
        break;
    }

    if (target == current) {
      _candidateDirections.remove(id);
      _candidateDirectionStart.remove(id);
      return current;
    }

    // If this object was not seen recently (> 1000ms), accept the target direction immediately
    if (previousSeen != null && now.difference(previousSeen).inMilliseconds > 1000) {
      _activeDirections[id] = target;
      _candidateDirections.remove(id);
      _candidateDirectionStart.remove(id);
      return target;
    }

    // Temporal smoothing: candidate must persist for directionChangeStabilityMs (300-500ms)
    if (_candidateDirections[id] != target) {
      _candidateDirections[id] = target;
      _candidateDirectionStart[id] = now;
      return current;
    }

    final stableDuration = now.difference(_candidateDirectionStart[id]!).inMilliseconds;
    if (stableDuration >= directionChangeStabilityMs) {
      _activeDirections[id] = target;
      _candidateDirections.remove(id);
      _candidateDirectionStart.remove(id);
      return target;
    }

    return current;
  }

  /// Calculates proximity tier from relative bounding-box area and distance.
  ObjectProximity _resolveProximity(double relativeArea, double distanceM) {
    if (relativeArea >= veryNearAreaThreshold || distanceM < 0.9) {
      return ObjectProximity.veryNear;
    }
    if (relativeArea >= nearAreaThreshold || distanceM < 2.5) {
      return ObjectProximity.near;
    }
    return ObjectProximity.far;
  }

  /// Priority resolution:
  /// CRITICAL OBSTACLE > OBSTACLE AHEAD > KNOWN PERSON > NORMAL OBJECT
  AlertPriority _resolvePriority(StabilizedObject obj, ObjectDirection direction, ObjectProximity proximity) {
    final isCenter = direction == ObjectDirection.center;
    final isKnownPerson = obj.rawLabel.startsWith('person_') || obj.rawLabel.startsWith('known_');
    final isObstacleClass = obj.rawLabel == 'obstacle' || obj.rawLabel == 'wall' || obj.isWallHeuristic;

    // 1. CRITICAL OBSTACLE
    if ((obj.isWallHeuristic && isCenter) ||
        (proximity == ObjectProximity.veryNear && isCenter) ||
        (obj.isVehicle && obj.distanceM < 2.0)) {
      return AlertPriority.criticalObstacle;
    }

    // 2. OBSTACLE AHEAD
    if (isObstacleClass || (obj.isVehicle && isCenter)) {
      return AlertPriority.obstacleAhead;
    }

    // 3. KNOWN PERSON
    if (isKnownPerson) {
      return AlertPriority.knownPerson;
    }

    // 4. NORMAL OBJECT
    return AlertPriority.normalObject;
  }

  /// Short, deterministic descriptive English voice generator (fallback mode).
  String _formatNarrationEn(_EvaluatedCandidate c) {
    if (c.priority == AlertPriority.criticalObstacle) {
      return 'Stop and wait.';
    }

    final obj = c.object;
    final isObstacle = obj.rawLabel == 'obstacle' || obj.rawLabel == 'wall' || obj.isWallHeuristic;
    final label = isObstacle ? 'Obstacle' : _capitalize(obj.label);

    switch (c.direction) {
      case ObjectDirection.left:
        return '$label left.';
      case ObjectDirection.center:
        return '$label ahead.';
      case ObjectDirection.right:
        return '$label right.';
    }
  }

  /// Short, deterministic descriptive Tamil voice generator (fallback mode).
  String _formatNarrationTa(_EvaluatedCandidate c) {
    if (c.priority == AlertPriority.criticalObstacle) {
      return 'நின்று காத்திருங்கள்.';
    }

    final obj = c.object;
    final isKnownPerson = obj.rawLabel.startsWith('person_') || obj.rawLabel.startsWith('known_');
    final isObstacle = obj.rawLabel == 'obstacle' || obj.rawLabel == 'wall' || obj.isWallHeuristic;
    final label = isObstacle
        ? 'தடை'
        : (isKnownPerson ? _capitalize(obj.label) : _tamilLabel(obj.rawLabel));

    switch (c.direction) {
      case ObjectDirection.left:
        return '$label இடது.';
      case ObjectDirection.center:
        return '$label முன்னால்.';
      case ObjectDirection.right:
        return '$label வலது.';
    }
  }

  String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  static const Map<String, String> _taMap = {
    'person': 'நபர்',
    'chair': 'நாற்காலி',
    'laptop': 'லேப்டாப்',
    'table': 'மேஜை',
    'car': 'கார்',
    'bicycle': 'சைக்கிள்',
    'bottle': 'பாட்டில்',
    'cell phone': 'மொபைல்',
    'obstacle': 'தடை',
    'wall': 'சுவர்',
  };

  String _tamilLabel(String raw) => _taMap[raw] ?? raw;

  void reset() {
    _activeDirections.clear();
    _candidateDirections.clear();
    _candidateDirectionStart.clear();
    _lastSeenDirections.clear();
    _activeAction = null;
    _candidateAction = null;
    _candidateActionStart = null;
    _lastActionEvaluationTime = null;
    _lastObstacleSeenTime = null;
  }
}

class _EvaluatedCandidate {
  final StabilizedObject object;
  final ObjectDirection direction;
  final ObjectProximity proximity;
  final AlertPriority priority;

  const _EvaluatedCandidate({
    required this.object,
    required this.direction,
    required this.proximity,
    required this.priority,
  });
}
