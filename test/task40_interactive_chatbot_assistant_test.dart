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
  });
}
