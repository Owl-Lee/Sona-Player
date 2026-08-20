import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonar_vault/core/widgets/latest_snack_bar.dart';

void main() {
  testWidgets('a newer snack bar immediately replaces the previous message', (
    tester,
  ) async {
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              pageContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    showLatestSnackBar(
      pageContext,
      const SnackBar(content: Text('first operation')),
    );
    await tester.pump();
    expect(find.text('first operation'), findsOneWidget);

    showLatestSnackBar(
      pageContext,
      const SnackBar(content: Text('latest operation')),
    );
    await tester.pump();

    expect(find.text('first operation'), findsNothing);
    expect(find.text('latest operation'), findsOneWidget);
  });
}
