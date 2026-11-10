import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/database/tx_writer.dart';
import '../../domain/entities/shift_entity.dart';
import '../../domain/entities/shift_summary_entity.dart';

abstract class ShiftLocalDataSource {
  Future<bool> isShiftsEnabled();
  Future<void> setShiftsEnabled(bool enabled);
  Future<ShiftEntity?> getActiveShift();
  Future<ShiftSummaryEntity> getShiftSummary(String shiftId);
  Future<ShiftEntity> openShift({
    required int openingBalance,
    required String cashierId,
    String? cashierName,
  });
  Future<ShiftEntity> closeShift({
    required int countedBalance,
    String? shiftId,
    required String userId,
  });
  Future<List<ShiftEntity>> getShiftHistory({int limit = 20});
}

@LazySingleton(as: ShiftLocalDataSource)
class ShiftLocalDataSourceImpl implements ShiftLocalDataSource {
  final AppDatabase _db;
  final BranchProvider _branchProvider;
  final TxWriter _tx;
  final _uuid = const Uuid();

  ShiftLocalDataSourceImpl(this._db, this._branchProvider, this._tx);

  Future<String> _branchId() => _branchProvider.getBranchId();

  @override
  Future<bool> isShiftsEnabled() async {
    final row = await (_db.select(_db.appMeta)
          ..where((t) => t.key.equals('shifts_enabled')))
        .getSingleOrNull();
    if (row == null) return true; // Default is true
    return row.value.toLowerCase() == 'true';
  }

