import 'reverse_geocoding_service.dart';

/// Formatter that transforms geocoded location components into natural, grammatically
/// correct Tamil sentences, with normalization and phonetic transliteration for English place names.
///
/// Sections 8, 9, 10 of MASTER PROMPT:
/// - Order: LOCALITY / AREA → CITY → STATE
/// - "நீங்கள் இஞ்சம்பாக்கம், சென்னை, தமிழ்நாட்டில் இருக்கிறீர்கள்."
/// - Never includes raw coordinates, accuracy, or technical terms.
class TamilLocationFormatter {
  // ── Curated Dictionary of Tamil Nadu cities, states, and major localities ──
  static final Map<String, String> _knownPlaces = {
    // States / Regions
    'tamil nadu': 'தமிழ்நாடு',
    'tamilnadu': 'தமிழ்நாடு',
    'karnataka': 'கர்நாடகா',
    'kerala': 'கேரளா',
    'andhra pradesh': 'ஆந்திரப் பிரதேசம்',
    'telangana': 'தெலங்கானா',
    'puducherry': 'புதுச்சேரி',
    'pondicherry': 'புதுச்சேரி',
    'india': 'இந்தியா',

    // Major Cities & Districts
    'chennai': 'சென்னை',
    'madras': 'சென்னை',
    'coimbatore': 'கோயம்புத்தூர்',
    'madurai': 'மதுரை',
    'tiruchirappalli': 'திருச்சிராப்பள்ளி',
    'trichy': 'திருச்சிராப்பள்ளி',
    'salem': 'சேலம்',
    'tirunelveli': 'திருநெல்வேலி',
    'erode': 'ஈரோடு',
    'vellore': 'வேலூர்',
    'thoothukudi': 'தூத்துக்குடி',
    'tuticorin': 'தூத்துக்குடி',
    'dindigul': 'திண்டுக்கல்',
    'thanjavur': 'தஞ்சாவூர்',
    'kanchipuram': 'காஞ்சிபுரம்',
    'kancheepuram': 'காஞ்சிபுரம்',
    'tiruvannamalai': 'திருவண்ணாமலை',
    'cuddalore': 'கடலூர்',
    'villupuram': 'விழுப்புரம்',
    'nagapattinam': 'நாகப்பட்டினம்',
    'pudukkottai': 'புதுக்கோட்டை',
    'karur': 'கரூர்',
    'sivaganga': 'சிவகங்கை',
    'ramanathapuram': 'இராமநாதபுரம்',
    'virudhunagar': 'விருதுநகர்',
    'theni': 'தேனி',
    'namakkal': 'நாமக்கல்',
    'dharmapuri': 'தருமபுரி',
    'krishnagiri': 'கிருஷ்ணகிரி',
    'nilgiris': 'நீலகிரி',
    'ooty': 'நீலகிரி',
    'ariyalur': 'அரியலூர்',
    'perambalur': 'பெரம்பலூர்',
    'kallakurichi': 'கள்ளக்குறிச்சி',
    'ranipet': 'இராணிப்பேட்டை',
    'tirupathur': 'திருப்பத்தூர்',
    'chengalpattu': 'செங்கல்பட்டு',
    'tenkasi': 'தென்காசி',
    'kanniyakumari': 'கன்னியாகுமரி',
    'kanyakumari': 'கன்னியாகுமரி',
    'bengaluru': 'பெங்களூரு',
    'bangalore': 'பெங்களூரு',

    // Localities & Neighborhoods (Chennai & surrounds)
    'injambakkam': 'இஞ்சம்பாக்கம்',
    'adyar': 'அடையாறு',
    'kodambakkam': 'கோடம்பாக்கம்',
    't nagar': 'தியாகராய நகர்',
    't. nagar': 'தியாகராய நகர்',
    'thyagaraya nagar': 'தியாகராய நகர்',
    'velachery': 'வேளச்சேரி',
    'tambaram': 'தாம்பரம்',
    'guindy': 'கிண்டி',
    'mylapore': 'மயிலாப்பூர்',
    'thiruvanmiyur': 'திருவான்மியூர்',
    'besant nagar': 'பெசன்ட் நகர்',
    'sholinganallur': 'சோழிங்கநல்லூர்',
    'perungudi': 'பெருங்குடி',
    'thoraipakkam': 'துரைப்பாக்கம்',
    'palavakkam': 'பாலவாக்கம்',
    'neelankarai': 'நீலாங்கரை',
    'kottivakkam': 'கொட்டிவாக்கம்',
    'anna nagar': 'அண்ணா நகர்',
    'nungambakkam': 'நுங்கம்பாக்கம்',
    'alwarpet': 'ஆழ்வார்பேட்டை',
    'egmore': 'எழும்பூர்',
    'royapettah': 'இராயப்பேட்டை',
    'saidapet': 'சைதாப்பேட்டை',
    'chromepet': 'குரோம்பேட்டை',
    'pallavaram': 'பல்லாவரம்',
    'porur': 'போரூர்',
    'vadapalani': 'வடபழனி',
    'koyambedu': 'கோயம்பேடு',
    'ambattur': 'அம்பத்தூர்',
    'avadi': 'ஆவடி',
    'madhavaram': 'மாதவரம்',
    'red hills': 'செங்குன்றம்',
    'perambur': 'பெரம்பூர்',
    'tondiarpet': 'தண்டையார்பேட்டை',
    'washermanpet': 'வண்ணாரப்பேட்டை',
    'triplicane': 'திருவல்லிக்கேணி',
    'medavakkam': 'மேடவாக்கம்',
    'pallikaranai': 'பள்ளிக்கரணை',
    'sithalapakkam': 'சித்தாலப்பாக்கம்',
    'perumbakkam': 'பெரும்பாக்கம்',
    'kelambakkam': 'கேளம்பாக்கம்',
    'siruseri': 'சிறுசேரி',
    'navalur': 'நாவலூர்',
    'thiruporur': 'திருப்போரூர்',
    'mahabalipuram': 'மாமல்லபுரம்',
    'mamallapuram': 'மாமல்லபுரம்',
    'poonamallee': 'பூந்தமல்லி',
    'mangadu': 'மாங்காடு',
    'kundrathur': 'குன்றத்தூர்',
    'mambalam': 'மாம்பலம்',
    'ashok nagar': 'அசோக் நகர்',
    'kk nagar': 'கே கே நகர்',
    'k.k. nagar': 'கே கே நகர்',
    'chetpet': 'சேத்துப்பட்டு',
    'kilpauk': 'கீழ்ப்பாக்கம்',
    'chintadripet': 'சிந்தாதிரிப்பேட்டை',
    'purasaiwakkam': 'புரசைவாக்கம்',
    'mandaveli': 'மந்தைவெளி',
    'san thome': 'சாந்தோம்',
    'santhome': 'சாந்தோம்',
    'teynampet': 'தேனாம்பேட்டை',
  };

