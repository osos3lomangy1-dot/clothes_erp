import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/features/partners/domain/entities/partner_entity.dart';
import 'package:clothes_erp/features/partners/data/datasources/partners_local_data_source.dart';

void main() {
  late AppDatabase db;
  late PartnersLocalDataSource ds;
  const branchId = 'test_branch';

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    ds = PartnersLocalDataSourceImpl(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('save partner and retrieve partner list', () async {
    final p1 = PartnerEntity(
      id: 'p1',
      name: 'أحمد محمود',
      phone: '01011112222',
      percentage: 60.0,
      capital: 10000000,
      notes: 'شريك مؤسس بنسبة 60%',
      createdAt: DateTime.now(),
    );

    final p2 = PartnerEntity(
      id: 'p2',
      name: 'محمد علي',
      phone: '01033334444',
      percentage: 40.0,
      capital: 5000000,
      createdAt: DateTime.now(),
    );

    await ds.savePartner(p1);
    await ds.savePartner(p2);

    final partners = await ds.getPartners();
    expect(partners.length, 2);
    expect(partners[0].name, 'أحمد محمود');
    expect(partners[1].percentage, 40.0);

    // Update partner
    final updatedP1 = p1.copyWith(name: 'أحمد محمود المعدل');
    await ds.savePartner(updatedP1);
    final partnersAfter = await ds.getPartners();
    expect(partnersAfter.length, 2);
    expect(partnersAfter[0].name, 'أحمد محمود المعدل');

    // Delete partner
    await ds.deletePartner('p2');
    final partnersFinal = await ds.getPartners();
    expect(partnersFinal.length, 1);
    expect(partnersFinal.first.id, 'p1');
  });

  test('profit summary calculates revenue, cogs, expenses, and net profit correctly', () async {
    final now = DateTime.now();

    // 1. Product & Variant
    await db.into(db.categories).insert(CategoriesCompanion.insert(
      id: 'c1',
      branchId: branchId,
      name: 'قمصان',
      createdAt: now,
      updatedAt: now,
    ));
    await db.into(db.products).insert(ProductsCompanion.insert(
      id: 'prod1',
      branchId: branchId,
      name: 'قميص أبيض',
      categoryId: 'c1',
      createdAt: now,
      updatedAt: now,
    ));
    await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
      id: 'var1',
      branchId: branchId,
      productId: 'prod1',
      sku: 'SHIRT-W-L',
      color: 'White',
      size: 'L',
      costPrice: 15000, // 150 EGP
      sellPrice: 25000, // 250 EGP
      quantity: const Value(50),
      createdAt: now,
      updatedAt: now,
    ));

    // 2. Sale: 2 shirts sold, revenue = 50000 (500 EGP), cost = 30000 (300 EGP)
    await db.into(db.sales).insert(SalesCompanion.insert(
      id: 'sale1',
      branchId: branchId,
      shortRef: 'S1',
      cashierId: 'cashier1',
      subtotal: 50000,
      discountType: 'none',
      total: 50000,
      paymentMethod: 'cash',
      date: now,
      createdAt: now,
      updatedAt: now,
    ));
    await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
      id: 'item1',
      branchId: branchId,
      saleId: 'sale1',
      variantId: 'var1',
      productName: 'قميص أبيض',
      color: 'White',
      size: 'L',
      qty: 2,
      priceSnapshot: 25000,
      costSnapshot: 15000,
      lineTotal: 50000,
      createdAt: now,
    ));

    // 3. Expense: 5000 (50 EGP)
    await db.into(db.expenses).insert(ExpensesCompanion.insert(
      id: 'exp1',
      branchId: branchId,
      category: 'كهرباء',
      amount: 5000,
      userId: 'user1',
      expenseDate: now,
      createdAt: now,
      updatedAt: now,
    ));

    final summary = await ds.getProfitSummary();

    // Revenue: 500 EGP (50000 piasters)
    expect(summary.totalRevenue, 50000);
    // Cost: 300 EGP (30000 piasters)
    expect(summary.totalCost, 30000);
    // Gross Profit: 200 EGP (20000 piasters)
    expect(summary.grossProfit, 20000);
    // Expenses: 50 EGP (5000 piasters)
    expect(summary.totalExpenses, 5000);
    // Net Profit: 150 EGP (15000 piasters)
    expect(summary.netProfit, 15000);
  });
}

