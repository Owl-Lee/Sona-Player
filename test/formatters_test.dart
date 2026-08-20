import 'package:flutter_test/flutter_test.dart';
import 'package:sonar_vault/core/utils/formatters.dart';

void main() {
  test('formats short and long durations', () {
    expect(formatDuration(const Duration(minutes: 3, seconds: 7)), '3:07');
    expect(
      formatDuration(const Duration(hours: 1, minutes: 2, seconds: 9)),
      '1:02:09',
    );
  });

  test('formats common file sizes', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1024 * 1024), '1.0 MB');
    expect(formatBytes(2 * 1024 * 1024 * 1024), '2.00 GB');
  });
}
