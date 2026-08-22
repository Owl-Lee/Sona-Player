import 'package:flutter_test/flutter_test.dart';
import 'package:sonar_vault/core/utils/serialized_task_queue.dart';

void main() {
  test('rapid transport tasks remain ordered and never overlap', () async {
    final queue = SerializedTaskQueue();
    final started = <int>[];
    final completed = <int>[];
    var active = 0;
    var peakActive = 0;

    final operations = List.generate(2000, (index) {
      return queue.run(() async {
        started.add(index);
        active++;
        peakActive = active > peakActive ? active : peakActive;
        if (index % 7 == 0) await Future<void>.delayed(Duration.zero);
        completed.add(index);
        active--;
      });
    });
    await Future.wait(operations);

    expect(peakActive, 1);
    expect(started, List.generate(2000, (index) => index));
    expect(completed, started);
  });

  test('one failed native action does not poison later controls', () async {
    final queue = SerializedTaskQueue();
    final completed = <int>[];
    final results = await Future.wait(
      List.generate(250, (index) async {
        try {
          await queue.run(() async {
            if (index % 23 == 0) throw StateError('synthetic native failure');
            completed.add(index);
          });
          return true;
        } catch (_) {
          return false;
        }
      }),
    );

    expect(results.where((value) => !value), hasLength(11));
    expect(completed, hasLength(239));
    expect(completed.last, 249);
  });
}
