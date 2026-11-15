import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/features/promotions/domain/entities/promotion.dart';
import 'package:clothes_erp/features/promotions/domain/entities/promotion_report_entity.dart';
import 'package:clothes_erp/features/promotions/domain/repositories/promotions_repository.dart';
import 'package:clothes_erp/features/promotions/presentation/cubits/promotions_cubit.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePromotionsRepository implements PromotionsRepository {
  List<Promotion> promotions = [];
  bool shouldFail = false;
  String failureMessage = 'Repository error';

  @override
  Future<Either<Failure, List<Promotion>>> getAllPromotions({bool includeInactive = true}) async {
    if (shouldFail) return Left(CacheFailure(failureMessage));
    return Right(includeInactive ? promotions : promotions.where((p) => p.isActive).toList());
  }

  @override
  Future<Either<Failure, List<Promotion>>> getActivePromotions({DateTime? now}) async {
    if (shouldFail) return Left(CacheFailure(failureMessage));
    final ref = now ?? DateTime.now();
    return Right(promotions
        .where((p) => p.isActive && !p.startsAt.isAfter(ref) && !p.endsAt.isBefore(ref))
        .toList());
  }

  @override
  Future<Either<Failure, List<Promotion>>> listPromotions({bool includeInactive = true}) =>
      getAllPromotions(includeInactive: includeInactive);

  @override
  Future<Either<Failure, Promotion?>> getPromotionById(String id) async {
    if (shouldFail) return Left(CacheFailure(failureMessage));
    return Right(promotions.where((p) => p.id == id).firstOrNull);
  }

  @override
  Future<Either<Failure, void>> createPromotion(Promotion promotion) async {
    if (shouldFail) return Left(CacheFailure(failureMessage));
    promotions.add(promotion);
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> updatePromotion(Promotion promotion) async {
    if (shouldFail) return Left(CacheFailure(failureMessage));
    final idx = promotions.indexWhere((p) => p.id == promotion.id);
    if (idx != -1) {
      promotions[idx] = promotion;
    }
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> deactivatePromotion(String id) async {
    if (shouldFail) return Left(CacheFailure(failureMessage));
    final idx = promotions.indexWhere((p) => p.id == id);
    if (idx != -1) {
      promotions[idx] = promotions[idx].copyWith(isActive: false);
    }
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> deletePromotion(String id) async {
    if (shouldFail) return Left(CacheFailure(failureMessage));
    promotions.removeWhere((p) => p.id == id);
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> recordApplications(List<AppliedPromotion> applications) async {
    return const Right(null);
  }

  @override
  Future<Either<Failure, PromotionReportEntity>> getPromotionReport({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    return const Right(PromotionReportEntity(
      totalDiscountPiasters: 0,
      totalApplications: 0,
      totalSalesWithPromotions: 0,
      topPromotions: [],
    ));
  }
}

void main() {
  late _FakePromotionsRepository repo;
  late PromotionsCubit cubit;

  final samplePromo = Promotion(
    id: 'promo-1',
    branchId: 'branch-1',
    name: 'خصم الصيف',
    type: 'percent',
    scope: 'all',
    valueBp: 1500, // 15%
    minQuantity: 1,
    startsAt: DateTime(2026, 6, 1),
    endsAt: DateTime(2026, 8, 31),
    isActive: true,
    priority: 10,
    createdBy: 'admin',
    createdAt: DateTime(2026, 6, 1),
    updatedAt: DateTime(2026, 6, 1),
  );

  setUp(() {
    repo = _FakePromotionsRepository();
    cubit = PromotionsCubit(repo);
  });

  tearDown(() {
    cubit.close();
  });

  test('1. loadAll transitions from initial to loading to success with list', () async {
    repo.promotions = [samplePromo];
    expect(cubit.state.status, PromotionsStatus.initial);

    final future = cubit.loadAll();
    expect(cubit.state.status, PromotionsStatus.loading);

    await future;
    expect(cubit.state.status, PromotionsStatus.success);
    expect(cubit.state.promotions.length, 1);
    expect(cubit.state.promotions.first.name, 'خصم الصيف');
  });

  test('2. loadAll transitions to error state when repository fails', () async {
    repo.shouldFail = true;
    repo.failureMessage = 'Database disk full';

    await cubit.loadAll();
    expect(cubit.state.status, PromotionsStatus.error);
    expect(cubit.state.errorMessage, 'Database disk full');
  });

  test('3. createPromotion adds promotion and reloads list on success', () async {
    final success = await cubit.createPromotion(samplePromo);
    expect(success, isTrue);
    expect(cubit.state.status, PromotionsStatus.success);
    expect(cubit.state.promotions.length, 1);
  });

  test('4. createPromotion emits errorMessage and returns false on failure', () async {
    repo.shouldFail = true;
    repo.failureMessage = 'Feature disabled';

    final success = await cubit.createPromotion(samplePromo);
    expect(success, isFalse);
    expect(cubit.state.errorMessage, 'Feature disabled');
  });

  test('5. updatePromotion modifies existing promotion and reloads list', () async {
    repo.promotions = [samplePromo];
    final updated = samplePromo.copyWith(name: 'خصم الصيف المحدث', valueBp: 2000);

    final success = await cubit.updatePromotion(updated);
    expect(success, isTrue);
    expect(cubit.state.promotions.first.name, 'خصم الصيف المحدث');
    expect(cubit.state.promotions.first.valueBp, 2000);
  });

  test('6. deactivatePromotion and deletePromotion succeed and update repository', () async {
    repo.promotions = [samplePromo];

    final deactSuccess = await cubit.deactivatePromotion('promo-1');
    expect(deactSuccess, isTrue);
    expect(cubit.state.promotions.first.isActive, isFalse);

    final delSuccess = await cubit.deletePromotion('promo-1');
    expect(delSuccess, isTrue);
    expect(cubit.state.promotions, isEmpty);
  });

  testWidgets('7. Form validation checks for promotion values and percentages',
      (tester) async {
    final formKey = GlobalKey<FormState>();
    final valueController = TextEditingController();
    String type = 'percent';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: valueController,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'القيمة مطلوبة';
                    final n = double.tryParse(v);
                    if (n == null || n <= 0) return 'أدخل رقماً موجباً أكبر من 0';
                    if (type == 'percent' && n > 100) {
                      return 'النسبة المئوية لا يمكن أن تتجاوز 100%';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Empty check
    valueController.text = '';
    expect(formKey.currentState!.validate(), isFalse);

    // Negative / zero check
    valueController.text = '0';
    expect(formKey.currentState!.validate(), isFalse);

    valueController.text = '-5';
    expect(formKey.currentState!.validate(), isFalse);

    // Percent > 100 check
    valueController.text = '120';
    expect(formKey.currentState!.validate(), isFalse);

    // Valid percent
    valueController.text = '25';
    expect(formKey.currentState!.validate(), isTrue);

    // Fixed type allows values > 100
    type = 'fixed';
    valueController.text = '150';
    expect(formKey.currentState!.validate(), isTrue);
  });
}

