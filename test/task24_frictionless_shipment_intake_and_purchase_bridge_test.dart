import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/di/injection.dart';
import 'package:clothes_erp/features/auth/domain/entities/user_entity.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/inventory/data/datasources/inventory_local_data_source.dart';
import 'package:clothes_erp/features/inventory/presentation/cubits/goods_receipt_cubit.dart';
import 'package:clothes_erp/features/inventory/presentation/screens/blind_receive_screen.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/purchases_cubit.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/purchases_state.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/suppliers_cubit.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/suppliers_state.dart';
import 'package:clothes_erp/features/purchases/presentation/screens/create_purchase_screen.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _FakeAuthCubit()
      : super(
          AuthAuthenticated(
            UserEntity(
              id: 'user-intake-1',
              name: 'أحمد مستلم المخزن',
              email: 'intake@store.com',
              role: 'admin',
              isActive: true,
              createdAt: DateTime.now(),
            ),
          ),
        );

  @override
  Future<void> login(String email, String password) async {}
  @override
  Future<void> logout() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSuppliersCubit extends Cubit<SuppliersState> implements SuppliersCubit {
  _FakeSuppliersCubit() : super(const SuppliersState(status: SuppliersStatus.loaded, suppliers: []));

  @override
  Future<void> loadSuppliers() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePurchasesCubit extends Cubit<PurchasesState> implements PurchasesCubit {
  _FakePurchasesCubit() : super(const PurchasesState());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _FakeAuthCubit authCubit;
  late _FakeSuppliersCubit suppliersCubit;
  late _FakePurchasesCubit purchasesCubit;
  late GoodsReceiptCubit goodsReceiptCubit;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    authCubit = _FakeAuthCubit();
    suppliersCubit = _FakeSuppliersCubit();
    purchasesCubit = _FakePurchasesCubit();

    if (getIt.isRegistered<AppDatabase>()) {
      await getIt.unregister<AppDatabase>();
    }
    getIt.registerSingleton<AppDatabase>(db);

    final bp = BranchProvider(db);
    final tx = TxWriter(db);
    final invDs = InventoryLocalDataSource(db, bp, tx);
    goodsReceiptCubit = GoodsReceiptCubit(invDs);

    if (getIt.isRegistered<GoodsReceiptCubit>()) {
      await getIt.unregister<GoodsReceiptCubit>();
    }
    getIt.registerFactory<GoodsReceiptCubit>(() => goodsReceiptCubit);

    // Seed test category, product, and existing variant
    await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            id: 'cat-textiles',
            branchId: 'branch-1',
            name: 'مفروشات وسجاد',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );

    await db.into(db.products).insert(
          ProductsCompanion.insert(
            id: 'prod-carpet-1',
            branchId: 'branch-1',
            categoryId: 'cat-textiles',
            name: 'سجادة حرير فاخرة',
            activityType: const drift.Value('textilesDecor'),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );

    await db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            id: 'var-carpet-2x3',
            branchId: 'branch-1',
            productId: 'prod-carpet-1',
            sku: 'SKU-2X3M-101',
            size: '2×3 م',
            color: 'بيج',
            costPrice: 45000, // 450.00 EGP
            sellPrice: 65000, // 650.00 EGP
            quantity: const drift.Value(5),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
  });

  tearDown(() async {
    await db.close();
    if (getIt.isRegistered<AppDatabase>()) {
      await getIt.unregister<AppDatabase>();
    }
    if (getIt.isRegistered<GoodsReceiptCubit>()) {
      await getIt.unregister<GoodsReceiptCubit>();
    }
  });

  Widget buildTestWidget() {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthCubit>.value(value: authCubit),
        BlocProvider<GoodsReceiptCubit>.value(value: goodsReceiptCubit),
        BlocProvider<SuppliersCubit>.value(value: suppliersCubit),
        BlocProvider<PurchasesCubit>.value(value: purchasesCubit),
      ],
      child: const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: BlindReceiveScreen(),
        ),
      ),
    );
  }

  group('Task 24: Frictionless Multi-Item Shipment Intake & Purchase Bridging', () {
    testWidgets('1. Search dialog stays open on item addition, updates count badge, and closes via done button',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Open search dialog
      await tester.tap(find.text('بحث واختيار من القائمة'));
      await tester.pumpAndSettle();

      expect(find.text('اختيار صنف للاستلام'), findsOneWidget);
      expect(find.text('سجادة حرير فاخرة'), findsOneWidget);

      // Add variant (+1)
      final addBtnFinder = find.byKey(const Key('search_add_item_btn_var-carpet-2x3'));
      expect(addBtnFinder, findsOneWidget);
      await tester.tap(addBtnFinder);
      await tester.pumpAndSettle();

      // Dialog must NOT dismiss!
      expect(find.text('اختيار صنف للاستلام'), findsOneWidget);

      // Added badge appears
      final badgeFinder = find.byKey(const Key('search_item_added_badge_var-carpet-2x3'));
      expect(badgeFinder, findsOneWidget);
      expect(find.text('تمت إضافة +1 | الإجمالي: 1'), findsOneWidget);

      // Add again (+1) -> updates to 2
      await tester.tap(addBtnFinder);
      await tester.pumpAndSettle();
      expect(find.text('تمت إضافة +1 | الإجمالي: 2'), findsOneWidget);

      // Close dialog via done button
      final doneBtnFinder = find.byKey(const Key('search_dialog_done_btn'));
      expect(doneBtnFinder, findsOneWidget);
      await tester.tap(doneBtnFinder);
      await tester.pumpAndSettle();

      // Returned to shipment screen with 2 pieces
      expect(find.text('اختيار صنف للاستلام'), findsNothing);
      expect(find.text('سجادة حرير فاخرة'), findsOneWidget);
      expect(find.text('2'), findsWidgets);
    });

    testWidgets('2. Multi-variant creation retains dialog with save_and_add_another_variant_btn',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Open Add Variant dialog
      await tester.tap(find.byKey(const Key('blind_receive_add_variant_btn')));
      await tester.pumpAndSettle();

      expect(find.text('إضافة مقاس جديد لصنف مسجل في الشحنة'), findsOneWidget);

      // Enter size 3x4 m
      final sizeField = find.byKey(const Key('new_variant_size_field'));
      await tester.enterText(sizeField, '3×4 م');
      final costField = find.byKey(const Key('new_variant_cost_field'));
      await tester.enterText(costField, '850.00');
      final qtyField = find.byKey(const Key('new_variant_qty_field'));
      await tester.enterText(qtyField, '4');
      await tester.pump();

      // Click "حفظ وإضافة مقاس آخر لنفس الموديل"
      final addAnotherBtn = find.byKey(const Key('save_and_add_another_variant_btn'));
      expect(addAnotherBtn, findsOneWidget);
      await tester.tap(addAnotherBtn);
      await tester.pumpAndSettle();

      // Dialog should still be open!
      expect(find.text('إضافة مقاس جديد لصنف مسجل في الشحنة'), findsOneWidget);

      // Enter second size 1.5x2 m and click "حفظ وإنهاء"
      await tester.enterText(sizeField, '1.5×2 م');
      await tester.enterText(costField, '300.00');
      await tester.enterText(qtyField, '6');
      await tester.pump();

      final confirmBtn = find.byKey(const Key('confirm_add_new_variant_btn'));
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // Dialog closed and both items appear in the shipment table
      expect(find.text('إضافة مقاس جديد لصنف مسجل في الشحنة'), findsNothing);
      expect(find.text('3×4 م'), findsOneWidget);
      expect(find.text('1.5×2 م'), findsOneWidget);
    });

    testWidgets('3. Cost price is editable in shipment table and updates database product_variants',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Add item via search
      await tester.tap(find.text('بحث واختيار من القائمة'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'إضافة'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('search_dialog_done_btn')));
      await tester.pumpAndSettle();

      // Initial cost price should show 450.00 ج.م (from DB: 45000 piasters)
      expect(find.text('450.00 ج.م'), findsOneWidget);

      // Tap on cost price button to edit
      final editCostBtn = find.byKey(const Key('edit_cost_price_btn_var-carpet-2x3'));
      expect(editCostBtn, findsOneWidget);
      await tester.tap(editCostBtn);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cost_price_input_field')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('cost_price_input_field')), '480.00');
      await tester.pump();

      await tester.tap(find.byKey(const Key('confirm_edit_cost_btn')));
      await tester.pumpAndSettle();

      // Cost price updated on screen
      expect(find.text('480.00 ج.م'), findsOneWidget);

      // Verify DB was updated
      final updatedVariant = await (db.select(db.productVariants)
            ..where((v) => v.id.equals('var-carpet-2x3')))
          .getSingle();
      expect(updatedVariant.costPrice, equals(48000));
    });

    testWidgets('4. Shipment intake summary modal displays metrics and saves as shipment only',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Add item via search
      await tester.tap(find.text('بحث واختيار من القائمة'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'إضافة'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('search_dialog_done_btn')));
      await tester.pumpAndSettle();

      // Tap save receipt
      await tester.tap(find.text('حفظ الشحنة (1 قطعة)'));
      await tester.pumpAndSettle();

      // Summary modal opens
      expect(find.text('ملخص شحنة البضاعة المستلمة'), findsOneWidget);
      expect(find.text('عدد الأصناف'), findsOneWidget);
      expect(find.text('إجمالي القطع'), findsOneWidget);
      expect(find.text('إجمالي التكلفة'), findsOneWidget);
      expect(find.text('أحمد مستلم المخزن'), findsOneWidget);

      // Click "حفظ كشحنة مخزنية فقط"
      final saveShipmentOnlyBtn = find.byKey(const Key('save_shipment_only_btn'));
      expect(saveShipmentOnlyBtn, findsOneWidget);
      await tester.tap(saveShipmentOnlyBtn);
      await tester.pumpAndSettle();

      // Modal closed and goods receipt was created
      expect(find.text('ملخص شحنة البضاعة المستلمة'), findsNothing);
      final receipts = await db.select(db.goodsReceipts).get();
      expect(receipts.length, equals(1));
      expect(receipts.first.cashierId, equals('أحمد مستلم المخزن'));
    });

    testWidgets('5. Saving and converting to purchase navigates to CreatePurchaseScreen with initial items',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Add item via search
      await tester.tap(find.text('بحث واختيار من القائمة'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'إضافة'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('search_dialog_done_btn')));
      await tester.pumpAndSettle();

      // Tap save receipt
      await tester.tap(find.text('حفظ الشحنة (1 قطعة)'));
      await tester.pumpAndSettle();

      // Click "حفظ والتحويل لفاتورة مشتريات"
      final convertBtn = find.byKey(const Key('save_and_convert_to_purchase_btn'));
      expect(convertBtn, findsOneWidget);
      await tester.tap(convertBtn);
      await tester.pumpAndSettle();

      // Navigated to CreatePurchaseScreen
      expect(find.byType(CreatePurchaseScreen), findsOneWidget);
      expect(find.text('فاتورة مشتريات جديدة'), findsOneWidget);

      // Pre-filled items are present in purchase screen
      expect(find.text('سجادة حرير فاخرة'), findsWidgets);
      expect(find.text('450.00 ج.م'), findsWidgets); // cost price pre-filled in table and summary
    });

    testWidgets('6. CreatePurchaseScreen is self-healing and mounts cleanly without external SuppliersCubit provider',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      if (getIt.isRegistered<SuppliersCubit>()) {
        await getIt.unregister<SuppliersCubit>();
      }
      getIt.registerFactory<SuppliersCubit>(() => suppliersCubit);

      if (getIt.isRegistered<PurchasesCubit>()) {
        await getIt.unregister<PurchasesCubit>();
      }
      getIt.registerFactory<PurchasesCubit>(() => purchasesCubit);

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: const MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: CreatePurchaseScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CreatePurchaseScreen), findsOneWidget);
      expect(find.text('فاتورة مشتريات جديدة'), findsOneWidget);
    });
  });
}
