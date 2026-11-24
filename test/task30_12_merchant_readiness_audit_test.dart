import 'package:clothes_erp/core/constants/retail_sector.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/services/store_presets_engine.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/dashboard/data/datasources/dashboard_local_data_source.dart';
import 'package:clothes_erp/features/dashboard/domain/entities/dashboard_stats_entity.dart';
import 'package:clothes_erp/features/inventory/data/datasources/inventory_local_data_source.dart';
import 'package:clothes_erp/features/invoices/domain/entities/invoice_details_entity.dart';
import 'package:clothes_erp/features/invoices/domain/entities/invoice_item_details_entity.dart';
import 'package:clothes_erp/features/invoices/presentation/services/receipt_pdf_service.dart';
import 'package:clothes_erp/features/pos/data/datasources/pos_local_data_source.dart';
import 'package:clothes_erp/features/products/domain/entities/activity_type.dart';
import 'package:clothes_erp/features/reports/data/datasources/reports_local_data_source.dart';
import 'package:clothes_erp/features/reports/domain/entities/sales_report_entity.dart';
import 'package:clothes_erp/features/reports/presentation/cubits/reports_cubit.dart';
import 'package:clothes_erp/features/reports/presentation/cubits/reports_state.dart';
import 'package:clothes_erp/features/reports/presentation/screens/reports_screen.dart';
import 'package:clothes_erp/features/returns/data/datasources/returns_local_data_source.dart';
import 'package:clothes_erp/features/returns/domain/entities/return_item_entity.dart';
import 'package:clothes_erp/features/settings/data/services/activity_settings_service.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

class _TestBranchProvider implements BranchProvider {
  @override
  Future<String> getBranchId() async => 'test_branch';
}

class _FakeAuthLocalDataSource implements AuthLocalDataSource {
  UserModel? _cached;
  @override
  Future<void> cacheUser(UserModel user) async => _cached = user;
  @override
  Future<UserModel?> getCachedUser() async => _cached;
  @override
  Future<void> clearCache() async => _cached = null;
}

class _FakeReportsCubit extends Cubit<ReportsState> implements ReportsCubit {
  _FakeReportsCubit(super.initialState);

  @override
  Future<void> loadReport(DateTime startDate, DateTime endDate) async {}
}

