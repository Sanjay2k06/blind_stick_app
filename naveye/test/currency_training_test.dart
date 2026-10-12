import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:naveye/services/currency_recognition_service.dart';

void main() {
  group('CurrencyRecognitionService — Trained Dataset Validation (money_image)', () {
    final service = CurrencyRecognitionService.instance;

    test('All 12 dataset images decode and classify correctly', () {
      final dir = Directory('money_image');
      expect(dir.existsSync(), isTrue);

      final expectedMap = {
        '100rs_front_back_new.jpg': InrDenomination.oneHundred,
        '100rs_model1_front.jpg': InrDenomination.oneHundred,
        '10rs_model1_back.jpg': InrDenomination.ten,
        '10rs_model1_front.jpg': InrDenomination.ten,
        '10rs_model2_back.jpg': InrDenomination.ten,
        '10rs_model2_front.jpg': InrDenomination.ten,
        '2000_front_back.jpg': InrDenomination.twoThousand,
        '200_front_back.jpg': InrDenomination.twoHundred,
        '20rs_model1_frontend.jpg': InrDenomination.twenty,
        '20rs_model2_back.jpg': InrDenomination.twenty,
        '20rs_model2_frontend.jpg': InrDenomination.twenty,
        '500rs_image_front_back.jpg': InrDenomination.fiveHundred,
      };

      for (final entry in expectedMap.entries) {
        final f = File('money_image/${entry.key}');
        expect(f.existsSync(), isTrue, reason: 'File should exist: ${entry.key}');

        final bytes = f.readAsBytesSync();
        final decoded = img.decodeImage(bytes)!;

        final res = service.recognize(image: decoded);

        expect(
          res.denomination,
          equals(entry.value),
          reason: 'File ${entry.key} was expected to classify as ${entry.value} but got ${res.denomination} (${res.spokenTextEn})',
        );
        expect(res.isConfident, isTrue);
        expect(res.userAmountTa, contains('ரூபாய் உள்ளது'));
        expect(res.userAmountEn, contains('Rupees'));
      }
    });

    test('Correctly accumulates wallet balance across multiple banknotes', () {
      service.resetWallet();
      expect(service.walletBalance, equals(0));

      final f500 = File('money_image/500rs_image_front_back.jpg');
      final img500 = img.decodeImage(f500.readAsBytesSync())!;
      final res1 = service.recognize(image: img500, addToWallet: true);
      expect(res1.value, equals(500));
      expect(service.walletBalance, equals(500));

      final f100 = File('money_image/100rs_front_back_new.jpg');
      final img100 = img.decodeImage(f100.readAsBytesSync())!;
      final res2 = service.recognize(image: img100, addToWallet: true);
      expect(res2.value, equals(100));
      expect(service.walletBalance, equals(600));

      final f2000 = File('money_image/2000_front_back.jpg');
      final img2000 = img.decodeImage(f2000.readAsBytesSync())!;
      final res3 = service.recognize(image: img2000, addToWallet: true);
      expect(res3.value, equals(2000));
      expect(service.walletBalance, equals(2600));

      expect(service.getWalletStatusTa(), equals('உங்களிடம் மொத்தம் 2600 ரூபாய் உள்ளது.'));
      expect(service.getWalletStatusEn(), equals('You have a total of 2600 Rupees.'));

      service.resetWallet();
      expect(service.walletBalance, equals(0));
    });

    test('recognizeLiveStream classifies all dataset banknotes confidently', () {
      final expectedMap = {
        '100rs_front_back_new.jpg': InrDenomination.oneHundred,
        '100rs_model1_front.jpg': InrDenomination.oneHundred,
        '10rs_model1_back.jpg': InrDenomination.ten,
        '10rs_model1_front.jpg': InrDenomination.ten,
        '10rs_model2_back.jpg': InrDenomination.ten,
        '10rs_model2_front.jpg': InrDenomination.ten,
        '2000_front_back.jpg': InrDenomination.twoThousand,
        '200_front_back.jpg': InrDenomination.twoHundred,
        '20rs_model1_frontend.jpg': InrDenomination.twenty,
        '20rs_model2_back.jpg': InrDenomination.twenty,
        '20rs_model2_frontend.jpg': InrDenomination.twenty,
        '500rs_image_front_back.jpg': InrDenomination.fiveHundred,
      };

      for (final entry in expectedMap.entries) {
        final f = File('money_image/${entry.key}');
        final bytes = f.readAsBytesSync();
        final decoded = img.decodeImage(bytes)!;

        final res = service.recognizeLiveStream(decoded);
        expect(res.denomination, equals(entry.value));
        expect(res.isConfident, isTrue);
        expect(res.confidence, greaterThanOrEqualTo(0.70));
      }
    });

    test('recognizeLiveStream correctly rejects non-banknote blank or ambient images', () {
      // Solid black image
      final blackImg = img.Image(width: 200, height: 100);
      expect(service.recognizeLiveStream(blackImg).denomination, equals(InrDenomination.unknown));

      // Neutral gray image
      final grayImg = img.Image(width: 200, height: 100);
      for (int y = 0; y < 100; y++) {
        for (int x = 0; x < 200; x++) {
          grayImg.setPixelRgb(x, y, 128, 128, 128);
        }
      }
      expect(service.recognizeLiveStream(grayImg).denomination, equals(InrDenomination.unknown));

      // Concrete road / grey floor
      final roadImg = img.Image(width: 320, height: 240);
      for (int y = 0; y < 240; y++) {
        for (int x = 0; x < 320; x++) {
          final n = ((x + y * 2) % 25) - 12;
          roadImg.setPixelRgb(x, y, (140 + n).clamp(0, 255), (138 + n).clamp(0, 255), (135 + n).clamp(0, 255));
        }
      }
      final roadLive = service.recognizeLiveStream(roadImg);
      expect(roadLive.denomination, equals(InrDenomination.unknown));
      expect(roadLive.isConfident, isFalse);

      final roadSingle = service.recognize(image: roadImg);
      expect(roadSingle.denomination, equals(InrDenomination.unknown));
      expect(roadSingle.isConfident, isFalse);

      // Wooden desk / tabletop
      final deskImg = img.Image(width: 320, height: 240);
      for (int y = 0; y < 240; y++) {
        for (int x = 0; x < 320; x++) {
          final n = (x % 15) - 7;
          deskImg.setPixelRgb(x, y, (180 + n).clamp(0, 255), (145 + (n * 0.8).toInt()).clamp(0, 255), (115 + (n * 0.6).toInt()).clamp(0, 255));
        }
      }
      final deskLive = service.recognizeLiveStream(deskImg);
      expect(deskLive.denomination, equals(InrDenomination.unknown));
      expect(deskLive.isConfident, isFalse);

      final deskSingle = service.recognize(image: deskImg);
      expect(deskSingle.denomination, equals(InrDenomination.unknown));
      expect(deskSingle.isConfident, isFalse);

      // Warm indoor wall
      final wallImg = img.Image(width: 320, height: 240);
      for (int y = 0; y < 240; y++) {
        for (int x = 0; x < 320; x++) {
          final n = (x * y) % 20;
          wallImg.setPixelRgb(x, y, (215 + n).clamp(0, 255), (195 + n).clamp(0, 255), (150 + n).clamp(0, 255));
        }
      }
      final wallLive = service.recognizeLiveStream(wallImg);
      expect(wallLive.denomination, equals(InrDenomination.unknown));
      expect(wallLive.isConfident, isFalse);

      final wallSingle = service.recognize(image: wallImg);
      expect(wallSingle.denomination, equals(InrDenomination.unknown));
      expect(wallSingle.isConfident, isFalse);
    });
  });
}
