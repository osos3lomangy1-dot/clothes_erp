import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/database/tx_writer.dart';

class WalletTransactionResult {
  final String transactionId;
  final int newWalletBalancePiasters;
  final int drawerDeltaPiasters;
  final int profitPiasters;

  const WalletTransactionResult({
    required this.transactionId,
    required this.newWalletBalancePiasters,
    required this.drawerDeltaPiasters,
    required this.profitPiasters,
  });
}

@lazySingleton
class MobileWalletsService {
  final AppDatabase _db;
  final BranchProvider _branchProvider;
  final TxWriter _txWriter;
  final _uuid = const Uuid();

  MobileWalletsService(this._db, this._branchProvider, this._txWriter);

  static const List<String> providerTypes = [
    'vodafone_cash',
    'instapay',
    'etisalat_cash',
    'orange_cash',
    'fawry',
    'other',
  ];

  static const List<String> transactionTypes = [
    'deposit_out_transfer',
    'withdraw_in_cash',
    'topup_from_drawer',
    'bill_payment',
  ];

  static String providerLabel(String type) {
    switch (type) {
      case 'vodafone_cash':
        return 'فودافون كاش';
      case 'instapay':
        return 'إنستا باي (InstaPay)';
      case 'etisalat_cash':
        return 'اتصالات كاش';
      case 'orange_cash':
        return 'أورنج كاش';
      case 'fawry':
        return 'فوري / ماكينة شحن';
      default:
        return 'محفظة أخرى';
    }
  }

  static String transactionTypeLabel(String type) {
    switch (type) {
      case 'deposit_out_transfer':
        return 'تحويل صادر للعميل';
      case 'withdraw_in_cash':
        return 'سحب نقدي للعميل';
      case 'topup_from_drawer':
        return 'تغذية المحفظة من الدرج';
      case 'bill_payment':
        return 'سداد فواتير / شحن';
      default:
        return type;
    }
  }

  /// Computes wallet delta, drawer cash delta, and profit (commission only).
  static ({int walletDelta, int drawerDelta, int profit}) calculateDeltas({
    required String type,
    required int amountPiasters,
    required int commissionPiasters,
  }) {
    if (amountPiasters <= 0) {
      throw Exception('المبلغ يجب أن يكون أكبر من صفر');
    }
    if (commissionPiasters < 0) {
      throw Exception('العمولة لا يمكن أن تكون سالبة');
    }

    switch (type) {
      case 'deposit_out_transfer':
      case 'bill_payment':
        return (
          walletDelta: -amountPiasters,
          drawerDelta: amountPiasters + commissionPiasters,
          profit: commissionPiasters,
        );
      case 'withdraw_in_cash':
        if (commissionPiasters > amountPiasters) {
          throw Exception('العمولة لا يمكن أن تتجاوز مبلغ السحب');
        }
        return (
          walletDelta: amountPiasters,
          drawerDelta: -(amountPiasters - commissionPiasters),
          profit: commissionPiasters,
        );
      case 'topup_from_drawer':
        return (
          walletDelta: amountPiasters,
          drawerDelta: -amountPiasters,
          profit: 0,
        );
      default:
        throw Exception('نوع العملية غير مدعوم: $type');
    }
  }