class _FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _FakeAuthCubit(UserModel user) : super(AuthAuthenticated(user));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  late TxWriter tx;
  late BranchProvider branchProvider;
  const branchId = 'test_branch';

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    branchProvider = _TestBranchProvider();
    tx = TxWriter(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Addendum 30.12: Financial Truth', () {
    test('Dashboard excludes supplier_payment from todayExpenses and excludes cancelled sales', () async {
      final now = DateTime.now();
      final dashboardDs = DashboardLocalDataSourceImpl(db);

      await db.into(db.categories).insert(CategoriesCompanion.insert(
        id: 'cat1',
        branchId: branchId,
        name: 'أجهزة منزلية',
        createdAt: now,
        updatedAt: now,
      ));
      await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'prod1',
        branchId: branchId,
        name: 'خلاط كهربائي',
        categoryId: 'cat1',
        createdAt: now,
        updatedAt: now,
      ));
      await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
        id: 'v1',
        branchId: branchId,
        productId: 'prod1',
        sku: 'MIX-01',
        color: 'أبيض',
        size: 'قياسي',
        quantity: const Value(10),
        costPrice: 50000,
        sellPrice: 100000,
        createdAt: now,
        updatedAt: now,
      ));

      // Valid sale (with discount -> lineTotal = 90000)
      await db.into(db.sales).insert(SalesCompanion.insert(
        id: 'sale_ok',
        branchId: branchId,
        shortRef: 'S001',
        cashierId: 'c1',
        subtotal: 90000,
        discountType: 'fixed',
        discountValue: const Value(10000),
        total: 90000,
        paymentMethod: 'cash',
        status: const Value('completed'),
        date: now,
        createdAt: now,
        updatedAt: now,
      ));
      await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
        id: 'si_ok',
        branchId: branchId,
        saleId: 'sale_ok',
        variantId: 'v1',
        productName: 'خلاط كهربائي',
        color: 'أبيض',
        size: 'قياسي',
        qty: 1,
        priceSnapshot: 100000,
        costSnapshot: 50000,
        lineDiscount: const Value(10000),
        lineTotal: 90000,
        createdAt: now,
      ));

      // Cancelled sale (must be excluded)
      await db.into(db.sales).insert(SalesCompanion.insert(
        id: 'sale_cancel',
        branchId: branchId,
        shortRef: 'S002',
        cashierId: 'c1',
        subtotal: 100000,
        discountType: 'none',
        total: 100000,
        paymentMethod: 'cash',
        status: const Value('cancelled'),
        date: now,
        createdAt: now,
        updatedAt: now,
      ));

      // Operating expense (included)
      await db.into(db.expenses).insert(ExpensesCompanion.insert(
        id: 'exp_op',
        branchId: branchId,
        category: 'كهرباء',
        kind: const Value('operating'),
        amount: 5000,
        expenseDate: now,
        userId: 'c1',
        createdAt: now,
        updatedAt: now,
      ));

      // Supplier payment expense (must be excluded)
      await db.into(db.expenses).insert(ExpensesCompanion.insert(
        id: 'exp_sup',
        branchId: branchId,
        category: 'سداد مورد',
        kind: const Value('supplier_payment'),
        amount: 40000,
        expenseDate: now,
        userId: 'c1',
        createdAt: now,
        updatedAt: now,
      ));

      final stats = await dashboardDs.getDashboardStats();
      expect(stats.todaySales, 90000);
      expect(stats.todayTransactions, 1);
      expect(stats.todayExpenses, 5000);
      expect(stats.todayEstimatedNetProfit, 90000 - 50000 - 5000);
      expect(stats.todayTopProducts.first.totalRevenue, 90000);
    });

    test('DashboardStatsEntity.netTodaySalesAfterReturns computes net properly', () {
      const stats = DashboardStatsEntity(
        todaySales: 50000,
        todayReturnsTotal: 15000,
      );
      expect(stats.netTodaySalesAfterReturns, 35000);

      const overReturned = DashboardStatsEntity(
        todaySales: 10000,
        todayReturnsTotal: 25000,
      );
      expect(overReturned.netTodaySalesAfterReturns, 0);
    });

    test('Reports excludes cancelled sales, computes totalReturns and netRevenue', () async {
      final now = DateTime.now();
      final reportsDs = ReportsLocalDataSourceImpl(db);

      await db.into(db.sales).insert(SalesCompanion.insert(
        id: 'r_ok',
        branchId: branchId,
        shortRef: 'R001',
        cashierId: 'c1',
        subtotal: 60000,
        discountType: 'none',
        total: 60000,
        paymentMethod: 'cash',
        status: const Value('completed'),
        date: now,
        createdAt: now,
        updatedAt: now,
      ));
      await db.into(db.sales).insert(SalesCompanion.insert(
        id: 'r_cancel',
        branchId: branchId,
        shortRef: 'R002',
        cashierId: 'c1',
        subtotal: 80000,
        discountType: 'none',
        total: 80000,
        paymentMethod: 'cash',
        status: const Value('cancelled'),
        date: now,
        createdAt: now,
        updatedAt: now,
      ));
      await db.into(db.returns).insert(ReturnsCompanion.insert(
        id: 'ret_1',
        branchId: branchId,
        saleId: const Value('r_ok'),
        refundAmount: 15000,
        paymentMethod: 'cash',
        reason: 'استرجاع عميل',
        cashierId: 'c1',
        date: now,
        createdAt: now,
        updatedAt: now,
      ));

      final report = await reportsDs.getSalesReport(
        startDate: now.subtract(const Duration(days: 1)),
        endDate: now.add(const Duration(days: 1)),
      );
      expect(report.totalRevenue, 60000);
      expect(report.totalTransactions, 1);
      expect(report.totalReturns, 15000);
      expect(report.netRevenue, 45000);
    });
  });

  group('Addendum 30.12: StorePreset.homeTextiles & Engine', () {
    test('StorePreset.homeTextiles exists in onboardingPresets with correct config', () {
      expect(StorePreset.onboardingPresets, contains(StorePreset.homeTextiles));
      expect(
        StorePreset.homeTextiles.activities,
        equals({ActivityType.homeLiving, ActivityType.textilesDecor}),
      );
      expect(StorePreset.homeTextiles.enableInstallments, isTrue);
    });

    test('StorePresetsEngine sets RetailSector.houseware and installments for homeTextiles', () async {
      final authDs = _FakeAuthLocalDataSource();
      final featureGate = FeatureGate(db, authDs, tx, branchProvider);
      final activityService = ActivitySettingsService(db, featureGate);

      await StorePresetsEngine.applyPreset(
        preset: StorePreset.homeTextiles,
        featureGate: featureGate,
        activityService: activityService,
      );

      final sector = await featureGate.getMeta(RetailSector.metaKey);
      final installmentsEnabled = await featureGate.isEnabled(FeatureKeys.installments);
      final presetCode = await featureGate.getMeta('store.preset');
      final enabledActs = await activityService.getEnabledActivities();

      expect(sector, RetailSector.houseware);
      expect(installmentsEnabled, isTrue);
      expect(presetCode, 'homeTextiles');
      expect(enabledActs.toSet(), equals({ActivityType.homeLiving, ActivityType.textilesDecor}));
    });
  });

  group('Addendum 30.12: Fractional Meter Stock Accuracy', () {
    test('POS checkout & Returns preserve fractional meter stock in stock_decimal_<variantId>', () async {
      final now = DateTime.now();
      final inventoryDs = InventoryLocalDataSource(db, branchProvider, tx);
      final posDs = PosLocalDataSource(db, branchProvider, tx, inventoryDs);
      final returnsDs = ReturnsLocalDataSourceImpl(db, branchProvider, tx, inventoryDs);

      await db.into(db.categories).insert(CategoriesCompanion.insert(
        id: 'cat_tex',
        branchId: branchId,
        name: 'سجاد بالمتر',
        createdAt: now,
        updatedAt: now,
      ));
      await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'prod_tex',
        branchId: branchId,
        name: 'سجاد تركي عرض 2م',
        categoryId: 'cat_tex',
        activityType: const Value('textiles_decor'),
        createdAt: now,
        updatedAt: now,
      ));
      await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
        id: 'v_tex',
        branchId: branchId,
        productId: 'prod_tex',
        sku: 'CARP-01',
        color: 'بيج',
        size: 'رول 2م',
        quantity: const Value(10),
        costPrice: 10000,
        sellPrice: 20000,
        createdAt: now,
        updatedAt: now,
      ));

      final saleId = await posDs.checkout(
        items: [
          {
            'variantId': 'v_tex',
            'name': 'سجاد تركي عرض 2م',
            'color': 'بيج',
            'size': 'رول 2م',
            'qty': 3, // ceil(2.5)
            'decimalQty': 2.5,
            'effectiveQty': 2.5,
            'unit': 'م',
            'price': 20000,
            'cost': 10000,
            'discount': 0,
            'promotionDiscount': 0,
            'isReturn': false,
          },
        ],
        total: 50000,
        cashierId: 'c1',
        paymentMethod: 'cash',
      );

      final decimalMeta = await (db.select(db.appMeta)
            ..where((m) => m.key.equals('stock_decimal_v_tex')))
          .getSingle();
      expect(double.parse(decimalMeta.value), closeTo(7.5, 0.001));

      final variantAfterSale = await (db.select(db.productVariants)
            ..where((v) => v.id.equals('v_tex')))
          .getSingle();
      expect(variantAfterSale.quantity, 7);

      // Now return the 2.5m item
      final saleItems = await returnsDs.getSaleItems(saleId);
      expect(saleItems.length, 1);

      await returnsDs.processReturn(
        saleId: saleId,
        items: [
          ReturnItemEntity(
            saleItemId: saleItems.first.id,
            variantId: 'v_tex',
            productName: 'سجاد تركي عرض 2م',
            color: 'بيج',
            size: saleItems.first.size,
            maxQty: saleItems.first.qty,
            qty: saleItems.first.qty,
            refundUnitPrice: 16666,
          ),
        ],
        reason: 'تغيير المقاس',
        userId: 'c1',
      );

      final decimalMetaAfterReturn = await (db.select(db.appMeta)
            ..where((m) => m.key.equals('stock_decimal_v_tex')))
          .getSingle();
      expect(double.parse(decimalMetaAfterReturn.value), closeTo(10.0, 0.001));

      final variantAfterReturn = await (db.select(db.productVariants)
            ..where((v) => v.id.equals('v_tex')))
          .getSingle();
      expect(variantAfterReturn.quantity, 10);
    });
  });

  group('Addendum 30.12: Warranty Receipt & Reports Overflow', () {
    test('ReceiptPdfService generates PDF with warrantyPeriod & brandOrModel', () async {
      final invoice = InvoiceDetailsEntity(
        id: 'inv_w1',
        shortRef: 'W001',
        date: DateTime(2026, 11, 24, 14, 0),
        cashierId: 'c1',
        cashierName: 'أحمد',
        subtotal: 250000,
        discountAmount: 0,
        total: 250000,
        paymentMethod: 'نقدي (كاش)',
        items: const [
          InvoiceItemDetailsEntity(
            id: 'ii_1',
            variantId: 'v_app',
            productName: 'مكنسة كهربائية 2000 وات',
            color: 'أسود',
            size: 'قياسي',
            qty: 1,
            price: 250000,
            lineTotal: 250000,
            warrantyPeriod: '24 شهر',
            brandOrModel: 'توشيبا VC-EA100',
          ),
        ],
      );

      final bytes = await ReceiptPdfService.generateReceiptPdf(
        invoice,
        isHospitality: false,
      );
      expect(bytes, isNotEmpty);
    });

    testWidgets('ReportsScreen wraps KPI & Cash Flow cards cleanly on narrow width', (tester) async {
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeCubit = _FakeReportsCubit(
        ReportsLoaded(
          SalesReportEntity(
            startDate: DateTime(2026, 11, 1),
            endDate: DateTime(2026, 11, 24),
            totalRevenue: 120000,
            totalCost: 70000,
            totalProfit: 50000,
            totalExpenses: 10000,
            totalReturns: 5000,
            totalTransactions: 8,
            paymentMethodBreakdown: const {'cash': 120000},
            cashFlowIn: 120000,
            cashFlowOut: 15000,
          ),
        ),
      );

      final fakeAuthCubit = _FakeAuthCubit(
        UserModel(
          id: 'admin_1',
          name: 'المدير العام',
          email: 'admin@test.com',
          role: 'admin',
          isActive: true,
          createdAt: DateTime(2026, 11, 1),
        ),
      );

      final sl = GetIt.instance;
      await sl.reset();
      sl.registerFactory<ReportsCubit>(() => fakeCubit);
      addTearDown(() async => sl.reset());

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: BlocProvider<AuthCubit>.value(
              value: fakeAuthCubit,
              child: const ReportsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('صافي المبيعات بعد المرتجعات'), findsOneWidget);
    });
  });
}
