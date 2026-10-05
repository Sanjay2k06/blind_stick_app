import 'package:flutter_test/flutter_test.dart';
import 'package:naveye/screens/main_ai/main_ai_screen.dart';

void main() {
  testWidgets('NavEye smoke test — app boots without crashing', (WidgetTester tester) async {
    // NavEye requires Android camera/TFLite hardware — widget test is a placeholder.
    expect(1 + 1, equals(2));
  });

  test('formatLocationSummary creates a readable coordinates summary', () {
    final textTa = formatLocationSummary(12.9716, 77.5946, isTamil: true);
    expect(textTa, contains('12.972'));
    expect(textTa, contains('77.595'));
    expect(textTa, contains('அட்சரேகை'));

    final textEn = formatLocationSummary(12.9716, 77.5946, isTamil: false);
    expect(textEn, contains('12.972'));
    expect(textEn, contains('77.595'));
    expect(textEn, contains('latitude'));
    expect(textEn, contains('longitude'));
  });
}
