import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/database/tx_writer.dart';

abstract class CustomersLocalDataSource {
  Future<List<Customer>> getCustomers({String? search});
  Future<Customer?> getCustomerById(String id);
  Future<Customer?> getCustomerByPhone(String phone);
  Future<void> addCustomer({
    required String name,
    required String phone,
    int loyaltyPoints = 0,
    int discountPercent = 0,
    String customerType = 'retail',
    int creditLimit = 0,
    String userId = 'system',
  });
  Future<void> updateCustomer({
    required String id,
    required String name,
    required String phone,
    int? loyaltyPoints,
    int? discountPercent,
    String? customerType,
    int? creditLimit,
    String userId = 'system',
  });
  Future<void> softDeleteCustomer(String id, {String userId = 'system'});
  Future<String> recordCustomerPayment({
    required String customerId,
    required int amount,
    required String paymentMethod,
    String? shiftId,
    String? referenceNumber,
    String? notes,
    String userId = 'admin',
  });
  Future<List<CustomerPayment>> getCustomerPayments(String customerId);
  Future<int> getCustomerCreditDebt(String customerId);
}

@LazySingleton(as: CustomersLocalDataSource)
class CustomersLocalDataSourceImpl implements CustomersLocalDataSource {
  final AppDatabase _db;
  final BranchProvider _branchProvider;
  final TxWriter _tx;
  final _uuid = const Uuid();

  CustomersLocalDataSourceImpl(this._db, this._branchProvider, this._tx);

  Future<String> _branchId() => _branchProvider.getBranchId();

  @override
  Future<List<Customer>> getCustomers({String? search}) async {
    var query = _db.select(_db.customers)..where((c) => c.deletedAt.isNull());
    if (search != null && search.trim().isNotEmpty) {
      final s = search.trim();
      query = query..where((c) => c.name.contains(s) | c.phone.contains(s));
    }
    query = query..orderBy([(c) => OrderingTerm.desc(c.createdAt)]);
    return query.get();
  }

  @override
  Future<Customer?> getCustomerById(String id) async {
    return (_db.select(_db.customers)
          ..where((c) => c.id.equals(id) & c.deletedAt.isNull()))
        .getSingleOrNull();
  }

  @override
  Future<Customer?> getCustomerByPhone(String phone) async {
    return (_db.select(_db.customers)
          ..where((c) => c.phone.equals(phone) & c.deletedAt.isNull()))
        .getSingleOrNull();
  }

  @override
  Future<void> addCustomer({
    required String name,
    required String phone,
    int loyaltyPoints = 0,
    int discountPercent = 0,
    String customerType = 'retail',
    int creditLimit = 0,
    String userId = 'system',
  }) async {
    final cleanName = name.trim();
    final cleanPhone = phone.trim();
    if (cleanName.isEmpty) throw Exception('اسم العميل مطلوب');
    if (cleanPhone.isEmpty) throw Exception('رقم هاتف العميل مطلوب');
    if (discountPercent < 0 || discountPercent > 100) {
      throw Exception('نسبة الخصم يجب أن تكون بين 0% و 100%');
    }
    if (loyaltyPoints < 0) {
      throw Exception('نقاط الولاء لا يمكن أن تكون سالبة');
    }

    final existingAny = await (_db.select(
      _db.customers,
    )..where((c) => c.phone.equals(cleanPhone))).getSingleOrNull();

    final now = DateTime.now();
    final branchId = await _branchId();

    if (existingAny != null) {
      if (existingAny.deletedAt == null) {
        throw Exception(
          'رقم الهاتف ($cleanPhone) مسجّل بالفعل للعميل "${existingAny.name}"',
        );
      }
      // Reactivate previously soft-deleted customer cleanly instead of failing UNIQUE
      await _tx.write(
        writeFn: () async {
          await (_db.update(
            _db.customers,
          )..where((c) => c.id.equals(existingAny.id))).write(
            CustomersCompanion(
              name: Value(cleanName),
              loyaltyPoints: Value(loyaltyPoints),
              discountPercent: Value(discountPercent),
              customerType: Value(customerType),
              creditLimit: Value(creditLimit),
              deletedAt: const Value(null),
              updatedAt: Value(now),
            ),
          );
        },
        branchId: branchId,
        entity: 'customer',
        entityId: existingAny.id,
        operation: 'restore',
        userId: userId,
      );
      return;
    }

    final id = _uuid.v4();
    await _tx.write(
      writeFn: () async {
        await _db.into(_db.customers).insert(
              CustomersCompanion.insert(
                id: id,
                branchId: branchId,
                name: cleanName,
                phone: cleanPhone,
                loyaltyPoints: Value(loyaltyPoints),
                discountPercent: Value(discountPercent),
                customerType: Value(customerType),
                creditLimit: Value(creditLimit),
                createdAt: now,
                updatedAt: now,
              ),
            );
      },
      branchId: branchId,
      entity: 'customer',
      entityId: id,
      operation: 'insert',
      userId: userId,
    );
  }

