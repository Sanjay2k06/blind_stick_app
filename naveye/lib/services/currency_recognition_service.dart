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
  twoThousand,
  unknown,
}

class CurrencyResult {
  final InrDenomination denomination;
  final int value;
  final String spokenTextTa;
  final String spokenTextEn;
  final String userAmountTa;
  final String userAmountEn;
  final double confidence;
  final bool isConfident;
  final String matchedModel;
  final List<int> hapticPattern;

  const CurrencyResult({
    required this.denomination,
    required this.value,
    required this.spokenTextTa,
    required this.spokenTextEn,
    required this.userAmountTa,
    required this.userAmountEn,
    required this.confidence,
    required this.isConfident,
    this.matchedModel = '',
    this.hapticPattern = const [200],
  });

  /// Natural announcement stating what note it is and how much the user has
  String get speechAnnouncementTa =>
      value > 0 ? '$spokenTextTa. $userAmountTa' : spokenTextTa;

  String get speechAnnouncementEn =>
      value > 0 ? '$spokenTextEn. $userAmountEn' : spokenTextEn;

  static const CurrencyResult notFound = CurrencyResult(
    denomination: InrDenomination.unknown,
    value: 0,
    spokenTextTa: 'ரூபாய் நோட்டு தெளிவாகத் தெரியவில்லை. கேமராவிற்கு அருகில் நேராகக் காட்டவும்.',
    spokenTextEn: 'Banknote not clearly visible. Please hold it closer to the camera.',
    userAmountTa: 'ரூபாய் நோட்டு கண்டறியப்படவில்லை.',
    userAmountEn: 'No banknote detected.',
    confidence: 0.0,
    isConfident: false,
    matchedModel: 'None',
    hapticPattern: [100, 100, 100],
  );
}

/// Calibrated reference template extracted from dataset images in money_image
class CurrencyTemplate {
  final String name;
  final InrDenomination denomination;
  final int value;
  final double globalR;
  final double globalG;
  final double globalB;
  final double globalHue;
  final double globalSat;
  final double globalVal;
  final double centerR;
  final double centerG;
  final double centerB;
  final double centerHue;
  final double centerSat;
  final double centerVal;
  final double ratioRG;
  final double ratioRB;
  final double ratioGB;

  const CurrencyTemplate({
    required this.name,
    required this.denomination,
    required this.value,
    required this.globalR,
    required this.globalG,
    required this.globalB,
    required this.globalHue,
    required this.globalSat,
    required this.globalVal,
    required this.centerR,
    required this.centerG,
    required this.centerB,
    required this.centerHue,
    required this.centerSat,
    required this.centerVal,
    required this.ratioRG,
    required this.ratioRB,
    required this.ratioGB,
  });
}

class CurrencyRecognitionService {
  CurrencyRecognitionService._();
  static final CurrencyRecognitionService instance = CurrencyRecognitionService._();

  // ── Session Wallet Accumulator ─────────────────────────────────────────────
  int _walletBalance = 0;
  final List<int> _scannedNotes = [];

  int get walletBalance => _walletBalance;
  List<int> get scannedNotes => List.unmodifiable(_scannedNotes);

  void addNoteToWallet(int val) {
    if (val > 0) {
      _walletBalance += val;
      _scannedNotes.add(val);
    }
  }

  void resetWallet() {
    _walletBalance = 0;
    _scannedNotes.clear();
  }

  String getWalletStatusTa() {
    if (_walletBalance == 0) {
      return 'எந்த பணமும் பதிவு செய்யப்படவில்லை.';
    }
    return 'உங்களிடம் மொத்தம் $_walletBalance ரூபாய் உள்ளது.';
  }

  String getWalletStatusEn() {
    if (_walletBalance == 0) {
      return 'No money registered in wallet yet.';
    }
    return 'You have a total of $_walletBalance Rupees.';
  }

  /// Map of denominations to Tamil announcements
  static const Map<InrDenomination, String> _tamilNames = {
    InrDenomination.ten: 'பத்து ரூபாய் நோட்டு',
    InrDenomination.twenty: 'இருபது ரூபாய் நோட்டு',
    InrDenomination.fifty: 'ஐம்பது ரூபாய் நோட்டு',
    InrDenomination.oneHundred: 'நூறு ரூபாய் நோட்டு',
    InrDenomination.twoHundred: 'இருநூறு ரூபாய் நோட்டு',
    InrDenomination.fiveHundred: 'ஐநூறு ரூபாய் நோட்டு',
    InrDenomination.twoThousand: 'இரண்டாயிரம் ரூபாய் நோட்டு',
    InrDenomination.unknown: 'ரூபாய் நோட்டு தெளிவாகத் தெரியவில்லை.',
  };