  /// Normalizes a place name from English to Tamil.
  /// If in the known dictionary, returns standard Tamil name.
  /// Otherwise cleans up affixes and provides safe phonetic transliteration.
  static String normalizeToTamil(String input) {
    if (input.trim().isEmpty) return '';
    final cleaned = input.trim();

    // Check if already in Tamil (contains Tamil Unicode range U+0B80 - U+0BFF)
    if (_isTamilText(cleaned)) {
      return cleaned;
    }

    final lower = cleaned.toLowerCase();

    // Direct dictionary match
    if (_knownPlaces.containsKey(lower)) {
      return _knownPlaces[lower]!;
    }

    // Try suffix replacements (e.g. "Adyar West" -> "அடையாறு மேற்கு")
    for (final entry in _knownPlaces.entries) {
      if (lower.startsWith(entry.key)) {
        final remainder = lower.substring(entry.key.length).trim();
        if (remainder.isEmpty) return entry.value;
        if (remainder == 'east') return '${entry.value} கிழக்கு';
        if (remainder == 'west') return '${entry.value} மேற்கு';
        if (remainder == 'north') return '${entry.value} வடக்கு';
        if (remainder == 'south') return '${entry.value} தெற்கு';
      }
    }

    // Replace common street/area suffixes
    String processed = cleaned;
    processed = processed.replaceAll(RegExp(r'\bNagar\b', caseSensitive: false), 'நகர்');
    processed = processed.replaceAll(RegExp(r'\bColony\b', caseSensitive: false), 'காலனி');
    processed = processed.replaceAll(RegExp(r'\bStreet\b', caseSensitive: false), 'தெரு');
    processed = processed.replaceAll(RegExp(r'\bRoad\b', caseSensitive: false), 'சாலை');
    processed = processed.replaceAll(RegExp(r'\bRd\b', caseSensitive: false), 'சாலை');
    processed = processed.replaceAll(RegExp(r'\bLayout\b', caseSensitive: false), 'நகர்');

    // If partially transliterated or contains English, apply safe phonetic transliteration
    return _transliterateToTamil(processed);
  }

  static bool _isTamilText(String text) {
    for (final rune in text.runes) {
      if (rune >= 0x0B80 && rune <= 0x0BFF) return true;
    }
    return false;
  }