  @override
  Future<void> setShiftsEnabled(bool enabled) async {
    await _db.into(_db.appMeta).insertOnConflictUpdate(
      AppMetaCompanion(
        key: const Value('shifts_enabled'),
        value: Value(enabled.toString()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<ShiftEntity?> getActiveShift() async {
    final row = await (_db.select(_db.shifts)
          ..where((s) => s.closedAt.isNull() & s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.desc(s.openedAt)])
          ..limit(1))
        .getSingleOrNull();

    if (row == null) return null;
    return _toEntity(row);
  }

  @override
  Future<ShiftEntity> openShift({
    required int openingBalance,
    required String cashierId,
    String? cashierName,
  }) async {
    if (openingBalance < 0) {
      throw Exception('الرصيد الافتتاحي لا يمكن أن يكون سالباً');
    }

    final active = await getActiveShift();
    if (active != null) {
      throw Exception('توجد وردية مفتوحة بالفعل. يرجى إغلاقها أولاً قبل فتح وردية جديدة.');
    }

    final branchId = await _branchId();
    final shiftId = _uuid.v4();
    final now = DateTime.now();

    await _tx.write(
      writeFn: () async {
        await _db.into(_db.shifts).insert(
          ShiftsCompanion.insert(
            id: shiftId,
            branchId: branchId,
            cashierId: cashierId,
            openingBalance: openingBalance,
            openedAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
      },
      branchId: branchId,
      entity: 'shift',
      entityId: shiftId,
      operation: 'insert',
      userId: cashierId,
    );

    final inserted = await (_db.select(_db.shifts)..where((s) => s.id.equals(shiftId))).getSingle();
    return _toEntity(inserted, cashierName: cashierName);
  }

  @override
  Future<ShiftSummaryEntity> getShiftSummary(String shiftId) async {
    final shiftRow = await (_db.select(_db.shifts)..where((s) => s.id.equals(shiftId))).getSingleOrNull();
    if (shiftRow == null) {
      throw Exception('الوردية غير موجودة');
    }

    final shiftEntity = _toEntity(shiftRow);
    final openedAt = shiftRow.openedAt;
    final closedAt = shiftRow.closedAt ?? DateTime.now();

    // 1. Sales query: linked to shiftId OR in time range with same cashier
    final salesQuery = _db.select(_db.sales)
      ..where((s) =>
          (s.shiftId.equals(shiftId) |
              (s.shiftId.isNull() &
                  s.cashierId.equals(shiftRow.cashierId) &
                  s.date.isBiggerOrEqualValue(openedAt) &
                  s.date.isSmallerOrEqualValue(closedAt))) &
          s.deletedAt.isNull());

    final sales = await salesQuery.get();

    int cashSales = 0;
    int cardSales = 0;
    int otherSales = 0;

    for (final sale in sales) {
      final method = sale.paymentMethod.toLowerCase();
      if (method == 'cash' || method.contains('كاش') || method.contains('نقدي')) {
        cashSales += sale.total;
      } else if (method == 'card' || method == 'visa' || method.contains('فيزا') || method.contains('بطاقة')) {
        cardSales += sale.total;
      } else {
        otherSales += sale.total;
      }
    }

    // 2. Returns query
    final returnsQuery = _db.select(_db.returns)
      ..where((r) =>
          r.cashierId.equals(shiftRow.cashierId) &
          r.date.isBiggerOrEqualValue(openedAt) &
          r.date.isSmallerOrEqualValue(closedAt) &
          r.deletedAt.isNull());

    final returns = await returnsQuery.get();
    int cashReturns = 0;
    for (final ret in returns) {
      final method = ret.paymentMethod.toLowerCase();
      if (method == 'cash' || method.contains('كاش') || method.contains('نقدي')) {
        cashReturns += ret.refundAmount;
      }
    }

    // 3. Cash Expenses query
    final expensesQuery = _db.select(_db.expenses)
      ..where((e) =>
          e.userId.equals(shiftRow.cashierId) &
          e.expenseDate.isBiggerOrEqualValue(openedAt) &
          e.expenseDate.isSmallerOrEqualValue(closedAt) &
          e.deletedAt.isNull());

    final expenses = await expensesQuery.get();
    int cashExpenses = 0;
    for (final exp in expenses) {
      cashExpenses += exp.amount;
    }

    final expectedCash = shiftRow.openingBalance + cashSales - cashReturns - cashExpenses;

    return ShiftSummaryEntity(
      shift: shiftEntity,
      cashSales: cashSales,
      cardSales: cardSales,
      otherSales: otherSales,
      cashReturns: cashReturns,
      cashExpenses: cashExpenses,
      totalSalesCount: sales.length,
      expectedCashInDrawer: expectedCash,
    );
  }

  @override
  Future<ShiftEntity> closeShift({
    required int countedBalance,
    String? shiftId,
    required String userId,
  }) async {
    if (countedBalance < 0) {
      throw Exception('المبلغ الفعلي في الدرج لا يمكن أن يكون سالباً');
    }

    Shift? targetShift;
    if (shiftId != null) {
      targetShift = await (_db.select(_db.shifts)..where((s) => s.id.equals(shiftId))).getSingleOrNull();
    } else {
      targetShift = await (_db.select(_db.shifts)
            ..where((s) => s.closedAt.isNull() & s.deletedAt.isNull())
            ..orderBy([(s) => OrderingTerm.desc(s.openedAt)])
            ..limit(1))
          .getSingleOrNull();
    }

    if (targetShift == null || targetShift.closedAt != null) {
      throw Exception('لا توجد وردية مفتوحة لإغلاقها.');
    }

    final branchId = await _branchId();
    final now = DateTime.now();

    final summary = await getShiftSummary(targetShift.id);
    final expected = summary.expectedCashInDrawer;
    final diff = countedBalance - expected;

    await _tx.write(
      writeFn: () async {
        await (_db.update(_db.shifts)..where((s) => s.id.equals(targetShift!.id))).write(
          ShiftsCompanion(
            closedAt: Value(now),
            expectedBalance: Value(expected),
            countedBalance: Value(countedBalance),
            difference: Value(diff),
            updatedAt: Value(now),
          ),
        );
      },
      branchId: branchId,
      entity: 'shift',
      entityId: targetShift.id,
      operation: 'update',
      userId: userId,
    );

    final updated = await (_db.select(_db.shifts)..where((s) => s.id.equals(targetShift!.id))).getSingle();
    return _toEntity(updated);
  }

  @override
  Future<List<ShiftEntity>> getShiftHistory({int limit = 20}) async {
    final rows = await (_db.select(_db.shifts)
          ..where((s) => s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.desc(s.openedAt)])
          ..limit(limit))
        .get();

    return rows.map(_toEntity).toList();
  }

  ShiftEntity _toEntity(Shift row, {String? cashierName}) {
    return ShiftEntity(
      id: row.id,
      branchId: row.branchId,
      cashierId: row.cashierId,
      cashierName: cashierName ?? row.cashierId,
      openingBalance: row.openingBalance,
      openedAt: row.openedAt,
      closedAt: row.closedAt,
      expectedBalance: row.expectedBalance,
      countedBalance: row.countedBalance,
      difference: row.difference,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }
}

