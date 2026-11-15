import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/promotion.dart' as domain;
import '../../domain/entities/promotion_report_entity.dart';

abstract class PromotionsLocalDataSource {
  Future<List<domain.Promotion>> getActivePromotions({
    required String branchId,
    DateTime? now,
  });
  Future<List<domain.Promotion>> getAllPromotions({
    required String branchId,
    bool includeInactive = true,
  });
  Future<domain.Promotion?> getPromotionById(String id);
  Future<void> createPromotion(domain.Promotion promotion);
  Future<void> updatePromotion(domain.Promotion promotion);
  Future<void> deactivatePromotion(String id);
  Future<void> deletePromotion(String id);
  Future<void> recordApplications(List<domain.AppliedPromotion> applications);
  Future<PromotionReportEntity> getPromotionReport({
    required String branchId,
    DateTime? startDate,
    DateTime? endDate,
  });
}

@LazySingleton(as: PromotionsLocalDataSource)
class PromotionsLocalDataSourceImpl implements PromotionsLocalDataSource {
  final AppDatabase _db;

  PromotionsLocalDataSourceImpl(this._db);

  domain.Promotion _mapRowToEntity(Promotion row) {
    return domain.Promotion(
      id: row.id,
      branchId: row.branchId,
      name: row.name,
      description: row.description,
      type: row.type,
      scope: row.scope,
      targetId: row.targetId,
      valueBp: row.valueBp,
      valuePiasters: row.valuePiasters,
      minQuantity: row.minQuantity,
      startsAt: row.startsAt,
      endsAt: row.endsAt,
      isActive: row.isActive,
      priority: row.priority,
      createdBy: row.createdBy,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
    );
  }

  PromotionsCompanion _mapEntityToCompanion(domain.Promotion entity) {
    return PromotionsCompanion(
      id: Value(entity.id),
      branchId: Value(entity.branchId),
      name: Value(entity.name),
      description: Value(entity.description),
      type: Value(entity.type),
      scope: Value(entity.scope),
      targetId: Value(entity.targetId),
      valueBp: Value(entity.valueBp),
      valuePiasters: Value(entity.valuePiasters),
      minQuantity: Value(entity.minQuantity),
      startsAt: Value(entity.startsAt),
      endsAt: Value(entity.endsAt),
      isActive: Value(entity.isActive),
      priority: Value(entity.priority),
      createdBy: Value(entity.createdBy),
      createdAt: Value(entity.createdAt),
      updatedAt: Value(entity.updatedAt),
      deletedAt: Value(entity.deletedAt),
    );
  }

  PromotionApplicationsCompanion _mapAppToCompanion(
    domain.AppliedPromotion app,
  ) {
    return PromotionApplicationsCompanion(
      id: Value(app.id),
      branchId: Value(app.branchId),
      promotionId: Value(app.promotionId),
      saleId: Value(app.saleId),
      saleItemId: Value(app.saleItemId),
      discountPiasters: Value(app.discountPiasters),
      createdAt: Value(app.createdAt),
      deletedAt: Value(app.deletedAt),
    );
  }

  @override
  Future<List<domain.Promotion>> getActivePromotions({
    required String branchId,
    DateTime? now,
  }) async {
    final ref = now ?? DateTime.now();
    final query = _db.select(_db.promotions)
      ..where(
        (p) =>
            p.branchId.equals(branchId) &
            p.deletedAt.isNull() &
            p.isActive.equals(true) &
            p.startsAt.isSmallerOrEqualValue(ref) &
            p.endsAt.isBiggerOrEqualValue(ref),
      )
      ..orderBy([
        (p) => OrderingTerm.desc(p.priority),
        (p) => OrderingTerm.asc(p.id),
      ]);
    final rows = await query.get();
    return rows.map(_mapRowToEntity).toList();
  }

