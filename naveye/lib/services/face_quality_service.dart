import 'dart:math';
import 'dart:ui';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

class FaceQualityConfig {
  final double minScore;
  final double minFaceSizeRatio;
  final double minBrightness;
  final double maxBrightness;
  final double minSharpness;
  final double minTemporalStability;
  final double minFrontalness;
  final double maxOcclusion;
  final int minObservations;
  final double detectionWeight;
  final double sizeWeight;
  final double brightnessWeight;
  final double sharpnessWeight;
  final double stabilityWeight;
  final double frontalnessWeight;
  final double occlusionWeight;

  const FaceQualityConfig({
    this.minScore = 0.56,
    this.minFaceSizeRatio = 0.04,
    this.minBrightness = 35.0,
    this.maxBrightness = 220.0,
    this.minSharpness = 0.2,
    this.minTemporalStability = 0.64,
    this.minFrontalness = 0.45,
    this.maxOcclusion = 0.45,
    this.minObservations = 3,
    this.detectionWeight = 0.30,
    this.sizeWeight = 0.22,
    this.brightnessWeight = 0.18,
    this.sharpnessWeight = 0.16,
    this.stabilityWeight = 0.10,
    this.frontalnessWeight = 0.04,
    this.occlusionWeight = 0.10,
  });
}

class FaceQualityResult {
  final double score;
  final bool passed;
  final bool faceLargeEnough;
  final bool brightnessOk;
  final bool sharpnessOk;
  final bool stableEnough;
  final String? reason;

  const FaceQualityResult({
    required this.score,
    required this.passed,
    required this.faceLargeEnough,
    required this.brightnessOk,
    required this.sharpnessOk,
    required this.stableEnough,
    this.reason,
  });
}

class FaceQualityService {
  static const FaceQualityConfig defaultConfig = FaceQualityConfig();

  final FaceQualityConfig config;

  FaceQualityService({this.config = defaultConfig});

  FaceQualityResult evaluateCandidate({
    required double detectionConfidence,
    required double faceSizeRatio,
    required double brightness,
    required double sharpness,
    double temporalStability = 0.0,
    double frontalness = 0.5,
    double occlusion = 0.0,
    int observations = 1,
    DateTime? observationTime,
  }) {
    final detectionScore = detectionConfidence.clamp(0.0, 1.0);
    final sizeScore = _normaliseSize(faceSizeRatio);
    final brightnessScore = _normaliseBrightness(brightness);
    final sharpnessScore = sharpness.clamp(0.0, 1.0);
    final frontalScore = frontalness.clamp(0.0, 1.0);
    final stabilityScore = temporalStability.clamp(0.0, 1.0);
    final occlusionScore = (1.0 - occlusion.clamp(0.0, 1.0)).clamp(0.0, 1.0);

    final weightedScore =
        (detectionScore * config.detectionWeight) +
        (sizeScore * config.sizeWeight) +
        (brightnessScore * config.brightnessWeight) +
        (sharpnessScore * config.sharpnessWeight) +
        (stabilityScore * config.stabilityWeight) +
        (frontalScore * config.frontalnessWeight) +
        (occlusionScore * config.occlusionWeight);

    final faceLargeEnough = faceSizeRatio >= config.minFaceSizeRatio;
    final brightnessOk = brightness >= config.minBrightness && brightness <= config.maxBrightness;
    final sharpnessOk = sharpness >= config.minSharpness;
    final stableEnough = observations >= config.minObservations || stabilityScore >= config.minTemporalStability;
    final frontalOk = frontalScore >= config.minFrontalness;
    final occlusionOk = occlusion <= config.maxOcclusion;

    final passed =
        weightedScore >= config.minScore &&
        faceLargeEnough &&
        brightnessOk &&
        sharpnessOk &&
        stableEnough &&
        frontalOk &&
        occlusionOk;

    String? reason;
    if (!faceLargeEnough) {
      reason ??= 'face too small';
    }
    if (!brightnessOk) {
      reason ??= 'brightness outside safe range';
    }
    if (!sharpnessOk) {
      reason ??= 'face is too blurry';
    }
    if (!stableEnough) {
      reason ??= 'face not stable enough';
    }
    if (!frontalOk) {
      reason ??= 'face angle is poor';
    }
    if (!occlusionOk) {
      reason ??= 'face partially occluded';
    }
    if (!passed && reason == null) {
      reason = 'quality below threshold';
    }

    return FaceQualityResult(
      score: weightedScore,
      passed: passed,
      faceLargeEnough: faceLargeEnough,
      brightnessOk: brightnessOk,
      sharpnessOk: sharpnessOk,
      stableEnough: stableEnough,
      reason: reason,
    );
  }

