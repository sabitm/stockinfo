import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stockinfo/main.dart';

void main() {
  testWidgets('Preview page shows controls without network', (tester) async {
    await tester.pumpWidget(const StockApp());

    expect(find.text('StockInfo'), findsOneWidget);
    expect(find.text('Load'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('7D'), findsOneWidget);
    expect(find.text('14D'), findsOneWidget);
    expect(find.text('31D'), findsOneWidget);
    expect(find.text('60D'), findsOneWidget);
    expect(find.text('90D'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
