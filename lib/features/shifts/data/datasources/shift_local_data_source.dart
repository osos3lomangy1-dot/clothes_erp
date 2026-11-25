import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/database/tx_writer.dart';
import '../../../../core/features/feature_gate.dart';
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
  final FeatureGate _featureGate;
  final _uuid = const Uuid();

  ShiftLocalDataSourceImpl(this._db, this._branchProvider, this._tx, this._featureGate);

  Future<String> _branchId() => _branchProvider.getBranchId();

  @override
  Future<bool> isShiftsEnabled() async {
    return _featureGate.isEnabled(FeatureKeys.shifts);
  }

  @override
  Future<void> setShiftsEnabled(bool enabled) async {
    await _featureGate.setFeatureEnabled(FeatureKeys.shifts, enabled, userId: 'system');
  }

  @override
  Future<ShiftEntity?> getActiveShift() async {
    final row = await (_db.select(_db.shifts)
          ..where((s) => s.closedAt.isNull() & s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.desc(s.openedAt)])
          ..limit(1))
        .getSingleOrNull();

    if (row == null) return null;
    final cashierName = await _resolveCashierName(row.cashierId);
    return _toEntity(row, cashierName: cashierName);
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

    final cashierName = await _resolveCashierName(shiftRow.cashierId);
    final shiftEntity = _toEntity(shiftRow, cashierName: cashierName);
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

    // 2. Returns query: all cash returns during this shift timeframe
    final returnsQuery = _db.select(_db.returns)
      ..where((r) =>
          (r.cashierId.equals(shiftRow.cashierId) | r.branchId.equals(shiftRow.branchId)) &
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

    // 3. Cash Expenses query: all expenses during this shift timeframe
    final expensesQuery = _db.select(_db.expenses)
      ..where((e) =>
          (e.userId.equals(shiftRow.cashierId) | e.branchId.equals(shiftRow.branchId)) &
          e.expenseDate.isBiggerOrEqualValue(openedAt) &
          e.expenseDate.isSmallerOrEqualValue(closedAt) &
          e.deletedAt.isNull());

    final expenses = await expensesQuery.get();
    int cashExpenses = 0;
    for (final exp in expenses) {
      cashExpenses += exp.amount;
    }

    // 4. Cash Movements direction-based calculation (Phase 2 §2.5)
    final openedAtSec = openedAt.millisecondsSinceEpoch ~/ 1000;
    final closedAtSec = closedAt.millisecondsSinceEpoch ~/ 1000;

    final movementsQuery = _db.select(_db.cashMovements)
      ..where((m) =>
          (m.shiftId.equals(shiftId) |
              (m.shiftId.isNull() &
                  m.createdAt.isBiggerOrEqualValue(openedAtSec) &
                  m.createdAt.isSmallerOrEqualValue(closedAtSec))) &
          m.deletedAt.isNull());
    final movements = await movementsQuery.get();

    final walletTxRows = await (_db.select(_db.walletTransactions)
          ..where((w) =>
              (w.shiftId.equals(shiftId) |
                  (w.shiftId.isNull() &
                      w.createdAt.isBiggerOrEqualValue(shiftRow.openedAt) &
                      w.createdAt.isSmallerOrEqualValue(closedAt))) &
              w.deletedAt.isNull()))
        .get();

    int walletNetCash = 0;
    int walletCommissions = 0;
    for (final wt in walletTxRows) {
      if (wt.type == 'deposit_out_transfer' || wt.type == 'bill_payment') {
        walletNetCash += wt.amount + wt.commission;
        walletCommissions += wt.commission;
      } else if (wt.type == 'withdraw_in_cash') {
        walletNetCash -= (wt.amount - wt.commission);
        walletCommissions += wt.commission;
      } else if (wt.type == 'topup_from_drawer') {
        walletNetCash -= wt.amount;
      }
    }

    final int expectedCash;
    int effectiveCashSales = cashSales;
    int effectiveCardSales = cardSales;
    int effectiveCashExpenses = cashExpenses;

    if (movements.isNotEmpty) {
      final cashIn = movements
          .where((m) => m.method == 'cash' && m.direction == 'in')
          .fold<int>(0, (s, m) => s + m.amountPiasters);
      final cashOut = movements
          .where((m) => m.method == 'cash' && m.direction == 'out')
          .fold<int>(0, (s, m) => s + m.amountPiasters);
      expectedCash = shiftRow.openingBalance + cashIn - cashOut;

      final movementCashSales = movements
          .where((m) => m.method == 'cash' && m.type == 'sale' && m.direction == 'in')
          .fold<int>(0, (s, m) => s + m.amountPiasters);
      final movementCardSales = movements
          .where((m) => m.method == 'card' && m.type == 'sale' && m.direction == 'in')
          .fold<int>(0, (s, m) => s + m.amountPiasters);

      if (movementCashSales > 0 || movementCardSales > 0) {
        effectiveCashSales = movementCashSales;
        effectiveCardSales = movementCardSales;
      }

      final movementExpenses = movements
          .where((m) =>
              m.method == 'cash' &&
              (m.type == 'withdrawal' || m.type == 'expense') &&
              m.direction == 'out')
          .fold<int>(0, (s, m) => s + m.amountPiasters);
      if (movementExpenses > 0) {
        effectiveCashExpenses += movementExpenses;
      }
    } else {
      expectedCash =
          shiftRow.openingBalance + cashSales + walletNetCash - cashReturns - cashExpenses;
    }

    final tipsPool = movements
        .where((m) =>
            m.direction == 'in' &&
            (m.notes?.contains('إكرامية عاملين (Tips)') ?? false))
        .fold<int>(0, (s, m) => s + m.amountPiasters);

    final cashInstallments = movements
        .where((m) =>
            m.method == 'cash' &&
            (m.type == 'installment_payment' || m.type == 'installment_down') &&
            m.direction == 'in')
        .fold<int>(0, (s, m) => s + m.amountPiasters);

    final cardInstallments = movements
        .where((m) =>
            m.method == 'card' &&
            (m.type == 'installment_payment' || m.type == 'installment_down') &&
            m.direction == 'in')
        .fold<int>(0, (s, m) => s + m.amountPiasters);

    final repairCollectedCash = movements
        .where((m) =>
            m.method == 'cash' &&
            ((m.notes?.contains('عربون صيانة') ?? false) ||
                (m.notes?.contains('تحصيل صيانة') ?? false)))
        .fold<int>(0, (s, m) => s + (m.direction == 'in' ? m.amountPiasters : -m.amountPiasters));

    return ShiftSummaryEntity(
      shift: shiftEntity,
      cashSales: effectiveCashSales,
      cardSales: effectiveCardSales,
      otherSales: otherSales,
      cashReturns: cashReturns,
      cashExpenses: effectiveCashExpenses,
      cashInstallments: cashInstallments,
      cardInstallments: cardInstallments,
      tipsPool: tipsPool,
      walletNetCash: walletNetCash,
      walletCommissions: walletCommissions,
      repairCollectedCash: repairCollectedCash,
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
    final cashierName = await _resolveCashierName(updated.cashierId);
    return _toEntity(updated, cashierName: cashierName);
  }

  @override
  Future<List<ShiftEntity>> getShiftHistory({int limit = 20}) async {
    final rows = await (_db.select(_db.shifts)
          ..where((s) => s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.desc(s.openedAt)])
          ..limit(limit))
        .get();

    final userIds = rows.map((r) => r.cashierId).toSet();
    final users = await (_db.select(_db.users)..where((u) => u.id.isIn(userIds))).get();
    final userMap = {for (final u in users) u.id: u.displayName};

    return rows.map((row) {
      String name = userMap[row.cashierId] ?? row.cashierId;
      if (row.cashierId == 'admin_default' || row.cashierId == 'admin') name = 'المدير العام';
      if (row.cashierId == 'cashier_default' || row.cashierId == 'cashier') name = 'كاشير 1';
      return _toEntity(row, cashierName: name);
    }).toList();
  }

  Future<String> _resolveCashierName(String cashierId) async {
    if (cashierId == 'admin_default' || cashierId == 'admin') return 'المدير العام';
    if (cashierId == 'cashier_default' || cashierId == 'cashier') return 'كاشير 1';
    final user = await (_db.select(_db.users)..where((u) => u.id.equals(cashierId))).getSingleOrNull();
    if (user != null && user.displayName.isNotEmpty) {
      return user.displayName;
    }
    return cashierId;
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

