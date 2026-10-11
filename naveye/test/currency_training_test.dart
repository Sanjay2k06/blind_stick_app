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
  });
}
