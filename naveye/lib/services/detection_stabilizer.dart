import 'dart:math' as math;
import 'detector_service.dart';

/// Represents a temporally stabilized, tracked object across frames.
class StabilizedObject {
  final int trackingId;
  final String rawLabel;
  final String label;
  final double confidence;
  final double xCenter;
  final double yCenter;
  final double xMin;
  final double yMin;
  final double xMax;
  final double yMax;
  final double relativeArea;
  final double distanceM;
  final bool isWallHeuristic;
  final bool isVehicle;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final int consecutiveFrames;

  const StabilizedObject({
    required this.trackingId,
    required this.rawLabel,
    required this.label,
    required this.confidence,
    required this.xCenter,
    required this.yCenter,
    required this.xMin,
    required this.yMin,
    required this.xMax,
    required this.yMax,
    required this.relativeArea,
    required this.distanceM,
    required this.isWallHeuristic,
    required this.isVehicle,
    required this.firstSeen,
    required this.lastSeen,
    required this.consecutiveFrames,
  });

  double get width => (xMax - xMin).abs();
  double get height => (yMax - yMin).abs();

  StabilizedObject copyWith({
    int? trackingId,
    String? rawLabel,
    String? label,
    double? confidence,
    double? xCenter,
    double? yCenter,
    double? xMin,
    double? yMin,
    double? xMax,
    double? yMax,
    double? relativeArea,
    double? distanceM,
    bool? isWallHeuristic,
    bool? isVehicle,
    DateTime? firstSeen,
    DateTime? lastSeen,
    int? consecutiveFrames,
  }) {
    return StabilizedObject(
      trackingId: trackingId ?? this.trackingId,
      rawLabel: rawLabel ?? this.rawLabel,
      label: label ?? this.label,
      confidence: confidence ?? this.confidence,
      xCenter: xCenter ?? this.xCenter,
      yCenter: yCenter ?? this.yCenter,
      xMin: xMin ?? this.xMin,
      yMin: yMin ?? this.yMin,
      xMax: xMax ?? this.xMax,
      yMax: yMax ?? this.yMax,
      relativeArea: relativeArea ?? this.relativeArea,
      distanceM: distanceM ?? this.distanceM,
      isWallHeuristic: isWallHeuristic ?? this.isWallHeuristic,
      isVehicle: isVehicle ?? this.isVehicle,
      firstSeen: firstSeen ?? this.firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
      consecutiveFrames: consecutiveFrames ?? this.consecutiveFrames,
    );
  }
}

/// Internal tracking representation before and during stabilization.
class _TrackedDetection {
  final int id;
  final String rawLabel;
  String label;
  double confidence;
  double xMin;
  double yMin;
  double xMax;
  double yMax;
  double xCenter;
  double yCenter;
  double distanceM;
  bool isWallHeuristic;
  bool isVehicle;
  final DateTime firstSeen;
  DateTime lastSeen;
  int consecutiveFrames;
  int missedFrames;

  _TrackedDetection({
    required this.id,
    required this.rawLabel,
    required this.label,
    required this.confidence,
    required this.xMin,
    required this.yMin,
    required this.xMax,
    required this.yMax,
    required this.xCenter,
    required this.yCenter,
    required this.distanceM,
    required this.isWallHeuristic,
    required this.isVehicle,
    required this.firstSeen,
    required this.lastSeen,
    this.consecutiveFrames = 1,
    this.missedFrames = 0,
  });

  double get relativeArea => ((xMax - xMin).abs() * (yMax - yMin).abs()).clamp(0.0, 1.0);

  StabilizedObject toStabilized() {
    return StabilizedObject(
      trackingId: id,
      rawLabel: rawLabel,
      label: label,
      confidence: confidence,
      xCenter: xCenter,
      yCenter: yCenter,
      xMin: xMin,
      yMin: yMin,
      xMax: xMax,
      yMax: yMax,
      relativeArea: relativeArea,
      distanceM: distanceM,
      isWallHeuristic: isWallHeuristic,
      isVehicle: isVehicle,
      firstSeen: firstSeen,
      lastSeen: lastSeen,
      consecutiveFrames: consecutiveFrames,
    );
  }
}

/// Service providing temporal tracking, bounding box smoothing, and
/// false-positive suppression across consecutive camera frames.
class DetectionStabilizer {
  int _nextId = 1;
  final List<_TrackedDetection> _tracks = [];

  /// Minimum time (ms) an object must persist before being considered stabilized.
  /// Configurable between 300–500 ms (default: 350 ms).
  int stabilityThresholdMs;

  /// Minimum consecutive detection frames required.
  int minStableFrames;

  /// Maximum time (ms) a lost track is remembered before eviction.
  int maxTrackAgeMs;

  /// Minimum confidence threshold for an object to be stabilized.
  double confidenceThreshold;

  /// Exponential smoothing factor for bounding box coordinates (0.0 to 1.0).
  /// Higher means faster tracking response; lower means heavier smoothing.
  double positionSmoothingFactor;

  DetectionStabilizer({
    this.stabilityThresholdMs = 350,
    this.minStableFrames = 2,
    this.maxTrackAgeMs = 2000,
    this.confidenceThreshold = 0.50,
    this.positionSmoothingFactor = 0.65,
  });

