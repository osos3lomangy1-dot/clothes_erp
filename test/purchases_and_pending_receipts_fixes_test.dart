import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/di/injection.dart';
import 'package:clothes_erp/features/auth/domain/entities/user_entity.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/inventory/data/datasources/inventory_local_data_source.dart';
import 'package:clothes_erp/features/inventory/presentation/cubits/goods_receipt_cubit.dart';
import 'package:clothes_erp/features/purchases/domain/entities/supplier_entity.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/purchases_cubit.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/purchases_state.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/suppliers_cubit.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/suppliers_state.dart';
import 'package:clothes_erp/features/purchases/presentation/screens/create_purchase_screen.dart';
import 'package:clothes_erp/features/purchases/presentation/screens/purchases_screen.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _FakeAuthCubit()
      : super(AuthAuthenticated(
          UserEntity(
            id: 'user-test',
            name: 'أحمد المحاسب',
            email: 'test@test.com',
            role: 'admin',
            isActive: true,
            createdAt: DateTime.now(),
          ),
        ));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSuppliersCubit extends Cubit<SuppliersState> implements SuppliersCubit {
  _FakeSuppliersCubit()
      : super(SuppliersState(
          suppliers: [
            SupplierEntity(
              id: 'sup-1',
              branchId: 'branch-1',
              name: 'مورد النسيج الراقي',
              balance: 0,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          ],
        ));

  @override
  Future<void> loadSuppliers() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePurchasesCubit extends Cubit<PurchasesState> implements PurchasesCubit {
  _FakePurchasesCubit() : super(const PurchasesState());

  @override
  Future<void> loadPurchases({String? supplierId, String? paymentStatus}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BranchProvider branchProvider;
  late TxWriter tx;
  late InventoryLocalDataSource inventoryDs;
  late GoodsReceiptCubit goodsReceiptCubit;
  late _FakeAuthCubit authCubit;
  late _FakeSuppliersCubit suppliersCubit;
  late _FakePurchasesCubit purchasesCubit;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    branchProvider = BranchProvider(db);
    tx = TxWriter(db);
    inventoryDs = InventoryLocalDataSource(db, branchProvider, tx);
    goodsReceiptCubit = GoodsReceiptCubit(inventoryDs);
    authCubit = _FakeAuthCubit();
    suppliersCubit = _FakeSuppliersCubit();
    purchasesCubit = _FakePurchasesCubit();

    if (getIt.isRegistered<AppDatabase>()) {
      await getIt.unregister<AppDatabase>();
    }
    getIt.registerSingleton<AppDatabase>(db);

    if (getIt.isRegistered<GoodsReceiptCubit>()) {
      await getIt.unregister<GoodsReceiptCubit>();
    }
    getIt.registerFactory<GoodsReceiptCubit>(() => goodsReceiptCubit);

    if (getIt.isRegistered<SuppliersCubit>()) {
      await getIt.unregister<SuppliersCubit>();
    }
    getIt.registerFactory<SuppliersCubit>(() => suppliersCubit);

    if (getIt.isRegistered<PurchasesCubit>()) {
      await getIt.unregister<PurchasesCubit>();
    }
    getIt.registerFactory<PurchasesCubit>(() => purchasesCubit);

    final now = DateTime.now();
    await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            id: 'cat-1',
            branchId: 'branch-1',
            name: 'مفروشات وسجاد',
            createdAt: now,
            updatedAt: now,
          ),
        );

    await db.into(db.products).insert(
          ProductsCompanion.insert(
            id: 'prod-1',
            branchId: 'branch-1',
            categoryId: 'cat-1',
            name: 'سجادة صوف كلاسيك',
            createdAt: now,
            updatedAt: now,
          ),
        );

    await db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            id: 'var-1',
            branchId: 'branch-1',
            productId: 'prod-1',
            sku: 'SKU-2X3M-001',
            size: '2×3 م',
            color: 'أحمر كلاسيك',
            costPrice: 50000, // 500.00 EGP
            sellPrice: 75000, // 750.00 EGP
            quantity: const drift.Value(10),
            createdAt: now,
            updatedAt: now,
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
    if (getIt.isRegistered<SuppliersCubit>()) {
      await getIt.unregister<SuppliersCubit>();
    }
    if (getIt.isRegistered<PurchasesCubit>()) {
      await getIt.unregister<PurchasesCubit>();
    }
  });

  group('Purchases and Pending Receipts Tests', () {
    test('1. Cancelling a pending goods receipt reverses stock and updates status to cancelled', () async {
      // 1. Create a goods receipt with 5 pieces
      final receipt = await inventoryDs.createGoodsReceipt(
        items: [
          GoodsReceiptDraftItem(variantId: 'var-1', quantity: 5),
        ],
        cashierId: 'user-test',
        notes: 'شحنة اختبار',
      );

      // Verify stock increased from 10 to 15
      final variantAfterReceive = await (db.select(db.productVariants)..where((v) => v.id.equals('var-1'))).getSingle();
      expect(variantAfterReceive.quantity, equals(15));
      expect(receipt.status, equals('pending'));

      // 2. Cancel the goods receipt
      await inventoryDs.cancelGoodsReceipt(receiptId: receipt.id, userId: 'user-test');

      // Verify status is now cancelled
      final updatedReceipt = await inventoryDs.getGoodsReceiptById(receipt.id);
      expect(updatedReceipt!.status, equals('cancelled'));

      // Verify stock was reversed back from 15 to 10
      final variantAfterCancel = await (db.select(db.productVariants)..where((v) => v.id.equals('var-1'))).getSingle();
      expect(variantAfterCancel.quantity, equals(10));
    });

    testWidgets('2. CreatePurchaseScreen auto-fetches variant cost price from DB when opened from receipt',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final receipt = await inventoryDs.createGoodsReceipt(
        items: [
          GoodsReceiptDraftItem(variantId: 'var-1', quantity: 3),
        ],
        cashierId: 'user-test',
      );

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>.value(value: authCubit),
            BlocProvider<SuppliersCubit>.value(value: suppliersCubit),
            BlocProvider<PurchasesCubit>.value(value: purchasesCubit),
          ],
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: CreatePurchaseScreen(initialGoodsReceipt: receipt),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify cost price was loaded from DB (50000 piasters = 500.00 EGP), NOT 0.0
      expect(find.text('500.00 ج.م'), findsWidgets);
      // Total invoice is 3 * 500 = 1500.00 EGP
      expect(find.text('1500.00 ج.م'), findsWidgets);
    });

    testWidgets('3. User can edit cost price and quantity in purchase invoice after item is added',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final receipt = await inventoryDs.createGoodsReceipt(
        items: [
          GoodsReceiptDraftItem(variantId: 'var-1', quantity: 2),
        ],
        cashierId: 'user-test',
      );

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>.value(value: authCubit),
            BlocProvider<SuppliersCubit>.value(value: suppliersCubit),
            BlocProvider<PurchasesCubit>.value(value: purchasesCubit),
          ],
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: CreatePurchaseScreen(initialGoodsReceipt: receipt),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial price is 500.00 EGP
      expect(find.text('500.00 ج.م'), findsWidgets);

      // Tap on edit cost button
      final editBtn = find.byKey(const Key('edit_purchase_cost_btn_0'));
      expect(editBtn, findsOneWidget);
      await tester.tap(editBtn);
      await tester.pumpAndSettle();

      // Edit dialog appears
      expect(find.text('تعديل سعر وتفاصيل الصنف بالفاتورة'), findsOneWidget);

      // Change price from 500.00 to 520.00
      await tester.enterText(find.byKey(const Key('edit_item_cost_field_0')), '520.00');
      await tester.pump();

      // Click save
      await tester.tap(find.byKey(const Key('save_item_edit_btn')));
      await tester.pumpAndSettle();

      // Price is updated in the table
      expect(find.text('520.00 ج.م'), findsWidgets);
    });

    testWidgets('4. PurchasesScreen allows deleting/cancelling pending receipt with confirmation',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Create a pending receipt
      final receipt = await inventoryDs.createGoodsReceipt(
        items: [
          GoodsReceiptDraftItem(variantId: 'var-1', quantity: 4),
        ],
        cashierId: 'user-test',
        notes: 'شحنة للإلغاء',
      );

      await goodsReceiptCubit.loadGoodsReceipts(status: 'pending');

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>.value(value: authCubit),
            BlocProvider<GoodsReceiptCubit>.value(value: goodsReceiptCubit),
            BlocProvider<SuppliersCubit>.value(value: suppliersCubit),
            BlocProvider<PurchasesCubit>.value(value: purchasesCubit),
          ],
          child: const MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: PurchasesScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to pending receipts tab (Tab index 1)
      await tester.tap(find.text('استلامات معلقة (Pending Receipts)'));
      await tester.pumpAndSettle();

      // Find delete button
      final deleteBtn = find.byKey(Key('delete_pending_receipt_${receipt.id}'));
      expect(deleteBtn, findsOneWidget);
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      // Confirmation dialog opens
      expect(find.text('تأكيد الحذف'), findsOneWidget);

      // Confirm delete
      await tester.tap(find.byKey(const Key('confirm_delete_pending_receipt_btn')));
      await tester.pumpAndSettle();

      // The receipt is removed from the pending list
      expect(find.byKey(Key('delete_pending_receipt_${receipt.id}')), findsNothing);

      // Verify database status is cancelled
      final dbReceipt = await inventoryDs.getGoodsReceiptById(receipt.id);
      expect(dbReceipt!.status, equals('cancelled'));
    });
  });
}
