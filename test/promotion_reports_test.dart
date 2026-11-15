import 'package:clothes_erp/core/database/app_database.dart' hide Promotion;
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/promotions/data/datasources/promotions_local_data_source.dart';
import 'package:clothes_erp/features/promotions/data/repositories/promotions_repository_impl.dart';
import 'package:clothes_erp/features/promotions/domain/entities/promotion.dart';
import 'package:clothes_erp/features/promotions/domain/entities/promotion_report_entity.dart';
import 'package:clothes_erp/features/reports/presentation/cubits/promotions_report_cubit.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBranchProvider implements BranchProvider {
  @override
  Future<String> getBranchId() async => 'branch-1';
}

class _FakeFeatureGate implements FeatureGate {
  @override
  Future<bool> isEnabled(String key) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  late PromotionsLocalDataSource localDataSource;
  late PromotionsRepositoryImpl repository;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    localDataSource = PromotionsLocalDataSourceImpl(db);
    repository = PromotionsRepositoryImpl(
      localDataSource,
      _FakeFeatureGate(),
      _FakeBranchProvider(),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('zero applications returns empty topPromotions and 0 totals', () async {
    final report = await localDataSource.getPromotionReport(branchId: 'branch-1');
    expect(report.totalDiscountPiasters, 0);
    expect(report.totalApplications, 0);
    expect(report.totalSalesWithPromotions, 0);
    expect(report.topPromotions, isEmpty);
  });

  test('top promotions query calculates count, totalDiscount, and distinct sales correctly', () async {
    final now = DateTime.now();
    // 1. Create two promotions
    final promoA = Promotion(
      id: 'p-1',
      branchId: 'branch-1',
      name: 'عرض الصيف',
      type: 'percent',
      scope: 'all',
      valueBp: 1000,
      minQuantity: 1,
      startsAt: now.subtract(const Duration(days: 10)),
      endsAt: now.add(const Duration(days: 10)),
      isActive: true,
      priority: 10,
      createdBy: 'admin',
      createdAt: now,
      updatedAt: now,
    );
    final promoB = Promotion(
      id: 'p-2',
      branchId: 'branch-1',
      name: 'عرض الجمعة',
      type: 'fixed',
      scope: 'all',
      valuePiasters: 2000,
      minQuantity: 1,
      startsAt: now.subtract(const Duration(days: 10)),
      endsAt: now.add(const Duration(days: 10)),
      isActive: true,
      priority: 5,
      createdBy: 'admin',
      createdAt: now,
      updatedAt: now,
    );
    await localDataSource.createPromotion(promoA);
    await localDataSource.createPromotion(promoB);

    // 2. Insert applications
    // Sale 1: promo A (500), promo B (2000)
    // Sale 2: promo A (1000)
    await localDataSource.recordApplications([
      AppliedPromotion(
        id: 'app-1',
        branchId: 'branch-1',
        promotionId: 'p-1',
        promotionName: 'عرض الصيف',
        saleId: 's-1',
        saleItemId: 'item-1',
        cartLineIndex: 0,
        discountPiasters: 500,
        createdAt: now,
      ),
      AppliedPromotion(
        id: 'app-2',
        branchId: 'branch-1',
        promotionId: 'p-2',
        promotionName: 'عرض الجمعة',
        saleId: 's-1',
        saleItemId: 'item-2',
        cartLineIndex: 1,
        discountPiasters: 2000,
        createdAt: now,
      ),
      AppliedPromotion(
        id: 'app-3',
        branchId: 'branch-1',
        promotionId: 'p-1',
        promotionName: 'عرض الصيف',
        saleId: 's-2',
        saleItemId: 'item-3',
        cartLineIndex: 0,
        discountPiasters: 1000,
        createdAt: now,
      ),
    ]);

    final result = await repository.getPromotionReport();
    expect(result.isRight(), isTrue);

    final report = result.getOrElse(() => const PromotionReportEntity(
          totalDiscountPiasters: 0,
          totalApplications: 0,
          totalSalesWithPromotions: 0,
          topPromotions: [],
        ));

    expect(report.totalDiscountPiasters, 3500); // 500 + 2000 + 1000
    expect(report.totalApplications, 3);
    expect(report.totalSalesWithPromotions, 2); // s-1, s-2
    expect(report.topPromotions.length, 2);

    // Top promo by discount: promo B (2000) > promo A (1500)
    expect(report.topPromotions.first.promotionId, 'p-2');
    expect(report.topPromotions.first.promotionName, 'عرض الجمعة');
    expect(report.topPromotions.first.count, 1);
    expect(report.topPromotions.first.totalDiscountPiasters, 2000);

    expect(report.topPromotions[1].promotionId, 'p-1');
    expect(report.topPromotions[1].promotionName, 'عرض الصيف');
    expect(report.topPromotions[1].count, 2);
    expect(report.topPromotions[1].totalDiscountPiasters, 1500);
  });

  test('date filtering filters out applications outside start/end date range', () async {
    final now = DateTime(2026, 6, 15, 12, 0);
    final past = DateTime(2026, 5, 10);
    final future = DateTime(2026, 7, 20);

    final promo = Promotion(
      id: 'p-1',
      branchId: 'branch-1',
      name: 'عرض الصيف',
      type: 'percent',
      scope: 'all',
      valueBp: 1000,
      minQuantity: 1,
      startsAt: past,
      endsAt: future,
      isActive: true,
      priority: 10,
      createdBy: 'admin',
      createdAt: past,
      updatedAt: past,
    );
    await localDataSource.createPromotion(promo);

    await localDataSource.recordApplications([
      AppliedPromotion(
        id: 'app-old',
        branchId: 'branch-1',
        promotionId: 'p-1',
        promotionName: 'عرض الصيف',
        saleId: 's-old',
        saleItemId: 'item-old',
        cartLineIndex: 0,
        discountPiasters: 300,
        createdAt: past,
      ),
      AppliedPromotion(
        id: 'app-target',
        branchId: 'branch-1',
        promotionId: 'p-1',
        promotionName: 'عرض الصيف',
        saleId: 's-cur',
        saleItemId: 'item-cur',
        cartLineIndex: 0,
        discountPiasters: 800,
        createdAt: now,
      ),
      AppliedPromotion(
        id: 'app-future',
        branchId: 'branch-1',
        promotionId: 'p-1',
        promotionName: 'عرض الصيف',
        saleId: 's-fut',
        saleItemId: 'item-fut',
        cartLineIndex: 0,
        discountPiasters: 900,
        createdAt: future,
      ),
    ]);

    final report = await localDataSource.getPromotionReport(
      branchId: 'branch-1',
      startDate: DateTime(2026, 6, 1),
      endDate: DateTime(2026, 6, 30),
    );

    expect(report.totalApplications, 1);
    expect(report.totalDiscountPiasters, 800);
    expect(report.totalSalesWithPromotions, 1);
  });

  test('PromotionsReportCubit emits loading then success with report', () async {
    final cubit = PromotionsReportCubit(repository);
    expect(cubit.state.status, PromotionsReportStatus.initial);

    final future = cubit.load();
    expect(cubit.state.status, PromotionsReportStatus.loading);

    await future;
    expect(cubit.state.status, PromotionsReportStatus.success);
    expect(cubit.state.report, isNotNull);
    expect(cubit.state.report!.totalDiscountPiasters, 0);
  });
}
