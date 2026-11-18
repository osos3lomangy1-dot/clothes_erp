import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/customers/data/datasources/customers_local_data_source.dart';
import 'package:clothes_erp/features/customers/data/services/customer_ledger_service.dart';
import 'package:clothes_erp/features/dashboard/data/datasources/dashboard_local_data_source.dart';
import 'package:clothes_erp/features/installments/data/services/manager_pin_service.dart';
import 'package:clothes_erp/features/inventory/data/datasources/inventory_local_data_source.dart';
import 'package:clothes_erp/features/pos/data/datasources/pos_local_data_source.dart';
import 'package:clothes_erp/features/pos/domain/entities/payment_split.dart';
import 'package:clothes_erp/features/returns/data/datasources/returns_local_data_source.dart';
import 'package:clothes_erp/features/returns/domain/entities/return_item_entity.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeInventoryLocalDataSource extends Fake implements InventoryLocalDataSource {
  @override
  Future<void> applyStockMovement({
    required String variantId,
    required int qtyDelta,
    required StockMovementType type,
    String? reason,
    String? userId,
    String? refType,
    String? refId,
  }) async {}
}

class _FakeAuthLocalDataSource extends Fake implements AuthLocalDataSource {
  UserModel? _cachedUser;

  @override
  Future<UserModel?> getCachedUser() async => _cachedUser;

  @override
  Future<void> cacheUser(UserModel user) async {
    _cachedUser = user;
  }
}

