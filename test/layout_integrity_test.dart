import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonar_vault/core/widgets/whole_item_viewport.dart';
import 'package:sonar_vault/features/player/presentation/vinyl_record.dart';
import 'package:sonar_vault/features/shell/presentation/main_shell.dart';

void main() {
  test('desktop sidebar compacts at QA-height windows', () {
    expect(shouldUseCompactDesktopSidebar(648), isTrue);
    expect(shouldUseCompactDesktopSidebar(699), isTrue);
    expect(shouldUseCompactDesktopSidebar(700), isFalse);
    expect(shouldUseCompactDesktopSidebar(900), isFalse);
  });

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

  testWidgets('mobile shell keeps an 8px gap above the compact player', (
    tester,
  ) async {
    const surfaceKey = ValueKey('mobile-list-surface');
    const listKey = ValueKey('mobile-list-viewport');
    const playerKey = ValueKey('compact-player');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 539,
            child: Column(
              children: [
                Expanded(
                  child: Material(
                    key: surfaceKey,
                    child: WholeItemViewport(
                      itemExtent: 72,
                      child: ColoredBox(key: listKey, color: Colors.blue),
                    ),
                  ),
                ),
                SizedBox(height: 8),
                SizedBox(key: playerKey, height: 60),
              ],
            ),
          ),
        ),
      ),
    );

    final surfaceRect = tester.getRect(find.byKey(surfaceKey));
    final playerRect = tester.getRect(find.byKey(playerKey));
    expect(playerRect.top - surfaceRect.bottom, 8);
    expect(surfaceRect.height, 471);
    expect(tester.getSize(find.byKey(listKey)).height, 432);
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
