import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:stockinfo/main.dart';

void main() {
  testWidgets('Page shows controls without network', (tester) async {
    SharedPreferences.setMockInitialValues({});
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

  testWidgets('Restores saved ticker and range', (tester) async {
    SharedPreferences.setMockInitialValues({
      'ticker': 'AAPL',
      'range': 31,
      'auto': false,
      'dip': '-3.0',
      'profit': '5.0',
    });
    await tester.pumpWidget(const StockApp());
    await tester.pump();

    expect(find.text('AAPL'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
