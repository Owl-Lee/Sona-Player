import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonar_vault/core/widgets/whole_item_viewport.dart';
import 'package:sonar_vault/features/player/presentation/vinyl_record.dart';

void main() {
  testWidgets('fixed list viewport only exposes complete item extents', (
    tester,
  ) async {
    const childKey = ValueKey('whole-list-child');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 539,
            child: WholeItemViewport(
              itemExtent: 66,
              child: ColoredBox(key: childKey, color: Colors.blue),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(childKey)).height, 528);
  });

  testWidgets('vinyl layout center is not shifted by the tonearm', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: VinylRecord(
            track: null,
            size: 220,
            turns: AlwaysStoppedAnimation<double>(0),
            isPlaying: false,
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(VinylRecord)), const Size(220, 220));
  });
}
