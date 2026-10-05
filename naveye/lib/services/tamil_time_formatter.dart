/// Formats local device time into natural, grammatically correct spoken Tamil.
///
/// Section 12 of MASTER PROMPT:
/// - "இப்போது நேரம் காலை பத்து மணி முப்பது நிமிடங்கள்."
/// - Device local timezone
/// - Never speaks raw timestamps, numbers, UTC, or ISO strings.
class TamilTimeFormatter {
  static const Map<int, String> _hourWords = {
    1: 'ஒன்று',
    2: 'இரண்டு',
    3: 'மூன்று',
    4: 'நான்கு',
    5: 'ஐந்து',
    6: 'ஆறு',
    7: 'ஏழு',
    8: 'எட்டு',
    9: 'ஒன்பது',
    10: 'பத்து',
    11: 'பதினொன்று',
    12: 'பன்னிரண்டு',
  };

  static const Map<int, String> _minuteWords = {
    1: 'ஒன்று',
    2: 'இரண்டு',
    3: 'மூன்று',
    4: 'நான்கு',
    5: 'ஐந்து',
    6: 'ஆறு',
    7: 'ஏழு',
    8: 'எட்டு',
    9: 'ஒன்பது',
    10: 'பத்து',
    11: 'பதினொன்று',
    12: 'பன்னிரண்டு',
    13: 'பதின்மூன்று',
    14: 'பதflowனான்கு', // or பதினான்கு
    15: 'பதினைந்து',
    16: 'பதினாறு',
    17: 'பதினேழு',
    18: 'பதினெட்டு',
    19: 'பத்தொன்பது',
    20: 'இருபது',
    21: 'இருபத்தொன்று',
    22: 'இருபத்திரண்டு',
    23: 'இருபத்துமூன்று',
    24: 'இருபத்துநான்கு',
    25: 'இருபத்தைந்து',
    26: 'இருபத்தாறு',
    27: 'இருபத்தேழு',
    28: 'இருபத்தெட்டு',
    29: 'இருபத்தொன்பது',
    30: 'முப்பது',
    31: 'முப்பத்தொன்று',
    32: 'முப்பத்திரண்டு',
    33: 'முப்பத்துமூன்று',
    34: 'முப்பத்துநான்கு',
    35: 'முப்பத்தைந்து',
    36: 'முப்பத்தாறு',
    37: 'முப்பத்தேழு',
    38: 'முப்பத்தெட்டு',
    39: 'முப்பத்தொன்பது',
    40: 'நாற்பது',
    41: 'நாற்பத்தொன்று',
    42: 'நாற்பத்திரண்டு',
    43: 'நாற்பத்துமூன்று',
    44: 'நாற்பத்துநான்கு',
    45: 'நாற்பத்தைந்து',
    46: 'நாற்பத்தாறு',
    47: 'நாற்பத்தேழு',
    48: 'நாற்பத்தெட்டு',
    49: 'நாற்பத்தொன்பது',
    50: 'ஐம்பது',
    51: 'ஐம்பத்தொன்று',
    52: 'ஐம்பத்திரண்டு',
    53: 'ஐம்பத்துமூன்று',
    54: 'ஐம்பத்துநான்கு',
    55: 'ஐம்பத்தைந்து',
    56: 'ஐம்பத்தாறு',
    57: 'ஐம்பத்தேழு',
    58: 'ஐம்பத்தெட்டு',
    59: 'ஐம்பத்தொன்பது',
  };

  /// Returns the time period in Tamil (காலை, மதியம், மாலை, இரவு) based on the 24h hour.
  static String getTimePeriod(int hour24) {
    if (hour24 >= 4 && hour24 < 12) {
      return 'காலை';
    } else if (hour24 >= 12 && hour24 < 16) {
      return 'மதியம்';
    } else if (hour24 >= 16 && hour24 < 20) {
      return 'மாலை';
    } else {
      return 'இரவு';
    }
  }

  /// Converts a [DateTime] into a natural Tamil sentence.
  /// If [dateTime] is omitted, uses [DateTime.now()].
  ///
  /// Examples:
  /// - 10:30 AM -> "இப்போது நேரம் காலை பத்து மணி முப்பது நிமிடங்கள்."
  /// - 10:00 AM -> "இப்போது நேரம் காலை பத்து மணி."
  /// - 04:15 PM -> "இப்போது நேரம் மாலை நான்கு மணி பதினைந்து நிமிடங்கள்."
  /// - 09:45 PM -> "இப்போது நேரம் இரவு ஒன்பது மணி நாற்பத்தைந்து நிமிடங்கள்."
  static String formatTime([DateTime? dateTime]) {
    final dt = dateTime ?? DateTime.now();
    final period = getTimePeriod(dt.hour);

    int hour12 = dt.hour % 12;
    if (hour12 == 0) hour12 = 12;

    final hourWord = _hourWords[hour12] ?? 'பத்து';
    final minute = dt.minute;

    if (minute == 0) {
      return 'இப்போது நேரம் $period $hourWord மணி.';
    }

    final minuteWord = _minuteWords[minute];
    if (minuteWord != null) {
      return 'இப்போது நேரம் $period $hourWord மணி $minuteWord நிமிடங்கள்.';
    }

    return 'இப்போது நேரம் $period $hourWord மணி.';
  }
}