  /// Safe rule-based phonetic transliteration from English Latin characters to Tamil.
  /// Ensures Tamil TTS speaks the word smoothly without sounding out Latin letters.
  static String _transliterateToTamil(String text) {
    final Map<String, String> multiMap = {
      'sh': 'ஷ', 'th': 'த', 'ch': 'ச', 'zh': 'ழ', 'dh': 'த',
      'ph': 'ப', 'kh': 'க', 'gh': 'க', 'bh': 'ப', 'ng': 'ங்',
    };

    final Map<String, String> charMap = {
      'a': 'அ', 'b': 'ப', 'c': 'ச', 'd': 'ட', 'e': 'எ',
      'f': 'ப', 'g': 'க', 'h': 'ஹ', 'i': 'இ', 'j': 'ஜ',
      'k': 'க', 'l': 'ல', 'm': 'ம', 'n': 'ந', 'o': 'ஒ',
      'p': 'ப', 'q': 'க', 'r': 'ர', 's': 'ஸ', 't': 'ட',
      'u': 'உ', 'v': 'வ', 'w': 'வ', 'x': 'க்ஸ்', 'y': 'ய',
      'z': 'ஜ',
    };

    final buffer = StringBuffer();
    int i = 0;
    final lower = text.toLowerCase();

    while (i < lower.length) {
      if (_isTamilText(lower[i])) {
        buffer.write(text[i]);
        i++;
        continue;
      }

      if (i + 1 < lower.length) {
        final pair = lower.substring(i, i + 2);
        if (multiMap.containsKey(pair)) {
          buffer.write(multiMap[pair]);
          i += 2;
          continue;
        }
      }

      final single = lower[i];
      if (charMap.containsKey(single)) {
        buffer.write(charMap[single]);
      } else {
        buffer.write(single);
      }
      i++;
    }

    return buffer.toString();
  }

  /// Formats geocoded location into natural Tamil sentence.
  ///
  /// Examples:
  /// - Locality "Injambakkam", City "Chennai", State "Tamil Nadu":
  ///   "நீங்கள் இஞ்சம்பாக்கம், சென்னை, தமிழ்நாட்டில் இருக்கிறீர்கள்."
  /// - Locality "Adyar", City "Chennai", State "Tamil Nadu":
  ///   "நீங்கள் அடையாறு, சென்னை, தமிழ்நாட்டில் இருக்கிறீர்கள்."
  static String formatLocation(GeocodedLocationInfo? location) {
    if (location == null || location.isEmpty) {
      return 'நீங்கள் தற்போது உங்கள் இருப்பிடத்தில் இருக்கிறீர்கள்.';
    }

    final rawLocality = location.locality?.trim();
    final rawCity = location.city?.trim();
    final rawState = location.state?.trim();

    final loc = (rawLocality != null && rawLocality.isNotEmpty)
        ? normalizeToTamil(rawLocality)
        : null;
    final city = (rawCity != null && rawCity.isNotEmpty)
        ? normalizeToTamil(rawCity)
        : null;
    final state = (rawState != null && rawState.isNotEmpty)
        ? normalizeToTamil(rawState)
        : null;

    // Helper for state inflected ending (e.g. தமிழ்நாட்டில்)
    String formatState(String st) {
      if (st == 'தமிழ்நாடு') {
        return 'தமிழ்நாட்டில்';
      }
      return '$st-ல்';
    }

    // Helper for city inflected ending (e.g. சென்னையில்)
    String formatCityIn(String c) {
      if (c == 'சென்னை') {
        return 'சென்னையில்';
      }
      return '$c-ல்';
    }

    // Case 1: All three are present
    if (loc != null && loc.isNotEmpty &&
        city != null && city.isNotEmpty &&
        state != null && state.isNotEmpty) {
      if (loc.toLowerCase() == city.toLowerCase()) {
        return 'நீங்கள் $city, ${formatState(state)} இருக்கிறீர்கள்.';
      }
      return 'நீங்கள் $loc, $city, ${formatState(state)} இருக்கிறீர்கள்.';
    }

    // Case 2: Locality + City
    if (loc != null && loc.isNotEmpty && city != null && city.isNotEmpty) {
      if (loc.toLowerCase() == city.toLowerCase()) {
        return 'நீங்கள் ${formatCityIn(city)} இருக்கிறீர்கள்.';
      }
      return 'நீங்கள் $loc, ${formatCityIn(city)} இருக்கிறீர்கள்.';
    }

    // Case 3: City + State
    if (city != null && city.isNotEmpty && state != null && state.isNotEmpty) {
      return 'நீங்கள் $city, ${formatState(state)} இருக்கிறீர்கள்.';
    }

    // Case 4: Locality + State
    if (loc != null && loc.isNotEmpty && state != null && state.isNotEmpty) {
      return 'நீங்கள் $loc, ${formatState(state)} இருக்கிறீர்கள்.';
    }

    // Case 5: Locality only
    if (loc != null && loc.isNotEmpty) {
      return 'நீங்கள் $loc பகுதியில் இருக்கிறீர்கள்.';
    }

    // Case 6: City only
    if (city != null && city.isNotEmpty) {
      return 'நீங்கள் ${formatCityIn(city)} இருக்கிறீர்கள்.';
    }

    return 'நீங்கள் தற்போது உங்கள் இருப்பிடத்தில் இருக்கிறீர்கள்.';
  }
}
