import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/di/injection.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/services/excel_workbook_service.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/dashboard/data/services/offline_smart_assistant_service.dart';
import 'package:clothes_erp/features/dashboard/presentation/widgets/offline_smart_assistant_dialog.dart';
import 'package:clothes_erp/features/dashboard/presentation/widgets/store_financial_interview_dialog.dart';
import 'package:clothes_erp/features/partners/domain/entities/partner_entity.dart';
import 'package:clothes_erp/features/returns/presentation/cubits/returns_cubit.dart';
import 'package:clothes_erp/features/returns/presentation/cubits/returns_state.dart';
import 'package:clothes_erp/features/returns/presentation/screens/return_screen.dart';

class _FakeAuthLocalDataSource implements AuthLocalDataSource {
  @override
  Future<void> cacheUser(UserModel user) async {}

  @override
  Future<void> clearCache() async {}

  @override
  Future<UserModel?> getCachedUser() async => null;
}

class _StubReturnsCubit extends Cubit<ReturnsState> implements ReturnsCubit {
  _StubReturnsCubit() : super(const ReturnsState());

  @override
  Future<void> init() async {}

  @override
  Future<void> loadRecentSales() async {}

  @override
  Future<void> searchSale(String query) async {}

  @override
  void clearSelection() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Uint8List _buildWorkbookBytes(Map<String, List<List<dynamic>>> sheets) {
  final excel = Excel.createExcel();
  final firstSheetName = sheets.keys.first;
  final defaultSheet = excel.getDefaultSheet();
  if (defaultSheet != null && defaultSheet != firstSheetName) {
    excel.rename(defaultSheet, firstSheetName);
  }
  for (final entry in sheets.entries) {
    final sheet = excel[entry.key];
    for (final row in entry.value) {
      sheet.appendRow(
        row.map((v) => TextCellValue(v.toString())).toList(),
      );
    }
  }
  return Uint8List.fromList(excel.encode()!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BranchProvider bp;
  late TxWriter tx;
  late ExcelWorkbookService excelService;
  late OfflineSmartAssistantService assistantService;
  const branchId = 'branch_main';

  setUp(() async {
    await getIt.reset();
    db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    bp = BranchProvider(db);
    tx = TxWriter(db);
    excelService = ExcelWorkbookService(db, bp, tx);
    assistantService = OfflineSmartAssistantService(db);

    getIt.registerSingleton<AppDatabase>(db);
    getIt.registerSingleton<BranchProvider>(bp);
    getIt.registerSingleton<TxWriter>(tx);
    getIt.registerSingleton<ExcelWorkbookService>(excelService);
    getIt.registerSingleton<OfflineSmartAssistantService>(assistantService);
  });

  tearDown(() async {
    await db.close();
    await getIt.reset();
  });

  group('Task 39.1: ReturnScreen Split View, History Cards & Shortcuts', () {
    testWidgets('renders Master-Detail Split View on wide screen, F2/Esc work, and History tab shows summary cards', (tester) async {
      final stubCubit = _StubReturnsCubit();
      getIt.registerFactory<ReturnsCubit>(() => stubCubit);

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: ReturnScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('returns_split_view')), findsOneWidget);
      expect(find.byKey(const Key('returns_empty_detail_placeholder')), findsOneWidget);

      // F2 focuses search, Esc clears search
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pump();
      await tester.enterText(find.byKey(const Key('return_search_field')), 'S100');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byKey(const Key('return_search_field'))).controller?.text,
        isEmpty,
      );

      // Switch to History tab and verify summary cards
      await tester.tap(find.text('سجل فواتير المرتجعات'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('returns_history_summary_cards')), findsOneWidget);
      expect(find.text('مرتجعات اليوم'), findsOneWidget);
      expect(find.text('إجمالي المسترد اليوم'), findsOneWidget);

      await stubCubit.close();
    });
  });

  group('Task 39.2: Excel Expenses, Historical Sales & Lenient Mode', () {
    test('imports expenses, historicalSales, and handles missing optional fields in lenientMode', () async {
      final bytes = _buildWorkbookBytes({
        'المصروفات': [
          ['بند المصروف', 'المبلغ', 'التاريخ', 'ملاحظات'],
          ['إيجار المحل', '5000', '', 'بدون تاريخ'],
        ],
        'المبيعات': [
          ['إجمالي الفاتورة', 'طريقة الدفع', 'اسم العميل'],
          ['1200', 'كاش', 'عميل سابق'],
        ],
        'العملاء': [
          ['اسم العميل', 'رقم الهاتف'],
          ['عميل بدون هاتف', ''],
        ],
      });

      // Strict mode rejects missing customer phone
      final strictPreview = await excelService.analyzeMultiSheetWorkbook(
        bytes,
        lenientMode: false,
      );
      expect(strictPreview.newCustomers.length, 0);
      expect(strictPreview.errorCount, greaterThan(0));

      // Lenient mode fills defaults with warnings and allows full import
      final lenientPreview = await excelService.analyzeMultiSheetWorkbook(
        bytes,
        lenientMode: true,
      );
      expect(lenientPreview.newExpenses.length, 1);
      expect(lenientPreview.newHistoricalSales.length, 1);
      expect(lenientPreview.newCustomers.length, 1);
      expect(lenientPreview.warningCount, greaterThan(0));

      final res = await excelService.executeWorkbookImport(
        preview: lenientPreview,
        userId: 'admin',
      );
      expect(res.expensesAdded, 1);
      expect(res.historicalSalesAdded, 1);
      expect(res.customersAdded, 1);

      final dbExpenses = await db.select(db.expenses).get();
      expect(dbExpenses.first.amount, 500000);
      final dbSales = await db.select(db.sales).get();
      expect(dbSales.first.total, 120000);
    });
  });

  group('Task 39.3: StoreFinancialInterviewDialog', () {
    testWidgets('saves partners capital and monthly expense budget to AppMeta', (tester) async {
      bool? dialogRes;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  dialogRes = await StoreFinancialInterviewDialog.show(context);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('interview_capital_field')), '200000');
      await tester.enterText(find.byKey(const Key('interview_budget_field')), '12000');
      await tester.tap(find.byKey(const Key('interview_has_partners_switch')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('interview_partner_name_0')), 'أحمد');
      await tester.enterText(find.byKey(const Key('interview_partner_percent_0')), '60');

      await tester.tap(find.byKey(const Key('interview_save_btn')));
      await tester.pumpAndSettle();

      expect(dialogRes, isTrue);

      final budgetRow = await tester.runAsync(
        () => (db.select(db.appMeta)
              ..where((t) => t.key.equals('finance.monthly_expense_budget')))
            .getSingle(),
      );
      expect(budgetRow?.value, '1200000');

      final partnersRow = await tester.runAsync(
        () => (db.select(db.appMeta)
              ..where((t) => t.key.equals('partners_registry')))
            .getSingle(),
      );
      final decoded = jsonDecode(partnersRow!.value) as List<dynamic>;
      final partner = PartnerEntity.fromJson(decoded.first as Map<String, dynamic>);
      expect(partner.name, 'أحمد');
      expect(partner.percentage, 60.0);
      expect(partner.capital, 12000000);
    });
  });

  group('Task 39.4: OfflineSmartAssistantService & Dialog', () {
    test('answers profit, top products, stagnant, stockout, budget & overdue installments offline', () async {
      final now = DateTime.now();
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: 'c1',
              branchId: branchId,
              name: 'عام',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p1',
              branchId: branchId,
              name: 'سماعة بلوتوث',
              categoryId: 'c1',
              minStock: const Value(5),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: 'v1',
              branchId: branchId,
              productId: 'p1',
              sku: 'EAR-1',
              color: 'أسود',
              size: 'قياسي',
              quantity: const Value(2), // below minStock
              costPrice: 10000,
              sellPrice: 25000,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.sales).insert(
            SalesCompanion.insert(
              id: 's1',
              branchId: branchId,
              shortRef: 'S-1',
              cashierId: 'admin',
              subtotal: 25000,
              discountType: 'none',
              total: 25000,
              paymentMethod: 'cash',
              date: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.saleItems).insert(
            SaleItemsCompanion.insert(
              id: 'si1',
              branchId: branchId,
              saleId: 's1',
              variantId: 'v1',
              productName: 'سماعة بلوتوث',
              color: 'أسود',
              size: 'قياسي',
              qty: 1,
              priceSnapshot: 25000,
              costSnapshot: 10000,
              lineTotal: 25000,
              createdAt: now,
            ),
          );
      await db.into(db.appMeta).insert(
            AppMetaCompanion.insert(
              key: 'finance.monthly_expense_budget',
              value: '1000000',
              updatedAt: now,
            ),
          );
      await db.into(db.expenses).insert(
            ExpensesCompanion.insert(
              id: 'e1',
              branchId: branchId,
              category: 'كهرباء',
              amount: 200000,
              expenseDate: now,
              userId: 'admin',
              createdAt: now,
              updatedAt: now,
            ),
          );

      await db.into(db.suppliers).insert(
            SuppliersCompanion.insert(
              id: 'sup1',
              branchId: branchId,
              name: 'شركة النيل للموبايلات',
              balance: const Value(350000),
              createdAt: now,
              updatedAt: now,
            ),
          );

      final profit = await assistantService.getTodayProfitInsight();
      expect(profit.summary, contains('-')); // 250 - 100 - 2000 = -1850
      expect(profit.details.join(' '), contains('أمس'));

      final top = await assistantService.getTopProfitableProductsInsight();
      expect(top.summary, contains('سماعة بلوتوث'));

      final stockout = await assistantService.getStockoutVelocityInsight();
      expect(stockout.isAlert, isTrue);

      final budget = await assistantService.getMonthlyBudgetComparisonInsight();
      expect(budget.summary, contains('20%'));

      final dues = await assistantService.getSuppliersDuesInsight();
      expect(dues.summary, contains('3500'));

      // Arabic NLU + Egyptian colloquialism + direct product lookup
      final nluProfit = await assistantService.ask('كسبت كام النهارده');
      expect(nluProfit.any((i) => i.id == 'today_profit'), isTrue);

      final nluSuppliers = await assistantService.ask('علينا كام للموردين');
      expect(nluSuppliers.any((i) => i.id == 'suppliers_dues'), isTrue);

      final nluProduct = await assistantService.ask('سعر وربح سماعه بلوتوث');
      expect(nluProduct.any((i) => i.id == 'product_lookup'), isTrue);

      final briefing = await assistantService.getDailyBriefing();
      expect(briefing.length, greaterThanOrEqualTo(4));
    });

    testWidgets('OfflineSmartAssistantDialog renders Daily Briefing, prompt chips, and respects FeatureGate for action buttons', (tester) async {
      final gate = FeatureGate(db, _FakeAuthLocalDataSource(), tx, bp);
      getIt.registerSingleton<FeatureGate>(gate);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => OfflineSmartAssistantDialog.show(context),
                child: const Text('Assistant'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Assistant'));
      await tester.pumpAndSettle();

      expect(find.text('المساعد التحليلي الذكي (أوفلاين)'), findsOneWidget);
      expect(find.byKey(const Key('smart_assistant_briefing_header')), findsOneWidget);

      await tester.tap(find.widgetWithText(ActionChip, 'الأقساط المتأخرة'));
      await tester.pumpAndSettle();
      expect(find.text('لا توجد عقود تقسيط متأخرة'), findsAtLeastNWidgets(2));
      // FeatureKeys.installments defaults to false, so action button must be hidden
      expect(find.byKey(const Key('assistant_action_overdue_installments')), findsNothing);

      gate.dispose();
    });
  });
}

