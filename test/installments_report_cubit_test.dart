import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/features/installments/domain/entities/installment_summary.dart';
import 'package:clothes_erp/features/installments/domain/facades/installments_facade.dart';
import 'package:clothes_erp/features/reports/presentation/cubits/installments_report_cubit.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeInstallmentsFacadeForReport implements InstallmentsFacade {
  bool shouldFail = false;
  int monthlyBase = 1000;

  @override
  Future<Either<Failure, InstallmentSummary>> getSummary({DateTime? now}) async {
    if (shouldFail) {
      return const Left(CacheFailure('Database error'));
    }
    final current = now ?? DateTime.now();
    return Right(InstallmentSummary(
      totalOutstanding: 50000,
      monthlyCollected: monthlyBase * current.month,
      overdueTotal: 10000,
      overdueCount: 2,
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeInstallmentsFacadeForReport fakeFacade;
  late InstallmentsReportCubit cubit;

  setUp(() {
    fakeFacade = FakeInstallmentsFacadeForReport();
    cubit = InstallmentsReportCubit(fakeFacade);
  });

  tearDown(() async {
    await cubit.close();
  });

  test('initial state is correct', () {
    expect(cubit.state.status, InstallmentsReportStatus.initial);
    expect(cubit.state.summary, isNull);
    expect(cubit.state.monthlyTrend, isEmpty);
  });

  test('load emits success with summary and 6 months trend', () async {
    final fixedNow = DateTime(2026, 6, 15);
    await cubit.load(now: fixedNow);

    expect(cubit.state.status, InstallmentsReportStatus.success);
    expect(cubit.state.summary, isNotNull);
    expect(cubit.state.summary!.totalOutstanding, 50000);
    expect(cubit.state.summary!.overdueCount, 2);

    expect(cubit.state.monthlyTrend.length, 6);
    // Month 1 to Month 6
    expect(cubit.state.monthlyTrend.last.month.month, 6);
    expect(cubit.state.monthlyTrend.first.month.month, 1);
  });

  test('load emits error when facade fails', () async {
    fakeFacade.shouldFail = true;
    final fixedNow = DateTime(2026, 6, 15);
    await cubit.load(now: fixedNow);

    expect(cubit.state.status, InstallmentsReportStatus.error);
    expect(cubit.state.errorMessage, 'Database error');
  });
}

