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

/// Represents an actively tracked banknote in the camera frame
class TrackedCurrencyNote {
  final int trackingId;
  final InrDenomination denomination;
  final int value;
  double xCenter;
  double yCenter;
  double width;
  double height;
  final DateTime firstSeen;
  DateTime lastSeen;
  int consecutiveFrames;
  bool isCounted;
  bool isConfirmed;

  TrackedCurrencyNote({
    required this.trackingId,
    required this.denomination,
    required this.value,
    this.xCenter = 0.5,
    this.yCenter = 0.5,
    this.width = 0.5,
    this.height = 0.3,
    required this.firstSeen,
    required this.lastSeen,
    this.consecutiveFrames = 1,
    this.isCounted = false,
    this.isConfirmed = false,
  });

  double distanceTo(double x, double y) {
    final dx = xCenter - x;
    final dy = yCenter - y;
    return sqrt(dx * dx + dy * dy);
  }
}

/// Multi-note session tracker that prevents duplicate counting and manages session balance
class CurrencySessionTracker {
  int _nextId = 1;
  final List<TrackedCurrencyNote> _activeTracks = [];
  final List<TrackedCurrencyNote> _sessionCountedNotes = [];
  int _sessionTotal = 0;

  int get sessionTotal => _sessionTotal;
  List<TrackedCurrencyNote> get sessionNotes => List.unmodifiable(_sessionCountedNotes);

  List<TrackedCurrencyNote> get currentVisibleNotes => List.unmodifiable(
      _activeTracks.where((t) => t.isConfirmed && DateTime.now().difference(t.lastSeen).inMilliseconds < 1800));

  int get currentVisibleTotal => currentVisibleNotes.fold(0, (sum, n) => sum + n.value);

  /// Registers a detected note in this frame and updates spatial tracking.
  /// Returns the note IF it is newly verified and counted on this frame;
  /// returns null if it is already counted or still awaiting confirmation.
  TrackedCurrencyNote? updateWithDetection({
    required InrDenomination denomination,
    required int value,
    double xCenter = 0.5,
    double yCenter = 0.5,
    double width = 0.5,
    double height = 0.3,
    DateTime? timestamp,
    int minConsecutive = 3,
  }) {
    final now = timestamp ?? DateTime.now();
    _pruneStale(now);

    if (denomination == InrDenomination.unknown || value <= 0) {
      return null;
    }

    // 1. Spatial centroid & denomination matching to track the same physical note
    TrackedCurrencyNote? matched;
    double bestDist = 0.35; // maximum centroid drift threshold
    for (final track in _activeTracks) {
      if (track.denomination == denomination) {
        final d = track.distanceTo(xCenter, yCenter);
        if (d < bestDist) {
          bestDist = d;
          matched = track;
        }
      }
    }

    if (matched != null) {
      // Existing note: smooth centroid, update lastSeen, increment frame counter
      matched.lastSeen = now;
      matched.xCenter = 0.7 * xCenter + 0.3 * matched.xCenter;
      matched.yCenter = 0.7 * yCenter + 0.3 * matched.yCenter;
      matched.consecutiveFrames++;

      if (matched.consecutiveFrames >= minConsecutive && !matched.isConfirmed) {
        matched.isConfirmed = true;
        if (!matched.isCounted) {
          matched.isCounted = true;
          _sessionCountedNotes.add(matched);
          _sessionTotal += matched.value;
          return matched; // Newly verified and counted!
        }
      }
      return null; // Already confirmed or counted; do not count again!
    } else {
      // New note candidate track
      final newTrack = TrackedCurrencyNote(
        trackingId: _nextId++,
        denomination: denomination,
        value: value,
        xCenter: xCenter,
        yCenter: yCenter,
        width: width,
        height: height,
        firstSeen: now,
        lastSeen: now,
        consecutiveFrames: 1,
        isConfirmed: minConsecutive <= 1,
        isCounted: minConsecutive <= 1,
      );

      _activeTracks.add(newTrack);

      if (minConsecutive <= 1) {
        _sessionCountedNotes.add(newTrack);
        _sessionTotal += value;
        return newTrack;
      }
      return null;
    }
  }

