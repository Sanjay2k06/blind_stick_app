import 'package:flutter_test/flutter_test.dart';
import 'package:naveye/services/face_quality_service.dart';
import 'package:naveye/services/sync_queue_service.dart';

void main() {
  group('FaceQualityService', () {
    test('accepts a good-quality face and rejects a poor one', () {
      final good = FaceQualityService().evaluateCandidate(
        detectionConfidence: 0.94,
        faceSizeRatio: 0.18,
        brightness: 135,
        sharpness: 0.82,
        temporalStability: 0.9,
        frontalness: 0.85,
        occlusion: 0.08,
      );

      final poor = FaceQualityService().evaluateCandidate(
        detectionConfidence: 0.34,
        faceSizeRatio: 0.04,
        brightness: 18,
        sharpness: 0.18,
        temporalStability: 0.2,
        frontalness: 0.32,
        occlusion: 0.68,
      );

      expect(good.passed, isTrue);
      expect(good.score, greaterThanOrEqualTo(FaceQualityService.defaultConfig.minScore));
      expect(poor.passed, isFalse);
      expect(poor.score, lessThan(FaceQualityService.defaultConfig.minScore));
    });

    test('temporal stability requires multiple consistent observations', () {
      final tracker = FaceQualityService();
      final now = DateTime.now();

      final first = tracker.evaluateCandidate(
        detectionConfidence: 0.88,
        faceSizeRatio: 0.16,
        brightness: 120,
        sharpness: 0.8,
        temporalStability: 0.5,
        frontalness: 0.72,
        occlusion: 0.1,
        observationTime: now,
      );

      final second = tracker.evaluateCandidate(
        detectionConfidence: 0.9,
        faceSizeRatio: 0.17,
        brightness: 125,
        sharpness: 0.82,
        temporalStability: 0.78,
        frontalness: 0.75,
        occlusion: 0.09,
        observationTime: now.add(const Duration(milliseconds: 250)),
      );

      final third = tracker.evaluateCandidate(
        detectionConfidence: 0.91,
        faceSizeRatio: 0.18,
        brightness: 128,
        sharpness: 0.84,
        temporalStability: 0.88,
        frontalness: 0.77,
        occlusion: 0.08,
        observationTime: now.add(const Duration(milliseconds: 500)),
      );

      expect(first.passed || second.passed || third.passed, isTrue);
      expect(tracker.isStableForRegistration(['good', 'good', 'good']), isTrue);
    });
  });

  group('SyncQueueService', () {
    test('queue state transitions follow pending to synced with retries', () {
      final state = SyncQueueService.nextStatus('pending', 0, 0);
      final failed = SyncQueueService.nextStatus('failed', 2, 120000);
      final retryDelay = SyncQueueService.retryDelaySeconds(3);

      expect(state, 'syncing');
      expect(failed, 'syncing');
      expect(retryDelay, greaterThan(0));
    });
  });
}