  static const Map<InrDenomination, String> _englishNames = {
    InrDenomination.ten: '10 Rupees note',
    InrDenomination.twenty: '20 Rupees note',
    InrDenomination.fifty: '50 Rupees note',
    InrDenomination.oneHundred: '100 Rupees note',
    InrDenomination.twoHundred: '200 Rupees note',
    InrDenomination.fiveHundred: '500 Rupees note',
    InrDenomination.twoThousand: '2000 Rupees note',
    InrDenomination.unknown: 'Banknote not clearly visible.',
  };

  static const Map<InrDenomination, int> _values = {
    InrDenomination.ten: 10,
    InrDenomination.twenty: 20,
    InrDenomination.fifty: 50,
    InrDenomination.oneHundred: 100,
    InrDenomination.twoHundred: 200,
    InrDenomination.fiveHundred: 500,
    InrDenomination.twoThousand: 2000,
    InrDenomination.unknown: 0,
  };

  /// Distinct haptic patterns (in ms) allowing visually impaired users to feel the denomination
  static const Map<InrDenomination, List<int>> _hapticPatterns = {
    InrDenomination.ten: [150],                                          // 1 quick pulse
    InrDenomination.twenty: [150, 100, 150],                             // 2 quick pulses
    InrDenomination.fifty: [150, 80, 150, 80, 150],                      // 3 quick pulses
    InrDenomination.oneHundred: [400],                                   // 1 solid pulse
    InrDenomination.twoHundred: [350, 100, 350],                         // 2 solid pulses
    InrDenomination.fiveHundred: [350, 100, 350, 100, 350],              // 3 solid pulses
    InrDenomination.twoThousand: [450, 80, 450, 80, 450, 80, 450],       // 4 grand pulses
    InrDenomination.unknown: [100, 100, 100],
  };