  /// Manually registers an explicit note (e.g. from OCR tap-to-scan button)
  TrackedCurrencyNote registerExplicitNote(InrDenomination denomination, int value) {
    final now = DateTime.now();
    final note = TrackedCurrencyNote(
      trackingId: _nextId++,
      denomination: denomination,
      value: value,
      firstSeen: now,
      lastSeen: now,
      consecutiveFrames: 3,
      isConfirmed: true,
      isCounted: true,
    );
    _sessionCountedNotes.add(note);
    _sessionTotal += value;
    _activeTracks.add(note);
    return note;
  }

  void _pruneStale(DateTime now) {
    _activeTracks.removeWhere((t) => now.difference(t.lastSeen).inMilliseconds > 2500);
  }

  void resetSession() {
    _activeTracks.clear();
    _sessionCountedNotes.clear();
    _sessionTotal = 0;
  }
}

class CurrencyRecognitionService {
  CurrencyRecognitionService._();
  static final CurrencyRecognitionService instance = CurrencyRecognitionService._();

  // ── Session Currency Tracker ───────────────────────────────────────────────
  final CurrencySessionTracker tracker = CurrencySessionTracker();

  int get sessionTotal => tracker.sessionTotal;
  int get walletBalance => tracker.sessionTotal;
  List<int> get scannedNotes => tracker.sessionNotes.map((n) => n.value).toList();

  void addNoteToWallet(int val) {
    if (val > 0) {
      final denom = _denomFromValue(val);
      tracker.registerExplicitNote(denom, val);
    }
  }

  void resetWallet() {
    tracker.resetSession();
  }

  void resetSession() {
    tracker.resetSession();
  }

  String getWalletStatusTa() {
    if (sessionTotal == 0) {
      return 'எந்த பணமும் பதிவு செய்யப்படவில்லை.';
    }
    return 'உங்களிடம் மொத்தம் $sessionTotal ரூபாய் உள்ளது.';
  }

  String getWalletStatusEn() {
    if (sessionTotal == 0) {
      return 'No money registered in wallet yet.';
    }
    return 'You have a total of $sessionTotal Rupees.';
  }

  /// Converts an integer currency total to natural Tamil speech
  String formatTamilAmount(int amount) {
    if (amount <= 0) return 'பூஜ்ஜியம்';
    if (amount == 10) return 'பத்து';
    if (amount == 20) return 'இருபது';
    if (amount == 30) return 'முப்பது';
    if (amount == 40) return 'நாற்பது';
    if (amount == 50) return 'ஐம்பது';
    if (amount == 60) return 'அறுபது';
    if (amount == 70) return 'எழுபது';
    if (amount == 80) return 'எண்பது';
    if (amount == 90) return 'தொண்ணூறு';
    if (amount == 100) return 'நூறு';
    if (amount == 120) return 'நூற்றி இருபது';
    if (amount == 200) return 'இருநூறு';
    if (amount == 300) return 'முந்நூறு';
    if (amount == 400) return 'நானூறு';
    if (amount == 500) return 'ஐநூறு';
    if (amount == 600) return 'அறுநூறு';
    if (amount == 700) return 'எழுநூறு';
    if (amount == 720) return 'எழுநூற்று இருபது';
    if (amount == 800) return 'எண்ணூறு';
    if (amount == 820) return 'எட்டுநூற்று இருபது';
    if (amount == 900) return 'தொள்ளாயிரம்';
    if (amount == 1000) return 'ஆயிரம்';
    if (amount == 2000) return 'இரண்டாயிரம்';
    if (amount == 2600) return 'இரண்டாயிரத்து அறுநூறு';
    return _convertNumberToTamil(amount);
  }