  @override
  Future<List<domain.Promotion>> getAllPromotions({
    required String branchId,
    bool includeInactive = true,
  }) async {
    var query = _db.select(_db.promotions)
      ..where((p) => p.branchId.equals(branchId) & p.deletedAt.isNull());
    if (!includeInactive) {
      query = query..where((p) => p.isActive.equals(true));
    }
    query = query
      ..orderBy([
        (p) => OrderingTerm.desc(p.priority),
        (p) => OrderingTerm.desc(p.createdAt),
      ]);
    final rows = await query.get();
    return rows.map(_mapRowToEntity).toList();
  }

  @override
  Future<domain.Promotion?> getPromotionById(String id) async {
    final row = await (_db.select(
      _db.promotions,
    )..where((p) => p.id.equals(id) & p.deletedAt.isNull())).getSingleOrNull();
    return row == null ? null : _mapRowToEntity(row);
  }

  @override
  Future<void> createPromotion(domain.Promotion promotion) async {
    await _db.into(_db.promotions).insert(_mapEntityToCompanion(promotion));
  }

  @override
  Future<void> updatePromotion(domain.Promotion promotion) async {
    await _db.update(_db.promotions).replace(_mapEntityToCompanion(promotion));
  }

  @override
  Future<void> deactivatePromotion(String id) async {
    await (_db.update(_db.promotions)..where((p) => p.id.equals(id))).write(
      PromotionsCompanion(
        isActive: const Value(false),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> deletePromotion(String id) async {
    final now = DateTime.now();
    await (_db.update(_db.promotions)..where((p) => p.id.equals(id))).write(
      PromotionsCompanion(
        isActive: const Value(false),
        updatedAt: Value(now),
        deletedAt: Value(now),
      ),
    );
  }

  @override
  Future<void> recordApplications(
    List<domain.AppliedPromotion> applications,
  ) async {
    if (applications.isEmpty) return;
    await _db.batch((batch) {
      for (final app in applications) {
        batch.insert(_db.promotionApplications, _mapAppToCompanion(app));
      }
    });
  }

  @override
  Future<PromotionReportEntity> getPromotionReport({
    required String branchId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final query = _db.select(_db.promotionApplications).join([
      leftOuterJoin(
        _db.promotions,
        _db.promotions.id.equalsExp(_db.promotionApplications.promotionId),
      ),
    ])..where(
        _db.promotionApplications.branchId.equals(branchId) &
            _db.promotionApplications.deletedAt.isNull(),
      );

    if (startDate != null) {
      final start =
          DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0);
      query.where(_db.promotionApplications.createdAt.isBiggerOrEqualValue(start));
    }
    if (endDate != null) {
      final end =
          DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);
      query.where(_db.promotionApplications.createdAt.isSmallerOrEqualValue(end));
    }

    final rows = await query.get();

    int totalDiscount = 0;
    final Set<String> distinctSales = {};
    final Map<String, ({String name, int count, int discount})> promoStats = {};

    for (final r in rows) {
      final app = r.readTable(_db.promotionApplications);
      final promo = r.readTableOrNull(_db.promotions);

      totalDiscount += app.discountPiasters;
      distinctSales.add(app.saleId);

      final current = promoStats[app.promotionId];
      final name = promo?.name ?? current?.name ?? 'عرض محذوف';
      final prevCount = current?.count ?? 0;
      final prevDiscount = current?.discount ?? 0;

      promoStats[app.promotionId] = (
        name: name,
        count: prevCount + 1,
        discount: prevDiscount + app.discountPiasters,
      );
    }

    final topPromos = promoStats.entries.map((e) {
      return PromotionUsageItem(
        promotionId: e.key,
        promotionName: e.value.name,
        count: e.value.count,
        totalDiscountPiasters: e.value.discount,
      );
    }).toList()
      ..sort((a, b) => b.totalDiscountPiasters.compareTo(a.totalDiscountPiasters));

    return PromotionReportEntity(
      totalDiscountPiasters: totalDiscount,
      totalApplications: rows.length,
      totalSalesWithPromotions: distinctSales.length,
      topPromotions: topPromos,
    );
  }
}
