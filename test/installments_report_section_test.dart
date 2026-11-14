import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/features/installments/domain/entities/installment_summary.dart';
import 'package:clothes_erp/features/installments/domain/facades/installments_facade.dart';
import 'package:clothes_erp/features/reports/presentation/cubits/installments_report_cubit.dart';
import 'package:clothes_erp/features/reports/presentation/widgets/installments_report_section.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

class FakeInstallmentsFacadeForSection implements InstallmentsFacade {
  bool shouldFail = false;

  @override
  Future<Either<Failure, InstallmentSummary>> getSummary({
    DateTime? now,
  }) async {
    if (shouldFail) {
      return const Left(CacheFailure('فشل في جلب البيانات'));
    }
    return const Right(
      InstallmentSummary(
        totalOutstanding: 75000,
        monthlyCollected: 25000,
        overdueTotal: 15000,
        overdueCount: 3,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final sl = GetIt.instance;
  late FakeInstallmentsFacadeForSection fakeFacade;

  setUp(() async {
    await sl.reset();
    fakeFacade = FakeInstallmentsFacadeForSection();
    sl.registerFactory<InstallmentsReportCubit>(
      () => InstallmentsReportCubit(fakeFacade),
    );
  });

  tearDown(() async {
    await sl.reset();
  });

  Widget buildTestWidget() {
    return const MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(child: InstallmentsReportSection()),
        ),
      ),
    );
  }

  testWidgets('renders metric cards with correct summary data', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('التقسيط'), findsOneWidget);
    expect(find.text('إجمالي المتبقي'), findsOneWidget);
    expect(find.text('750.00'), findsOneWidget);

    expect(find.text('المحصل هذا الشهر'), findsOneWidget);
    expect(find.text('250.00'), findsOneWidget);

    expect(find.text('إجمالي المتأخرات'), findsOneWidget);
    expect(find.text('150.00'), findsOneWidget);

    expect(find.text('عدد العقود المتأخرة'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    expect(find.text('التحصيل خلال 6 أشهر'), findsOneWidget);
  });

  testWidgets('renders error message when loading fails', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    fakeFacade.shouldFail = true;

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('خطأ: فشل في جلب البيانات'), findsOneWidget);
  });
}
