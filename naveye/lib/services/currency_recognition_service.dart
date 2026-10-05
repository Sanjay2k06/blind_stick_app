import 'dart:math';
import 'package:image/image.dart' as img;

/// Supported Indian Rupee Banknotes
enum InrDenomination {
  ten,
  twenty,
  fifty,
  oneHundred,
  twoHundred,
  fiveHundred,
  unknown,
}

class CurrencyResult {
  final InrDenomination denomination;
  final int value;
  final String spokenTextTa;
  final String spokenTextEn;
  final double confidence;
  final bool isConfident;

  const CurrencyResult({
    required this.denomination,
    required this.value,
    required this.spokenTextTa,
    required this.spokenTextEn,
    required this.confidence,
    required this.isConfident,
  });

  static const CurrencyResult notFound = CurrencyResult(
    denomination: InrDenomination.unknown,
    value: 0,
    spokenTextTa: 'ரூபாய் நோட்டு தெளிவாகத் தெரியவில்லை. கேமராவிற்கு அருகில் நேராகக் காட்டவும்.',
    spokenTextEn: 'Banknote not clearly visible. Please hold it closer to the camera.',
    confidence: 0.0,
    isConfident: false,
  );
}

class CurrencyRecognitionService {
  CurrencyRecognitionService._();
  static final CurrencyRecognitionService instance = CurrencyRecognitionService._();

  /// Map of denominations to Tamil announcements
  static const Map<InrDenomination, String> _tamilNames = {
    InrDenomination.ten: 'பத்து ரூபாய் நோட்டு',
    InrDenomination.twenty: 'இருபது ரூபாய் நோட்டு',
    InrDenomination.fifty: 'ஐம்பது ரூபாய் நோட்டு',
    InrDenomination.oneHundred: 'நூறு ரூபாய் நோட்டு',
    InrDenomination.twoHundred: 'இருநூறு ரூபாய் நோட்டு',
    InrDenomination.fiveHundred: 'ஐநூறு ரூபாய் நோட்டு',
    InrDenomination.unknown: 'ரூபாய் நோட்டு தெளிவாகத் தெரியவில்லை.',
  };

  static const Map<InrDenomination, int> _values = {
    InrDenomination.ten: 10,
    InrDenomination.twenty: 20,
    InrDenomination.fifty: 50,
    InrDenomination.oneHundred: 100,
    InrDenomination.twoHundred: 200,
    InrDenomination.fiveHundred: 500,
    InrDenomination.unknown: 0,
  };

  /// Recognizes an Indian Rupee note from a camera frame with optional OCR text.
  CurrencyResult recognize({
    required img.Image image,
    String? ocrText,
  }) {
    // 1. First priority: Check OCR digits if text is available
    if (ocrText != null && ocrText.isNotEmpty) {
      final ocrMatch = _matchFromText(ocrText);
      if (ocrMatch != InrDenomination.unknown) {
        return CurrencyResult(
          denomination: ocrMatch,
          value: _values[ocrMatch]!,
          spokenTextTa: _tamilNames[ocrMatch]!,
          spokenTextEn: '${_values[ocrMatch]} Rupees note',
          confidence: 0.95,
          isConfident: true,
        );
      }
    }

    // 2. Second priority: Color histogram analysis on central crop
    final colorMatch = _matchFromColor(image);
    if (colorMatch.denomination != InrDenomination.unknown && colorMatch.confidence >= 0.55) {
      return colorMatch;
    }

    return CurrencyResult.notFound;
  }

  /// OCR text numeral extraction
  InrDenomination _matchFromText(String text) {
    final clean = text.replaceAll(RegExp(r'[^0-9]'), ' ');
    final tokens = clean.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    if (tokens.contains('500')) return InrDenomination.fiveHundred;
    if (tokens.contains('200')) return InrDenomination.twoHundred;
    if (tokens.contains('100')) return InrDenomination.oneHundred;
    if (tokens.contains('50')) return InrDenomination.fifty;
    if (tokens.contains('20')) return InrDenomination.twenty;
    if (tokens.contains('10')) return InrDenomination.ten;

    // Check substring matches
    if (text.contains('500')) return InrDenomination.fiveHundred;
    if (text.contains('200')) return InrDenomination.twoHundred;
    if (text.contains('100')) return InrDenomination.oneHundred;
    if (text.contains('50')) return InrDenomination.fifty;
    if (text.contains('20')) return InrDenomination.twenty;
    if (text.contains('10')) return InrDenomination.ten;

    return InrDenomination.unknown;
  }

