import 'package:flutter_test/flutter_test.dart';
import 'package:sonar_vault/features/cloud/domain/cloud_recycle_policy.dart';

void main() {
  group('cloud recycle policy', () {
    final active = <String, dynamic>{'id': 'active', 'deleted_at': null};
    final recent = <String, dynamic>{
      'id': 'recent',
      'deleted_at': '2026-08-10T12:00:00Z',
    };
    final expired = <String, dynamic>{
      'id': 'expired',
      'deleted_at': '2026-07-01T12:00:00Z',
    };

    test('partitions active and recycled rows without changing order', () {
      final rows = [recent, active, expired];
      expect(activeCloudTrackRows(rows).map((row) => row['id']), ['active']);
      expect(recycledCloudTrackRows(rows).map((row) => row['id']), [
        'recent',
        'expired',
      ]);
    });

    test('expires only after the thirty day retention window', () {
      final now = DateTime.utc(2026, 8, 22, 12);
      expect(isCloudTrackRecycleExpired(active, now: now), isFalse);
      expect(isCloudTrackRecycleExpired(recent, now: now), isFalse);
      expect(isCloudTrackRecycleExpired(expired, now: now), isTrue);
      expect(recoverableCloudTrackRows([active, recent, expired], now: now), [
        recent,
      ]);
      expect(expiredCloudTrackRows([active, recent, expired], now: now), [
        expired,
      ]);
    });

    test('the exact retention boundary is expired and hidden', () {
      final deletedAt = DateTime.utc(2026, 7, 23, 12);
      final row = <String, dynamic>{
        'id': 'boundary',
        'deleted_at': deletedAt.toIso8601String(),
      };
      final boundary = deletedAt.add(cloudRecycleRetention);

      expect(
        isCloudTrackRecycleExpired(
          row,
          now: boundary.subtract(const Duration(microseconds: 1)),
        ),
        isFalse,
      );
      expect(isCloudTrackRecycleExpired(row, now: boundary), isTrue);
      expect(recoverableCloudTrackRows([row], now: boundary), isEmpty);
      expect(expiredCloudTrackRows([row], now: boundary), [row]);
    });
  });
}
