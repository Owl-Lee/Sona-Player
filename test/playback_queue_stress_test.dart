import 'package:flutter_test/flutter_test.dart';

import 'dart:math';

import 'package:sonar_vault/features/library/domain/track.dart';
import 'package:sonar_vault/features/player/application/player_controller.dart';
import 'package:sonar_vault/features/player/domain/playback_queue_policy.dart';

Track track(int id) => Track(
  id: id,
  path: 'C:/music/$id.mp3',
  title: 'Track $id',
  artist: 'Sona',
  album: 'Stress',
  duration: const Duration(minutes: 3),
  fileSize: 1024,
  contentHash: 'hash-$id',
  importedAt: DateTime.utc(2026),
);

void main() {
  group('playback queue stress policy', () {
    test('ten thousand next and previous operations always stay in range', () {
      for (final mode in VaultPlaybackMode.values) {
        var index = 0;
        for (var operation = 0; operation < 10000; operation++) {
          index = nextPlaybackQueueIndex(
            length: 137,
            currentIndex: index,
            forward: operation.isEven,
            mode: mode,
            shuffleOffset: operation % 136 + 1,
          );
          expect(index, inInclusiveRange(0, 136));
        }
      }
    });

    test('loop mode wraps at both ends', () {
      expect(
        nextPlaybackQueueIndex(
          length: 3,
          currentIndex: 2,
          forward: true,
          mode: VaultPlaybackMode.loop,
        ),
        0,
      );
      expect(
        nextPlaybackQueueIndex(
          length: 3,
          currentIndex: 0,
          forward: false,
          mode: VaultPlaybackMode.loop,
        ),
        2,
      );
    });

    test(
      'selecting from a new list replaces and de-duplicates the context',
      () {
        final selected = track(99);
        final normalized = normalizedPlaybackQueue(selected, [
          track(1),
          track(2),
          track(2),
        ]);
        expect(normalized.map((item) => item.id), [99, 1, 2]);
      },
    );

    test('same content is de-duplicated across temporary and database ids', () {
      final local = track(7);
      final cloudCandidate = Track(
        path: 'C:/cache/7.mp3',
        title: local.title,
        artist: local.artist,
        album: local.album,
        duration: local.duration,
        fileSize: local.fileSize,
        contentHash: local.contentHash,
        importedAt: local.importedAt,
      );

      final normalized = normalizedPlaybackQueue(cloudCandidate, [
        local,
        cloudCandidate,
        local,
      ]);

      expect(normalized, hasLength(1));
      expect(normalized.single.contentHash, local.contentHash);
    });

    test('one hundred thousand seeded source switches, moves and deletions preserve invariants', () {
      final random = Random(0x50A);
      var library = List.generate(80, track);
      var queue = <Track>[];
      Track? current;
      var moves = 0;
      var sourceSwitches = 0;
      var deletions = 0;
      var mvDetaches = 0;
      var nextImportedId = 1000;

      for (var operation = 0; operation < 100000; operation++) {
        switch (random.nextInt(5)) {
          case 0:
            final source = List.generate(
              random.nextInt(30) + 1,
              (_) => library[random.nextInt(library.length)],
            );
            current = source[random.nextInt(source.length)];
            queue = normalizedPlaybackQueue(current, source);
            sourceSwitches++;
          case 1:
          case 2:
            if (queue.isEmpty || current == null) continue;
            final currentIndex = queue.indexWhere(
              (item) => samePlaybackTrack(item, current!),
            );
            final nextIndex = nextPlaybackQueueIndex(
              length: queue.length,
              currentIndex: currentIndex,
              forward: operation.isEven,
              mode: VaultPlaybackMode.values[operation % 3],
              shuffleOffset: queue.length <= 1
                  ? null
                  : random.nextInt(queue.length - 1) + 1,
            );
            current = queue[nextIndex];
            moves++;
          case 3:
            if (library.length <= 5) continue;
            final removed = library.removeAt(random.nextInt(library.length));
            final reconciled = reconcilePlaybackQueue(
              current: current,
              queue: queue,
              available: library,
            );
            queue = reconciled.queue;
            current = reconciled.current;
            if (current == null && queue.isNotEmpty) current = queue.first;
            expect(queue.any((item) => item.id == removed.id), isFalse);
            // Re-import a distinct item so the destructive branch continues
            // to run throughout the entire seeded campaign.
            library.add(track(nextImportedId++));
            deletions++;
          case 4:
            final index = random.nextInt(library.length);
            final previous = library[index];
            final withVideo = previous.copyWith(
              videoPath: 'C:/video/${previous.id}.mp4',
            );
            library[index] = withVideo;
            var reconciled = reconcilePlaybackQueue(
              current: current,
              queue: queue,
              available: library,
            );
            library[index] = withVideo.copyWith(clearVideoPath: true);
            reconciled = reconcilePlaybackQueue(
              current: reconciled.current,
              queue: reconciled.queue,
              available: library,
            );
            queue = reconciled.queue;
            current = reconciled.current;
            if (current?.id == previous.id) expect(current!.hasVideo, isFalse);
            mvDetaches++;
        }

        final ids = queue.map((item) => item.id).whereType<int>().toList();
        final hashes = queue.map((item) => item.contentHash).toList();
        expect(ids.toSet(), hasLength(ids.length));
        expect(hashes.toSet(), hasLength(hashes.length));
        final currentId = current?.id;
        if (currentId != null) {
          expect(library.any((item) => item.id == currentId), isTrue);
        }
      }

      expect(moves, greaterThan(20000));
      expect(sourceSwitches, greaterThan(10000));
      expect(deletions, greaterThan(10000));
      expect(mvDetaches, greaterThan(10000));
    });

    test('empty and one-item queues cannot produce invalid indexes', () {
      expect(
        nextPlaybackQueueIndex(
          length: 0,
          currentIndex: 50,
          forward: true,
          mode: VaultPlaybackMode.shuffle,
        ),
        0,
      );
      expect(
        nextPlaybackQueueIndex(
          length: 1,
          currentIndex: 0,
          forward: false,
          mode: VaultPlaybackMode.loop,
        ),
        0,
      );
    });
  });
}
