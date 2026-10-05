import 'package:flutter/foundation.dart';
import 'package:naveye/services/detector_service.dart';

class FinderFeedback {
  final bool isFound;
  final String targetLabel;
  final String spokenTextTa;
  final double alignmentScore; // 0.0 (far/off-screen) to 1.0 (perfectly centered & close)
  final double distanceM;
  final bool isReachable; // within 0.8 meters

  const FinderFeedback({
    required this.isFound,
    required this.targetLabel,
    required this.spokenTextTa,
    required this.alignmentScore,
    required this.distanceM,
    required this.isReachable,
  });

  static FinderFeedback searching(String target) => FinderFeedback(
    isFound: false,
    targetLabel: target,
    spokenTextTa: '$target தேடப்படுகிறது. கேமராவை மெதுவாக சுழற்றவும்.',
    alignmentScore: 0.0,
    distanceM: 10.0,
    isReachable: false,
  );
}

class ObjectFinderService {
  ObjectFinderService._();
  static final ObjectFinderService instance = ObjectFinderService._();

  String? _activeTarget;
  String? get activeTarget => _activeTarget;
  bool get isActive => _activeTarget != null;

  DateTime _lastAnnouncement = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastSpoken = '';

  /// Maps Tamil / English query terms to COCO model detection classes
  static const Map<String, List<String>> _targetSynonyms = {
    'bottle': ['bottle'],
    'பாட்டில்': ['bottle'],
    'phone': ['cell phone'],
    'cell phone': ['cell phone'],
    'போன்': ['cell phone'],
    'செல்போன்': ['cell phone'],
    'மொபைல்': ['cell phone'],
    'key': ['remote', 'mouse', 'cell phone'],
    'keys': ['remote', 'mouse', 'cell phone'],
    'சாவி': ['remote', 'mouse', 'cell phone'],
    'chair': ['chair'],
    'நாற்காலி': ['chair'],
    'laptop': ['laptop'],
    'லேப்டாப்': ['laptop'],
    'கணினி': ['laptop'],
    'book': ['book'],
    'புத்தகம்': ['book'],
    'cup': ['cup'],
    'கப்': ['cup'],
    'கோப்பை': ['cup'],
    'bag': ['backpack', 'handbag'],
    'backpack': ['backpack'],
    'பேக்': ['backpack', 'handbag'],
    'கைப்பை': ['handbag'],
    'umbrella': ['umbrella'],
    'குடை': ['umbrella'],
  };

  /// Set the active search target from user speech
  String? setTargetFromQuery(String query) {
    final lower = query.toLowerCase().trim();
    for (final entry in _targetSynonyms.entries) {
      if (lower.contains(entry.key)) {
        _activeTarget = entry.value.first;
        _lastSpoken = '';
        debugPrint('ObjectFinder: active target set to $_activeTarget for query "$query"');
        return _activeTarget;
      }
    }

    // Direct match with COCO classes
    _activeTarget = lower;
    _lastSpoken = '';
    return _activeTarget;
  }

  void cancel() {
    _activeTarget = null;
    _lastSpoken = '';
  }

  /// Evaluates detection results during finder mode
  FinderFeedback? evaluateDetections(List<DetectionResult> detections, DateTime now) {
    if (_activeTarget == null) return null;

    final targetClasses = _targetSynonyms[_activeTarget] ?? [_activeTarget!];

    // Find best match matching any of the target classes
    DetectionResult? bestMatch;
    for (final det in detections) {
      final matches = targetClasses.any((cls) =>
          det.label.toLowerCase().contains(cls) || det.rawLabel.toLowerCase().contains(cls));
      if (matches) {
        if (bestMatch == null || det.distanceM < bestMatch.distanceM) {
          bestMatch = det;
        }
      }
    }

    if (bestMatch == null) {
      // Throttle searching announcement to every 5 seconds
      if (now.difference(_lastAnnouncement).inMilliseconds >= 5000) {
        _lastAnnouncement = now;
        final nameTa = getTamilName(_activeTarget!);
        return FinderFeedback.searching(nameTa);
      }
      return null;
    }

    // Calculate centering score
    final xCenter = bestMatch.xCenter;
    final dist = bestMatch.distanceM;
    final centerOffset = (xCenter - 0.5).abs();
    final isCentered = centerOffset <= 0.15;
    final isReachable = dist <= 0.85;

    // Alignment score 0.0 to 1.0
    final alignmentScore = ((1.0 - centerOffset * 2.0).clamp(0.0, 1.0) * 0.5) +
        ((1.0 - (dist / 4.0)).clamp(0.0, 1.0) * 0.5);

    final nameTa = getTamilName(bestMatch.label);
    String messageTa;

    if (isReachable && isCentered) {
      messageTa = '$nameTa நேராக உங்கள் அருகில் உள்ளது! கையை நீட்டி எடுக்கலாம்.';
    } else if (isReachable) {
      final side = xCenter < 0.5 ? 'இடப்பக்கம்' : 'வலப்பக்கம்';
      messageTa = '$nameTa உங்கள் அருகில் $side உள்ளது.';
    } else if (isCentered) {
      messageTa = '$nameTa நேராக முன்னால் உள்ளது. தூரம் ${dist.toStringAsFixed(1)} மீட்டர்.';
    } else if (xCenter < 0.35) {
      messageTa = '$nameTa இடப்பக்கம் உள்ளது. இடதுபுறம் திரும்பவும்.';
    } else {
      messageTa = '$nameTa வலப்பக்கம் உள்ளது. வலதுபுறம் திரும்பவும்.';
    }

    // Cooldown logic: do not speak identical message within 2.5 seconds
    if (now.difference(_lastAnnouncement).inMilliseconds >= 2500 || messageTa != _lastSpoken) {
      _lastAnnouncement = now;
      _lastSpoken = messageTa;

      return FinderFeedback(
        isFound: true,
        targetLabel: nameTa,
        spokenTextTa: messageTa,
        alignmentScore: alignmentScore,
        distanceM: dist,
        isReachable: isReachable,
      );
    }

    return null;
  }

  String getTamilName(String englishLabel) {
    final lower = englishLabel.toLowerCase();
    if (lower.contains('bottle')) return 'பாட்டில்';
    if (lower.contains('phone')) return 'செல்போன்';
    if (lower.contains('remote') || lower.contains('mouse')) return 'சாவி அல்லது சாதனம்';
    if (lower.contains('chair')) return 'நாற்காலி';
    if (lower.contains('laptop')) return 'லேப்டாப்';
    if (lower.contains('book')) return 'புத்தகம்';
    if (lower.contains('cup')) return 'கோப்பை';
    if (lower.contains('backpack') || lower.contains('bag')) return 'பை';
    if (lower.contains('umbrella')) return 'குடை';
    return englishLabel;
  }
}
