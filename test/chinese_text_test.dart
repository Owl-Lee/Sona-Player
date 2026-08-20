import 'package:flutter_test/flutter_test.dart';
import 'package:sonar_vault/core/utils/chinese_text.dart';

void main() {
  test('normalizes recognized metadata to Simplified Chinese', () {
    expect(toSimplifiedChinese('陳奕迅 · 美麗的神話'), '陈奕迅 · 美丽的神话');
    expect(toSimplifiedChinese('成龍、金喜善'), '成龙、金喜善');
  });

  test('preserves non-Chinese metadata', () {
    expect(
      toSimplifiedChinese('Eason Chan · AIR 2026'),
      'Eason Chan · AIR 2026',
    );
  });
}