  bool isStableForRegistration(List<String> history) {
    if (history.length < config.minObservations) return false;
    final stable = history.where((h) => h == 'good').length;
    return stable >= max(2, (history.length * 0.7).ceil());
  }

  static double _normaliseSize(double faceSizeRatio) {
    // Safe approximation: 0.04 is low-quality, 0.20 is strong. Anything larger is capped.
    final ratio = faceSizeRatio.clamp(0.0, 0.30);
    if (ratio <= 0.0) return 0.0;
    return (ratio / 0.18).clamp(0.0, 1.0);
  }

  static double _normaliseBrightness(double brightness) {
    final value = brightness.clamp(0.0, 255.0);
    // Aim for mid-tone faces; very dark or washed-out frames score lower.
    return (1.0 - ((value - 75.0).abs() / 180.0)).clamp(0.0, 1.0);
  }

  static double estimateBrightness(img.Image image, Rect box) {
    final x0 = box.left.toInt().clamp(0, image.width - 1);
    final y0 = box.top.toInt().clamp(0, image.height - 1);
    final x1 = box.right.toInt().clamp(0, image.width - 1);
    final y1 = box.bottom.toInt().clamp(0, image.height - 1);
    if (x1 <= x0 || y1 <= y0) return 120.0;

    int total = 0;
    int count = 0;
    for (int y = y0; y < y1; y++) {
      for (int x = x0; x < x1; x++) {
        final pixel = image.getPixel(x, y);
        total += ((pixel.r + pixel.g + pixel.b) / 3).round();
        count++;
      }
    }
    if (count == 0) return 120.0;
    return (total / count).toDouble();
  }

  static double estimateSharpness(img.Image image, Rect box) {
    final x0 = box.left.toInt().clamp(0, image.width - 1);
    final y0 = box.top.toInt().clamp(0, image.height - 1);
    final x1 = box.right.toInt().clamp(0, image.width - 1);
    final y1 = box.bottom.toInt().clamp(0, image.height - 1);
    if (x1 <= x0 || y1 <= y0) return 0.35;

    double totalGradient = 0.0;
    int count = 0;
    for (int y = y0 + 1; y < y1 - 1; y++) {
      for (int x = x0 + 1; x < x1 - 1; x++) {
        final p = image.getPixel(x, y);
        final p1 = image.getPixel(x + 1, y);
        final p2 = image.getPixel(x, y + 1);
        final gx = (p1.r - p.r).abs() + (p1.g - p.g).abs() + (p1.b - p.b).abs();
        final gy = (p2.r - p.r).abs() + (p2.g - p.g).abs() + (p2.b - p.b).abs();
        totalGradient += (gx + gy) / 2.0;
        count++;
      }
    }
    if (count == 0) return 0.35;
    final avg = totalGradient / count;
    return (avg / 255.0).clamp(0.0, 1.0);
  }

  static double estimateFrontalness(Face face) {
    try {
      final yaw = face.headEulerAngleY ?? 0.0;
      final roll = face.headEulerAngleZ ?? 0.0;
      final yawAbs = yaw.abs();
      final rollAbs = roll.abs();
      final score = (1.0 - ((yawAbs / 35.0).clamp(0.0, 1.0) * 0.7 + (rollAbs / 30.0).clamp(0.0, 1.0) * 0.3));
      return score.clamp(0.0, 1.0);
    } catch (_) {
      return 0.7;
    }
  }

  static double estimateOcclusion(Face face) {
    try {
      final leftEye = face.landmarks[FaceLandmarkType.leftEye];
      final rightEye = face.landmarks[FaceLandmarkType.rightEye];
      final noseBase = face.landmarks[FaceLandmarkType.noseBase];
      int missing = 0;
      if (leftEye == null) missing++;
      if (rightEye == null) missing++;
      if (noseBase == null) missing++;
      return (missing / 3.0).clamp(0.0, 1.0);
    } catch (_) {
      return 0.2;
    }
  }
}
