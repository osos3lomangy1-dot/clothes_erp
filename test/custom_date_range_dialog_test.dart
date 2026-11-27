import 'package:clothes_erp/core/widgets/custom_date_range_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CustomDateRangeDialog selects preset and returns DateTimeRange', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    DateTimeRange? picked;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                picked = await showCustomDateRangeDialog(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('تحديد الفترة الزمنية'), findsOneWidget);
    expect(find.text('آخر 7 أيام'), findsOneWidget);

    await tester.tap(find.text('آخر 7 أيام'));
    await tester.pumpAndSettle();

    expect(find.text('7 يوم'), findsOneWidget);

    await tester.tap(find.text('تطبيق الفترة'));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.end.difference(picked!.start).inDays, 6);
  });
}

