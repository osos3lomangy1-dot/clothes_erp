import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/database/app_database.dart';

class KitchenWasteReasonBreakdown {
  final String reason;
  final int count;
  final int totalQuantity;
  final int totalLossPiasters;
  final double percentage;

  const KitchenWasteReasonBreakdown({
    required this.reason,
    required this.count,
    required this.totalQuantity,
    required this.totalLossPiasters,
    required this.percentage,
  });
}

class KitchenWasteAuditReport {
  final int totalLossPiasters;
  final int totalMovementsCount;
  final int totalQuantityWasted;
  final List<KitchenWasteReasonBreakdown> breakdown;

  const KitchenWasteAuditReport({
    required this.totalLossPiasters,
    required this.totalMovementsCount,
    required this.totalQuantityWasted,
    required this.breakdown,
  });

  static const empty = KitchenWasteAuditReport(
    totalLossPiasters: 0,
    totalMovementsCount: 0,
    totalQuantityWasted: 0,
    breakdown: [],
  );
}

@lazySingleton
class KitchenWasteAuditService {
  final AppDatabase _db;

  KitchenWasteAuditService(this._db);

  static const List<String> standardReasons = [
    'احتراق طهي',
    'سوء تخزين وتبريد',
    'انتهاء صلاحية',
    'خطأ زبون',
    'أخرى',
  ];

  String _normalizeReason(String? rawReason) {
    if (rawReason == null || rawReason.trim().isEmpty) return 'أخرى';
    final lower = rawReason.trim();
    if (lower.contains('احتراق') || lower.contains('طهي')) return 'احتراق طهي';
    if (lower.contains('تخزين') || lower.contains('تبريد') || lower.contains('تلف')) return 'سوء تخزين وتبريد';
    if (lower.contains('صلاحية') || lower.contains('انتهاء')) return 'انتهاء صلاحية';
    if (lower.contains('زبون') || lower.contains('استرجاع') || lower.contains('طلب خاطئ')) return 'خطأ زبون';
    return 'أخرى';
  }

  Future<KitchenWasteAuditReport> auditKitchenWaste({
    DateTime? from,
    DateTime? to,
    String? branchId,
  }) async {
    final query = _db.select(_db.inventoryLogs).join([
      leftOuterJoin(
        _db.productVariants,
        _db.productVariants.id.equalsExp(_db.inventoryLogs.variantId),
      ),
    ]);

    query.where(
      _db.inventoryLogs.refType.equals('kitchen_waste') |
          _db.inventoryLogs.reason.like('%هالك مطبخ%'),
    );

    if (branchId != null) {
      query.where(_db.inventoryLogs.branchId.equals(branchId));
    }
    if (from != null) {
      query.where(_db.inventoryLogs.createdAt.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      query.where(_db.inventoryLogs.createdAt.isSmallerOrEqualValue(to));
    }

    query.orderBy([OrderingTerm.desc(_db.inventoryLogs.createdAt)]);

    final rows = await query.get();
    if (rows.isEmpty) {
      return KitchenWasteAuditReport.empty;
    }

    int totalLossPiasters = 0;
    int totalQuantityWasted = 0;

    final Map<String, int> reasonLossMap = {};
    final Map<String, int> reasonQtyMap = {};
    final Map<String, int> reasonCountMap = {};

    for (final r in standardReasons) {
      reasonLossMap[r] = 0;
      reasonQtyMap[r] = 0;
      reasonCountMap[r] = 0;
    }

    for (final row in rows) {
      final log = row.readTable(_db.inventoryLogs);
      final variant = row.readTableOrNull(_db.productVariants);

      final qty = log.qtyDelta.abs();
      totalQuantityWasted += qty.round();

      final costPerUnit = (variant != null && variant.costPrice > 0)
          ? variant.costPrice
          : (variant?.sellPrice ?? 0);

      final lossPiasters = (qty * costPerUnit).round();
      totalLossPiasters += lossPiasters;

      final normalizedReason = _normalizeReason(log.reason);
      reasonLossMap[normalizedReason] =
          (reasonLossMap[normalizedReason] ?? 0) + lossPiasters;
      reasonQtyMap[normalizedReason] =
          (reasonQtyMap[normalizedReason] ?? 0) + qty.round();
      reasonCountMap[normalizedReason] =
          (reasonCountMap[normalizedReason] ?? 0) + 1;
    }

    final List<KitchenWasteReasonBreakdown> breakdown = [];
    for (final reason in standardReasons) {
      final loss = reasonLossMap[reason] ?? 0;
      final qty = reasonQtyMap[reason] ?? 0;
      final count = reasonCountMap[reason] ?? 0;

      if (count > 0 || loss > 0) {
        final pct = totalLossPiasters > 0
            ? (loss / totalLossPiasters) * 100.0
            : 0.0;

        breakdown.add(KitchenWasteReasonBreakdown(
          reason: reason,
          count: count,
          totalQuantity: qty,
          totalLossPiasters: loss,
          percentage: pct,
        ));
      }
    }

    // Sort descending by loss
    breakdown.sort((a, b) => b.totalLossPiasters.compareTo(a.totalLossPiasters));

    return KitchenWasteAuditReport(
      totalLossPiasters: totalLossPiasters,
      totalMovementsCount: rows.length,
      totalQuantityWasted: totalQuantityWasted,
      breakdown: breakdown,
    );
  }
}
