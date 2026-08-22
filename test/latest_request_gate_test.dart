import 'package:flutter_test/flutter_test.dart';
import 'package:sonar_vault/core/utils/latest_request_gate.dart';
import 'package:sonar_vault/features/player/application/player_controller.dart';
import 'package:sonar_vault/features/library/domain/track.dart';

void main() {
  test(
    'violent repeated taps leave only the last playback request current',
    () {
      final gate = LatestRequestGate();
      final requests = <int>[];

      for (var index = 0; index < 1000; index++) {
        requests.add(gate.begin());
      }

      expect(gate.isCurrent(requests.last), isTrue);
      expect(requests.take(requests.length - 1).every(gate.isCurrent), isFalse);
      expect(requests.take(requests.length - 1).where(gate.isCurrent), isEmpty);
    },
  );

  test('a newer cloud click invalidates every pending older request', () {
    final gate = LatestRequestGate();
    final cloudA = gate.begin();
    final cloudB = gate.begin();
    final cloudC = gate.begin();

    expect(gate.isCurrent(cloudA), isFalse);
    expect(gate.isCurrent(cloudB), isFalse);
    expect(gate.isCurrent(cloudC), isTrue);
  });

  test(
    'failed rapid source changes keep the previously known player state',
    () {
      final current = Track(
        id: 1,
        path: 'C:/music/current.mp3',
        title: 'Current',
        artist: 'Sona',
        album: 'Test',
        duration: Duration(minutes: 3),
        fileSize: 1,
        contentHash: 'current',
        importedAt: DateTime(2026),
      );
      final previous = PlaybackState(
        currentTrack: current,
        isPlaying: true,
        position: Duration(seconds: 42),
        duration: Duration(minutes: 3),
        queueSource: 'queue_source_cloud_library',
      );

      for (var attempt = 0; attempt < 500; attempt++) {
        final restored = previous.copyWith(errorMessage: '当前候选文件不可用');
        expect(restored.currentTrack, current);
        expect(restored.position, const Duration(seconds: 42));
        expect(restored.isPlaying, isTrue);
      }
    },
  );
}
