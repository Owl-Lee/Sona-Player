import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonar_vault/features/player/domain/media_transport_coordinator.dart';

void main() {
  test(
    'a stale native open is discarded before the newer source opens',
    () async {
      final transport = MediaTransportCoordinator();
      final firstOpenStarted = Completer<void>();
      final releaseFirstOpen = Completer<void>();
      final events = <String>[];
      String? nativeSource;

      final firstRequest = transport.beginSourceRequest();
      final first = transport.run(() async {
        final opened = await transport.openLatest(
          request: firstRequest,
          open: () async {
            events.add('open:A:start');
            firstOpenStarted.complete();
            await releaseFirstOpen.future;
            nativeSource = 'A';
            events.add('open:A:end');
          },
          discardStale: () async {
            events.add('discard:A');
            nativeSource = null;
          },
          commit: () => events.add('commit:A'),
        );
        expect(opened, isFalse);
      });

      await firstOpenStarted.future;
      final secondRequest = transport.beginSourceRequest();
      final second = transport.run(() async {
        final opened = await transport.openLatest(
          request: secondRequest,
          open: () async {
            events.add('open:B');
            nativeSource = 'B';
          },
          discardStale: () async {
            events.add('discard:B');
            nativeSource = null;
          },
          commit: () => events.add('commit:B'),
        );
        expect(opened, isTrue);
      });

      releaseFirstOpen.complete();
      await Future.wait([first, second]);

      expect(nativeSource, 'B');
      expect(events, [
        'open:A:start',
        'open:A:end',
        'discard:A',
        'open:B',
        'commit:B',
      ]);
    },
  );

  test('deleting a source during open leaves no stale native media', () async {
    final transport = MediaTransportCoordinator();
    final openStarted = Completer<void>();
    final releaseOpen = Completer<void>();
    String? nativeSource;
    var discarded = 0;

    final request = transport.beginSourceRequest();
    final opening = transport.run(() async {
      final opened = await transport.openLatest(
        request: request,
        open: () async {
          openStarted.complete();
          await releaseOpen.future;
          nativeSource = 'deleted-track';
        },
        discardStale: () async {
          discarded += 1;
          nativeSource = null;
        },
        commit: () => fail('a deleted source must never commit'),
      );
      expect(opened, isFalse);
    });

    await openStarted.future;
    transport.beginSourceRequest(); // Library reconciliation invalidates it.
    releaseOpen.complete();
    await opening;

    expect(discarded, 1);
    expect(nativeSource, isNull);
  });

  test('a superseded native open that throws is still unloaded', () async {
    final transport = MediaTransportCoordinator();
    final openStarted = Completer<void>();
    final releaseOpen = Completer<void>();
    var staleSourceLoaded = false;
    var discarded = 0;

    final request = transport.beginSourceRequest();
    final opening = transport.run(() async {
      await expectLater(
        transport.openLatest(
          request: request,
          open: () async {
            openStarted.complete();
            await releaseOpen.future;
            staleSourceLoaded = true;
            throw StateError('native open failed after replacing the source');
          },
          discardStale: () async {
            discarded += 1;
            staleSourceLoaded = false;
          },
          commit: () => fail('a failed stale source must never commit'),
        ),
        throwsStateError,
      );
    });

    await openStarted.future;
    transport.beginSourceRequest();
    releaseOpen.complete();
    await opening;

    expect(discarded, 1);
    expect(staleSourceLoaded, isFalse);
  });
}