  /// Color space classification for Indian Banknotes (New Mahatma Gandhi Series)
  CurrencyResult _matchFromColor(img.Image image) {
    final cx = image.width ~/ 2;
    final cy = image.height ~/ 2;
    final rx = image.width ~/ 4;
    final ry = image.height ~/ 4;

    double totalR = 0, totalG = 0, totalB = 0;
    int sampled = 0;

    // Sample central 50% grid
    final step = max(2, (image.width ~/ 80));
    for (int y = cy - ry; y < cy + ry; y += step) {
      for (int x = cx - rx; x < cx + rx; x += step) {
        if (x < 0 || x >= image.width || y < 0 || y >= image.height) continue;
        final p = image.getPixel(x, y);
        totalR += p.r;
        totalG += p.g;
        totalB += p.b;
        sampled++;
      }
    }

    if (sampled == 0) return CurrencyResult.notFound;

    final avgR = totalR / sampled;
    final avgG = totalG / sampled;
    final avgB = totalB / sampled;

    // Convert average RGB to HSV
    final hsv = _rgbToHsv(avgR, avgG, avgB);
    final h = hsv[0]; // 0 - 360
    final s = hsv[1]; // 0.0 - 1.0
    final v = hsv[2]; // 0.0 - 1.0

    InrDenomination detected = InrDenomination.unknown;
    double score = 0.0;

    // ₹500: Stone Grey (Low saturation, balanced RGB)
    if (s < 0.20 && v > 0.30 && v < 0.85 && (avgR - avgG).abs() < 25 && (avgG - avgB).abs() < 25) {
      detected = InrDenomination.fiveHundred;
      score = 0.80 - s; // lower saturation = higher confidence
    }
    // ₹200: Bright Yellow / Orange-Yellow
    else if (h >= 32 && h <= 52 && s >= 0.40 && v >= 0.50 && avgR > avgG && avgG > avgB) {
      detected = InrDenomination.twoHundred;
      score = 0.75 + min(0.20, s * 0.2);
    }
    // ₹100: Lavender / Purple (Blue > Green, high hue 235 - 295)
    else if (h >= 235 && h <= 295 && s >= 0.15 && v >= 0.35 && avgB > avgG) {
      detected = InrDenomination.oneHundred;
      score = 0.75 + min(0.20, s * 0.2);
    }
    // ₹50: Fluorescent Blue / Cyan (H: 165 - 225, B > R)
    else if (h >= 165 && h <= 225 && s >= 0.25 && v >= 0.35 && avgB > avgR) {
      detected = InrDenomination.fifty;
      score = 0.75 + min(0.20, s * 0.2);
    }
    // ₹20: Greenish Yellow (H: 55 - 90, Green dominant)
    else if (h >= 55 && h <= 90 && s >= 0.25 && v >= 0.40 && avgG > avgB) {
      detected = InrDenomination.twenty;
      score = 0.75;
    }
    // ₹10: Chocolate Brown (H: 12 - 32, Red > Green > Blue, moderate to low V)
    else if (h >= 10 && h <= 32 && s >= 0.20 && v <= 0.60 && avgR > avgG && avgG > avgB) {
      detected = InrDenomination.ten;
      score = 0.70;
    }

    if (detected != InrDenomination.unknown) {
      return CurrencyResult(
        denomination: detected,
        value: _values[detected]!,
        spokenTextTa: _tamilNames[detected]!,
        spokenTextEn: '${_values[detected]} Rupees note',
        confidence: score.clamp(0.0, 0.95),
        isConfident: score >= 0.60,
      );
    }

    return CurrencyResult.notFound;
  }

  /// RGB [0..255] to HSV [H 0..360, S 0..1, V 0..1]
  List<double> _rgbToHsv(double r, double g, double b) {
    r /= 255.0;
    g /= 255.0;
    b /= 255.0;

    final maxVal = max(r, max(g, b));
    final minVal = min(r, min(g, b));
    final delta = maxVal - minVal;

    double h = 0;
    if (delta > 0.00001) {
      if (maxVal == r) {
        h = 60.0 * (((g - b) / delta) % 6);
      } else if (maxVal == g) {
        h = 60.0 * (((b - r) / delta) + 2);
      } else {
        h = 60.0 * (((r - g) / delta) + 4);
      }
    }
    if (h < 0) h += 360.0;

    final s = maxVal == 0 ? 0.0 : delta / maxVal;
    final v = maxVal;
    return [h, s, v];
  }
}
