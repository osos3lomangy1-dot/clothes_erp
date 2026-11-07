import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/entities/partner_entity.dart';

class ProfitSummary {
  final int totalRevenue;
  final int totalCost;
  final int grossProfit;
  final int totalExpenses;
  final int netProfit;

  const ProfitSummary({
    required this.totalRevenue,
    required this.totalCost,
    required this.grossProfit,
    required this.totalExpenses,
    required this.netProfit,
  });
}

abstract class PartnersLocalDataSource {
  Future<List<PartnerEntity>> getPartners();
  Future<void> savePartner(PartnerEntity partner);
  Future<void> deletePartner(String id);
  Future<ProfitSummary> getProfitSummary({DateTime? from, DateTime? to});
}

@LazySingleton(as: PartnersLocalDataSource)
class PartnersLocalDataSourceImpl implements PartnersLocalDataSource {
  final AppDatabase _db;
  final _uuid = const Uuid();
  static const String _storageKey = 'partners_registry';

  PartnersLocalDataSourceImpl(this._db);

  @override
  Future<List<PartnerEntity>> getPartners() async {
    final row = await (_db.select(_db.appMeta)
          ..where((t) => t.key.equals(_storageKey)))
        .getSingleOrNull();

    if (row == null || row.value.trim().isEmpty) {
      return [];
    }

    try {
      final List<dynamic> decoded = jsonDecode(row.value);
      return decoded.map((e) => PartnerEntity.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _persist(List<PartnerEntity> list) async {
    final encoded = jsonEncode(list.map((e) => e.toJson()).toList());
    final now = DateTime.now();

    await _db.into(_db.appMeta).insertOnConflictUpdate(
          AppMetaCompanion.insert(
            key: _storageKey,
            value: encoded,
            updatedAt: now,
          ),
        );
  }

  @override
  Future<void> savePartner(PartnerEntity partner) async {
    final current = await getPartners();
    final id = partner.id.isNotEmpty ? partner.id : _uuid.v4();
    final toSave = partner.copyWith(id: id);

    final idx = current.indexWhere((p) => p.id == id);
    if (idx >= 0) {
      current[idx] = toSave;
    } else {
      current.add(toSave);
    }

    await _persist(current);
  }

  @override
  Future<void> deletePartner(String id) async {
    final current = await getPartners();
    current.removeWhere((p) => p.id == id);
    await _persist(current);
  }

  @override
  Future<ProfitSummary> getProfitSummary({DateTime? from, DateTime? to}) async {
    // 1. Sales Revenue
    var salesQ = _db.select(_db.sales)..where((s) => s.deletedAt.isNull());
    if (from != null) salesQ = salesQ..where((s) => s.date.isBiggerOrEqualValue(from));
    if (to != null) salesQ = salesQ..where((s) => s.date.isSmallerOrEqualValue(to));
    final sales = await salesQ.get();
    final totalRevenue = sales.fold<int>(0, (sum, s) => sum + s.total);

    // 2. Cost of Goods Sold from SaleItems
    final saleIds = sales.map((s) => s.id).toSet();
    final items = saleIds.isEmpty
        ? <SaleItem>[]
        : await (_db.select(_db.saleItems)..where((i) => i.saleId.isIn(saleIds))).get();
    final totalCost = items.fold<int>(0, (sum, i) => sum + (i.costSnapshot * i.qty));

    final grossProfit = totalRevenue - totalCost;

    // 3. Expenses
    var expQ = _db.select(_db.expenses)..where((e) => e.deletedAt.isNull());
    if (from != null) expQ = expQ..where((e) => e.expenseDate.isBiggerOrEqualValue(from));
    if (to != null) expQ = expQ..where((e) => e.expenseDate.isSmallerOrEqualValue(to));
    final expenses = await expQ.get();
    final totalExpenses = expenses.fold<int>(0, (sum, e) => sum + e.amount);

    final netProfit = grossProfit - totalExpenses;

    return ProfitSummary(
      totalRevenue: totalRevenue,
      totalCost: totalCost,
      grossProfit: grossProfit,
      totalExpenses: totalExpenses,
      netProfit: netProfit,
    );
  }
}
