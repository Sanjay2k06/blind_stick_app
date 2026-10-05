import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrResult {
  final String rawText;
  final String spokenTextTa;
  final String spokenTextEn;
  final bool hasText;
  final List<String> detectedLines;

  const OcrResult({
    required this.rawText,
    required this.spokenTextTa,
    required this.spokenTextEn,
    required this.hasText,
    required this.detectedLines,
  });

  static const empty = OcrResult(
    rawText: '',
    spokenTextTa: 'எழுத்துக்கள் எதுவும் தெளிவாகத் தெரியவில்லை. கேமராவை வாசகத்திற்கு நேராகப் பிடிக்கவும்.',
    spokenTextEn: 'No text clearly detected. Please hold the camera facing the text.',
    hasText: false,
    detectedLines: [],
  );
}

class OcrService {
  OcrService._();
  static final OcrService instance = OcrService._();

  TextRecognizer? _recognizer;

  TextRecognizer get recognizer {
    _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    return _recognizer!;
  }

  /// Processes an image file for on-device OCR
  Future<OcrResult> processImageFile(String filePath) async {
    try {
      final inputImage = InputImage.fromFilePath(filePath);
      return await processInputImage(inputImage);
    } catch (e) {
      debugPrint('OCR file error: $e');
      return OcrResult.empty;
    }
  }

  /// Processes an InputImage directly
  Future<OcrResult> processInputImage(InputImage inputImage) async {
    try {
      final RecognizedText recognized = await recognizer.processImage(inputImage);
      final text = recognized.text.trim();

      if (text.isEmpty) {
        return OcrResult.empty;
      }

      final lines = <String>[];
      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          final clean = line.text.trim();
          if (clean.isNotEmpty) {
            lines.add(clean);
          }
        }
      }

      // Check for special signage (Restrooms, Exits, Bus numbers)
      final specialSign = _detectSpecialSign(text);
      final spokenTa = specialSign.isNotEmpty
          ? specialSign
          : 'கண்டறியப்பட்ட வாசகம்: ${_cleanForSpeech(text)}';

      return OcrResult(
        rawText: text,
        spokenTextTa: spokenTa,
        spokenTextEn: 'Detected text: ${_cleanForSpeech(text)}',
        hasText: true,
        detectedLines: lines,
      );
    } catch (e) {
      debugPrint('OCR processing error: $e');
      return OcrResult.empty;
    }
  }

  /// Identifies common important signs (Restrooms, Emergency exits, Route boards)
  String _detectSpecialSign(String raw) {
    final lower = raw.toLowerCase();

    // Restroom / Toilet signs
    if (lower.contains('men') || lower.contains('gents') || raw.contains('ஆண்கள்')) {
      return 'அறிவிப்புப் பலகை: ஆண்கள் கழிப்பறை.';
    }
    if (lower.contains('women') || lower.contains('ladies') || raw.contains('பெண்கள்')) {
      return 'அறிவிப்புப் பலகை: பெண்கள் கழிப்பறை.';
    }
    if (lower.contains('toilet') || lower.contains('restroom') || raw.contains('கழிப்பறை')) {
      return 'அறிவிப்புப் பலகை: கழிப்பறை.';
    }

    // Emergency exit
    if (lower.contains('exit') || lower.contains('emergency exit') || raw.contains('வெளியேறும் வழி')) {
      return 'அறிவிப்புப் பலகை: வெளியேறும் வழி.';
    }

    // Entrance
    if (lower.contains('entrance') || lower.contains('entry') || raw.contains('நுழைவு')) {
      return 'அறிவிப்புப் பலகை: நுழைவு வாயில்.';
    }

    // Danger / Caution
    if (lower.contains('danger') || lower.contains('caution') || raw.contains('எச்சரிக்கை')) {
      return 'எச்சரிக்கை பலகை முன்னால் உள்ளது. கவனமாக இருக்கவும்.';
    }

    return '';
  }

  /// Cleans OCR text for natural speech pronunciation
  String _cleanForSpeech(String text) {
    // Replace newlines with commas and remove multiple spaces
    final oneline = text.replaceAll('\n', ', ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneline.length > 150) {
      return '${oneline.substring(0, 147)}...';
    }
    return oneline;
  }

  void dispose() {
    _recognizer?.close();
    _recognizer = null;
  }
}