  @override
  Future<void> updateCustomer({
    required String id,
    required String name,
    required String phone,
    int? loyaltyPoints,
    int? discountPercent,
    String? customerType,
    int? creditLimit,
    String userId = 'system',
  }) async {
    final cleanName = name.trim();
    final cleanPhone = phone.trim();
    if (cleanName.isEmpty) throw Exception('اسم العميل مطلوب');
    if (cleanPhone.isEmpty) throw Exception('رقم هاتف العميل مطلوب');
    if (discountPercent != null && (discountPercent < 0 || discountPercent > 100)) {
      throw Exception('نسبة الخصم يجب أن تكون بين 0% و 100%');
    }
    if (loyaltyPoints != null && loyaltyPoints < 0) {
      throw Exception('نقاط الولاء لا يمكن أن تكون سالبة');
    }

    final duplicate = await (_db.select(_db.customers)
          ..where((c) => c.phone.equals(cleanPhone) & c.id.isNotValue(id)))
        .getSingleOrNull();
    if (duplicate != null) {
      throw Exception(
        'رقم الهاتف ($cleanPhone) مستخدم بالفعل لعميل آخر ("${duplicate.name}")',
      );
    }

    final now = DateTime.now();
    final branchId = await _branchId();

    await _tx.write(
      writeFn: () async {
        await (_db.update(_db.customers)..where((c) => c.id.equals(id))).write(
          CustomersCompanion(
            name: Value(cleanName),
            phone: Value(cleanPhone),
            loyaltyPoints: loyaltyPoints != null
                ? Value(loyaltyPoints)
                : const Value.absent(),
            discountPercent: discountPercent != null
                ? Value(discountPercent)
                : const Value.absent(),
            customerType: customerType != null
                ? Value(customerType)
                : const Value.absent(),
            creditLimit: creditLimit != null
                ? Value(creditLimit)
                : const Value.absent(),
            updatedAt: Value(now),
          ),
        );
      },
      branchId: branchId,
      entity: 'customer',
      entityId: id,
      operation: 'update',
      userId: userId,
    );
  }