void main() {
  late AppDatabase db;
  late BranchProvider branchProvider;
  late TxWriter txWriter;
  late CustomersLocalDataSource customersDs;
  late PosLocalDataSource posDs;
  late ReturnsLocalDataSource returnsDs;
  late CustomerLedgerService ledgerService;
  late DashboardLocalDataSource dashboardDs;
  late ManagerPinService pinService;
  late FeatureGate featureGate;
  late _FakeAuthLocalDataSource authDs;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    branchProvider = BranchProvider(db);
    txWriter = TxWriter(db);
    final inv = _FakeInventoryLocalDataSource();
    authDs = _FakeAuthLocalDataSource();
    featureGate = FeatureGate(db, authDs, txWriter, branchProvider);
    pinService = ManagerPinService(db, txWriter, branchProvider, authDs, featureGate);

    customersDs = CustomersLocalDataSourceImpl(db, branchProvider, txWriter);
    posDs = PosLocalDataSource(db, branchProvider, txWriter, inv);
    returnsDs = ReturnsLocalDataSourceImpl(db, branchProvider, txWriter, inv);
    ledgerService = CustomerLedgerService(db);
    dashboardDs = DashboardLocalDataSourceImpl(db);

    final now = DateTime.now();
    await authDs.cacheUser(
      UserModel(
        id: 'admin-1',
        name: 'Manager',
        email: 'manager@test.com',
        role: 'admin',
        isActive: true,
        createdAt: now,
      ),
    );

    // Open active shift
    await db.into(db.shifts).insert(
      ShiftsCompanion.insert(
        id: 'shift-1',
        branchId: 'branch-1',
        cashierId: 'admin-1',
        openedAt: now,
        openingBalance: 100000,
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> seedProductAndVariant({int initialQty = 10, int price = 30000}) async {
    final now = DateTime.now();
    await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        id: 'cat-1',
        branchId: 'branch-1',
        name: 'Shirts',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await db.into(db.products).insert(
      ProductsCompanion.insert(
        id: 'prod-1',
        branchId: 'branch-1',
        categoryId: 'cat-1',
        name: 'Linen Shirt',
        createdAt: now,
        updatedAt: now,
      ),
    );

    const varId = 'var-1';
    await db.into(db.productVariants).insert(
      ProductVariantsCompanion.insert(
        id: varId,
        branchId: 'branch-1',
        productId: 'prod-1',
        sku: 'SHIRT-L-WHITE',
        color: 'White',
        size: 'L',
        sellPrice: price,
        costPrice: 15000,
        quantity: Value(initialQty),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return varId;
  }

  test('full credit sale updates customer debt, reports in dashboard, and records no drawer cash movement', () async {
    final varId = await seedProductAndVariant(initialQty: 10, price: 30000); // 300 EGP

    await customersDs.addCustomer(
      name: 'عميل آجل',
      phone: '01011112222',
      customerType: 'retail',
      creditLimit: 100000, // 1000 EGP limit
    );

    final customers = await customersDs.getCustomers();
    final cust = customers.first;

    final saleId = await posDs.checkout(
      cashierId: 'admin-1',
      customerId: cust.id,
      total: 30000,
      paymentMethod: 'credit',
      items: [
        {
          'variantId': varId,
          'name': 'Linen Shirt',
          'color': 'White',
          'size': 'L',
          'qty': 1,
          'price': 30000,
          'cost': 15000,
          'discount': 0,
        }
      ],
    );

    expect(saleId, isNotEmpty);

    // Debt should be 30000 piasters (300 EGP)
    final debt = await customersDs.getCustomerCreditDebt(cust.id);
    expect(debt, 30000);

    // Drawer cash movements should have 0 records for this full credit sale
    final cashMoves = await (db.select(db.cashMovements)..where((m) => m.referenceId.equals(saleId))).get();
    expect(cashMoves.isEmpty, isTrue);

    // Financial summary in ledger service should report the debt
    final summaries = await ledgerService.getAllCustomerSummaries();
    expect(summaries[cust.id]?.creditDebtPiasters, 30000);

    // Dashboard stats should report total customer credit debt
    final stats = await dashboardDs.getDashboardStats();
    expect(stats.totalCustomerCreditDebts, 30000);
  });

  test('credit sale with down payment records cash movement only for the down payment and nets remaining debt', () async {
    final varId = await seedProductAndVariant(initialQty: 10, price: 50000); // 500 EGP

    await customersDs.addCustomer(
      name: 'عميل دفعة مقدمة',
      phone: '01022223333',
      creditLimit: 100000,
    );

    final cust = (await customersDs.getCustomers()).first;

    // Customer pays 100 EGP down payment in cash, 400 EGP remains on credit
    final saleId = await posDs.checkout(
      cashierId: 'admin-1',
      customerId: cust.id,
      total: 50000,
      paymentMethod: 'credit',
      splits: [
        const PaymentSplit(method: 'cash', amountPiasters: 10000),
        const PaymentSplit(method: 'credit', amountPiasters: 40000),
      ],
      items: [
        {
          'variantId': varId,
          'name': 'Linen Shirt',
          'color': 'White',
          'size': 'L',
          'qty': 1,
          'price': 50000,
          'cost': 15000,
          'discount': 0,
        }
      ],
    );

    // Cash movement should exist ONLY for the 10000 piasters down-payment
    final cashMoves = await (db.select(db.cashMovements)..where((m) => m.referenceId.equals(saleId))).get();
    expect(cashMoves.length, 1);
    expect(cashMoves.first.amountPiasters, 10000);
    expect(cashMoves.first.direction, 'in');

    // Customer debt should be 40000 piasters (400 EGP)
    final debt = await customersDs.getCustomerCreditDebt(cust.id);
    expect(debt, 40000);
  });

  test('customer payment collection records payment and drawer cash movement into active shift', () async {
    await customersDs.addCustomer(
      name: 'محمود عبد الرازق',
      phone: '01033334444',
      creditLimit: 200000,
    );

    final cust = (await customersDs.getCustomers()).first;

    // Create a 600 EGP credit sale
    final varId = await seedProductAndVariant(initialQty: 10, price: 60000);
    await posDs.checkout(
      cashierId: 'admin-1',
      customerId: cust.id,
      total: 60000,
      paymentMethod: 'credit',
      items: [
        {
          'variantId': varId,
          'name': 'Linen Shirt',
          'color': 'White',
          'size': 'L',
          'qty': 1,
          'price': 60000,
          'cost': 15000,
          'discount': 0,
        }
      ],
    );

    expect(await customersDs.getCustomerCreditDebt(cust.id), 60000);

    // Customer settles 400 EGP in cash (سند قبض)
    final payId = await customersDs.recordCustomerPayment(
      customerId: cust.id,
      amount: 40000,
      userId: 'admin-1',
      paymentMethod: 'cash',
      notes: 'سداد جزئي نقداً بالفرع',
    );

    // Debt should drop to 200 EGP
    expect(await customersDs.getCustomerCreditDebt(cust.id), 20000);

    // Drawer should have received the 400 EGP
    final move = await (db.select(db.cashMovements)..where((m) => m.referenceId.equals(payId))).getSingle();
    expect(move.amountPiasters, 40000);
    expect(move.direction, 'in');
    expect(move.type, 'deposit');
    expect(move.shiftId, 'shift-1');

    // Statement should include the payment
    final stmt = await ledgerService.getCustomerStatement(cust.id);
    expect(stmt.payments.length, 1);
    expect(stmt.payments.first.amount, 40000);
    expect(stmt.summary.creditDebtPiasters, 20000);
  });

  test('customer with open debt cannot be soft-deleted', () async {
    await customersDs.addCustomer(
      name: 'عميل عليه مديونية',
      phone: '01044445555',
      creditLimit: 50000,
    );

    final cust = (await customersDs.getCustomers()).first;

    final varId = await seedProductAndVariant(initialQty: 5, price: 20000);
    await posDs.checkout(
      cashierId: 'admin-1',
      customerId: cust.id,
      total: 20000,
      paymentMethod: 'credit',
      items: [
        {
          'variantId': varId,
          'name': 'Linen Shirt',
          'color': 'White',
          'size': 'L',
          'qty': 1,
          'price': 20000,
          'cost': 15000,
          'discount': 0,
        }
      ],
    );

    expect(
      () => customersDs.softDeleteCustomer(cust.id),
      throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('مديونية'))),
    );
  });

  test('credit returns reduce customer debt without cash drawer outflow', () async {
    await customersDs.addCustomer(
      name: 'عميل مرتجع آجل',
      phone: '01055556666',
      creditLimit: 100000,
    );

    final cust = (await customersDs.getCustomers()).first;

    final varId = await seedProductAndVariant(initialQty: 5, price: 30000);
    final saleId = await posDs.checkout(
      cashierId: 'admin-1',
      customerId: cust.id,
      total: 30000,
      paymentMethod: 'credit',
      items: [
        {
          'variantId': varId,
          'name': 'Linen Shirt',
          'color': 'White',
          'size': 'L',
          'qty': 1,
          'price': 30000,
          'cost': 15000,
          'discount': 0,
        }
      ],
    );

    expect(await customersDs.getCustomerCreditDebt(cust.id), 30000);

    // Process full return on the credit sale
    await returnsDs.processReturn(
      saleId: saleId,
      paymentMethod: 'credit',
      reason: 'مقاس غير مناسب',
      userId: 'admin-1',
      items: [
        ReturnItemEntity(
          variantId: varId,
          productName: 'Linen Shirt',
          maxQty: 1,
          qty: 1,
          refundUnitPrice: 30000,
        ),
      ],
    );

    // Net debt should drop back to 0
    expect(await customersDs.getCustomerCreditDebt(cust.id), 0);

    // No refund cash movement should exist
    final refundCashMoves = await (db.select(db.cashMovements)..where((m) => m.type.equals('refund'))).get();
    expect(refundCashMoves.isEmpty, isTrue);
  });

  test('manager PIN service supports credit sales pin configuration toggle', () async {
    // Default is false (optional)
    expect(await pinService.isCreditPinRequired(), isFalse);

    await pinService.setCreditPinRequired(required: true, userId: 'admin-1');
    expect(await pinService.isCreditPinRequired(), isTrue);

    await pinService.setCreditPinRequired(required: false, userId: 'admin-1');
    expect(await pinService.isCreditPinRequired(), isFalse);
  });
}