  /// Processes raw detections from a new camera frame and returns only
  /// stabilized, temporally verified objects.
  List<StabilizedObject> processFrame(List<DetectionResult> detections, {DateTime? timestamp}) {
    final now = timestamp ?? DateTime.now();

    // 1. Filter out raw detections below confidence threshold
    final validDetections = detections.where((d) => d.confidence >= confidenceThreshold).toList();

    final matchedTrackIds = <int>{};
    final matchedDetectionIndices = <int>{};

    // 2. Match detections with existing tracks
    for (int i = 0; i < validDetections.length; i++) {
      final det = validDetections[i];
      _TrackedDetection? bestTrack;
      double bestScore = -1.0;

      for (final track in _tracks) {
        if (matchedTrackIds.contains(track.id)) continue;
        if (track.rawLabel != det.rawLabel) continue;

        final iou = _calculateIoU(track, det);
        final centerDist = _calculateCenterDist(track, det);

        // Match criteria: significant IoU OR reasonable center proximity
        if (iou >= 0.15 || centerDist <= 0.35) {
          final score = iou * 0.7 + (1.0 - centerDist) * 0.3;
          if (score > bestScore) {
            bestScore = score;
            bestTrack = track;
          }
        }
      }

      if (bestTrack != null) {
        matchedTrackIds.add(bestTrack.id);
        matchedDetectionIndices.add(i);

        // Smooth bounding box coordinates
        final alpha = positionSmoothingFactor.clamp(0.1, 1.0);
        bestTrack.xMin = alpha * det.xMin + (1 - alpha) * bestTrack.xMin;
        bestTrack.yMin = alpha * det.yMin + (1 - alpha) * bestTrack.yMin;
        bestTrack.xMax = alpha * det.xMax + (1 - alpha) * bestTrack.xMax;
        bestTrack.yMax = alpha * det.yMax + (1 - alpha) * bestTrack.yMax;
        bestTrack.xCenter = (bestTrack.xMin + bestTrack.xMax) / 2;
        bestTrack.yCenter = (bestTrack.yMin + bestTrack.yMax) / 2;
        bestTrack.confidence = alpha * det.confidence + (1 - alpha) * bestTrack.confidence;
        bestTrack.distanceM = alpha * det.distanceM + (1 - alpha) * bestTrack.distanceM;
        bestTrack.label = det.label;
        bestTrack.isWallHeuristic = det.isWallHeuristic;
        bestTrack.isVehicle = det.isVehicle;
        bestTrack.lastSeen = now;
        bestTrack.consecutiveFrames++;
        bestTrack.missedFrames = 0;
      }
    }

    // 3. Update unmatched existing tracks and prune expired ones (> maxTrackAgeMs, 2.0s grace period)
    _tracks.removeWhere((track) {
      if (!matchedTrackIds.contains(track.id)) {
        track.missedFrames++;
        final ageMs = now.difference(track.lastSeen).inMilliseconds;
        if (ageMs > maxTrackAgeMs) {
          return true; // remove stale track after grace period
        }
      }
      return false;
    });

    // 4. Create new tracks for unmatched detections
    for (int i = 0; i < validDetections.length; i++) {
      if (matchedDetectionIndices.contains(i)) continue;
      final det = validDetections[i];
      final newTrack = _TrackedDetection(
        id: _nextId++,
        rawLabel: det.rawLabel,
        label: det.label,
        confidence: det.confidence,
        xMin: det.xMin,
        yMin: det.yMin,
        xMax: det.xMax,
        yMax: det.yMax,
        xCenter: (det.xMin + det.xMax) / 2,
        yCenter: (det.yMin + det.yMax) / 2,
        distanceM: det.distanceM,
        isWallHeuristic: det.isWallHeuristic,
        isVehicle: det.isVehicle,
        firstSeen: now,
        lastSeen: now,
        consecutiveFrames: 1,
        missedFrames: 0,
      );
      _tracks.add(newTrack);
    }

    // 5. Select stabilized objects meeting duration and frame count criteria
    final stabilized = <StabilizedObject>[];
    for (final track in _tracks) {
      // Must be seen recently (allows 450ms coasting for momentary single-frame drops)
      if (track.missedFrames > 0 && now.difference(track.lastSeen).inMilliseconds > 450) {
        continue;
      }

      final elapsedMs = now.difference(track.firstSeen).inMilliseconds;
      final isStable = elapsedMs >= stabilityThresholdMs &&
          track.consecutiveFrames >= minStableFrames &&
          track.confidence >= confidenceThreshold;

      // Wall heuristics and critical safety obstacles get expedited stabilization
      final isEmergency = (track.isWallHeuristic || (track.distanceM < 0.8 && track.consecutiveFrames >= 1));

      if (isStable || isEmergency) {
        stabilized.add(track.toStabilized());
      }
    }

    return stabilized;
  }

  double _calculateIoU(_TrackedDetection a, DetectionResult b) {
    final ix1 = math.max(a.xMin, b.xMin);
    final iy1 = math.max(a.yMin, b.yMin);
    final ix2 = math.min(a.xMax, b.xMax);
    final iy2 = math.min(a.yMax, b.yMax);

    final interW = math.max(0.0, ix2 - ix1);
    final interH = math.max(0.0, iy2 - iy1);
    final inter = interW * interH;
    if (inter <= 0.0) return 0.0;

    final areaA = (a.xMax - a.xMin) * (a.yMax - a.yMin);
    final areaB = (b.xMax - b.xMin) * (b.yMax - b.yMin);
    final union = areaA + areaB - inter;
    if (union <= 0.0) return 0.0;

    return inter / union;
  }

  double _calculateCenterDist(_TrackedDetection a, DetectionResult b) {
    final bCenter = (b.xMin + b.xMax) / 2;
    final bYCenter = (b.yMin + b.yMax) / 2;
    final dx = a.xCenter - bCenter;
    final dy = a.yCenter - bYCenter;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Clears all internal tracking state.
  void reset() {
    _tracks.clear();
    _nextId = 1;
  }
}