  @override
  Future<void> softDeleteCustomer(String id, {String userId = 'system'}) async {
    final activeContracts = await (_db.select(_db.customerInstallments)
          ..where(
            (c) =>
                c.customerId.equals(id) &
                c.deletedAt.isNull() &
                c.status.isIn(const ['active', 'overdue']),
          ))
        .get();
    if (activeContracts.isNotEmpty) {
      throw Exception(
        'لا يمكن حذف هذا العميل لوجود ${activeContracts.length} عقد تقسيط نشط أو متأخر باسمه.',
      );
    }

    final openDebt = await getCustomerCreditDebt(id);
    if (openDebt > 0) {
      throw Exception(
        'لا يمكن حذف هذا العميل لوجود مديونية آجلة قائمة عليه غير مسددة.',
      );
    }

    final now = DateTime.now();
    final branchId = await _branchId();

    await _tx.write(
      writeFn: () async {
        await (_db.update(_db.customers)..where((c) => c.id.equals(id))).write(
          CustomersCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      },
      branchId: branchId,
      entity: 'customer',
      entityId: id,
      operation: 'delete',
      userId: userId,
    );
  }

  @override
  Future<String> recordCustomerPayment({
    required String customerId,
    required int amount,
    required String paymentMethod,
    String? shiftId,
    String? referenceNumber,
    String? notes,
    String userId = 'admin',
  }) async {
    if (amount <= 0) throw Exception('مبلغ السداد يجب أن يكون أكبر من صفر');
    final now = DateTime.now();
    final branchId = await _branchId();
    final id = _uuid.v4();
    final ref = (referenceNumber != null && referenceNumber.trim().isNotEmpty)
        ? referenceNumber.trim()
        : 'REC-${now.millisecondsSinceEpoch}';

    String? effectiveShiftId = shiftId;
    if (effectiveShiftId == null) {
      final activeShift = await (_db.select(_db.shifts)
            ..where((s) => s.closedAt.isNull() & s.deletedAt.isNull())
            ..orderBy([(s) => OrderingTerm.desc(s.openedAt)])
            ..limit(1))
          .getSingleOrNull();
      effectiveShiftId = activeShift?.id;
    }

    await _tx.write(
      writeFn: () async {
        await _db.into(_db.customerPayments).insert(
          CustomerPaymentsCompanion.insert(
            id: id,
            branchId: branchId,
            customerId: customerId,
            shiftId: Value(effectiveShiftId),
            amount: amount,
            paymentMethod: Value(paymentMethod),
            referenceNumber: Value(ref),
            notes: Value(notes),
            createdBy: userId,
            paymentDate: now,
            createdAt: now,
          ),
        );

        await _db.into(_db.cashMovements).insert(
          CashMovementsCompanion.insert(
            id: _uuid.v4(),
            branchId: branchId,
            shiftId: Value(effectiveShiftId),
            type: 'deposit',
            method: paymentMethod,
            direction: 'in',
            amountPiasters: amount,
            referenceId: Value(id),
            notes: Value('تحصيل دفعة حساب عميل ($ref)'),
            createdAt: now.millisecondsSinceEpoch ~/ 1000,
            updatedAt: now.millisecondsSinceEpoch ~/ 1000,
          ),
        );
      },
      branchId: branchId,
      entity: 'customer_payment',
      entityId: id,
      operation: 'insert',
      userId: userId,
      payload: '{"customerId":"$customerId","amount":$amount,"method":"$paymentMethod"}',
    );
    return id;
  }

  @override
  Future<List<CustomerPayment>> getCustomerPayments(String customerId) async {
    return (_db.select(_db.customerPayments)
          ..where((t) => t.customerId.equals(customerId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.paymentDate)]))
        .get();
  }

  @override
  Future<int> getCustomerCreditDebt(String customerId) async {
    final creditSalesRows = await (_db.select(_db.sales)
          ..where(
            (s) =>
                s.customerId.equals(customerId) &
                s.paymentMethod.equals('credit') &
                s.status.isNotValue('cancelled') &
                s.deletedAt.isNull(),
          ))
        .get();

    int totalCreditSales = 0;
    if (creditSalesRows.isNotEmpty) {
      final saleIds = creditSalesRows.map((s) => s.id).toList();
      final downPayments = await (_db.select(_db.salePayments)
            ..where((sp) => sp.saleId.isIn(saleIds) & sp.deletedAt.isNull()))
          .get();

      final Map<String, int> saleToDownPayment = {};
      for (final sp in downPayments) {
        saleToDownPayment[sp.saleId] = (saleToDownPayment[sp.saleId] ?? 0) + sp.amountPiasters;
      }

      for (final s in creditSalesRows) {
        final paidDown = saleToDownPayment[s.id] ?? 0;
        final owed = s.total - paidDown;
        totalCreditSales += (owed < 0 ? 0 : owed);
      }
    }

    final paymentRows = await (_db.select(_db.customerPayments)
          ..where((p) => p.customerId.equals(customerId) & p.deletedAt.isNull()))
        .get();
    final totalPayments = paymentRows.fold<int>(0, (sum, p) => sum + p.amount);

    final returnQuery = _db.select(_db.returns).join([
      innerJoin(_db.sales, _db.sales.id.equalsExp(_db.returns.saleId)),
    ])..where(
      _db.sales.customerId.equals(customerId) &
      _db.returns.paymentMethod.equals('credit') &
      _db.returns.deletedAt.isNull(),
    );
    final returnRows = await returnQuery.get();
    final totalReturns = returnRows.fold<int>(0, (sum, row) => sum + row.readTable(_db.returns).refundAmount);

    final netDebt = totalCreditSales - totalPayments - totalReturns;
    return netDebt < 0 ? 0 : netDebt;
  }
}
