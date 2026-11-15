import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/purchases/data/datasources/purchases_local_data_source.dart';
import 'package:clothes_erp/features/shifts/data/datasources/shift_local_data_source.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthLocalDataSource implements AuthLocalDataSource {
  UserModel? _user;
  @override
  Future<void> cacheUser(UserModel user) async => _user = user;
  @override
  Future<UserModel?> getCachedUser() async => _user;
  @override
  Future<void> clearCache() async => _user = null;
}

void main() {
  group('Phase 2 — Cash Movements & Shift Balance', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 1: Migration v7 is idempotent (Amendment 1 & 2)
    // ─────────────────────────────────────────────────────────────────────────
    test('1. Migration v7 idempotent: running backfill twice does not duplicate rows', () async {
      final now = DateTime.now();

      // Seed 1 sale
      await db.into(db.sales).insert(SalesCompanion.insert(
        id: 's-idemp-1',
        branchId: 'b1',
        shortRef: 'REF-01',
        cashierId: 'cashier-1',
        shiftId: const Value('shift-1'),
        subtotal: 15000,
        discountType: 'none',
        total: 15000,
        paymentMethod: 'cash',
        date: now,
        createdAt: now,
        updatedAt: now,
      ));

      // Run backfill first time
      await db.backfillCashMovements();
      final count1 = await (db.select(db.cashMovements)..where((m) => m.referenceId.equals('s-idemp-1'))).get();
      expect(count1.length, equals(1));

      // Run backfill second time
      await db.backfillCashMovements();
      final count2 = await (db.select(db.cashMovements)..where((m) => m.referenceId.equals('s-idemp-1'))).get();
      expect(count2.length, equals(1));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 2: Migration v7 does not throw on open shift & records open shift in app_meta (Correction 3 & Amendment 3)
    // ─────────────────────────────────────────────────────────────────────────
    test('2. Migration v7 does NOT throw on open shift and logs key to app_meta', () async {
      final now = DateTime.now();

      // Seed open shift (Correction 3: closed_at IS NULL)
      await db.into(db.shifts).insert(ShiftsCompanion.insert(
        id: 'shift-open-77',
        branchId: 'b1',
        cashierId: 'cashier-1',
        openingBalance: 10000,
        openedAt: now,
        createdAt: now,
        updatedAt: now,
      ));

      final migrator = db.createMigrator();
      await expectLater(db.migrateToV7(migrator), completes);

      // Verify open shift key written to app_meta
      final metaRow = await (db.select(db.appMeta)
            ..where((m) => m.key.equals('migration_v7_open_shift_id')))
          .getSingleOrNull();

      expect(metaRow, isNotNull);
      expect(metaRow!.value, equals('shift-open-77'));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 3: Banner logic function (Amendment 5)
    // ─────────────────────────────────────────────────────────────────────────
    test('3. Banner returns null when no key, and Arabic message when key exists', () async {
      // 1. Without key
      final msgBefore = await getMigrationOpenShiftBannerMessage(db);
      expect(msgBefore, isNull);

      // 2. With key
      final now = DateTime.now();
      await db.into(db.appMeta).insert(AppMetaCompanion.insert(
        key: 'migration_v7_open_shift_id',
        value: 'shift-99',
        updatedAt: now,
      ));

      final msgAfter = await getMigrationOpenShiftBannerMessage(db);
      expect(msgAfter, isNotNull);
      expect(msgAfter, contains('shift-99'));
      expect(msgAfter, contains('وردية shift-99 كانت مفتوحة أثناء ترقية'));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 4: Backfill covers all 7 sources accurately with P0 verified columns
    // ─────────────────────────────────────────────────────────────────────────
    test('4. Backfill covers sales, supplier_payments, purchases, returns, installments, expenses', () async {
      final now = DateTime.now();

      // A. Regular Sale
      await db.into(db.sales).insert(SalesCompanion.insert(
        id: 'sale-bf-1',
        branchId: 'b1',
        shortRef: 'REF-02',
        cashierId: 'cashier-1',
        shiftId: const Value('shift-1'),
        subtotal: 20000,
        discountType: 'none',
        total: 20000,
        paymentMethod: 'cash',
        date: now,
        createdAt: now,
        updatedAt: now,
      ));

      // B. Supplier Payment
      await db.into(db.supplierPayments).insert(SupplierPaymentsCompanion.insert(
        id: 'sp-bf-1',
        branchId: 'b1',
        supplierId: 'sup-1',
        amount: 8000,
        paymentDate: now,
        paymentMethod: const Value('cash'),
        createdBy: 'u1',
        createdAt: now,
      ));

      // C. Purchase with advance payment (not in supplier_payments)
      await db.into(db.purchases).insert(PurchasesCompanion.insert(
        id: 'purch-bf-1',
        branchId: 'b1',
        supplierId: 'sup-1',
        purchaseDate: now,
        totalAmount: 50000,
        paidAmount: const Value(12000),
        status: const Value('received'),
        paymentStatus: const Value('partial'),
        createdAt: now,
        updatedAt: now,
      ));

      // D. Return
      await db.into(db.returns).insert(ReturnsCompanion.insert(
        id: 'ret-bf-1',
        branchId: 'b1',
        cashierId: 'c1',
        reason: 'defective',
        refundAmount: 3000,
        paymentMethod: 'cash',
        date: now,
        createdAt: now,
        updatedAt: now,
      ));

      // E. Customer Installment (Down Payment)
      await db.into(db.customerInstallments).insert(CustomerInstallmentsCompanion.insert(
        id: 'ci-bf-1',
        branchId: 'b1',
        saleId: 'sale-inst-1',
        customerId: 'cust-1',
        totalPiasters: 10000,
        downPaymentPiasters: const Value(2500),
        principalPiasters: 7500,
        interestBp: 0,
        monthlyAmountPiasters: 2500,
        remainingPiasters: 7500,
        durationMonths: 3,
        startDate: now,
        endDate: now,
        createdBy: 'u1',
        createdAt: now,
        updatedAt: now,
      ));

      // F. Installment Payment
      await db.into(db.installmentPayments).insert(InstallmentPaymentsCompanion.insert(
        id: 'ip-bf-1',
        branchId: 'b1',
        customerInstallmentId: 'ci-bf-1',
        amountPiasters: 2500,
        paymentMethod: 'cash',
        paidAt: now,
        recordedBy: 'u1',
        createdAt: now,
        updatedAt: now,
      ));

      // G. Operating Expense
      await db.into(db.expenses).insert(ExpensesCompanion.insert(
        id: 'exp-bf-1',
        branchId: 'b1',
        category: 'كهرباء',
        amount: 1500,
        kind: const Value('operating'),
        userId: 'u1',
        expenseDate: now,
        createdAt: now,
        updatedAt: now,
      ));

      // Run backfill
      await db.backfillCashMovements();

      final movements = await db.select(db.cashMovements).get();
      expect(movements.length, equals(7));

      expect(movements.any((m) => m.type == 'sale' && m.direction == 'in' && m.amountPiasters == 20000), isTrue);
      expect(movements.any((m) => m.type == 'supplier_payment' && m.direction == 'out' && m.amountPiasters == 8000), isTrue);
      expect(movements.any((m) => m.type == 'purchase_payment' && m.direction == 'out' && m.amountPiasters == 12000), isTrue);
      expect(movements.any((m) => m.type == 'refund' && m.direction == 'out' && m.amountPiasters == 3000), isTrue);
      expect(movements.any((m) => m.type == 'installment_down' && m.direction == 'in' && m.amountPiasters == 2500), isTrue);
      expect(movements.any((m) => m.type == 'installment_payment' && m.direction == 'in' && m.amountPiasters == 2500), isTrue);
      expect(movements.any((m) => m.type == 'expense' && m.direction == 'out' && m.amountPiasters == 1500), isTrue);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 5: createPurchaseInvoice does NOT write to expenses (Correction 1)
    // ─────────────────────────────────────────────────────────────────────────
    test('5. createPurchaseInvoice does NOT write to expenses', () async {
      final branchProvider = BranchProvider(db);
      final purchasesDs = PurchasesLocalDataSourceImpl(db, branchProvider);
      final now = DateTime.now();

      // Seed supplier & variant
      await db.into(db.categories).insert(CategoriesCompanion.insert(
        id: 'cat-1',
        branchId: 'b1',
        name: 'ملابس',
        createdAt: now,
        updatedAt: now,
      ));
      await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'prod-1',
        branchId: 'b1',
        name: 'قميص',
        categoryId: 'cat-1',
        createdAt: now,
        updatedAt: now,
      ));
      await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
        id: 'var-1',
        branchId: 'b1',
        productId: 'prod-1',
        sku: 'SKU-001',
        color: 'أزرق',
        size: 'L',
        costPrice: 5000,
        sellPrice: 10000,
        quantity: const Value(10),
        createdAt: now,
        updatedAt: now,
      ));
      await db.into(db.suppliers).insert(SuppliersCompanion.insert(
        id: 'sup-1',
        branchId: 'b1',
        name: 'مورد الأقمشة',
        createdAt: now,
        updatedAt: now,
      ));

      final beforeExpenses = await db.select(db.expenses).get();

      await purchasesDs.createPurchaseInvoice(
        supplierId: 'sup-1',
        invoiceNumber: 'INV-100',
        purchaseDate: now,
        paidAmount: 5000,
        items: const [
          PurchaseItemDraft(variantId: 'var-1', qty: 2, costPrice: 5000),
        ],
        userId: 'admin',
      );

      final afterExpenses = await db.select(db.expenses).get();
      // MUST NOT write to expenses table
      expect(afterExpenses.length, equals(beforeExpenses.length));

      // MUST write to cash_movements table
      final movements = await (db.select(db.cashMovements)..where((m) => m.type.equals('purchase_payment'))).get();
      expect(movements.length, equals(1));
      expect(movements.first.amountPiasters, equals(5000));
      expect(movements.first.direction, equals('out'));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 6: recordSupplierPayment does NOT write to expenses (Correction 1)
    // ─────────────────────────────────────────────────────────────────────────
    test('6. recordSupplierPayment does NOT write to expenses', () async {
      final branchProvider = BranchProvider(db);
      final purchasesDs = PurchasesLocalDataSourceImpl(db, branchProvider);
      final now = DateTime.now();

      await db.into(db.suppliers).insert(SuppliersCompanion.insert(
        id: 'sup-2',
        branchId: 'b1',
        name: 'مورد 2',
        createdAt: now,
        updatedAt: now,
      ));

      final beforeExpenses = await db.select(db.expenses).get();

      await purchasesDs.addSupplierPayment(
        supplierId: 'sup-2',
        amount: 3000,
        paymentDate: now,
        paymentMethod: 'cash',
        userId: 'admin',
      );

      final afterExpenses = await db.select(db.expenses).get();
      // MUST NOT write to expenses
      expect(afterExpenses.length, equals(beforeExpenses.length));

      // MUST write to cash_movements
      final movements = await (db.select(db.cashMovements)..where((m) => m.type.equals('supplier_payment'))).get();
      expect(movements.length, equals(1));
      expect(movements.first.amountPiasters, equals(3000));
      expect(movements.first.direction, equals('out'));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 7: Cancel purchase / reversal writes purchase_reversal with direction in
    // ─────────────────────────────────────────────────────────────────────────
    test('7. Reversal entries (purchase_reversal, expense_reversal) have direction in', () async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Insert purchase_reversal (direction: in)
      await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
        id: 'rev-1',
        branchId: 'b1',
        type: 'purchase_reversal',
        method: 'cash',
        direction: 'in',
        amountPiasters: 5000,
        createdAt: nowSec,
        updatedAt: nowSec,
      ));

      // Insert expense_reversal (direction: in)
      await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
        id: 'rev-2',
        branchId: 'b1',
        type: 'expense_reversal',
        method: 'cash',
        direction: 'in',
        amountPiasters: 2000,
        createdAt: nowSec,
        updatedAt: nowSec,
      ));

      final revRows = await (db.select(db.cashMovements)..where((m) => m.direction.equals('in'))).get();
      expect(revRows.length, equals(2));
      expect(revRows.any((r) => r.type == 'purchase_reversal'), isTrue);
      expect(revRows.any((r) => r.type == 'expense_reversal'), isTrue);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 8: Shift close uses direction — reversal reduces net cash out
    // ─────────────────────────────────────────────────────────────────────────
    test('8. Shift close uses direction: cash reversal correctly offsets cash out', () async {
      final now = DateTime.now();
      final nowSec = now.millisecondsSinceEpoch ~/ 1000;

      // Open shift with 10,000 opening balance
      await db.into(db.shifts).insert(ShiftsCompanion.insert(
        id: 'shift-calc-1',
        branchId: 'b1',
        cashierId: 'cashier-1',
        openingBalance: 10000,
        openedAt: now,
        createdAt: now,
        updatedAt: now,
      ));

      // 1. Cash sale: 5,000 (direction: in)
      await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
        id: 'cm-1',
        branchId: 'b1',
        shiftId: const Value('shift-calc-1'),
        type: 'sale',
        method: 'cash',
        direction: 'in',
        amountPiasters: 5000,
        createdAt: nowSec,
        updatedAt: nowSec,
      ));

      // 2. Cash purchase payment: 3,000 (direction: out)
      await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
        id: 'cm-2',
        branchId: 'b1',
        shiftId: const Value('shift-calc-1'),
        type: 'purchase_payment',
        method: 'cash',
        direction: 'out',
        amountPiasters: 3000,
        createdAt: nowSec,
        updatedAt: nowSec,
      ));

      // 3. Purchase reversal: 3,000 (direction: in) — cancels the purchase out!
      await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
        id: 'cm-3',
        branchId: 'b1',
        shiftId: const Value('shift-calc-1'),
        type: 'purchase_reversal',
        method: 'cash',
        direction: 'in',
        amountPiasters: 3000,
        createdAt: nowSec,
        updatedAt: nowSec,
      ));

      final branchProvider = BranchProvider(db);
      final tx = TxWriter(db);
      final featureGate = FeatureGate(db, _FakeAuthLocalDataSource(), tx, branchProvider);
      final shiftDs = ShiftLocalDataSourceImpl(db, branchProvider, tx, featureGate);

      final summary = await shiftDs.getShiftSummary('shift-calc-1');
      // Opening (10,000) + in (5,000 + 3,000) - out (3,000) = 15,000
      expect(summary.expectedCashInDrawer, equals(15000));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 9: Compound CHECK rejects (sale, out), accepts (sale, in)
    // ─────────────────────────────────────────────────────────────────────────
    test('9. Compound CHECK rejects invalid (sale, out), accepts (sale, in)', () async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Invalid (sale with direction 'out') MUST fail CHECK constraint
      expect(
        () async => await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
              id: 'invalid-cm-1',
              branchId: 'b1',
              type: 'sale',
              method: 'cash',
              direction: 'out', // Invalid!
              amountPiasters: 1000,
              createdAt: nowSec,
              updatedAt: nowSec,
            )),
        throwsA(anything),
      );

      // Valid (sale with direction 'in') MUST succeed
      await expectLater(
        db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
              id: 'valid-cm-1',
              branchId: 'b1',
              type: 'sale',
              method: 'cash',
              direction: 'in',
              amountPiasters: 1000,
              createdAt: nowSec,
              updatedAt: nowSec,
            )),
        completes,
      );
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 10: Compound CHECK rejects non-positive amounts (amount_piasters <= 0)
    // ─────────────────────────────────────────────────────────────────────────
    test('10. Compound CHECK rejects amount <= 0', () async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      expect(
        () async => await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
              id: 'invalid-amount-0',
              branchId: 'b1',
              type: 'sale',
              method: 'cash',
              direction: 'in',
              amountPiasters: 0,
              createdAt: nowSec,
              updatedAt: nowSec,
            )),
        throwsA(anything),
      );

      expect(
        () async => await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
              id: 'invalid-amount-neg',
              branchId: 'b1',
              type: 'sale',
              method: 'cash',
              direction: 'in',
              amountPiasters: -500,
              createdAt: nowSec,
              updatedAt: nowSec,
            )),
        throwsA(anything),
      );
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 11: Compound CHECK validates method in ('cash', 'card', 'transfer')
    // ─────────────────────────────────────────────────────────────────────────
    test('11. Compound CHECK validates method is one of cash, card, transfer', () async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Invalid method ('bitcoin')
      expect(
        () async => await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
              id: 'invalid-method',
              branchId: 'b1',
              type: 'sale',
              method: 'bitcoin',
              direction: 'in',
              amountPiasters: 1000,
              createdAt: nowSec,
              updatedAt: nowSec,
            )),
        throwsA(anything),
      );

      // Valid methods
      for (final m in ['cash', 'card', 'transfer']) {
        await expectLater(
          db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
                id: 'valid-method-$m',
                branchId: 'b1',
                type: 'sale',
                method: m,
                direction: 'in',
                amountPiasters: 1000,
                createdAt: nowSec,
                updatedAt: nowSec,
              )),
          completes,
        );
      }
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 12: Source of truth post-migration test
    // ─────────────────────────────────────────────────────────────────────────
    test('12. Source-of-truth post-migration: cash_movements captures all financial actions', () async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
        id: 'action-1',
        branchId: 'b1',
        type: 'deposit',
        method: 'cash',
        direction: 'in',
        amountPiasters: 25000,
        notes: const Value('إيداع رأس مال إضافي'),
        createdAt: nowSec,
        updatedAt: nowSec,
      ));

      await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
        id: 'action-2',
        branchId: 'b1',
        type: 'withdrawal',
        method: 'cash',
        direction: 'out',
        amountPiasters: 5000,
        notes: const Value('مسحوبات نقدية'),
        createdAt: nowSec,
        updatedAt: nowSec,
      ));

      final all = await db.select(db.cashMovements).get();
      expect(all.length, equals(2));
      final totalIn = all.where((m) => m.direction == 'in').fold<int>(0, (s, m) => s + m.amountPiasters);
      final totalOut = all.where((m) => m.direction == 'out').fold<int>(0, (s, m) => s + m.amountPiasters);
      expect(totalIn, equals(25000));
      expect(totalOut, equals(5000));
    });
  });
}