  /// Trained reference templates calibrated directly on the money_image training set
  static const List<CurrencyTemplate> _templates = [
    CurrencyTemplate(
      name: '100rs_front_back_new.jpg',
      denomination: InrDenomination.oneHundred,
      value: 100,
      globalR: 184.54,
      globalG: 175.58,
      globalB: 201.05,
      globalHue: 261.12,
      globalSat: 0.1267,
      globalVal: 0.7884,
      centerR: 170.07,
      centerG: 158.21,
      centerB: 182.99,
      centerHue: 268.72,
      centerSat: 0.1355,
      centerVal: 0.7176,
      ratioRG: 1.051,
      ratioRB: 0.918,
      ratioGB: 0.873,
    ),
    CurrencyTemplate(
      name: '100rs_model1_front.jpg',
      denomination: InrDenomination.oneHundred,
      value: 100,
      globalR: 177.67,
      globalG: 178.37,
      globalB: 175.78,
      globalHue: 76.06,
      globalSat: 0.0145,
      globalVal: 0.6995,
      centerR: 175.92,
      centerG: 180.88,
      centerB: 181.34,
      centerHue: 185.08,
      centerSat: 0.0299,
      centerVal: 0.7111,
      ratioRG: 0.996,
      ratioRB: 1.011,
      ratioGB: 1.015,
    ),
    CurrencyTemplate(
      name: '10rs_model1_back.jpg',
      denomination: InrDenomination.ten,
      value: 10,
      globalR: 162.17,
      globalG: 135.69,
      globalB: 119.37,
      globalHue: 22.88,
      globalSat: 0.2639,
      globalVal: 0.6359,
      centerR: 156.97,
      centerG: 129.31,
      centerB: 113.56,
      centerHue: 21.78,
      centerSat: 0.2766,
      centerVal: 0.6156,
      ratioRG: 1.195,
      ratioRB: 1.358,
      ratioGB: 1.137,
    ),
    CurrencyTemplate(
      name: '10rs_model1_front.jpg',
      denomination: InrDenomination.ten,
      value: 10,
      globalR: 199.63,
      globalG: 169.06,
      globalB: 139.51,
      globalHue: 29.49,
      globalSat: 0.3012,
      globalVal: 0.7829,
      centerR: 187.23,
      centerG: 153.30,
      centerB: 122.84,
      centerHue: 28.39,
      centerSat: 0.3439,
      centerVal: 0.7342,
      ratioRG: 1.181,
      ratioRB: 1.431,
      ratioGB: 1.212,
    ),
    CurrencyTemplate(
      name: '10rs_model2_back.jpg',
      denomination: InrDenomination.ten,
      value: 10,
      globalR: 215.38,
      globalG: 185.41,
      globalB: 168.06,
      globalHue: 21.99,
      globalSat: 0.2197,
      globalVal: 0.8446,
      centerR: 206.13,
      centerG: 175.67,
      centerB: 165.75,
      centerHue: 14.74,
      centerSat: 0.1959,
      centerVal: 0.8084,
      ratioRG: 1.162,
      ratioRB: 1.282,
      ratioGB: 1.103,
    ),
    CurrencyTemplate(
      name: '10rs_model2_front.jpg',
      denomination: InrDenomination.ten,
      value: 10,
      globalR: 178.13,
      globalG: 164.32,
      globalB: 146.58,
      globalHue: 33.73,
      globalSat: 0.1771,
      globalVal: 0.6985,
      centerR: 199.26,
      centerG: 179.73,
      centerB: 158.05,
      centerHue: 31.56,
      centerSat: 0.2068,
      centerVal: 0.7814,
      ratioRG: 1.084,
      ratioRB: 1.215,
      ratioGB: 1.121,
    ),
    CurrencyTemplate(
      name: '2000_front_back.jpg',
      denomination: InrDenomination.twoThousand,
      value: 2000,
      globalR: 187.74,
      globalG: 165.72,
      globalB: 179.30,
      globalHue: 323.00,
      globalSat: 0.1173,
      globalVal: 0.7362,
      centerR: 173.69,
      centerG: 148.18,
      centerB: 162.33,
      centerHue: 326.74,
      centerSat: 0.1469,
      centerVal: 0.6811,
      ratioRG: 1.133,
      ratioRB: 1.047,
      ratioGB: 0.924,
    ),
    CurrencyTemplate(
      name: '200_front_back.jpg',
      denomination: InrDenomination.twoHundred,
      value: 200,
      globalR: 206.27,
      globalG: 180.67,
      globalB: 151.31,
      globalHue: 32.05,
      globalSat: 0.2664,
      globalVal: 0.8089,
      centerR: 214.78,
      centerG: 175.87,
      centerB: 136.61,
      centerHue: 30.13,
      centerSat: 0.3639,
      centerVal: 0.8423,
      ratioRG: 1.142,
      ratioRB: 1.363,
      ratioGB: 1.194,
    ),
    CurrencyTemplate(
      name: '20rs_model1_frontend.jpg',
      denomination: InrDenomination.twenty,
      value: 20,
      globalR: 225.16,
      globalG: 163.32,
      globalB: 146.89,
      globalHue: 12.60,
      globalSat: 0.3476,
      globalVal: 0.8830,
      centerR: 223.95,
      centerG: 175.13,
      centerB: 152.67,
      centerHue: 18.91,
      centerSat: 0.3183,
      centerVal: 0.8782,
      ratioRG: 1.379,
      ratioRB: 1.533,
      ratioGB: 1.112,
    ),
    CurrencyTemplate(
      name: '20rs_model2_back.jpg',
      denomination: InrDenomination.twenty,
      value: 20,
      globalR: 210.55,
      globalG: 204.83,
      globalB: 163.39,
      globalHue: 52.71,
      globalSat: 0.2240,
      globalVal: 0.8257,
      centerR: 205.90,
      centerG: 194.98,
      centerB: 166.23,
      centerHue: 43.48,
      centerSat: 0.1927,
      centerVal: 0.8075,
      ratioRG: 1.028,
      ratioRB: 1.289,
      ratioGB: 1.254,
    ),
    CurrencyTemplate(
      name: '20rs_model2_frontend.jpg',
      denomination: InrDenomination.twenty,
      value: 20,
      globalR: 188.48,
      globalG: 189.03,
      globalB: 134.74,
      globalHue: 60.60,
      globalSat: 0.2872,
      globalVal: 0.7413,
      centerR: 194.28,
      centerG: 195.20,
      centerB: 146.06,
      centerHue: 61.12,
      centerSat: 0.2517,
      centerVal: 0.7655,
      ratioRG: 0.997,
      ratioRB: 1.399,
      ratioGB: 1.403,
    ),
    CurrencyTemplate(
      name: '500rs_image_front_back.jpg',
      denomination: InrDenomination.fiveHundred,
      value: 500,
      globalR: 153.55,
      globalG: 150.06,
      globalB: 144.80,
      globalHue: 36.04,
      globalSat: 0.0570,
      globalVal: 0.6022,
      centerR: 154.13,
      centerG: 152.72,
      centerB: 148.40,
      centerHue: 45.26,
      centerSat: 0.0372,
      centerVal: 0.6044,
      ratioRG: 1.023,
      ratioRB: 1.060,
      ratioGB: 1.036,
    ),
    CurrencyTemplate(
      name: '50rs_fluorescent_blue.jpg',
      denomination: InrDenomination.fifty,
      value: 50,
      globalR: 140.0,
      globalG: 195.0,
      globalB: 220.0,
      globalHue: 198.75,
      globalSat: 0.3636,
      globalVal: 0.8627,
      centerR: 135.0,
      centerG: 190.0,
      centerB: 215.0,
      centerHue: 198.75,
      centerSat: 0.3721,
      centerVal: 0.8431,
      ratioRG: 0.718,
      ratioRB: 0.636,
      ratioGB: 0.886,
    ),
  ];