  Future<List<CashWallet>> getWallets({bool activeOnly = false}) async {
    final branchId = await _branchProvider.getBranchId();
    final q = _db.select(_db.cashWallets)
      ..where(
        (t) =>
            t.branchId.equals(branchId) &
            t.deletedAt.isNull() &
            (activeOnly ? t.isActive.equals(true) : const Constant(true)),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    return q.get();
  }

  Stream<List<CashWallet>> watchWallets({bool activeOnly = false}) async* {
    final branchId = await _branchProvider.getBranchId();
    final q = _db.select(_db.cashWallets)
      ..where(
        (t) =>
            t.branchId.equals(branchId) &
            t.deletedAt.isNull() &
            (activeOnly ? t.isActive.equals(true) : const Constant(true)),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    yield* q.watch();
  }

  Future<List<WalletTransaction>> getRecentTransactions({
    String? walletId,
    int limit = 100,
  }) async {
    final branchId = await _branchProvider.getBranchId();
    final q = _db.select(_db.walletTransactions)
      ..where(
        (t) =>
            t.branchId.equals(branchId) &
            t.deletedAt.isNull() &
            (walletId != null
                ? t.walletId.equals(walletId)
                : const Constant(true)),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit);
    return q.get();
  }

  Future<CashWallet> createWallet({
    required String name,
    required String providerType,
    String phoneOrTerminal = '',
    int initialBalancePiasters = 0,
    int monthlyLimitPiasters = 0,
    String userId = 'admin',
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw Exception('يرجى إدخال اسم المحفظة أو الخط');
    }
    if (!providerTypes.contains(providerType)) {
      throw Exception('نوع مزود الخدمة غير صحيح');
    }
    if (monthlyLimitPiasters < 0) {
      throw Exception('الحد الشهري لا يمكن أن يكون سالباً');
    }

    final branchId = await _branchProvider.getBranchId();
    final now = DateTime.now();
    final id = _uuid.v4();

    await _txWriter.write(
      branchId: branchId,
      entity: 'cash_wallets',
      entityId: id,
      operation: 'create_wallet',
      userId: userId,
      writeFn: () async {
        await _db.into(_db.cashWallets).insert(
              CashWalletsCompanion.insert(
                id: id,
                branchId: branchId,
                name: cleanName,
                providerType: Value(providerType),
                phoneOrTerminal: Value(phoneOrTerminal.trim()),
                currentBalance: Value(initialBalancePiasters),
                monthlyLimit: Value(monthlyLimitPiasters),
                monthlyUsed: const Value(0),
                isActive: const Value(true),
                createdAt: now,
                updatedAt: now,
              ),
            );
      },
    );

    return (_db.select(_db.cashWallets)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  Future<void> updateWallet({
    required String walletId,
    required String name,
    required String providerType,
    String phoneOrTerminal = '',
    int monthlyLimitPiasters = 0,
    bool isActive = true,
    String userId = 'admin',
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw Exception('يرجى إدخال اسم المحفظة أو الخط');
    }
    final branchId = await _branchProvider.getBranchId();
    final now = DateTime.now();

    await _txWriter.write(
      branchId: branchId,
      entity: 'cash_wallets',
      entityId: walletId,
      operation: 'update_wallet',
      userId: userId,
      writeFn: () async {
        await (_db.update(_db.cashWallets)..where((t) => t.id.equals(walletId)))
            .write(
          CashWalletsCompanion(
            name: Value(cleanName),
            providerType: Value(providerType),
            phoneOrTerminal: Value(phoneOrTerminal.trim()),
            monthlyLimit: Value(monthlyLimitPiasters),
            isActive: Value(isActive),
            updatedAt: Value(now),
          ),
        );
      },
    );
  }

  Future<void> resetMonthlyUsed(
    String walletId, {
    String userId = 'admin',
  }) async {
    final branchId = await _branchProvider.getBranchId();
    await _txWriter.write(
      branchId: branchId,
      entity: 'cash_wallets',
      entityId: walletId,
      operation: 'reset_wallet_monthly_used',
      userId: userId,
      writeFn: () async {
        await (_db.update(_db.cashWallets)..where((t) => t.id.equals(walletId)))
            .write(
          CashWalletsCompanion(
            monthlyUsed: const Value(0),
            updatedAt: Value(DateTime.now()),
          ),
        );
      },
    );
  }

  Future<WalletTransactionResult> executeTransaction({
    required String walletId,
    required String type,
    required int amountPiasters,
    int commissionPiasters = 0,
    String? customerPhone,
    String? referenceNumber,
    String? notes,
    String? shiftId,
    String userId = 'admin',
  }) async {
    final effectiveCommission =
        type == 'topup_from_drawer' ? 0 : commissionPiasters;
    final deltas = calculateDeltas(
      type: type,
      amountPiasters: amountPiasters,
      commissionPiasters: effectiveCommission,
    );

    final branchId = await _branchProvider.getBranchId();
    final now = DateTime.now();
    final txId = _uuid.v4();

    String? effectiveShiftId = shiftId;
    if (effectiveShiftId == null) {
      final activeShift = await (_db.select(_db.shifts)
            ..where((s) => s.closedAt.isNull() & s.deletedAt.isNull())
            ..orderBy([(s) => OrderingTerm.desc(s.openedAt)])
            ..limit(1))
          .getSingleOrNull();
      effectiveShiftId = activeShift?.id;
    }

    late int newBalance;

    await _txWriter.write(
      branchId: branchId,
      entity: 'wallet_transactions',
      entityId: txId,
      operation: 'wallet_$type',
      userId: userId,
      writeFn: () async {
        final wallet = await (_db.select(_db.cashWallets)
              ..where((t) => t.id.equals(walletId) & t.deletedAt.isNull()))
            .getSingleOrNull();
        if (wallet == null) {
          throw Exception('المحفظة غير موجودة');
        }
        if (!wallet.isActive) {
          throw Exception('هذا الخط موقوف حالياً');
        }

        newBalance = wallet.currentBalance + deltas.walletDelta;
        if (newBalance < 0) {
          throw Exception('رصيد المحفظة غير كافٍ لإتمام العملية');
        }

        final bool countsAgainstMonthlyLimit = type != 'topup_from_drawer';
        final newMonthlyUsed = countsAgainstMonthlyLimit
            ? wallet.monthlyUsed + amountPiasters
            : wallet.monthlyUsed;
        if (countsAgainstMonthlyLimit &&
            wallet.monthlyLimit > 0 &&
            newMonthlyUsed > wallet.monthlyLimit) {
          throw Exception(
            'العملية تتجاوز الحد الشهري المتبقي للخط (${wallet.name})',
          );
        }

        await (_db.update(_db.cashWallets)..where((t) => t.id.equals(walletId)))
            .write(
          CashWalletsCompanion(
            currentBalance: Value(newBalance),
            monthlyUsed: Value(newMonthlyUsed),
            updatedAt: Value(now),
          ),
        );

        await _db.into(_db.walletTransactions).insert(
              WalletTransactionsCompanion.insert(
                id: txId,
                branchId: branchId,
                walletId: walletId,
                shiftId: Value(effectiveShiftId),
                type: type,
                amount: amountPiasters,
                commission: Value(effectiveCommission),
                customerPhone: Value(
                  customerPhone != null && customerPhone.trim().isNotEmpty
                      ? customerPhone.trim()
                      : null,
                ),
                referenceNumber: Value(
                  referenceNumber != null && referenceNumber.trim().isNotEmpty
                      ? referenceNumber.trim()
                      : null,
                ),
                notes: Value(
                  notes != null && notes.trim().isNotEmpty ? notes.trim() : null,
                ),
                userId: Value(userId),
                createdAt: now,
              ),
            );

        if (deltas.drawerDelta != 0) {
          final isCashIn = deltas.drawerDelta > 0;
          final nowSec = now.millisecondsSinceEpoch ~/ 1000;
          await _db.into(_db.cashMovements).insert(
                CashMovementsCompanion.insert(
                  id: _uuid.v4(),
                  branchId: branchId,
                  shiftId: Value(effectiveShiftId),
                  type: isCashIn ? 'deposit' : 'withdrawal',
                  direction: isCashIn ? 'in' : 'out',
                  method: 'cash',
                  amountPiasters: deltas.drawerDelta.abs(),
                  referenceId: Value(txId),
                  notes: Value(
                    '${transactionTypeLabel(type)} - ${wallet.name}',
                  ),
                  createdAt: nowSec,
                  updatedAt: nowSec,
                ),
              );
        }
      },
    );

    return WalletTransactionResult(
      transactionId: txId,
      newWalletBalancePiasters: newBalance,
      drawerDeltaPiasters: deltas.drawerDelta,
      profitPiasters: deltas.profit,
    );
  }
}

