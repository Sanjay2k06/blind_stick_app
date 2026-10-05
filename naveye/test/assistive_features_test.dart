import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:naveye/services/currency_recognition_service.dart';
import 'package:naveye/services/object_finder_service.dart';
import 'package:naveye/services/emergency_sos_service.dart';
import 'package:naveye/services/voice_command_service.dart';
import 'package:naveye/services/detector_service.dart';

void main() {
  group('Priority 2: Indian Currency / Banknote Identifier (ரூபாய் நோட்டுகள்)', () {
    final currencyService = CurrencyRecognitionService.instance;
    final dummyImage = img.Image(width: 100, height: 100);

    test('Identifies ₹500 banknote via OCR text with natural Tamil voice', () {
      final res = currencyService.recognize(
        image: dummyImage,
        ocrText: 'RESERVE BANK OF INDIA 500 RUPEES',
      );
      expect(res.denomination, equals(InrDenomination.fiveHundred));
      expect(res.value, equals(500));
      expect(res.spokenTextTa, equals('ஐநூறு ரூபாய் நோட்டு'));
      expect(res.isConfident, isTrue);
    });

    test('Identifies ₹200 banknote via OCR text with natural Tamil voice', () {
      final res = currencyService.recognize(
        image: dummyImage,
        ocrText: '200 RUPEES BHARAT',
      );
      expect(res.denomination, equals(InrDenomination.twoHundred));
      expect(res.value, equals(200));
      expect(res.spokenTextTa, equals('இருநூறு ரூபாய் நோட்டு'));
      expect(res.isConfident, isTrue);
    });

    test('Identifies ₹100 banknote via OCR text with natural Tamil voice', () {
      final res = currencyService.recognize(
        image: dummyImage,
        ocrText: 'ONE HUNDRED 100 RUPEES',
      );
      expect(res.denomination, equals(InrDenomination.oneHundred));
      expect(res.value, equals(100));
      expect(res.spokenTextTa, equals('நூறு ரூபாய் நோட்டு'));
      expect(res.isConfident, isTrue);
    });

    test('Identifies ₹50, ₹20, and ₹10 banknotes via OCR text', () {
      final res50 = currencyService.recognize(image: dummyImage, ocrText: '50 RUPEES');
      expect(res50.denomination, equals(InrDenomination.fifty));
      expect(res50.spokenTextTa, equals('ஐம்பது ரூபாய் நோட்டு'));

      final res20 = currencyService.recognize(image: dummyImage, ocrText: '20 RUPEES');
      expect(res20.denomination, equals(InrDenomination.twenty));
      expect(res20.spokenTextTa, equals('இருபது ரூபாய் நோட்டு'));

      final res10 = currencyService.recognize(image: dummyImage, ocrText: '10 RUPEES');
      expect(res10.denomination, equals(InrDenomination.ten));
      expect(res10.spokenTextTa, equals('பத்து ரூபாய் நோட்டு'));
    });

    test('Returns notFound fallback when no currency digits or patterns match', () {
      final res = currencyService.recognize(image: dummyImage, ocrText: 'random text without numbers');
      expect(res.denomination, equals(InrDenomination.unknown));
      expect(res.value, equals(0));
      expect(res.spokenTextTa, contains('ரூபாய் நோட்டு தெளிவாகத் தெரியவில்லை'));
    });
  });

  group('Priority 2: Object Finder Mode ("எங்கே இருக்கிறது?" / Hot-Cold Finder)', () {
    final finder = ObjectFinderService.instance;

    setUp(() {
      finder.cancel();
    });

    test('Maps Tamil query "சாவி எங்கே?" to keys/remote class', () {
      final target = finder.setTargetFromQuery('சாவி எங்கே?');
      expect(finder.isActive, isTrue);
      expect(target, equals('remote'));
    });

    test('Maps Tamil query "பாட்டில் எங்கே?" to bottle class', () {
      final target = finder.setTargetFromQuery('பாட்டில் எங்கே?');
      expect(finder.isActive, isTrue);
      expect(target, equals('bottle'));
      expect(finder.getTamilName('bottle'), equals('பாட்டில்'));
    });

    test('Maps English and Tamil queries for chair, phone, and laptop', () {
      expect(finder.setTargetFromQuery('நாற்காலி எங்கே'), equals('chair'));
      expect(finder.setTargetFromQuery('phone'), equals('cell phone'));
      expect(finder.setTargetFromQuery('லேப்டாப் எங்கே'), equals('laptop'));
    });

    test('Evaluates close centered target with reachable Tamil directive', () {
      finder.setTargetFromQuery('பாட்டில் எங்கே?');
      final now = DateTime.now();

      final detections = [
        const DetectionResult(
          label: 'bottle',
          rawLabel: 'bottle',
          confidence: 0.92,
          direction: 'முன்னால்',
          distance: '0.6 மீட்டர்',
          distanceM: 0.6,
          xCenter: 0.50,
        ),
      ];

      final feedback = finder.evaluateDetections(detections, now);
      expect(feedback, isNotNull);
      expect(feedback!.isFound, isTrue);
      expect(feedback.isReachable, isTrue);
      expect(feedback.spokenTextTa, contains('நேராக உங்கள் அருகில் உள்ளது! கையை நீட்டி எடுக்கலாம்'));
    });

    test('Evaluates left-side target with directional Tamil directive', () {
      finder.setTargetFromQuery('சாவி எங்கே?');
      final now = DateTime.now();

      final detections = [
        const DetectionResult(
          label: 'remote',
          rawLabel: 'remote',
          confidence: 0.88,
          direction: 'இடப்பக்கம்',
          distance: '1.8 மீட்டர்',
          distanceM: 1.8,
          xCenter: 0.20,
        ),
      ];

      final feedback = finder.evaluateDetections(detections, now);
      expect(feedback, isNotNull);
      expect(feedback!.isFound, isTrue);
      expect(feedback.isReachable, isFalse);
      expect(feedback.spokenTextTa, contains('இடப்பக்கம் உள்ளது. இடதுபுறம் திரும்பவும்'));
    });

    test('Evaluates right-side target with directional Tamil directive', () {
      finder.setTargetFromQuery('நாற்காலி எங்கே?');
      final now = DateTime.now();

      final detections = [
        const DetectionResult(
          label: 'chair',
          rawLabel: 'chair',
          confidence: 0.85,
          direction: 'வலப்பக்கம்',
          distance: '2.0 மீட்டர்',
          distanceM: 2.0,
          xCenter: 0.80,
        ),
      ];

      final feedback = finder.evaluateDetections(detections, now);
      expect(feedback, isNotNull);
      expect(feedback!.isFound, isTrue);
      expect(feedback.spokenTextTa, contains('வலப்பக்கம் உள்ளது. வலதுபுறம் திரும்பவும்'));
    });

    test('Cancel clears active target state', () {
      finder.setTargetFromQuery('பாட்டில் எங்கே?');
      expect(finder.isActive, isTrue);
      finder.cancel();
      expect(finder.isActive, isFalse);
      expect(finder.activeTarget, isNull);
    });
  });

  group('Priority 3: Emergency SOS & Location Payload', () {
    test('SosPayload correctly constructs GPS coordinates and Google Maps URL', () {
      const payload = SosPayload(
        latitude: 13.0827,
        longitude: 80.2707,
        batteryLevel: 85,
        emergencyContact: '+919876543210',
        messageTa: 'அவசர உதவி தேவை!',
        mapUrl: 'https://maps.google.com/?q=13.08270,80.27070',
      );

      expect(payload.latitude, equals(13.0827));
      expect(payload.longitude, equals(80.2707));
      expect(payload.batteryLevel, equals(85));
      expect(payload.emergencyContact, equals('+919876543210'));
      expect(payload.mapUrl, contains('https://maps.google.com/?q=13.08270,80.27070'));
    });
  });

  group('Priority 2 & 3: 100% Offline Tamil Voice Commands Parser', () {
    final voiceService = VoiceCommandService();

    test('Parses Emergency SOS triggers ("அவசரம்" and "உதவி")', () {
      expect(voiceService.parseCommand('அவசரம்'), equals(VoiceCommand.emergencySOS));
      expect(voiceService.parseCommand('உதவி'), equals(VoiceCommand.emergencySOS));
      expect(voiceService.parseCommand('ஆபத்து என்னை காப்பாற்று'), equals(VoiceCommand.emergencySOS));
      expect(voiceService.parseCommand('emergency sos'), equals(VoiceCommand.emergencySOS));
    });

    test('Parses Banknote Identifier commands', () {
      expect(voiceService.parseCommand('ரூபாய் நோட்டு'), equals(VoiceCommand.identifyCurrency));
      expect(voiceService.parseCommand('பணம் என்ன'), equals(VoiceCommand.identifyCurrency));
      expect(voiceService.parseCommand('check currency'), equals(VoiceCommand.identifyCurrency));
      expect(voiceService.parseCommand('banknote'), equals(VoiceCommand.identifyCurrency));
    });

    test('Parses Text & Signboard OCR reader commands', () {
      expect(voiceService.parseCommand('பலகையை படி'), equals(VoiceCommand.readText));
      expect(voiceService.parseCommand('எழுத்து வாசி'), equals(VoiceCommand.readText));
      expect(voiceService.parseCommand('read signboard'), equals(VoiceCommand.readText));
      expect(voiceService.parseCommand('read text'), equals(VoiceCommand.readText));
    });

    test('Parses Object Finder commands without confusing with location', () {
      expect(voiceService.parseCommand('சாவி எங்கே'), equals(VoiceCommand.findObject));
      expect(voiceService.parseCommand('பாட்டில் எங்கே'), equals(VoiceCommand.findObject));
      expect(voiceService.parseCommand('நாற்காலி எங்கே இருக்கிறது'), equals(VoiceCommand.findObject));
      expect(voiceService.parseCommand('find my keys'), equals(VoiceCommand.findObject));

      // Disambiguation: Location query should still map to whereAmI
      expect(voiceService.parseCommand('நான் எங்கே இருக்கிறேன்'), equals(VoiceCommand.whereAmI));
      expect(voiceService.parseCommand('என் இருப்பிடம் என்ன'), equals(VoiceCommand.whereAmI));
    });

    test('Parses Flashlight / Torch toggle commands', () {
      expect(voiceService.parseCommand('டார்ச் ஆன் செய்'), equals(VoiceCommand.toggleTorch));
      expect(voiceService.parseCommand('வெளிச்சம் வேண்டும்'), equals(VoiceCommand.toggleTorch));
      expect(voiceService.parseCommand('turn on flashlight'), equals(VoiceCommand.toggleTorch));
    });

    test('Parses TTS Speech Rate customization commands', () {
      expect(voiceService.parseCommand('வேகமாக பேசு'), equals(VoiceCommand.fasterSpeed));
      expect(voiceService.parseCommand('speed up speech'), equals(VoiceCommand.fasterSpeed));
      expect(voiceService.parseCommand('மெதுவாக பேசு'), equals(VoiceCommand.slowerSpeed));
      expect(voiceService.parseCommand('slow down voice'), equals(VoiceCommand.slowerSpeed));
    });

    test('Parses standard continuous navigation commands', () {
      expect(voiceService.parseCommand('தொடங்கு'), equals(VoiceCommand.start));
      expect(voiceService.parseCommand('நிறுத்து'), equals(VoiceCommand.stop));
      expect(voiceService.parseCommand('மீண்டும் சொல்'), equals(VoiceCommand.repeat));
      expect(voiceService.parseCommand('யார் இது'), equals(VoiceCommand.whoIsThis));
      expect(voiceService.parseCommand('அமைப்புகள்'), equals(VoiceCommand.openSettings));
      expect(voiceService.parseCommand('நபர்கள்'), equals(VoiceCommand.openPeople));
    });
  });
}