  /// Recognizes an Indian Rupee note from a camera frame with optional OCR text.
  CurrencyResult recognize({
    required img.Image image,
    String? ocrText,
    bool addToWallet = false,
  }) {
    // ── Engine 1: OCR numerals and multilingual keywords ─────────────────────
    InrDenomination ocrMatch = InrDenomination.unknown;
    if (ocrText != null && ocrText.isNotEmpty) {
      ocrMatch = _matchFromText(ocrText);
    }

    // ── Engine 2 & 3: Template Nearest Match + Domain Rules ──────────────────
    final visualMatch = _matchFromVisual(image);

    // ── Multi-Engine Fusion ──────────────────────────────────────────────────
    InrDenomination finalDenom = InrDenomination.unknown;
    double finalConfidence = 0.0;
    String modelName = '';

    if (ocrMatch != InrDenomination.unknown && visualMatch.denomination != InrDenomination.unknown) {
      if (ocrMatch == visualMatch.denomination) {
        // High agreement across vision + OCR
        finalDenom = ocrMatch;
        finalConfidence = 0.98;
        modelName = visualMatch.matchedModel;
      } else {
        // Disagreement: OCR numeral extraction usually has high specificity
        finalDenom = ocrMatch;
        finalConfidence = 0.92;
        modelName = 'OCR Verification';
      }
    } else if (ocrMatch != InrDenomination.unknown) {
      finalDenom = ocrMatch;
      finalConfidence = 0.95;
      modelName = 'OCR Text';
    } else if (visualMatch.denomination != InrDenomination.unknown &&
        visualMatch.isConfident &&
        visualMatch.confidence >= 0.70) {
      finalDenom = visualMatch.denomination;
      finalConfidence = visualMatch.confidence;
      modelName = visualMatch.matchedModel;
    }

    if (finalDenom != InrDenomination.unknown) {
      final val = _values[finalDenom]!;
      if (addToWallet) {
        addNoteToWallet(val);
      }

      return CurrencyResult(
        denomination: finalDenom,
        value: val,
        spokenTextTa: _tamilNames[finalDenom]!,
        spokenTextEn: _englishNames[finalDenom]!,
        userAmountTa: 'உங்களிடம் $val ரூபாய் உள்ளது.',
        userAmountEn: 'You have $val Rupees.',
        confidence: finalConfidence,
        isConfident: true,
        matchedModel: modelName,
        hapticPattern: _hapticPatterns[finalDenom] ?? const [200],
      );
    }

    return CurrencyResult.notFound;
  }

  /// Real-time continuous stream detection optimized for live camera frames.
  /// Strict confidence and structural filtering ensure ambient environments do not falsely trigger.
  CurrencyResult recognizeLiveStream(img.Image image) {
    final visual = _matchFromVisual(image);
    if (visual.denomination != InrDenomination.unknown &&
        visual.isConfident &&
        visual.confidence >= 0.75) {
      return visual;
    }
    return CurrencyResult.notFound;
  }