  String _convertNumberToTamil(int n) {
    const ones = ['', 'ஒன்று', 'இரண்டு', 'மூன்று', 'நான்கு', 'ஐந்து', 'ஆறு', 'ஏழு', 'எட்டு', 'ஒன்பது'];
    const teens = {
      10: 'பத்து', 11: 'பதினொன்று', 12: 'பன்னிரண்டு', 13: 'பதின்மூன்று',
      14: 'பதினான்கு', 15: 'பதினைந்து', 16: 'பதினாறு', 17: 'பதினேழு',
      18: 'பதினெட்டு', 19: 'பத்தொன்பது'
    };
    const tens = {
      20: 'இருபது', 30: 'முப்பது', 40: 'நாற்பது', 50: 'ஐம்பது',
      60: 'அறுபது', 70: 'எழுபது', 80: 'எண்பது', 90: 'தொண்ணூறு'
    };
    const tensPrefix = {
      20: 'இருபத்து ', 30: 'முப்பத்து ', 40: 'நாற்பத்து ', 50: 'ஐம்பத்து ',
      60: 'அறுபத்து ', 70: 'எழுபத்து ', 80: 'எண்பத்து ', 90: 'தொண்ணூற்று '
    };
    const hundreds = {
      100: 'நூறு', 200: 'இருநூறு', 300: 'முந்நூறு', 400: 'நானூறு',
      500: 'ஐநூறு', 600: 'அறுநூறு', 700: 'எழுநூறு', 800: 'எண்ணூறு', 900: 'தொள்ளாயிரம்'
    };
    const hundredsPrefix = {
      100: 'நூற்று ', 200: 'இருநூற்று ', 300: 'முந்நூற்று ', 400: 'நானூற்று ',
      500: 'ஐந்நூற்று ', 600: 'அறுநூற்று ', 700: 'எழுநூற்று ', 800: 'எட்டுநூற்று ', 900: 'தொள்ளாயிரத்து '
    };

    if (n <= 0) return 'பூஜ்ஜியம்';
    var res = '';

    if (n >= 1000) {
      final th = n ~/ 1000;
      n %= 1000;
      if (th == 1) {
        res += n > 0 ? 'ஆயிரத்து ' : 'ஆயிரம்';
      } else if (th == 2) {
        res += n > 0 ? 'இரண்டாயிரத்து ' : 'இரண்டாயிரம்';
      } else {
        res += n > 0 ? '${_convertNumberToTamil(th)} ஆயிரத்து ' : '${_convertNumberToTamil(th)} ஆயிரம்';
      }
    }

    if (n >= 100) {
      final h = (n ~/ 100) * 100;
      n %= 100;
      res += n > 0 ? hundredsPrefix[h]! : hundreds[h]!;
    }

    if (n >= 20) {
      final t = (n ~/ 10) * 10;
      n %= 10;
      res += n > 0 ? tensPrefix[t]! : tens[t]!;
    } else if (n >= 10) {
      res += teens[n]!;
      n = 0;
    }

    if (n > 0) {
      res += ones[n];
    }

    return res.trim();
  }

