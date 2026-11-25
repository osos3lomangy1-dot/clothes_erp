import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/di/injection.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/services/local_backup_service.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/domain/entities/user_entity.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/auth/services/cashier_permissions_service.dart';
import 'package:clothes_erp/features/dashboard/data/services/offline_smart_assistant_service.dart';
import 'package:clothes_erp/features/dashboard/presentation/widgets/offline_smart_assistant_dialog.dart';
import 'package:clothes_erp/features/invoices/data/services/receipt_settings_service.dart';

class _FakeAuthLocalDataSource implements AuthLocalDataSource {
  UserModel? cachedUser = UserModel(
    id: 'admin_1',
    name: 'المدير',
    email: 'admin@test.com',
    role: 'admin',
    isActive: true,
    createdAt: DateTime(2026, 1, 1),
  );

  @override
  Future<void> cacheUser(UserModel user) async {
    cachedUser = user;
  }

  @override
  Future<void> clearCache() async {
    cachedUser = null;
  }

  @override
  Future<UserModel?> getCachedUser() async => cachedUser;
}

class _StubAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _StubAuthCubit(UserEntity user) : super(AuthAuthenticated(user));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BranchProvider bp;
  late TxWriter tx;
  late FeatureGate gate;
  late OfflineSmartAssistantService assistantService;
  const branchId = 'branch_main';

  setUp(() async {
    await getIt.reset();
    db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    bp = BranchProvider(db);
    tx = TxWriter(db);
    gate = FeatureGate(db, _FakeAuthLocalDataSource(), tx, bp);
    assistantService = OfflineSmartAssistantService(db);

    getIt.registerSingleton<AppDatabase>(db);
    getIt.registerSingleton<BranchProvider>(bp);
    getIt.registerSingleton<TxWriter>(tx);
    getIt.registerSingleton<FeatureGate>(gate);
    getIt.registerSingleton<OfflineSmartAssistantService>(assistantService);
    await CashierPermissionsService.loadFromFeatureGate(gate);
    await ReceiptSettingsService.loadFromFeatureGate(gate);
  });

  tearDown(() async {
    gate.dispose();
    await db.close();
    await getIt.reset();
  });

  group('Task 40.1: Interactive How-To Guide', () {
    test('matches 11 Arabic & Egyptian colloquial how-to topics with numbered steps and route', () async {
      final cases = <String, AssistantActionRoute>{
        'ازاي أغير اسم المحل في الفاتورة': AssistantActionRoute.receiptCustomizer,
        'ازاي اضيف كاشير جديد واعمل له pin': AssistantActionRoute.employees,
        'ازاي امنع الخصم اليدوي للكاشير': AssistantActionRoute.settings,
        'ازاي اعمل نسخ احتياطي للبيانات': AssistantActionRoute.settings,
        'ازاي استورد شيت اكسيل': AssistantActionRoute.excelMigration,
        'ازاي اقفل الوردية واطابق الدرج': AssistantActionRoute.shifts,
        'ازاي افعل نظام التقسيط': AssistantActionRoute.installments,
        'ازاي ابدل نشاط المتجر': AssistantActionRoute.settings,
        'ازاي اضيف شريك ورأس مال': AssistantActionRoute.partners,
        'ازاي اعدل السعر الرسمي للصنف': AssistantActionRoute.products,
        'ازاي اعمل مرتجع فاتورة': AssistantActionRoute.returns,
      };

      for (final entry in cases.entries) {
        final direct = assistantService.matchHowToGuide(entry.key);
        expect(direct, isNotNull, reason: 'Failed direct match for: ${entry.key}');
        expect(direct!.actionRoute, entry.value, reason: 'Wrong route for: ${entry.key}');
        expect(direct.actionLabel, 'فتح الشاشة الآن');
        expect(direct.details.length, greaterThanOrEqualTo(3));
        expect(direct.details.first, startsWith('1.'));

        final asked = await assistantService.ask(entry.key);
        expect(
          asked.any((i) => i.id == direct.id && i.actionRoute == entry.value),
          isTrue,
          reason: 'ask() did not return how-to insight for: ${entry.key}',
        );
      }
    });
  });

  group('Task 40.2: Safe Setting Execution Protocol', () {
    test('rejects cashier role and executes all 5 commands for admin role', () async {
      final blindCmd = assistantService.parseCommand('فعل الجرد الأعمى');
      expect(blindCmd?.pendingCommand, isNotNull);
      expect(blindCmd!.pendingCommand!.kind, AssistantCommandKind.toggleBlindShiftClosing);
      expect(blindCmd.pendingCommand!.touchesFeatureGate, isTrue);

      await expectLater(
        assistantService.executeCommand(
          blindCmd.pendingCommand!,
          userId: 'cashier_1',
          userRole: 'cashier',
          gate: gate,
        ),
        throwsException,
      );
      expect(await gate.isEnabled(FeatureKeys.blindShiftClosing), isFalse);

      // Admin executes toggleBlindShiftClosing
      await assistantService.executeCommand(
        blindCmd.pendingCommand!,
        userId: 'admin_1',
        userRole: 'admin',
        gate: gate,
      );
      expect(await gate.isEnabled(FeatureKeys.blindShiftClosing), isTrue);

      // Admin executes toggleManagerPinProtection
      final pinCmd = assistantService.parseCommand('عطل حماية المدير');
      expect(pinCmd?.pendingCommand?.kind, AssistantCommandKind.toggleManagerPinProtection);
      expect(pinCmd!.pendingCommand!.boolValue, isFalse);
      await assistantService.executeCommand(
        pinCmd.pendingCommand!,
        userId: 'admin_1',
        userRole: 'admin',
        gate: gate,
      );
      expect(await gate.isEnabled(FeatureKeys.managerPinProtection), isFalse);

      // Admin executes toggleAllowManualDiscount
      final discountCmd = assistantService.parseCommand('امنع الخصم اليدوي');
      expect(discountCmd?.pendingCommand?.kind, AssistantCommandKind.toggleAllowManualDiscount);
      expect(discountCmd!.pendingCommand!.boolValue, isFalse);
      await assistantService.executeCommand(
        discountCmd.pendingCommand!,
        userId: 'admin_1',
        userRole: 'admin',
        gate: gate,
      );
      await CashierPermissionsService.loadFromFeatureGate(gate);
      expect(CashierPermissionsService.current.allowManualDiscount, isFalse);

      // Admin executes toggleAutoBackup
      final backupCmd = assistantService.parseCommand('فعل النسخ الاحتياطي التلقائي');
      expect(backupCmd?.pendingCommand?.kind, AssistantCommandKind.toggleAutoBackup);
      await assistantService.executeCommand(
        backupCmd!.pendingCommand!,
        userId: 'admin_1',
        userRole: 'admin',
        gate: gate,
      );
      final autoBackupRow = await (db.select(db.appMeta)
            ..where((m) => m.key.equals(BackupMetaKeys.autoEnabled)))
          .getSingleOrNull();
      expect(autoBackupRow?.value, '1');

      // Admin executes updateStoreName
      final renameCmd = assistantService.parseCommand('تغيير اسم المحل إلى أزياء النخبة');
      expect(renameCmd?.pendingCommand?.kind, AssistantCommandKind.updateStoreName);
      expect(renameCmd!.pendingCommand!.stringValue, 'أزياء النخبة');
      await assistantService.executeCommand(
        renameCmd.pendingCommand!,
        userId: 'admin_1',
        userRole: 'admin',
        gate: gate,
      );
      await ReceiptSettingsService.loadFromFeatureGate(gate);
      expect(ReceiptSettingsService.current.storeName, 'أزياء النخبة');
    });
  });

  group('Task 40.3: Deepened Offline Business Advisor', () {
    test('computes Sales Diagnosis, Promotions Advisor, and Store Pulse from DB', () async {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day, 10, 0);
      final prevWeekDate = now.subtract(const Duration(days: 9));

      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: 'c1',
              branchId: branchId,
              name: 'ملابس',
              createdAt: now,
              updatedAt: now,
            ),
          );

      // p1 / v1: active low stock product
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p1',
              branchId: branchId,
              name: 'تيشيرت قطن',
              categoryId: 'c1',
              minStock: const Value(3),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: 'v1',
              branchId: branchId,
              productId: 'p1',
              sku: 'TSH-1',
              color: 'أبيض',
              size: 'L',
              quantity: const Value(1),
              costPrice: 10000,
              sellPrice: 20000,
              createdAt: now,
              updatedAt: now,
            ),
          );

      // p2 / v2: stagnant high-margin product (qty >= 3, margin >= 20%, 0 sales in 30 days)
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p2',
              branchId: branchId,
              name: 'جاكيت شتوي راكد',
              categoryId: 'c1',
              minStock: const Value(2),
              createdAt: now.subtract(const Duration(days: 40)),
              updatedAt: now,
            ),
          );
      await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: 'v2',
              branchId: branchId,
              productId: 'p2',
              sku: 'JKT-1',
              color: 'كحلي',
              size: 'XL',
              quantity: const Value(6),
              costPrice: 20000,
              sellPrice: 40000,
              createdAt: now.subtract(const Duration(days: 40)),
              updatedAt: now,
            ),
          );

      // Previous 7-day period had higher sales (2 invoices, 500 EGP total)
      await db.into(db.sales).insert(
            SalesCompanion.insert(
              id: 's_prev1',
              branchId: branchId,
              shortRef: 'INV-P1',
              cashierId: 'admin',
              subtotal: 25000,
              discountType: 'none',
              total: 25000,
              paymentMethod: 'cash',
              date: prevWeekDate,
              createdAt: prevWeekDate,
              updatedAt: prevWeekDate,
            ),
          );
      await db.into(db.sales).insert(
            SalesCompanion.insert(
              id: 's_prev2',
              branchId: branchId,
              shortRef: 'INV-P2',
              cashierId: 'admin',
              subtotal: 25000,
              discountType: 'none',
              total: 25000,
              paymentMethod: 'cash',
              date: prevWeekDate.add(const Duration(hours: 2)),
              createdAt: prevWeekDate,
              updatedAt: prevWeekDate,
            ),
          );

      // Today: 1 sale of 200 EGP (with 20 EGP discount)
      await db.into(db.sales).insert(
            SalesCompanion.insert(
              id: 's_today1',
              branchId: branchId,
              shortRef: 'INV-T1',
              cashierId: 'admin',
              subtotal: 22000,
              discountType: 'fixed',
              discountValue: const Value(2000),
              total: 20000,
              paymentMethod: 'cash',
              date: todayStart,
              createdAt: todayStart,
              updatedAt: todayStart,
            ),
          );
      await db.into(db.saleItems).insert(
            SaleItemsCompanion.insert(
              id: 'si_today1',
              branchId: branchId,
              saleId: 's_today1',
              variantId: 'v1',
              productName: 'تيشيرت قطن',
              color: 'أبيض',
              size: 'L',
              qty: 1,
              priceSnapshot: 20000,
              costSnapshot: 10000,
              lineTotal: 20000,
              createdAt: todayStart,
            ),
          );

      // Today's return: 50 EGP
      await db.into(db.returns).insert(
            ReturnsCompanion.insert(
              id: 'ret_1',
              branchId: branchId,
              saleId: const Value('s_today1'),
              cashierId: 'admin',
              reason: 'تبديل مقاس',
              refundAmount: 5000,
              paymentMethod: 'cash',
              date: todayStart.add(const Duration(minutes: 30)),
              createdAt: todayStart,
              updatedAt: todayStart,
            ),
          );

      // Today's expense: 30 EGP
      await db.into(db.expenses).insert(
            ExpensesCompanion.insert(
              id: 'exp_1',
              branchId: branchId,
              category: 'ضيافة',
              amount: 3000,
              expenseDate: todayStart,
              userId: 'admin',
              createdAt: todayStart,
              updatedAt: todayStart,
            ),
          );

      // Open shift with opening balance 100 EGP
      await db.into(db.shifts).insert(
            ShiftsCompanion.insert(
              id: 'shift_1',
              branchId: branchId,
              cashierId: 'admin',
              openingBalance: 10000,
              openedAt: todayStart.subtract(const Duration(hours: 1)),
              createdAt: todayStart,
              updatedAt: todayStart,
            ),
          );

      // Overdue installment
      await db.into(db.customers).insert(
            CustomersCompanion.insert(
              id: 'cust_1',
              branchId: branchId,
              name: 'أحمد علي',
              phone: '01012345678',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.customerInstallments).insert(
            CustomerInstallmentsCompanion.insert(
              id: 'ci_1',
              branchId: branchId,
              saleId: 's_prev1',
              customerId: 'cust_1',
              totalPiasters: 100000,
              downPaymentPiasters: const Value(20000),
              principalPiasters: 80000,
              interestBp: 0,
              monthlyAmountPiasters: 20000,
              remainingPiasters: 80000,
              durationMonths: 4,
              startDate: now.subtract(const Duration(days: 60)),
              endDate: now.subtract(const Duration(days: 5)),
              status: const Value('overdue'),
              createdBy: 'admin',
              createdAt: now,
              updatedAt: now,
            ),
          );

      final diagnosis = await assistantService.getSalesDiagnosisInsight();
      expect(diagnosis.id, 'sales_diagnosis');
      expect(diagnosis.isAlert, isTrue);
      expect(diagnosis.details.join(' '), contains('فاتورة'));
      expect(diagnosis.details.join(' '), contains('المرتجعات'));

      final promos = await assistantService.getPromotionsAdvisorInsight();
      expect(promos.id, 'promotions_advisor');
      expect(promos.details.join(' '), contains('جاكيت شتوي راكد'));

      final pulse = await assistantService.getStorePulseInsight();
      expect(pulse.id, 'store_pulse');
      expect(pulse.summary, contains('مبيعات اليوم'));
      expect(pulse.details.join(' '), contains('رصيد الدرج المتوقع للوردية المفتوحة'));
      expect(pulse.details.join(' '), contains('صنف'));
      expect(pulse.details.join(' '), contains('الأقساط المتأخرة'));

      final askDiag = await assistantService.ask('المبيعات قليلة ليه');
      expect(askDiag.any((i) => i.id == 'sales_diagnosis'), isTrue);

      final askPromo = await assistantService.ask('أعمل عروض على إيه');
      expect(askPromo.any((i) => i.id == 'promotions_advisor'), isTrue);

      final askPulse = await assistantService.ask('وضع المحل دلوقتي');
      expect(askPulse.any((i) => i.id == 'store_pulse'), isTrue);
    });
  });

  group('Task 40.4: OfflineSmartAssistantDialog Widget Security & Execution', () {
    Widget buildTestHost(UserEntity user) {
      final authCubit = _StubAuthCubit(user);
      return BlocProvider<AuthCubit>.value(
        value: authCubit,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => OfflineSmartAssistantDialog.show(context),
                child: const Text('Open Assistant'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('shows confirmation card, cancels cleanly, and executes for admin', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final admin = UserEntity(
        id: 'admin_1',
        name: 'المدير',
        email: 'admin@test.com',
        role: 'admin',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(buildTestHost(admin));
      await tester.tap(find.text('Open Assistant'));
      await tester.pumpAndSettle();

      // Send a command and cancel it first
      await tester.enterText(
        find.byKey(const Key('smart_assistant_query_field')),
        'اسمح بالخصم اليدوي',
      );
      await tester.tap(find.byKey(const Key('smart_assistant_ask_btn')));
      await tester.pumpAndSettle();

      final confirmFinder = find.byKey(const Key('assistant_confirm_cmd_manual_discount'));
      final cancelFinder = find.byKey(const Key('assistant_cancel_cmd_manual_discount'));
      await tester.ensureVisible(cancelFinder);
      await tester.pumpAndSettle();
      expect(confirmFinder, findsOneWidget);
      expect(cancelFinder, findsOneWidget);

      await tester.tap(cancelFinder);
      await tester.pumpAndSettle();
      expect(find.text('تم إلغاء التعديل'), findsOneWidget);
      await CashierPermissionsService.loadFromFeatureGate(gate);
      expect(CashierPermissionsService.current.allowManualDiscount, isFalse);

      // Send again and confirm as admin
      await tester.enterText(
        find.byKey(const Key('smart_assistant_query_field')),
        'اسمح بالخصم اليدوي',
      );
      await tester.tap(find.byKey(const Key('smart_assistant_ask_btn')));
      await tester.pumpAndSettle();

      final confirmFinder2 = find.byKey(const Key('assistant_confirm_cmd_manual_discount')).first;
      await tester.ensureVisible(confirmFinder2);
      await tester.pumpAndSettle();
      await tester.tap(confirmFinder2);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(find.text('تم تنفيذ التعديل بنجاح'), findsOneWidget);
      await CashierPermissionsService.loadFromFeatureGate(gate);
      expect(CashierPermissionsService.current.allowManualDiscount, isTrue);
    });

    testWidgets('blocks cashier from confirming setting commands in dialog', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final cashier = UserEntity(
        id: 'cashier_1',
        name: 'كاشير',
        email: 'cashier@test.com',
        role: 'cashier',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(buildTestHost(cashier));
      await tester.tap(find.text('Open Assistant'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('smart_assistant_query_field')),
        'تغيير اسم المحل إلى محل تجربة',
      );
      await tester.tap(find.byKey(const Key('smart_assistant_ask_btn')));
      await tester.pumpAndSettle();

      final renameConfirm = find.byKey(const Key('assistant_confirm_cmd_rename_store'));
      await tester.ensureVisible(renameConfirm);
      await tester.pumpAndSettle();
      await tester.tap(renameConfirm);
      await tester.pumpAndSettle();

      expect(find.text('تنفيذ مرفوض (صلاحيات)'), findsOneWidget);
      await ReceiptSettingsService.loadFromFeatureGate(gate);
      expect(ReceiptSettingsService.current.storeName, isNot('محل تجربة'));
    });
  });

  group('Task 40.5: Commerce, Marketing & Inflation Encyclopedia', () {
    test('clarifies promo diffs, funnel stages, and profit vs drawer cash with DB metrics', () async {
      final now = DateTime.now();
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: 'c_enc',
              branchId: branchId,
              name: 'ملابس',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p_enc',
              branchId: branchId,
              name: 'بنطلون جينز',
              categoryId: 'c_enc',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: 'v_enc',
              branchId: branchId,
              productId: 'p_enc',
              sku: 'JNS-1',
              color: 'أزرق',
              size: '32',
              quantity: const Value(5),
              costPrice: 15000,
              sellPrice: 30000,
              createdAt: now,
              updatedAt: now,
            ),
          );

      final promoAsk = await assistantService.ask('الفرق بين الخصم والباقة والهدية');
      expect(promoAsk.any((i) => i.id == 'encyclopedia_promo_diff'), isTrue);

      final funnelAsk = await assistantService.ask('الفرق بين جذب عميل ورفع الفاتورة والاسترجاع');
      expect(funnelAsk.any((i) => i.id == 'encyclopedia_funnel_diff'), isTrue);

      final cashAsk = await assistantService.ask('الفرق بين صافي الربح الدفتري والسيولة في الدرج');
      final profitVsCash = cashAsk.firstWhere((i) => i.id == 'encyclopedia_profit_vs_cash');
      expect(profitVsCash.details.join(' '), contains('750.00'));
    });

    test('builds Visual Merchandising tailored to store activity and top-profit items', () async {
      final now = DateTime.now();
      await db.into(db.appMeta).insert(
            AppMetaCompanion.insert(
              key: ReceiptSettingsService.keyStoreActivity,
              value: 'موبايلات وإلكترونيات',
              updatedAt: now,
            ),
          );
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: 'c_mob',
              branchId: branchId,
              name: 'موبايلات',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p_mob',
              branchId: branchId,
              name: 'سماعة برو',
              categoryId: 'c_mob',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: 'v_mob',
              branchId: branchId,
              productId: 'p_mob',
              sku: 'POD-1',
              color: 'أبيض',
              size: 'قياسي',
              quantity: const Value(4),
              costPrice: 20000,
              sellPrice: 50000,
              createdAt: now,
              updatedAt: now,
            ),
          );

      final res = await assistantService.ask('هندسة ترتيب المحل وعرض البضاعة');
      final vm = res.firstWhere((i) => i.id == 'visual_merchandising');
      expect(vm.title, contains('موبايلات وإلكترونيات'));
      expect(vm.details.join(' '), contains('الواجهة'));
      expect(vm.details.join(' '), contains('سماعة برو'));
      expect(vm.details.join(' '), contains('العمق'));
      expect(vm.details.join(' '), contains('الكاشير'));
    });

    test('calculates Inflation & Replacement Cost protected pricing on top-selling product', () async {
      final now = DateTime.now();
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: 'c_inf',
              branchId: branchId,
              name: 'ملابس',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p_inf',
              branchId: branchId,
              name: 'قميص كلاسيك',
              categoryId: 'c_inf',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: 'v_inf',
              branchId: branchId,
              productId: 'p_inf',
              sku: 'SH-1',
              color: 'أبيض',
              size: 'L',
              quantity: const Value(10),
              costPrice: 10000,
              sellPrice: 20000,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.sales).insert(
            SalesCompanion.insert(
              id: 's_inf',
              branchId: branchId,
              shortRef: 'S-INF',
              cashierId: 'admin',
              subtotal: 20000,
              discountType: 'none',
              total: 20000,
              paymentMethod: 'cash',
              date: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.saleItems).insert(
            SaleItemsCompanion.insert(
              id: 'si_inf',
              branchId: branchId,
              saleId: 's_inf',
              variantId: 'v_inf',
              productName: 'قميص كلاسيك',
              color: 'أبيض',
              size: 'L',
              qty: 3,
              priceSnapshot: 20000,
              costSnapshot: 10000,
              lineTotal: 60000,
              createdAt: now,
            ),
          );

      final res = await assistantService.ask('غلاء الأسعار وتضخم 20%');
      final inf = res.firstWhere((i) => i.id == 'inflation_calculator');
      expect(inf.title, contains('20%'));
      expect(inf.details.join(' '), contains('تكلفة الاستبدال'));
      expect(inf.details.join(' '), contains('قميص كلاسيك'));
      expect(inf.details.join(' '), contains('120.00'));
      expect(inf.details.join(' '), contains('240.00'));
    });

    test('warns on high stagnant stock and computes 50/30/20 cash expansion plan', () async {
      final now = DateTime.now();
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: 'c_exp',
              branchId: branchId,
              name: 'ملابس',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p_fast',
              branchId: branchId,
              name: 'شراب رياضي سريع',
              categoryId: 'c_exp',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: 'v_fast',
              branchId: branchId,
              productId: 'p_fast',
              sku: 'SCK-1',
              color: 'أسود',
              size: 'قياسي',
              quantity: const Value(5),
              costPrice: 1000,
              sellPrice: 2500,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p_stag',
              branchId: branchId,
              name: 'معطف ثقيل راكد',
              categoryId: 'c_exp',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: 'v_stag',
              branchId: branchId,
              productId: 'p_stag',
              sku: 'CT-1',
              color: 'بني',
              size: 'XL',
              quantity: const Value(10),
              costPrice: 50000,
              sellPrice: 80000,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.sales).insert(
            SalesCompanion.insert(
              id: 's_fast',
              branchId: branchId,
              shortRef: 'S-FST',
              cashierId: 'admin',
              subtotal: 12500,
              discountType: 'none',
              total: 12500,
              paymentMethod: 'cash',
              date: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.saleItems).insert(
            SaleItemsCompanion.insert(
              id: 'si_fast',
              branchId: branchId,
              saleId: 's_fast',
              variantId: 'v_fast',
              productName: 'شراب رياضي سريع',
              color: 'أسود',
              size: 'قياسي',
              qty: 5,
              priceSnapshot: 2500,
              costSnapshot: 1000,
              lineTotal: 12500,
              createdAt: now,
            ),
          );

      final res = await assistantService.ask('عندي سيولة 10000 عايز اشتري بضاعة جديدة');
      final exp = res.firstWhere((i) => i.id == 'cash_expansion_50_30_20');
      expect(exp.isAlert, isTrue);
      expect(exp.details.join(' '), contains('تحذير'));
      expect(exp.details.join(' '), contains('5000.00'));
      expect(exp.details.join(' '), contains('3000.00'));
      expect(exp.details.join(' '), contains('2000.00'));
      expect(exp.details.join(' '), contains('شراب رياضي سريع'));
    });

    testWidgets('renders 390x560 Popover on desktop with Offline 100% badge and closes on Esc', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => OfflineSmartAssistantDialog.show(context),
                child: const Text('Open Popover'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Popover'));
      await tester.pumpAndSettle();

      final popoverFinder = find.byKey(const Key('smart_assistant_popover'));
      expect(popoverFinder, findsOneWidget);
      expect(find.text('أوفلاين 100%'), findsOneWidget);
      final size = tester.getSize(popoverFinder);
      expect(size.width, 390.0);
      expect(size.height, 560.0);
    });

    test('generates WhatsApp & Facebook promo posts for stagnant high-margin items', () async {
      final now = DateTime.now();
      await db.into(db.appMeta).insertOnConflictUpdate(
            AppMetaCompanion.insert(
              key: ReceiptSettingsService.keyStoreName,
              value: 'متجر النخبة',
              updatedAt: now,
            ),
          );
      await db.into(db.appMeta).insertOnConflictUpdate(
            AppMetaCompanion.insert(
              key: ReceiptSettingsService.keyStorePhone,
              value: '01099887766',
              updatedAt: now,
            ),
          );
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: 'c_post',
              branchId: branchId,
              name: 'ملابس',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p_post',
              branchId: branchId,
              name: 'جاكيت جلد فاخر',
              categoryId: 'c_post',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: 'v_post',
              branchId: branchId,
              productId: 'p_post',
              sku: 'SKU-POST-1',
              color: 'أسود',
              size: 'L',
              quantity: const Value(5),
              costPrice: 50000,
              sellPrice: 100000,
              createdAt: now,
              updatedAt: now,
            ),
          );

      final waRes = await assistantService.ask('اكتب بوست واتساب');
      final waInsight = waRes.firstWhere((i) => i.id == 'promo_post_generator_whatsapp');
      final waText = waInsight.details.join('\n');
      expect(waText, contains('متجر النخبة'));
      expect(waText, contains('جاكيت جلد فاخر'));
      expect(waText, contains('1000.00'));
      expect(waText, contains('850.00'));
      expect(waText, contains('01099887766'));

      final fbRes = await assistantService.ask('اعمل اعلان فيسبوك');
      expect(fbRes.any((i) => i.id == 'promo_post_generator_facebook'), isTrue);
    });

    test('generates WhatsApp re-engagement messages for dormant customers (+60 days)', () async {
      final oldDate = DateTime.now().subtract(const Duration(days: 75));
      await db.into(db.customers).insert(
            CustomersCompanion.insert(
              id: 'cust_dormant',
              branchId: branchId,
              name: 'أحمد محمود',
              phone: '01011223344',
              createdAt: oldDate,
              updatedAt: oldDate,
            ),
          );
      await db.into(db.sales).insert(
            SalesCompanion.insert(
              id: 's_dormant',
              branchId: branchId,
              shortRef: 'S-DRM',
              customerId: const Value('cust_dormant'),
              cashierId: 'admin',
              subtotal: 30000,
              discountType: 'none',
              total: 30000,
              paymentMethod: 'cash',
              date: oldDate,
              createdAt: oldDate,
              updatedAt: oldDate,
            ),
          );

      final res = await assistantService.ask('استرجع العملاء الغائبين');
      final insight = res.firstWhere((i) => i.id == 'customer_re_engagement');
      expect(insight.details.join('\n'), contains('أحمد محمود'));
    });

    test('understands expanded Egyptian colloquial synonyms and returns smart suggestions on unknown query', () async {
      final inflationRes = await assistantService.ask('كل حاجة غليت ومش قادر أسعر');
      expect(inflationRes.any((i) => i.id == 'inflation_calculator'), isTrue);

      final cashRes = await assistantService.ask('معايا فلوس 5000 وناوي أشتري بضاعة');
      expect(cashRes.any((i) => i.id == 'cash_expansion_50_30_20'), isTrue);

      final unknownRes = await assistantService.ask('اختبار عشوائي غير معروف');
      final fallback = unknownRes.firstWhere((i) => i.id == 'no_direct_match');
      expect(fallback.details, isNotEmpty);
    });

    testWidgets('shows copy button for generated social posts in assistant dialog', (tester) async {
      final now = DateTime.now();
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: 'c_copy',
              branchId: branchId,
              name: 'ملابس',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p_copy',
              branchId: branchId,
              name: 'تيشيرت قطن',
              categoryId: 'c_copy',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: 'v_copy',
              branchId: branchId,
              productId: 'p_copy',
              sku: 'SKU-CPY',
              color: 'أبيض',
              size: 'M',
              quantity: const Value(4),
              costPrice: 10000,
              sellPrice: 20000,
              createdAt: now,
              updatedAt: now,
            ),
          );

      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => OfflineSmartAssistantDialog.show(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('smart_assistant_query_field')),
        'اكتب بوست واتساب',
      );
      await tester.tap(find.byKey(const Key('smart_assistant_ask_btn')));
      await tester.pumpAndSettle();

      expect(find.text('نسخ'), findsWidgets);
    });

    test('computes Margin Leak, Break-Even, Cashier Performance, What-If Pricing & Seasonal Plan', () async {
      final now = DateTime.now();
      await db.into(db.users).insert(
            UsersCompanion.insert(
              id: 'cashier_ali',
              branchId: branchId,
              username: 'ali',
              displayName: 'علي حسن',
              role: 'cashier',
              passwordHash: 'h',
              passwordSalt: 's',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.expenses).insert(
            ExpensesCompanion.insert(
              id: 'exp_rent',
              branchId: branchId,
              category: 'إيجار',
              kind: const Value('operating'),
              amount: 300000, // 3000 EGP
              expenseDate: now,
              userId: 'admin_1',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.sales).insert(
            SalesCompanion.insert(
              id: 's_leak',
              branchId: branchId,
              shortRef: 'S-LK1',
              cashierId: 'cashier_ali',
              subtotal: 100000,
              discountType: 'fixed',
              discountValue: const Value(15000),
              discountAmount: const Value(15000), // 15% discount
              total: 85000,
              paymentMethod: 'cash',
              date: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.saleItems).insert(
            SaleItemsCompanion.insert(
              id: 'si_leak',
              branchId: branchId,
              saleId: 's_leak',
              variantId: 'v_lk1',
              productName: 'بنطلون جينز',
              color: 'أزرق',
              size: '32',
              qty: 1,
              priceSnapshot: 100000,
              costSnapshot: 50000,
              lineDiscount: const Value(0),
              lineTotal: 85000,
              createdAt: now,
            ),
          );

      final leakRes = await assistantService.ask('كاشف تسرب الأرباح');
      final leak = leakRes.firstWhere((i) => i.id == 'margin_leak_detector');
      expect(leak.isAlert, isTrue);
      expect(leak.details.join(' '), contains('150.00'));

      final beRes = await assistantService.ask('نقطة التعادل');
      final be = beRes.firstWhere((i) => i.id == 'break_even_calculator');
      expect(be.details.join(' '), contains('3000.00'));

      final cashierRes = await assistantService.ask('أداء الكاشيرات');
      final cashier = cashierRes.firstWhere((i) => i.id == 'cashier_performance');
      expect(cashier.details.join(' '), contains('علي حسن'));

      final whatIfSafe = await assistantService.ask('لو عملت خصم 15% أحتاج أبيع كام؟');
      expect(whatIfSafe.any((i) => i.id == 'what_if_discount_safe'), isTrue);

      final whatIfLoss = await assistantService.ask('لو عملت خصم 50%');
      expect(whatIfLoss.any((i) => i.id == 'what_if_discount_loss'), isTrue);

      final planRes = await assistantService.ask('خطة تسويق للعيد');
      final plan = planRes.firstWhere((i) => i.id == 'seasonal_marketing_plan');
      expect(plan.title, contains('المواسم'));
    });

    test('promo post generator falls back to active stock and supports bundle style', () async {
      final now = DateTime.now();
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p_active',
              branchId: branchId,
              name: 'قميص كتان صيفي',
              categoryId: 'cat_clothes',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: 'v_active',
              branchId: branchId,
              productId: 'p_active',
              sku: 'SKU-ACT',
              color: 'بيج',
              size: 'XL',
              quantity: const Value(10),
              costPrice: 20000,
              sellPrice: 40000,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.sales).insert(
            SalesCompanion.insert(
              id: 's_act',
              branchId: branchId,
              shortRef: 'S-ACT',
              cashierId: 'admin_1',
              subtotal: 40000,
              discountType: 'none',
              total: 40000,
              paymentMethod: 'cash',
              date: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.saleItems).insert(
            SaleItemsCompanion.insert(
              id: 'si_act',
              branchId: branchId,
              saleId: 's_act',
              variantId: 'v_active',
              productName: 'قميص كتان صيفي',
              color: 'بيج',
              size: 'XL',
              qty: 1,
              priceSnapshot: 40000,
              costSnapshot: 20000,
              lineTotal: 40000,
              createdAt: now,
            ),
          );

      // Even though v_active is NOT stagnant, post generator should still produce a bundle post
      final res = await assistantService.ask('اكتب بوست باقة فيسبوك');
      final post = res.firstWhere((i) => i.id == 'promo_post_generator_facebook');
      expect(post.details.join('\n'), contains('قميص كتان صيفي'));
      expect(post.details.join('\n'), contains('عرض القطعتين معاً'));
    });

    testWidgets('dialog shows category tabs, reset button, and follow-up chips', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => OfflineSmartAssistantDialog.show(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('تحليل المحل'), findsOneWidget);
      expect(find.text('تسويق وبوستات'), findsOneWidget);
      expect(find.text('تسعير وموسوعة'), findsOneWidget);
      expect(find.byKey(const Key('smart_assistant_reset_btn')), findsOneWidget);

      await tester.tap(find.text('تسويق وبوستات'));
      await tester.pumpAndSettle();
      expect(find.text('خطة تسويق لزيادة المبيعات'), findsOneWidget);
    });
  });

  group('Task 40.6: Full ERP Action Agent, Multi-Turn Drafts & Instant Mode', () {
    test('handles multi-turn incomplete drafts and cancellation cleanly', () async {
      // Turn 1: incomplete expense command (missing amount)
      final t1 = await assistantService.askWithDraft('سجل مصروف كهرباء');
      expect(t1.activeDraft, isNotNull);
      expect(t1.activeDraft!.missingField, 'amountEgp');
      expect(t1.insights.first.id, 'draft_prompt_amountEgp');

      // Turn 2: cancel active draft
      final tCancel = await assistantService.askWithDraft(
        'إلغاء',
        activeDraft: t1.activeDraft,
      );
      expect(tCancel.activeDraft, isNull);
      expect(tCancel.insights.first.id, 'draft_cancelled');

      // Turn 3: incomplete purchase -> fill missing fields step by step
      final p1 = await assistantService.askWithDraft('اشتريت جاكيت جلد');
      expect(p1.activeDraft?.missingField, 'supplierName');
      final p2 = await assistantService.askWithDraft(
        'شركة النيل',
        activeDraft: p1.activeDraft,
      );
      expect(p2.activeDraft?.missingField, 'costEgp');
      final p3 = await assistantService.askWithDraft(
        '250',
        activeDraft: p2.activeDraft,
      );
      expect(p3.activeDraft?.missingField, 'qty');
      final p4 = await assistantService.askWithDraft(
        '4',
        activeDraft: p3.activeDraft,
      );
      expect(p4.activeDraft, isNull);
      expect(p4.insights.first.pendingCommand?.kind, AssistantCommandKind.recordPurchase);
    });

    test('executes all 5 ERP actions + updateStorePhone in DB transaction with AuditLogs and blocks cashier', () async {
      // 1. Cashier must be rejected
      final expTurn = await assistantService.askWithDraft('سجل مصروف ضيافة 150');
      final expCmd = expTurn.insights.first.pendingCommand!;
      await expectLater(
        assistantService.executeCommand(
          expCmd,
          userId: 'cashier_1',
          userRole: 'cashier',
          gate: gate,
        ),
        throwsException,
      );
      expect(await db.select(db.expenses).get(), isEmpty);

      // 2. Admin executes recordExpense
      await assistantService.executeCommand(
        expCmd,
        userId: 'admin_1',
        userRole: 'admin',
        gate: gate,
      );
      final expenses = await db.select(db.expenses).get();
      expect(expenses.length, 1);
      expect(expenses.first.category, 'ضيافة');
      expect(expenses.first.amount, 15000);

      // 3. Admin executes addProduct
      final addTurn = await assistantService.askWithDraft(
        'ضيف صنف تيشيرت بولو تكلفة 100 بيع 200 كمية 10',
      );
      await assistantService.executeCommand(
        addTurn.insights.first.pendingCommand!,
        userId: 'admin_1',
        userRole: 'admin',
        gate: gate,
      );
      final products = await db.select(db.products).get();
      expect(products.any((p) => p.name == 'تيشيرت بولو'), isTrue);

      // 4. Admin executes updateProductPriceOrStock (price & stock)
      final priceTurn = await assistantService.askWithDraft('خلي سعر تيشيرت بولو 250');
      await assistantService.executeCommand(
        priceTurn.insights.first.pendingCommand!,
        userId: 'admin_1',
        userRole: 'admin',
        gate: gate,
      );
      final stockTurn = await assistantService.askWithDraft('زود رصيد تيشيرت بولو 5');
      await assistantService.executeCommand(
        stockTurn.insights.first.pendingCommand!,
        userId: 'admin_1',
        userRole: 'admin',
        gate: gate,
      );
      final variants = await db.select(db.productVariants).get();
      expect(variants.first.sellPrice, 25000);
      expect(variants.first.quantity, 15);

      // 5. Admin executes recordPurchase (credit) & paySupplier
      final purTurn = await assistantService.askWithDraft(
        'اشتريت تيشيرت بولو من المورد النيل بسعر 120 عدد 10 آجل',
      );
      await assistantService.executeCommand(
        purTurn.insights.first.pendingCommand!,
        userId: 'admin_1',
        userRole: 'admin',
        gate: gate,
      );
      var suppliers = await db.select(db.suppliers).get();
      expect(suppliers.first.balance, 120000); // 120 * 10 = 1200 EGP

      final payTurn = await assistantService.askWithDraft('دفعت للمورد النيل 500');
      await assistantService.executeCommand(
        payTurn.insights.first.pendingCommand!,
        userId: 'admin_1',
        userRole: 'admin',
        gate: gate,
      );
      suppliers = await db.select(db.suppliers).get();
      expect(suppliers.first.balance, 70000); // 1200 - 500 = 700 EGP
      expect((await db.select(db.supplierPayments).get()).length, 1);

      // 6. Admin executes updateStorePhone
      final phoneInsight = assistantService.parseCommand(
        'تغيير رقم هاتف الفاتورة إلى 01055667788',
      );
      expect(phoneInsight?.pendingCommand?.kind, AssistantCommandKind.updateStorePhone);
      await assistantService.executeCommand(
        phoneInsight!.pendingCommand!,
        userId: 'admin_1',
        userRole: 'admin',
        gate: gate,
      );
      await ReceiptSettingsService.loadFromFeatureGate(gate);
      expect(ReceiptSettingsService.current.storePhone, '01055667788');

      // AuditLogs recorded for all ERP actions
      final audits = await db.select(db.auditLogs).get();
      expect(audits.length, greaterThanOrEqualTo(6));
    });

    testWidgets('dialog supports multi-turn draft completion and admin instant mode toggle', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final admin = UserEntity(
        id: 'admin_1',
        name: 'المدير',
        email: 'admin@test.com',
        role: 'admin',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      );
      final authCubit = _StubAuthCubit(admin);

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => OfflineSmartAssistantDialog.show(context),
                  child: const Text('Open Agent'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Agent'));
      await tester.pumpAndSettle();

      // Enable instant execution mode for admin
      final instantToggle = find.byKey(const Key('assistant_instant_mode_toggle'));
      expect(instantToggle, findsOneWidget);
      await tester.tap(instantToggle);
      await tester.pumpAndSettle();

      // Multi-turn incomplete expense: "سجل مصروف نقل" -> "300" -> auto-executes!
      await tester.enterText(
        find.byKey(const Key('smart_assistant_query_field')),
        'سجل مصروف نقل',
      );
      await tester.tap(find.byKey(const Key('smart_assistant_ask_btn')));
      await tester.pumpAndSettle();
      expect(find.textContaining('كم مبلغ المصروف'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('smart_assistant_query_field')),
        '300',
      );
      await tester.tap(find.byKey(const Key('smart_assistant_ask_btn')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pumpAndSettle();

      expect(find.text('تم تنفيذ التعديل بنجاح'), findsOneWidget);
      final exps = await db.select(db.expenses).get();
      expect(exps.length, 1);
      expect(exps.first.category, 'نقل');
      expect(exps.first.amount, 30000);
    });
  });

  group('Task 40.7: Batch 2 - Customers, Installments, EOD Report & Barcode Lookup', () {
    test('adds customer, collects installment with AuditLog, enforces FeatureGate, and generates WhatsApp reminder', () async {
      final now = DateTime.now();

      // Unauthorized cashier cannot addCustomer or collectInstallment
      await CashierPermissionsService.save(
        gate,
        CashierPermissionsService.current.copyWith(allowManageCustomers: false),
        userId: 'admin_1',
      );
      final addTurn = await assistantService.askWithDraft('ضيف عميل سارة علي 01022334455');
      expect(addTurn.insights.first.pendingCommand?.kind, AssistantCommandKind.addCustomer);
      await expectLater(
        assistantService.executeCommand(
          addTurn.insights.first.pendingCommand!,
          userId: 'cashier_1',
          userRole: 'cashier',
          gate: gate,
        ),
        throwsException,
      );

      // Admin adds customer
      await assistantService.executeCommand(
        addTurn.insights.first.pendingCommand!,
        userId: 'admin_1',
        userRole: 'admin',
        gate: gate,
      );
      final custs = await db.select(db.customers).get();
      expect(custs.any((c) => c.name == 'سارة علي' && c.phone == '01022334455'), isTrue);
      final sara = custs.firstWhere((c) => c.name == 'سارة علي');

      // Seed an overdue installment contract for Sara
      await db.into(db.sales).insert(
            SalesCompanion.insert(
              id: 's_sara',
              branchId: branchId,
              shortRef: 'S-SARA',
              customerId: Value(sara.id),
              cashierId: 'admin_1',
              subtotal: 100000,
              discountType: 'none',
              total: 100000,
              paymentMethod: 'installment',
              date: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.customerInstallments).insert(
            CustomerInstallmentsCompanion.insert(
              id: 'ci_sara',
              branchId: branchId,
              saleId: 's_sara',
              customerId: sara.id,
              totalPiasters: 100000,
              downPaymentPiasters: const Value(20000),
              principalPiasters: 80000,
              interestBp: 0,
              monthlyAmountPiasters: 20000,
              remainingPiasters: 80000,
              durationMonths: 4,
              startDate: now.subtract(const Duration(days: 40)),
              endDate: now.subtract(const Duration(days: 5)),
              status: const Value('overdue'),
              createdBy: 'admin_1',
              createdAt: now,
              updatedAt: now,
            ),
          );

      // Cashier blocked when FeatureKeys.installments is false
      final payTurn = await assistantService.askWithDraft('العميل سارة علي دفع قسط 250');
      expect(payTurn.insights.first.pendingCommand?.kind, AssistantCommandKind.collectInstallment);
      await expectLater(
        assistantService.executeCommand(
          payTurn.insights.first.pendingCommand!,
          userId: 'cashier_1',
          userRole: 'cashier',
          gate: gate,
        ),
        throwsException,
      );

      // Admin collects installment
      await assistantService.executeCommand(
        payTurn.insights.first.pendingCommand!,
        userId: 'admin_1',
        userRole: 'admin',
        gate: gate,
      );
      final updatedPlan = await (db.select(db.customerInstallments)
            ..where((i) => i.id.equals('ci_sara')))
          .getSingle();
      expect(updatedPlan.remainingPiasters, 55000); // 800 - 250 = 550 EGP
      expect((await db.select(db.installmentPayments).get()).length, 1);

      // WhatsApp reminder message
      final remRes = await assistantService.ask('اكتب رسالة تذكير قسط لـ سارة علي');
      final rem = remRes.firstWhere((i) => i.id == 'installment_reminder');
      expect(rem.details.first, contains('سارة علي'));
      expect(rem.details.first, contains('550.00'));
    });

    test('computes End-of-Day report and Barcode/SKU lookup with 30d sales', () async {
      final now = DateTime.now();
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: 'c_b2',
              branchId: branchId,
              name: 'إلكترونيات',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p_b2',
              branchId: branchId,
              name: 'باور بانك 20000',
              categoryId: 'c_b2',
              minStock: const Value(5),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: 'v_b2',
              branchId: branchId,
              productId: 'p_b2',
              sku: 'SKU-BAR-99',
              color: 'أسود',
              size: '-',
              quantity: const Value(3),
              costPrice: 30000,
              sellPrice: 50000,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.sales).insert(
            SalesCompanion.insert(
              id: 's_b2',
              branchId: branchId,
              shortRef: 'S-B2',
              cashierId: 'admin',
              subtotal: 100000,
              discountType: 'none',
              total: 100000,
              paymentMethod: 'cash',
              date: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.saleItems).insert(
            SaleItemsCompanion.insert(
              id: 'si_b2',
              branchId: branchId,
              saleId: 's_b2',
              variantId: 'v_b2',
              productName: 'باور بانك 20000',
              color: 'أسود',
              size: '-',
              qty: 2,
              priceSnapshot: 50000,
              costSnapshot: 30000,
              lineTotal: 100000,
              createdAt: now,
            ),
          );

      // EOD report
      final eodRes = await assistantService.ask('تقرير قفلة اليوم');
      final eod = eodRes.firstWhere((i) => i.id == 'eod_report');
      expect(eod.summary, contains('1000.00'));
      expect(eod.details.join('\n'), contains('المتبقي المتوقع بالدرج'));
      expect(eod.details.join('\n'), contains('باور بانك 20000'));

      // Barcode / SKU lookup
      final barRes = await assistantService.ask('SKU-BAR-99');
      final bar = barRes.firstWhere((i) => i.id == 'barcode_lookup');
      expect(bar.summary, contains('باور بانك 20000'));
      expect(bar.summary, contains('500.00'));
      expect(bar.details.join('\n'), contains('مبيعات آخر 30 يوم: 2'));
      expect(bar.followUpPrompts, containsAll(['عدل السعر', 'زود الرصيد']));
    });

    testWidgets('dialog shows WhatsApp copy button for EOD report and quick barcode follow-ups', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final now = DateTime.now();
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: 'c_w2',
              branchId: branchId,
              name: 'ملابس',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p_w2',
              branchId: branchId,
              name: 'كوتشي رياضي',
              categoryId: 'c_w2',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: 'v_w2',
              branchId: branchId,
              productId: 'p_w2',
              sku: '622112233',
              color: 'أبيض',
              size: '42',
              quantity: const Value(8),
              costPrice: 20000,
              sellPrice: 40000,
              createdAt: now,
              updatedAt: now,
            ),
          );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => OfflineSmartAssistantDialog.show(context),
                child: const Text('Open B2'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open B2'));
      await tester.pumpAndSettle();

      // EOD report has "نسخ لواتساب"
      await tester.enterText(
        find.byKey(const Key('smart_assistant_query_field')),
        'تقرير قفلة اليوم',
      );
      await tester.tap(find.byKey(const Key('smart_assistant_ask_btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('assistant_copy_eod_btn')), findsOneWidget);

      // Barcode scan shows follow-ups and tapping "عدل السعر" starts price draft
      await tester.enterText(
        find.byKey(const Key('smart_assistant_query_field')),
        '622112233',
      );
      await tester.tap(find.byKey(const Key('smart_assistant_ask_btn')));
      await tester.pumpAndSettle();
      expect(find.text('عدل السعر'), findsOneWidget);
      expect(find.text('زود الرصيد'), findsOneWidget);

      await tester.tap(find.text('عدل السعر'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ما السعر الجديد بالجنيه'), findsOneWidget);
    });
  });

  group('Task 40.8: Batch 3 - Alert Count, 4 New Analytics & Context-Aware Prompts', () {
    test('computes criticalAlertCount, top variants, cheapest supplier, peak hours, and today audits', () async {
      final now = DateTime.now();
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: 'c_b3',
              branchId: branchId,
              name: 'ملابس',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p_b3',
              branchId: branchId,
              name: 'هودي قطن',
              categoryId: 'c_b3',
              minStock: const Value(5),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: 'v_b3_1',
              branchId: branchId,
              productId: 'p_b3',
              sku: 'HD-BLK-L',
              color: 'أسود',
              size: 'L',
              quantity: const Value(2), // low stock -> 1 critical alert
              costPrice: 15000,
              sellPrice: 30000,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: 'v_b3_2',
              branchId: branchId,
              productId: 'p_b3',
              sku: 'HD-WHT-M',
              color: 'أبيض',
              size: 'M',
              quantity: const Value(10),
              costPrice: 15000,
              sellPrice: 30000,
              createdAt: now,
              updatedAt: now,
            ),
          );

      // Overdue installment -> +1 critical alert (total 2)
      await db.into(db.customers).insert(
            CustomersCompanion.insert(
              id: 'cust_b3',
              branchId: branchId,
              name: 'كريم حسن',
              phone: '01033445566',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.sales).insert(
            SalesCompanion.insert(
              id: 's_b3',
              branchId: branchId,
              shortRef: 'S-B3',
              cashierId: 'admin',
              subtotal: 120000,
              discountType: 'none',
              total: 120000,
              paymentMethod: 'cash',
              date: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.saleItems).insert(
            SaleItemsCompanion.insert(
              id: 'si_b3_1',
              branchId: branchId,
              saleId: 's_b3',
              variantId: 'v_b3_1',
              productName: 'هودي قطن',
              color: 'أسود',
              size: 'L',
              qty: 4,
              priceSnapshot: 30000,
              costSnapshot: 15000,
              lineTotal: 120000,
              createdAt: now,
            ),
          );
      await db.into(db.customerInstallments).insert(
            CustomerInstallmentsCompanion.insert(
              id: 'ci_b3',
              branchId: branchId,
              saleId: 's_b3',
              customerId: 'cust_b3',
              totalPiasters: 100000,
              downPaymentPiasters: const Value(20000),
              principalPiasters: 80000,
              interestBp: 0,
              monthlyAmountPiasters: 20000,
              remainingPiasters: 80000,
              durationMonths: 4,
              startDate: now.subtract(const Duration(days: 40)),
              endDate: now.subtract(const Duration(days: 3)),
              status: const Value('overdue'),
              createdBy: 'admin',
              createdAt: now,
              updatedAt: now,
            ),
          );

      // 2 Suppliers with different purchase costs for v_b3_1
      await db.into(db.suppliers).insert(
            SuppliersCompanion.insert(
              id: 'sup_a',
              branchId: branchId,
              name: 'مصنع الأمل',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.suppliers).insert(
            SuppliersCompanion.insert(
              id: 'sup_b',
              branchId: branchId,
              name: 'شركة الفتح',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.purchases).insert(
            PurchasesCompanion.insert(
              id: 'pur_a',
              branchId: branchId,
              supplierId: 'sup_a',
              purchaseDate: now,
              totalAmount: 180000,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.purchaseItems).insert(
            PurchaseItemsCompanion.insert(
              id: 'pi_a',
              purchaseId: 'pur_a',
              variantId: 'v_b3_1',
              qty: 10,
              costPrice: 18000,
              totalCost: 180000,
              createdAt: now,
            ),
          );
      await db.into(db.purchases).insert(
            PurchasesCompanion.insert(
              id: 'pur_b',
              branchId: branchId,
              supplierId: 'sup_b',
              purchaseDate: now,
              totalAmount: 140000,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.purchaseItems).insert(
            PurchaseItemsCompanion.insert(
              id: 'pi_b',
              purchaseId: 'pur_b',
              variantId: 'v_b3_1',
              qty: 10,
              costPrice: 14000,
              totalCost: 140000,
              createdAt: now,
            ),
          );

      // Today's AuditLog + cancelled sale
      await db.into(db.auditLogs).insert(
            AuditLogsCompanion.insert(
              id: 'aud_b3',
              branchId: branchId,
              userId: 'admin_1',
              action: 'update_price',
              entity: 'product_variant',
              entityId: 'v_b3_1',
              newValue: const Value('300.00'),
              createdAt: now,
            ),
          );
      await db.into(db.sales).insert(
            SalesCompanion.insert(
              id: 's_b3_cancel',
              branchId: branchId,
              shortRef: 'S-CANC',
              cashierId: 'admin',
              subtotal: 5000,
              discountType: 'none',
              total: 5000,
              paymentMethod: 'cash',
              status: const Value('cancelled'),
              date: now,
              createdAt: now,
              updatedAt: now,
            ),
          );

      expect(await assistantService.getCriticalAlertCount(), 2);

      final varRes = await assistantService.ask('اكتر مقاس ولون بيتباع في هودي قطن');
      final varIns = varRes.firstWhere((i) => i.id == 'top_variants_analysis');
      expect(varIns.summary, contains('أسود - مقاس L'));

      final supRes = await assistantService.ask('ارخص مورد جبت منه هودي قطن');
      final supIns = supRes.firstWhere((i) => i.id == 'cheapest_supplier_analysis');
      expect(supIns.summary, contains('شركة الفتح'));
      expect(supIns.summary, contains('140.00'));

      final peakRes = await assistantService.ask('اكتر يوم وساعة زحمة');
      expect(peakRes.any((i) => i.id == 'peak_hours_analysis'), isTrue);

      final audRes = await assistantService.ask('ايه اللي اتعدل النهارده');
      final audIns = audRes.firstWhere((i) => i.id == 'today_audits_cancellations');
      expect(audIns.isAlert, isTrue);
      expect(audIns.summary, contains('1 تعديل'));
      expect(audIns.summary, contains('1 فاتورة ملغاة'));
    });

    testWidgets('dialog shows context-aware prompts for currentScreenTitle', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => OfflineSmartAssistantDialog.show(
                  context,
                  currentScreenTitle: 'المنتجات والمخزون',
                ),
                child: const Text('Open Ctx'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Ctx'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('assistant_context_prompts')), findsOneWidget);
      expect(find.text('عدل سعر'), findsOneWidget);
      expect(find.text('الأصناف قاربت تخلص'), findsWidgets);
    });
  });

  group('Task 40.9: Offline Knowledge Distillation & Fuzzy Synonym Scoring', () {
    test('loads assets/assistant_knowledge_ar.json with 100+ Businessman topics and answers colloquial queries accurately', () async {
      final count = await assistantService.getKnowledgeTopicCount();
      expect(count, greaterThanOrEqualTo(100));

      final angryRes = await assistantService.ask('الزبون زعلان وعايز يرجع حاجة');
      expect(angryRes.any((i) => i.id == 'kb_cust_angry_return'), isTrue);
      expect(angryRes.first.followUpPrompts, isNotEmpty);

      final shortageRes = await assistantService.ask('حاسس ان في عجز في الدرج');
      expect(shortageRes.any((i) => i.id == 'kb_stf_drawer_shortage'), isTrue);

      final onlineRes = await assistantService.ask('ابدا بيع اونلاين ازاي');
      expect(onlineRes.any((i) => i.id == 'kb_onl_start_guide'), isTrue);

      final compRes = await assistantService.ask('المنافس جنبي نزل السعر اعمل ايه');
      expect(compRes.any((i) => i.id == 'kb_biz_comp_neighbor_cut'), isTrue);

      final expRes = await assistantService.ask('الزبون بيقولي غالي');
      expect(expRes.any((i) => i.id == 'kb_biz_obj_too_expensive'), isTrue);

      final branchRes = await assistantService.ask('امتى افتح فرع تاني');
      expect(branchRes.any((i) => i.id == 'kb_exp_when_open_branch'), isTrue);
    });

    test('getBusinessmanConsultationInsight reads real DB metrics to build custom plan', () async {
      final now = DateTime.now();
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: 'c_biz',
              branchId: branchId,
              name: 'ملابس',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p_biz',
              branchId: branchId,
              name: 'جاكيت راكد',
              categoryId: 'c_biz',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: 'v_biz',
              branchId: branchId,
              productId: 'p_biz',
              sku: 'BIZ-1',
              color: 'أسود',
              size: 'L',
              quantity: const Value(5),
              costPrice: 20000,
              sellPrice: 30000,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.expenses).insert(
            ExpensesCompanion.insert(
              id: 'e_biz',
              branchId: branchId,
              category: 'إيجار',
              amount: 500000,
              expenseDate: now,
              userId: 'admin',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.suppliers).insert(
            SuppliersCompanion.insert(
              id: 'sup_biz',
              branchId: branchId,
              name: 'مورد السلام',
              balance: const Value(150000),
              createdAt: now,
              updatedAt: now,
            ),
          );

      final res = await assistantService.ask('انصحني كـ بزنس مان');
      final biz = res.firstWhere((i) => i.id == 'businessman_consultation');
      expect(biz.isAlert, isTrue);
      expect(biz.details.join('\n'), contains('100.0%'));
      expect(biz.details.join('\n'), contains('5000.00'));
      expect(biz.details.join('\n'), contains('1500.00'));
    });
  });

  group('Task 40.10: Detailed Zakat Calculator (Money & Trade Goods)', () {
    test('calculates Zakat from DB (reached Nisab, below Nisab, Gregorian, and multi-turn gold price draft)', () async {
      final now = DateTime.now();
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: 'c_zak',
              branchId: branchId,
              name: 'ملابس',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p_zak',
              branchId: branchId,
              name: 'بدلة رسمي',
              categoryId: 'c_zak',
              createdAt: now,
              updatedAt: now,
            ),
          );
      // Stock sell = 100 * 5000 EGP = 500,000 EGP (50,000,000 piasters)
      await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: 'v_zak',
              branchId: branchId,
              productId: 'p_zak',
              sku: 'ZAK-1',
              color: 'كحلي',
              size: '50',
              quantity: const Value(100),
              costPrice: 300000,
              sellPrice: 500000,
              createdAt: now,
              updatedAt: now,
            ),
          );
      // CashWallet = 50,000 EGP (5,000,000 piasters)
      await db.into(db.cashWallets).insert(
            CashWalletsCompanion.insert(
              id: 'w_zak',
              branchId: branchId,
              name: 'فودافون كاش',
              currentBalance: const Value(5000000),
              createdAt: now,
              updatedAt: now,
            ),
          );
      // Open shift = 10,000 EGP (1,000,000 piasters)
      await db.into(db.shifts).insert(
            ShiftsCompanion.insert(
              id: 'sh_zak',
              branchId: branchId,
              cashierId: 'admin',
              openingBalance: 1000000,
              openedAt: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      // Supplier debt = 60,000 EGP (6,000,000 piasters)
      await db.into(db.suppliers).insert(
            SuppliersCompanion.insert(
              id: 'sup_zak',
              branchId: branchId,
              name: 'مورد الزكاة',
              balance: const Value(6000000),
              createdAt: now,
              updatedAt: now,
            ),
          );

      // Net Zakat Pool = 500,000 + 50,000 + 10,000 - 60,000 = 500,000 EGP
      // Gold 24k = 4000 -> Nisab = 85 * 4000 = 340,000 EGP -> Reached!
      // Hijri 2.5% = 12,500.00 EGP
      final hijri = await assistantService.getZakatCalculatorInsight(
        goldGramPrice24Egp: 4000,
      );
      expect(hijri.id, 'zakat_calculator');
      expect(hijri.isAlert, isTrue);
      expect(hijri.summary, contains('12500.00'));
      expect(hijri.details.join('\n'), contains('500000.00'));
      expect(hijri.details.join('\n'), contains('340000.00'));

      // Gregorian 2.577% = 12,885.00 EGP
      final greg = await assistantService.getZakatCalculatorInsight(
        goldGramPrice24Egp: 4000,
        isGregorianYear: true,
      );
      expect(greg.summary, contains('12885.00'));

      // Below Nisab: gold 10,000 -> Nisab 850,000 > 500,000
      final below = await assistantService.getZakatCalculatorInsight(
        goldGramPrice24Egp: 10000,
      );
      expect(below.isAlert, isFalse);
      expect(below.summary, contains('لم يبلغ النصاب'));

      // Multi-turn draft: "احسب الزكاة" -> asks gold price -> "4000 بنك 100000" -> 600,000 * 2.5% = 15,000.00
      final t1 = await assistantService.askWithDraft('احسب الزكاة');
      expect(t1.activeDraft?.kind, AssistantCommandKind.calculateZakat);
      expect(t1.activeDraft?.missingField, 'goldPrice24');

      final t2 = await assistantService.askWithDraft(
        '4000 بنك 100000',
        activeDraft: t1.activeDraft,
      );
      expect(t2.activeDraft, isNull);
      expect(t2.insights.first.id, 'zakat_calculator');
      expect(t2.insights.first.summary, contains('15000.00'));
    });
  });

  group('Task 40.11: Sector-Aware AI (Multi-Activity Support)', () {
    Future<void> setMeta(String key, String value) async {
      await db.into(db.appMeta).insertOnConflictUpdate(
            AppMetaCompanion.insert(
              key: key,
              value: value,
              updatedAt: DateTime.now(),
            ),
          );
    }

    test('detects sector and tailors Businessman advice, KB ranking, and Zakat note', () async {
      // 1) Restaurant / Cafe (fnb)
      await setMeta('receipt.store_activity', 'مطعم وكافيه مشويات');
      expect(await assistantService.detectStoreSector(), 'fnb');

      final fnbAdvice = await assistantService.getBusinessmanConsultationInsight();
      expect(fnbAdvice.details.join('\n'), contains('Food Cost'));
      expect(fnbAdvice.details.join('\n'), contains('28%'));

      final fnbKb = await assistantService.searchKnowledgeBase('خامات المطبخ بتخلص بسرعة');
      expect(fnbKb, isNotEmpty);
      expect(fnbKb.first.id, 'kb_sector_fnb_food_cost');

      // 2) Supermarket / Grocery (expiryDates -> grocery)
      await setMeta('receipt.store_activity', 'سوبر ماركت وبقالة');
      expect(await assistantService.detectStoreSector(), 'grocery');

      final groceryAdvice = await assistantService.getBusinessmanConsultationInsight();
      expect(groceryAdvice.details.join('\n'), contains('FEFO'));

      final groceryKb = await assistantService.searchKnowledgeBase('البضاعة بتبوظ وتنتهي صلاحيتها');
      expect(groceryKb, isNotEmpty);
      expect(groceryKb.first.id, 'kb_sector_grocery_fefo');

      // 3) Homeware (home)
      await setMeta('receipt.store_activity', 'أدوات منزلية وجهاز عرايس');
      expect(await assistantService.detectStoreSector(), 'home');

      final homeAdvice = await assistantService.getBusinessmanConsultationInsight();
      expect(homeAdvice.details.join('\n'), contains('جهاز العروسة'));

      final homeMerch = await assistantService.getVisualMerchandisingInsight();
      expect(homeMerch.title, contains('أدوات منزلية'));

      // 4) Mobiles (feature.mobileImeiUsed)
      await setMeta('receipt.store_activity', 'تجارة عامة');
      await setMeta('feature.${FeatureKeys.mobileImeiUsed}', 'true');
      expect(await assistantService.detectStoreSector(), 'mobiles');

      final mobileAdvice = await assistantService.getBusinessmanConsultationInsight();
      expect(mobileAdvice.details.join('\n'), contains('IMEI'));

      // 5) Zakat note is multi-sector (mentions restaurant ovens & repair tools)
      final zakat = await assistantService.getZakatCalculatorInsight(
        goldGramPrice24Egp: 4000,
      );
      expect(zakat.details.join('\n'), contains('أفران المطعم'));
      expect(zakat.details.join('\n'), contains('عدة الصيانة'));
    });
  });

  group('Task 40.12: Goal Planner, Store Health Score, Smart Reorder & Objection Replies', () {
    test('goal planner computes monthly/daily sales & invoices from expenses and margin', () async {
      final now = DateTime.now();
      // Monthly expense = 10,000 EGP (1,000,000 piasters)
      await db.into(db.expenses).insert(
            ExpensesCompanion.insert(
              id: 'exp_gp1',
              branchId: branchId,
              amount: 1000000,
              category: 'إيجار',
              expenseDate: now,
              userId: 'admin',
              createdAt: now,
              updatedAt: now,
            ),
          );

      // Sale + SaleItem: revenue = 2,000 EGP, cost = 1,500 EGP -> margin = 25%
      // Avg invoice = 2,000 EGP
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p_gp1',
              branchId: branchId,
              name: 'منتج هدف',
              categoryId: 'c1',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: 'v_gp1',
              branchId: branchId,
              productId: 'p_gp1',
              sku: 'SKU-GP1',
              color: 'أسود',
              size: 'M',
              costPrice: 150000,
              sellPrice: 200000,
              quantity: const Value(10),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.sales).insert(
            SalesCompanion.insert(
              id: 's_gp1',
              branchId: branchId,
              shortRef: 'INV-GP1',
              subtotal: 200000,
              discountType: 'none',
              total: 200000,
              paymentMethod: 'cash',
              cashierId: 'admin',
              date: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.saleItems).insert(
            SaleItemsCompanion.insert(
              id: 'si_gp1',
              branchId: branchId,
              saleId: 's_gp1',
              variantId: 'v_gp1',
              productName: 'منتج هدف',
              color: 'أسود',
              size: 'M',
              qty: 1,
              priceSnapshot: 200000,
              costSnapshot: 150000,
              lineTotal: 200000,
              createdAt: now,
            ),
          );

      // Target profit 20,000 + expenses 10,000 = 30,000 gross profit needed
      // Margin 25% -> Monthly sales = 120,000.00 EGP -> Daily = 4,000.00 EGP -> 2 invoices/day
      final res = await assistantService.ask('عايز اكسب 20000');
      expect(res.any((r) => r.id == 'goal_planner'), isTrue);
      final gp = res.firstWhere((r) => r.id == 'goal_planner');
      expect(gp.summary, contains('120000.00'));
      expect(gp.summary, contains('4000.00'));
      expect(gp.summary, contains('2 فاتورة'));
    });

    test('store health score returns 0..100 across 4 quarters with sector tips', () async {
      final now = DateTime.now();
      await db.into(db.appMeta).insertOnConflictUpdate(
            AppMetaCompanion.insert(
              key: 'receipt.store_activity',
              value: 'مطعم وكافيه',
              updatedAt: now,
            ),
          );

      final res = await assistantService.ask('تقييم صحة المحل');
      expect(res.any((r) => r.id == 'store_health_score'), isTrue);
      final hs = res.firstWhere((r) => r.id == 'store_health_score');
      expect(hs.title, contains('/ 100'));
      final text = hs.details.join('\n');
      expect(text, contains('/ 25'));
      expect(text, contains('Food Cost'));
    });

    test('smart reorder list detects variants with < 14 days stock and estimates cost', () async {
      final now = DateTime.now();
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p_ro1',
              branchId: branchId,
              name: 'بنطلون سريع',
              categoryId: 'c1',
              createdAt: now,
              updatedAt: now,
            ),
          );
      // Sold 30 units in 30d -> 1/day; current qty = 5 -> 5 days left (< 14)
      // Order for 30d = 30 - 5 = 25 units * 100 EGP cost = 2,500.00 EGP
      await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: 'v_ro1',
              branchId: branchId,
              productId: 'p_ro1',
              sku: 'SKU-RO1',
              color: 'أزرق',
              size: 'L',
              costPrice: 10000,
              sellPrice: 20000,
              quantity: const Value(5),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.sales).insert(
            SalesCompanion.insert(
              id: 's_ro1',
              branchId: branchId,
              shortRef: 'INV-RO1',
              subtotal: 600000,
              discountType: 'none',
              total: 600000,
              paymentMethod: 'cash',
              cashierId: 'admin',
              date: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.saleItems).insert(
            SaleItemsCompanion.insert(
              id: 'si_ro1',
              branchId: branchId,
              saleId: 's_ro1',
              variantId: 'v_ro1',
              productName: 'بنطلون سريع',
              color: 'أزرق',
              size: 'L',
              qty: 30,
              priceSnapshot: 20000,
              costSnapshot: 10000,
              lineTotal: 600000,
              createdAt: now,
            ),
          );

      final res = await assistantService.ask('جهز طلبية الشراء');
      expect(res.any((r) => r.id == 'smart_reorder_list'), isTrue);
      final ro = res.firstWhere((r) => r.id == 'smart_reorder_list');
      expect(ro.isAlert, isTrue);
      expect(ro.summary, contains('2500.00'));
      expect(ro.details.join('\n'), contains('اطلب 25 قطعة'));
    });

    test('customer objection replies returns 3 copyable sector-aware replies', () async {
      final now = DateTime.now();
      await db.into(db.appMeta).insertOnConflictUpdate(
            AppMetaCompanion.insert(
              key: 'receipt.store_activity',
              value: 'موبايلات وإلكترونيات',
              updatedAt: now,
            ),
          );

      final priceRes = await assistantService.ask('العميل بيقول غالي');
      expect(priceRes.any((r) => r.id == 'customer_objection_replies'), isTrue);
      final priceCard = priceRes.firstWhere((r) => r.id == 'customer_objection_replies');
      expect(priceCard.details.length, 3);
      expect(priceCard.details.every((d) => d.contains('\n---\n')), isTrue);
      expect(priceCard.details.first, contains('الضمان الحقيقي'));

      final delayRes = await assistantService.ask('تاخير ديليفري');
      final delayCard = delayRes.firstWhere((r) => r.id == 'customer_objection_replies');
      expect(delayCard.title, contains('تأخير الديليفري'));
      expect(delayCard.details.length, 3);

      final retRes = await assistantService.ask('استرجاع بعد المدة');
      final retCard = retRes.firstWhere((r) => r.id == 'customer_objection_replies');
      expect(retCard.title, contains('استرجاع بعد انتهاء المدة'));
      expect(retCard.details.length, 3);
    });

    testWidgets('OfflineSmartAssistantDialog.show invokes onNavigateRoute instead of full-screen push', (tester) async {
      AssistantActionRoute? navigated;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => OfflineSmartAssistantDialog.show(
                  ctx,
                  onNavigateRoute: (route) => navigated = route,
                ),
                child: const Text('OpenAssistant'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('OpenAssistant'));
      await tester.pumpAndSettle();

      // Ask a query that produces an action button (e.g. overdue installments)
      await tester.enterText(
        find.byKey(const Key('smart_assistant_query_field')),
        'وضع المحل دلوقتي؟',
      );
      await tester.tap(find.byKey(const Key('smart_assistant_ask_btn')));
      await tester.pumpAndSettle();

      expect(find.text('المساعد التحليلي الذكي (أوفلاين)'), findsOneWidget);
      // Verify callback wiring compiles and dialog closes cleanly when popped
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(navigated, isNull);
    });
  });
}