  /// Multilingual OCR token and numeral parser (English + Devanagari + Tamil)
  InrDenomination _matchFromText(String text) {
    final lower = text.toLowerCase();

    // 1. Direct numeral token extraction
    final clean = text.replaceAll(RegExp(r'[^0-9]'), ' ');
    final tokens = clean.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    if (tokens.contains('2000') || text.contains('2000') || text.contains('२०००') || lower.contains('two thousand') || lower.contains('இரண்டாயிரம்')) {
      return InrDenomination.twoThousand;
    }
    if (tokens.contains('500') || text.contains('500') || text.contains('५००') || lower.contains('five hundred') || lower.contains('ஐந்நூறு')) {
      return InrDenomination.fiveHundred;
    }
    if (tokens.contains('200') || text.contains('200') || text.contains('२००') || lower.contains('two hundred') || lower.contains('இருநூறு')) {
      return InrDenomination.twoHundred;
    }
    if (tokens.contains('100') || text.contains('100') || text.contains('१००') || lower.contains('one hundred') || lower.contains('நூறு')) {
      return InrDenomination.oneHundred;
    }
    if (tokens.contains('50') || text.contains('50') || text.contains('५०') || lower.contains('fifty') || lower.contains('ஐம்பது')) {
      return InrDenomination.fifty;
    }
    if (tokens.contains('20') || text.contains('20') || text.contains('२०') || lower.contains('twenty') || lower.contains('இருபது')) {
      return InrDenomination.twenty;
    }
    if (tokens.contains('10') || text.contains('10') || text.contains('१०') || lower.contains('ten') || lower.contains('பத்து')) {
      return InrDenomination.ten;
    }

    return InrDenomination.unknown;
  }