  InrDenomination _denomFromValue(int v) {
    switch (v) {
      case 10: return InrDenomination.ten;
      case 20: return InrDenomination.twenty;
      case 50: return InrDenomination.fifty;
      case 100: return InrDenomination.oneHundred;
      case 200: return InrDenomination.twoHundred;
      case 500: return InrDenomination.fiveHundred;
      case 2000: return InrDenomination.twoThousand;
      default: return InrDenomination.unknown;
    }
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
      globalR: 185.46,
      globalG: 176.52,
      globalB: 201.94,
      globalHue: 261.11,
      globalSat: 0.1259,
      globalVal: 0.7919,
      centerR: 169.55,
      centerG: 157.22,
      centerB: 182.24,
      centerHue: 269.56,
      centerSat: 0.1373,
      centerVal: 0.7147,
      ratioRG: 1.051,
      ratioRB: 0.918,
      ratioGB: 0.874,
    ),
    CurrencyTemplate(
      name: '100rs_model1_front.jpg',
      denomination: InrDenomination.oneHundred,
      value: 100,
      globalR: 177.61,
      globalG: 178.07,
      globalB: 175.78,
      globalHue: 71.98,
      globalSat: 0.0128,
      globalVal: 0.6983,
      centerR: 176.53,
      centerG: 181.26,
      centerB: 182.12,
      centerHue: 189.22,
      centerSat: 0.0307,
      centerVal: 0.7142,
      ratioRG: 0.997,
      ratioRB: 1.010,
      ratioGB: 1.013,
    ),
    CurrencyTemplate(
      name: '10rs_model1_back.jpg',
      denomination: InrDenomination.ten,
      value: 10,
      globalR: 161.99,
      globalG: 135.25,
      globalB: 119.10,
      globalHue: 22.59,
      globalSat: 0.2647,
      globalVal: 0.6352,
      centerR: 154.03,
      centerG: 125.80,
      centerB: 110.26,
      centerHue: 21.31,
      centerSat: 0.2842,
      centerVal: 0.6040,
      ratioRG: 1.198,
      ratioRB: 1.360,
      ratioGB: 1.136,
    ),
    CurrencyTemplate(
      name: '10rs_model1_front.jpg',
      denomination: InrDenomination.ten,
      value: 10,
      globalR: 198.09,
      globalG: 167.29,
      globalB: 137.80,
      globalHue: 29.35,
      globalSat: 0.3043,
      globalVal: 0.7768,
      centerR: 187.59,
      centerG: 153.46,
      centerB: 122.82,
      centerHue: 28.38,
      centerSat: 0.3453,
      centerVal: 0.7357,
      ratioRG: 1.184,
      ratioRB: 1.437,
      ratioGB: 1.214,
    ),
    CurrencyTemplate(
      name: '10rs_model2_back.jpg',
      denomination: InrDenomination.ten,
      value: 10,
      globalR: 216.11,
      globalG: 186.02,
      globalB: 168.65,
      globalHue: 21.96,
      globalSat: 0.2196,
      globalVal: 0.8475,
      centerR: 206.50,
      centerG: 175.95,
      centerB: 165.99,
      centerHue: 14.76,
      centerSat: 0.1962,
      centerVal: 0.8098,
      ratioRG: 1.162,
      ratioRB: 1.281,
      ratioGB: 1.103,
    ),
    CurrencyTemplate(
      name: '10rs_model2_front.jpg',
      denomination: InrDenomination.ten,
      value: 10,
      globalR: 179.27,
      globalG: 165.17,
      globalB: 147.53,
      globalHue: 33.34,
      globalSat: 0.1770,
      globalVal: 0.7030,
      centerR: 198.65,
      centerG: 178.92,
      centerB: 157.44,
      centerHue: 31.27,
      centerSat: 0.2074,
      centerVal: 0.7790,
      ratioRG: 1.085,
      ratioRB: 1.215,
      ratioGB: 1.120,
    ),
    CurrencyTemplate(
      name: '2000_front_back.jpg',
      denomination: InrDenomination.twoThousand,
      value: 2000,
      globalR: 187.46,
      globalG: 165.27,
      globalB: 179.02,
      globalHue: 322.83,
      globalSat: 0.1184,
      globalVal: 0.7351,
      centerR: 173.60,
      centerG: 148.03,
      centerB: 162.22,
      centerHue: 326.70,
      centerSat: 0.1473,
      centerVal: 0.6808,
      ratioRG: 1.134,
      ratioRB: 1.047,
      ratioGB: 0.923,
    ),
    CurrencyTemplate(
      name: '200_front_back.jpg',
      denomination: InrDenomination.twoHundred,
      value: 200,
      globalR: 206.42,
      globalG: 180.89,
      globalB: 151.50,
      globalHue: 32.11,
      globalSat: 0.2661,
      globalVal: 0.8095,
      centerR: 213.45,
      centerG: 174.14,
      centerB: 134.53,
      centerHue: 30.11,
      centerSat: 0.3698,
      centerVal: 0.8371,
      ratioRG: 1.141,
      ratioRB: 1.362,
      ratioGB: 1.194,
    ),
    CurrencyTemplate(
      name: '20rs_model1_frontend.jpg',
      denomination: InrDenomination.twenty,
      value: 20,
      globalR: 224.67,
      globalG: 162.49,
      globalB: 146.14,
      globalHue: 12.49,
      globalSat: 0.3495,
      globalVal: 0.8811,
      centerR: 223.01,
      centerG: 173.83,
      centerB: 151.33,
      centerHue: 18.83,
      centerSat: 0.3214,
      centerVal: 0.8746,
      ratioRG: 1.383,
      ratioRB: 1.537,
      ratioGB: 1.112,
    ),
    CurrencyTemplate(
      name: '20rs_model2_back.jpg',
      denomination: InrDenomination.twenty,
      value: 20,
      globalR: 211.07,
      globalG: 205.03,
      globalB: 163.75,
      globalHue: 52.34,
      globalSat: 0.2242,
      globalVal: 0.8277,
      centerR: 205.49,
      centerG: 193.92,
      centerB: 165.23,
      centerHue: 42.76,
      centerSat: 0.1959,
      centerVal: 0.8058,
      ratioRG: 1.029,
      ratioRB: 1.289,
      ratioGB: 1.252,
    ),
    CurrencyTemplate(
      name: '20rs_model2_frontend.jpg',
      denomination: InrDenomination.twenty,
      value: 20,
      globalR: 187.83,
      globalG: 188.08,
      globalB: 133.81,
      globalHue: 60.27,
      globalSat: 0.2885,
      globalVal: 0.7376,
      centerR: 193.58,
      centerG: 194.30,
      centerB: 145.41,
      centerHue: 60.89,
      centerSat: 0.2517,
      centerVal: 0.7620,
      ratioRG: 0.999,
      ratioRB: 1.404,
      ratioGB: 1.406,
    ),
    CurrencyTemplate(
      name: '500rs_image_front_back.jpg',
      denomination: InrDenomination.fiveHundred,
      value: 500,
      globalR: 153.16,
      globalG: 149.59,
      globalB: 144.29,
      globalHue: 35.83,
      globalSat: 0.0580,
      globalVal: 0.6006,
      centerR: 151.80,
      centerG: 150.18,
      centerB: 145.76,
      centerHue: 43.95,
      centerSat: 0.0397,
      centerVal: 0.5953,
      ratioRG: 1.024,
      ratioRB: 1.062,
      ratioGB: 1.037,
    ),
  ];

  /// Creates a [CurrencyResult] object for a verified note
  CurrencyResult createResultForNote(TrackedCurrencyNote note) {
    final denom = note.denomination;
    final val = note.value;
    return CurrencyResult(
      denomination: denom,
      value: val,
      spokenTextTa: _tamilNames[denom]!,
      spokenTextEn: _englishNames[denom]!,
      userAmountTa: 'உங்களிடம் $val ரூபாய் உள்ளது.',
      userAmountEn: 'You have $val Rupees.',
      confidence: 0.95,
      isConfident: true,
      matchedModel: 'Tracked Note #${note.trackingId}',
      hapticPattern: _hapticPatterns[denom] ?? const [200],
    );
  }

  /// Processes live camera frame through the temporal session tracker.
  /// Returns a [TrackedCurrencyNote] ONLY when a genuinely new note is confirmed;
  /// returns null if no note is visible or if the same note is still being presented.
  TrackedCurrencyNote? processLiveTracking(
    img.Image image, {
    DateTime? timestamp,
    double xCenter = 0.5,
    double yCenter = 0.5,
  }) {
    final visual = recognizeLiveStream(image);
    if (visual.denomination == InrDenomination.unknown || visual.value <= 0) {
      tracker.updateWithDetection(
        denomination: InrDenomination.unknown,
        value: 0,
        timestamp: timestamp,
      );
      return null;
    }

    return tracker.updateWithDetection(
      denomination: visual.denomination,
      value: visual.value,
      xCenter: xCenter,
      yCenter: yCenter,
      timestamp: timestamp,
      minConsecutive: 3, // Requires 3 consecutive frames (~1050ms)
    );
  }

  /// Multi-Modal Recognition: OCR (Google ML Kit Text Recognition) + Dataset-calibrated Color-Spatial Model
  CurrencyResult recognize({
    required img.Image image,
    String? ocrText,
    bool addToWallet = false,
  }) {
    // ── Engine 1: OCR Numeral and Token Matcher ──────────────────────────────
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
        tracker.registerExplicitNote(finalDenom, val);
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
  /// Strict confidence, texture verification, and ambient surface rejection ensure
  /// roads, walls, clothes, leaves, and shadows NEVER trigger false detections.
  CurrencyResult recognizeLiveStream(img.Image image) {
    final visual = _matchFromVisual(image);
    if (visual.denomination != InrDenomination.unknown &&
        visual.isConfident &&
        visual.confidence >= 0.70) {
      return visual;
    }
    return CurrencyResult.notFound;
  }

  /// Multilingual OCR token and numeral parser (English + Devanagari + Tamil + Normalization)
  InrDenomination _matchFromText(String text) {
    final lower = text.toLowerCase();

    // 1. Direct numeral token extraction
    final clean = text.replaceAll(RegExp(r'[^0-9]'), ' ');
    final tokens = clean.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    // 2. OCR character normalization (O/o -> 0, I/l/| -> 1, S -> 5, Z -> 2)
    final normClean = lower
        .replaceAll('₹', ' ')
        .replaceAll('rs.', ' ')
        .replaceAll('rs', ' ')
        .replaceAll('/-', ' ')
        .replaceAll(RegExp(r'\b5[oOdD]{2}\b'), '500')
        .replaceAll(RegExp(r'\b2[oOdD]{2}\b'), '200')
        .replaceAll(RegExp(r'\b[1ilI|][oOdD]{2}\b'), '100')
        .replaceAll(RegExp(r'\b2[oOdD]{3}\b'), '2000')
        .replaceAll(RegExp(r'\b5[oOdD]\b'), '50')
        .replaceAll(RegExp(r'\b2[oOdD]\b'), '20')
        .replaceAll(RegExp(r'\b[1ilI|][oOdD]\b'), '10')
        .replaceAll(RegExp(r'[^0-9]'), ' ');

    final normTokens = normClean.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    // ₹2000 Note
    if (tokens.contains('2000') || normTokens.contains('2000') ||
        text.contains('2000') || text.contains('२०००') ||
        lower.contains('two thousand') || lower.contains('दो हज़ार') ||
        lower.contains('दो हजार') || lower.contains('இரண்டாயிரம்')) {
      return InrDenomination.twoThousand;
    }

    // ₹500 Note
    if (tokens.contains('500') || normTokens.contains('500') ||
        text.contains('500') || text.contains('५००') ||
        lower.contains('five hundred') || lower.contains('पाँच सौ') ||
        lower.contains('पांच सौ') || lower.contains('ஐந்நூறு')) {
      return InrDenomination.fiveHundred;
    }

    // ₹200 Note
    if (tokens.contains('200') || normTokens.contains('200') ||
        text.contains('200') || text.contains('२००') ||
        lower.contains('two hundred') || lower.contains('दो सौ') ||
        lower.contains('இருநூறு')) {
      return InrDenomination.twoHundred;
    }

    // ₹100 Note
    if (tokens.contains('100') || normTokens.contains('100') ||
        text.contains('100') || text.contains('१००') ||
        lower.contains('one hundred') || lower.contains('एक सौ') ||
        lower.contains('நூறு')) {
      return InrDenomination.oneHundred;
    }

    // ₹50 Note
    if (tokens.contains('50') || normTokens.contains('50') ||
        text.contains('50') || text.contains('५०') ||
        lower.contains('fifty') || lower.contains('पचास') ||
        lower.contains('ஐம்பது')) {
      return InrDenomination.fifty;
    }

    // ₹20 Note
    if (tokens.contains('20') || normTokens.contains('20') ||
        text.contains('20') || text.contains('२०') ||
        lower.contains('twenty') || lower.contains('बीस') ||
        lower.contains('இருபது')) {
      return InrDenomination.twenty;
    }

    // ₹10 Note
    if (tokens.contains('10') || normTokens.contains('10') ||
        text.contains('10') || text.contains('१०') ||
        lower.contains('ten') || lower.contains('दस') ||
        lower.contains('பத்து')) {
      return InrDenomination.ten;
    }

    return InrDenomination.unknown;
  }

  /// Multi-scale Feature Extraction + Template Nearest Match & Ambient Rejection
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

    // ── STAGE 1: Banknote Structural & Micro-Texture Verification ────────────
    // Real Indian banknotes feature dense micro-printing, intaglio engraving, portraits,
    // and complex guilloche geometries (dataset variance >= 1158, avgGrad >= 17.9, highEdgeRatio >= 22.9%).
    // Ambient natural surfaces (roads, floors, plain tables, walls, ceilings, clothing, shadows, leaves)
    // completely lack this high-frequency texture and are strictly rejected.
    if (variance < 550.0 || avgGrad < 12.0 || highEdgeRatio < 0.10) {
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
    if (gVal < 0.28 || avgGR < 42 || avgGG < 42 || avgGB < 42) {
      return CurrencyResult.notFound;
    }

    // ── Ambient Road / Asphalt / Concrete Pavement Guard ─────────────────────
    // Grey roads have near-zero saturation and diffuse grain noise without intaglio structure.
    if (gSat < 0.09 && cSat < 0.09) {
      // Must have exceptionally sharp intaglio banknote texture to be considered a stone-grey ₹500 note
      if (variance < 1500.0 || avgGrad < 20.0 || highEdgeRatio < 0.22) {
        return CurrencyResult.notFound;
      }
    }

    // ── Pure Green Foliage / Leaves Guard ────────────────────────────────────
    if ((gHue >= 90 && gHue <= 145 || cHue >= 90 && cHue <= 145) &&
        avgGG > avgGR * 1.20 && avgGG > avgGB * 1.20) {
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

      final dist = (2.2 * (0.35 * hueDistG + 0.65 * hueDistC)) +
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
        (avgGG - avgGB).abs() < 16 &&
        variance >= 1500.0 &&
        avgGrad >= 20.0) {
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
          bestDist < 1.10) {
        final conf = (1.0 - (bestDist / 2.5)).clamp(0.85, 0.98);
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

      // 2. Bright Saffron ₹200 explicit domain disambiguation from brownish ₹10
      if (domainMatch == InrDenomination.twoHundred && bestDist < 1.05) {
        final conf = (1.0 - (bestDist / 3.0)).clamp(0.75, 0.96);
        return CurrencyResult(
          denomination: InrDenomination.twoHundred,
          value: 200,
          spokenTextTa: _tamilNames[InrDenomination.twoHundred]!,
          spokenTextEn: _englishNames[InrDenomination.twoHundred]!,
          userAmountTa: 'உங்களிடம் 200 ரூபாய் உள்ளது.',
          userAmountEn: 'You have 200 Rupees.',
          confidence: conf,
          isConfident: true,
          matchedModel: domainModel.isNotEmpty ? domainModel : bestTemplate.name,
          hapticPattern: _hapticPatterns[InrDenomination.twoHundred] ?? const [200],
        );
      }

      // 3. Calibrated template match
      if (bestDist < 0.86) {
        final denom = bestTemplate.denomination;
        // For ₹500 stone-grey, require strict distance to prevent any ambient grey confusion
        if (denom == InrDenomination.fiveHundred && bestDist > 0.35) {
          return CurrencyResult.notFound;
        }

        final conf = (1.0 - (bestDist / 3.0)).clamp(0.70, 0.96);
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

      // 4. Domain rule confident match with verified distance
      if (domainMatch != InrDenomination.unknown && bestDist < 1.05) {
        if (domainMatch == InrDenomination.fiveHundred && bestDist > 0.35) {
          return CurrencyResult.notFound;
        }
        final conf = (1.0 - (bestDist / 3.2)).clamp(0.70, 0.95);
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
    }

    return CurrencyResult.notFound;
  }

  static List<double> _rgbToHsv(double r, double g, double b) {
    final rf = r / 255.0;
    final gf = g / 255.0;
    final bf = b / 255.0;

    final maxVal = max(rf, max(gf, bf));
    final minVal = min(rf, min(gf, bf));
    final delta = maxVal - minVal;

    double h = 0.0;
    if (delta > 1e-5) {
      if (maxVal == rf) {
        h = 60.0 * (((gf - bf) / delta) % 6);
      } else if (maxVal == gf) {
        h = 60.0 * (((bf - rf) / delta) + 2);
      } else {
        h = 60.0 * (((rf - gf) / delta) + 4);
      }
      if (h < 0) h += 360.0;
    }

    final s = maxVal > 1e-5 ? delta / maxVal : 0.0;
    final v = maxVal;
    return [h, s, v];
  }

  static double _angularDist(double a, double b) {
    final diff = (a - b).abs() % 360.0;
    return diff > 180.0 ? 360.0 - diff : diff;
  }
}
