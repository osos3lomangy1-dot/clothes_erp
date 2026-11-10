import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/features/invoices/data/datasources/invoices_local_data_source.dart';
import 'package:clothes_erp/features/invoices/data/repositories/invoices_repository_impl.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late BranchProvider branchProvider;
  late InvoicesLocalDataSource dataSource;
  late InvoicesRepositoryImpl repository;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    branchProvider = BranchProvider(db);
    final branchId = await branchProvider.getBranchId();

    dataSource = InvoicesLocalDataSourceImpl(db);
    repository = InvoicesRepositoryImpl(dataSource);

    final now = DateTime.now();

    // 1. Seed test user (Cashier)
    await db.into(db.users).insert(
      UsersCompanion.insert(
        id: 'user_cashier_1',
        branchId: branchId,
        username: 'ahmed_cashier',
        displayName: 'كاشير أحمد',
        role: 'cashier',
        passwordHash: 'hash123',
        passwordSalt: 'salt123',
        createdAt: now,
        updatedAt: now,
      ),
    );

    // 2. Seed test category
    await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        id: 'cat_shirts',
        branchId: branchId,
        name: 'قمصان',
        createdAt: now,
        updatedAt: now,
      ),
    );

    // 3. Seed test customer
    await db.into(db.customers).insert(
      CustomersCompanion.insert(
        id: 'cust_omar',
        branchId: branchId,
        name: 'عمر التميمي',
        phone: '01012345678',
        createdAt: now,
        updatedAt: now,
      ),
    );

    // 4. Seed test product
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        id: 'prod_shirt',
        branchId: branchId,
        name: 'قميص كاجوال كلاسيك',
        categoryId: 'cat_shirts',
        createdAt: now,
        updatedAt: now,
      ),
    );

    // 5. Seed test product variant
    await db.into(db.productVariants).insert(
      ProductVariantsCompanion.insert(
        id: 'var_shirt_blue_m',
        branchId: branchId,
        productId: 'prod_shirt',
        sku: '1234567890123',
        size: 'M',
        color: 'أزرق',
        quantity: const Value(50),
        costPrice: 15000,
        sellPrice: 25000,
        wholesalePrice: const Value(20000),
        createdAt: now,
        updatedAt: now,
      ),
    );

    // 6. Seed Sale 1: completed today, Cash, customer Omar
    await db.into(db.sales).insert(
      SalesCompanion.insert(
        id: 'sale_001',
        branchId: branchId,
        shortRef: 'A1B2C3',
        date: now,
        cashierId: 'user_cashier_1',
        customerId: const Value('cust_omar'),
        paymentMethod: 'cash',
        subtotal: 50000,
        discountType: 'fixed',
        discountAmount: const Value(5000),
        total: 45000,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await db.into(db.saleItems).insert(
      SaleItemsCompanion.insert(
        id: 'item_001_1',
        branchId: branchId,
        saleId: 'sale_001',
        variantId: 'var_shirt_blue_m',
        productName: 'قميص كاجوال كلاسيك',
        color: 'أزرق',
        size: 'M',
        qty: 2,
        priceSnapshot: 25000,
        costSnapshot: 15000,
        lineDiscount: const Value(5000),
        lineTotal: 45000,
        createdAt: now,
      ),
    );

    // 7. Seed Sale 2: 5 days ago, Card payment
    final fiveDaysAgo = now.subtract(const Duration(days: 5));
    await db.into(db.sales).insert(
      SalesCompanion.insert(
        id: 'sale_002',
        branchId: branchId,
        shortRef: 'X9Y8Z7',
        date: fiveDaysAgo,
        cashierId: 'user_cashier_1',
        customerId: const Value('cust_omar'),
        paymentMethod: 'card',
        subtotal: 25000,
        discountType: 'none',
        discountAmount: const Value(0),
        total: 25000,
        createdAt: fiveDaysAgo,
        updatedAt: fiveDaysAgo,
      ),
    );

    await db.into(db.saleItems).insert(
      SaleItemsCompanion.insert(
        id: 'item_002_1',
        branchId: branchId,
        saleId: 'sale_002',
        variantId: 'var_shirt_blue_m',
        productName: 'قميص كاجوال كلاسيك',
        color: 'أزرق',
        size: 'M',
        qty: 1,
        priceSnapshot: 25000,
        costSnapshot: 15000,
        lineDiscount: const Value(0),
        lineTotal: 25000,
        createdAt: fiveDaysAgo,
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Invoices Local DataSource & Repository Tests', () {
    test('getInvoices returns all sales with joined customer, cashier, and items', () async {
      final invoices = await dataSource.getInvoices();

      expect(invoices.length, 2);

      // Latest invoice first (sale_001)
      final first = invoices.first;
      expect(first.id, 'sale_001');
      expect(first.shortRef, 'A1B2C3');
      expect(first.cashierName, 'كاشير أحمد');
      expect(first.customerName, 'عمر التميمي');
      expect(first.customerPhone, '01012345678');
      expect(first.subtotal, 50000);
      expect(first.discountAmount, 5000);
      expect(first.total, 45000);
      expect(first.paymentMethod, 'cash');
      expect(first.items.length, 1);
      expect(first.items.first.productName, 'قميص كاجوال كلاسيك');
      expect(first.items.first.qty, 2);
      expect(first.items.first.lineTotal, 45000);
    });

    test('getInvoiceByShortRef and getInvoiceById return expected invoice details', () async {
      final byRef = await dataSource.getInvoiceByShortRef('A1B2C3');
      expect(byRef, isNotNull);
      expect(byRef!.id, 'sale_001');
      expect(byRef.items.length, 1);
      expect(byRef.customerName, 'عمر التميمي');

      final byId = await dataSource.getInvoiceById('sale_002');
      expect(byId, isNotNull);
      expect(byId!.shortRef, 'X9Y8Z7');
      expect(byId.paymentMethod, 'card');
      expect(byId.total, 25000);

      final nonExistent = await dataSource.getInvoiceByShortRef('NOT_FOUND');
      expect(nonExistent, isNull);
    });

    test('getInvoices filters by search query (shortRef, customer name, customer phone)', () async {
      // Search by shortRef
      final resRef = await dataSource.getInvoices(search: 'A1B2');
      expect(resRef.length, 1);
      expect(resRef.first.shortRef, 'A1B2C3');

      // Search by customer name
      final resName = await dataSource.getInvoices(search: 'عمر');
      expect(resName.length, 2);

      // Search by phone
      final resPhone = await dataSource.getInvoices(search: '01012345');
      expect(resPhone.length, 2);

      // Search non-existent
      final resEmpty = await dataSource.getInvoices(search: 'غير موجود');
      expect(resEmpty.isEmpty, isTrue);
    });

    test('getInvoices filters by date range and paymentMethod', () async {
      final now = DateTime.now();

      // Today only
      final todayOnly = await dataSource.getInvoices(
        fromDate: now,
        toDate: now,
      );
      expect(todayOnly.length, 1);
      expect(todayOnly.first.id, 'sale_001');

      // Filter by paymentMethod = 'card'
      final cardOnly = await dataSource.getInvoices(paymentMethod: 'card');
      expect(cardOnly.length, 1);
      expect(cardOnly.first.id, 'sale_002');

      // Repository layer call test
      final repoRes = await repository.getInvoices(paymentMethod: 'cash');
      expect(repoRes.isRight(), isTrue);
      repoRes.fold(
        (_) => fail('Should not fail'),
        (list) {
          expect(list.length, 1);
          expect(list.first.id, 'sale_001');
        },
      );
    });
  });
}