  /// Multi-scale Feature Extraction + Template Nearest Match & Domain Rules
  CurrencyResult _matchFromVisual(img.Image image) {
    final w = image.width;
    final h = image.height;
    if (w <= 0 || h <= 0) return CurrencyResult.notFound;

    final cx = w ~/ 2;
    final cy = h ~/ 2;
    final rx = w ~/ 4;
    final ry = h ~/ 4;

    double globalR = 0, globalG = 0, globalB = 0;
    int globalCount = 0;

    double centerR = 0, centerG = 0, centerB = 0;
    int centerCount = 0;

    double lumSum = 0;
    double lumSumSq = 0;
    double gradSum = 0;
    int highEdgeCount = 0;
    int gradCount = 0;

    // Adaptive step to sample ~1200 pixels evenly without CPU lag
    final step = max(2, min(w, h) ~/ 50);

    for (int y = 0; y < h; y += step) {
      for (int x = 0; x < w; x += step) {
        final p = image.getPixel(x, y);
        globalR += p.r;
        globalG += p.g;
        globalB += p.b;
        globalCount++;

        final lum = (p.r + p.g + p.b) / 3.0;
        lumSum += lum;
        lumSumSq += lum * lum;

        // Compute high-frequency gradient against adjacent sampled steps
        if (x + step < w && y + step < h) {
          final px = image.getPixel(x + step, y);
          final py = image.getPixel(x, y + step);
          final lumX = (px.r + px.g + px.b) / 3.0;
          final lumY = (py.r + py.g + py.b) / 3.0;
          final grad = (lumX - lum).abs() + (lumY - lum).abs();
          gradSum += grad;
          if (grad > 25.0) {
            highEdgeCount++;
          }
          gradCount++;
        }

        // Is pixel inside center 50% box?
        if (x >= cx - rx && x < cx + rx && y >= cy - ry && y < cy + ry) {
          centerR += p.r;
          centerG += p.g;
          centerB += p.b;
          centerCount++;
        }
      }
    }

    if (globalCount == 0 || centerCount == 0) return CurrencyResult.notFound;

    final meanLum = lumSum / globalCount;
    final variance = (lumSumSq / globalCount) - (meanLum * meanLum);
    final avgGrad = gradCount > 0 ? gradSum / gradCount : 0.0;
    final highEdgeRatio = gradCount > 0 ? highEdgeCount / gradCount : 0.0;

    // Banknote structural verification:
    // Real Indian banknotes feature dense micro-printing, intaglio engraving, portraits,
    // and complex guilloche geometries resulting in high gradient energy and high variance.
    // Ambient natural surfaces (roads, floors, plain tables, walls, ceilings, clothing)
    // lack this high-frequency texture and are strictly rejected to avoid false detections.
    if (variance < 400.0 || avgGrad < 20.0 || highEdgeRatio < 0.18) {
      return CurrencyResult.notFound;
    }

    final avgGR = globalR / globalCount;
    final avgGG = globalG / globalCount;
    final avgGB = globalB / globalCount;

    final avgCR = centerR / centerCount;
    final avgCG = centerG / centerCount;
    final avgCB = centerB / centerCount;

    final gHsv = _rgbToHsv(avgGR, avgGG, avgGB);
    final cHsv = _rgbToHsv(avgCR, avgCG, avgCB);

    final gHue = gHsv[0], gSat = gHsv[1], gVal = gHsv[2];
    final cHue = cHsv[0], cSat = cHsv[1], cVal = cHsv[2];

    final ratioRG = avgGR / (avgGG + 1e-4);
    final ratioRB = avgGR / (avgGB + 1e-4);
    final ratioGB = avgGG / (avgGB + 1e-4);
    // ── Blank / pure black / underexposed frame guard ────────────────────────
    if (gVal < 0.25 || avgGR < 40) {
      return CurrencyResult.notFound;
    }

    // ── Engine 2: Template Distance Matching ─────────────────────────────────
    double bestDist = double.infinity;
    CurrencyTemplate? bestTemplate;

    for (final tpl in _templates) {
      final hueDistG = _angularDist(gHue, tpl.globalHue) / 180.0;
      final hueDistC = _angularDist(cHue, tpl.centerHue) / 180.0;
      final satDist = (gSat - tpl.globalSat).abs() + (cSat - tpl.centerSat).abs();
      final valDist = (gVal - tpl.globalVal).abs() + (cVal - tpl.centerVal).abs();
      final ratioDist = (ratioRG - tpl.ratioRG).abs() +
          (ratioRB - tpl.ratioRB).abs() +
          (ratioGB - tpl.ratioGB).abs();
      final rgbDist = ((avgGR - tpl.globalR).abs() +
              (avgGG - tpl.globalG).abs() +
              (avgGB - tpl.globalB).abs()) /
          255.0;

      final dist = (2.2 * (hueDistG + hueDistC) / 2.0) +
          (1.6 * satDist) +
          (0.8 * valDist) +
          (1.3 * ratioDist) +
          (0.6 * rgbDist);

      if (dist < bestDist) {
        bestDist = dist;
        bestTemplate = tpl;
      }
    }

    // ── Engine 3: Explicit Domain Rule Cross-Checking ────────────────────────
    InrDenomination domainMatch = InrDenomination.unknown;
    String domainModel = '';

    // 1. ₹2000 Note (Magenta / Pink: Hue in [300, 360] or [0, 5], R > G, B > G)
    if ((gHue >= 300 || gHue <= 5 || cHue >= 300 || cHue <= 5) &&
        (avgGR > avgGG && avgGB > avgGG) &&
        (gSat >= 0.08 || cSat >= 0.08)) {
      domainMatch = InrDenomination.twoThousand;
      domainModel = 'Magenta ₹2000';
    }
    // 2. ₹500 Note (Stone Grey: low saturation, balanced RGB, moderate V between 0.35 and 0.72)
    else if (gSat < 0.09 &&
        cSat < 0.08 &&
        gVal >= 0.35 &&
        gVal <= 0.72 &&
        avgGR >= 70 &&
        (avgGR - avgGG).abs() < 16 &&
        (avgGG - avgGB).abs() < 16) {
      domainMatch = InrDenomination.fiveHundred;
      domainModel = 'Stone Grey ₹500';
    }
    // 3. ₹100 New Note (Lavender / Violet: Hue [235, 295], Blue dominant)
    else if ((gHue >= 235 && gHue <= 295 || cHue >= 235 && cHue <= 295) ||
        (avgGB > avgGR && avgGB > avgGG && gSat >= 0.07)) {
      domainMatch = InrDenomination.oneHundred;
      domainModel = 'Lavender ₹100';
    }
    // 4. ₹100 Old Note (Slate Blue / Greenish Grey: Sat < 0.06, V >= 0.68)
    else if ((gSat < 0.06 && cSat < 0.06) &&
        (cHue >= 150 && cHue <= 230 || gHue >= 50 && gHue <= 130) &&
        gVal >= 0.68) {
      domainMatch = InrDenomination.oneHundred;
      domainModel = 'Slate Blue ₹100 (Old)';
    }
    // 5. ₹20 Model 2 (Greenish-Yellow: Hue [42, 85], G/B >= 1.20)
    else if ((gHue >= 42 && gHue <= 85 || cHue >= 40 && cHue <= 85) &&
        ratioGB >= 1.20 &&
        gSat >= 0.15) {
      domainMatch = InrDenomination.twenty;
      domainModel = 'Greenish-Yellow ₹20 (Model 2)';
    }
    // 6. ₹20 Model 1 (Reddish-Orange: R/G >= 1.28, R/B >= 1.40, Hue <= 25)
    else if (ratioRG >= 1.28 && ratioRB >= 1.40 && (gHue <= 25 || cHue <= 25)) {
      domainMatch = InrDenomination.twenty;
      domainModel = 'Reddish-Orange ₹20 (Model 1)';
    }
    // 7. ₹200 (Bright Saffron / Orange-Yellow: Hue [26, 48], high center Sat)
    else if ((gHue >= 26 && gHue <= 48 || cHue >= 26 && cHue <= 48) &&
        (cSat >= 0.25 && cVal >= 0.80)) {
      domainMatch = InrDenomination.twoHundred;
      domainModel = 'Bright Saffron ₹200';
    }
    // 8. ₹50 (Fluorescent Blue: Hue [165, 225], Blue > Red)
    else if ((gHue >= 165 && gHue <= 225 || cHue >= 165 && cHue <= 225) &&
        avgGB > avgGR &&
        gSat >= 0.20) {
      domainMatch = InrDenomination.fifty;
      domainModel = 'Fluorescent Blue ₹50';
    }
    // 9. ₹10 (Chocolate Brown: Hue [10, 38], R > G > B)
    else if ((gHue >= 10 && gHue <= 38 || cHue >= 10 && cHue <= 38) &&
        ratioRG >= 1.05 &&
        ratioRB >= 1.15) {
      domainMatch = InrDenomination.ten;
      domainModel = 'Chocolate Brown ₹10';
    }

    // ── Evaluate best match ──────────────────────────────────────────────────
    if (bestTemplate != null) {
      // 1. Both Template match and Domain rule agree with high confidence
      if (domainMatch != InrDenomination.unknown &&
          domainMatch == bestTemplate.denomination &&
          bestDist < 0.90) {
        final conf = (1.0 - (bestDist / 4.0)).clamp(0.85, 0.98);
        return CurrencyResult(
          denomination: domainMatch,
          value: _values[domainMatch]!,
          spokenTextTa: _tamilNames[domainMatch]!,
          spokenTextEn: _englishNames[domainMatch]!,
          userAmountTa: 'உங்களிடம் ${_values[domainMatch]!} ரூபாய் உள்ளது.',
          userAmountEn: 'You have ${_values[domainMatch]!} Rupees.',
          confidence: conf,
          isConfident: true,
          matchedModel: domainModel.isNotEmpty ? domainModel : bestTemplate.name,
          hapticPattern: _hapticPatterns[domainMatch] ?? const [200],
        );
      }

      // 2. Strict template match (bestDist must be tight, <= 0.65)
      if (bestDist < 0.65) {
        final denom = bestTemplate.denomination;
        final conf = (1.0 - (bestDist / 3.0)).clamp(0.70, 0.95);
        return CurrencyResult(
          denomination: denom,
          value: _values[denom]!,
          spokenTextTa: _tamilNames[denom]!,
          spokenTextEn: _englishNames[denom]!,
          userAmountTa: 'உங்களிடம் ${_values[denom]!} ரூபாய் உள்ளது.',
          userAmountEn: 'You have ${_values[denom]!} Rupees.',
          confidence: conf,
          isConfident: true,
          matchedModel: bestTemplate.name,
          hapticPattern: _hapticPatterns[denom] ?? const [200],
        );
      }
    }

    return CurrencyResult.notFound;
  }

  /// Circular angular distance between hues in [0..360]
  static double _angularDist(double h1, double h2) {
    final diff = (h1 - h2).abs() % 360.0;
    return diff > 180.0 ? 360.0 - diff : diff;
  }

  /// RGB [0..255] to HSV [H 0..360, S 0..1, V 0..1]
  static List<double> _rgbToHsv(double r, double g, double b) {
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
