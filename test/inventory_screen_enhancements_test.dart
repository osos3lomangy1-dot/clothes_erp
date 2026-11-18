import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/features/inventory/data/datasources/inventory_local_data_source.dart';
import 'package:clothes_erp/features/inventory/data/repositories/inventory_repository_impl.dart';
import 'package:clothes_erp/features/inventory/domain/usecases/get_all_inventory_usecase.dart';
import 'package:clothes_erp/features/inventory/domain/usecases/get_low_stock_usecase.dart';
import 'package:clothes_erp/features/inventory/presentation/cubits/inventory_cubit.dart';
import 'package:clothes_erp/features/inventory/presentation/widgets/inventory_action_dialogs.dart';
import 'package:clothes_erp/features/product_variants/domain/entities/variant_entity.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late BranchProvider branchProvider;
  late TxWriter tx;
  late InventoryLocalDataSource dataSource;
  late InventoryRepositoryImpl repo;
  late InventoryCubit cubit;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    branchProvider = BranchProvider(db);
    tx = TxWriter(db);
    dataSource = InventoryLocalDataSource(db, branchProvider, tx);
    repo = InventoryRepositoryImpl(dataSource);
    cubit = InventoryCubit(
      GetAllInventoryUseCase(repo),
      GetLowStockUseCase(repo),
      dataSource,
    );
  });

  tearDown(() async {
    await cubit.close();
    await db.close();
  });

  Future<void> seedInventory() async {
    final now = DateTime(2026, 6, 15);
    await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            id: 'cat-1',
            branchId: 'b1',
            name: 'بناطيل',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db.into(db.products).insert(
          ProductsCompanion.insert(
            id: 'prod-1',
            branchId: 'b1',
            name: 'بنطلون جينز',
            categoryId: 'cat-1',
            minStock: const drift.Value(12), // custom minStock > 5
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            id: 'var-1',
            branchId: 'b1',
            productId: 'prod-1',
            sku: 'JNS-32',
            color: 'أزرق',
            size: '32',
            quantity: const drift.Value(8), // <= minStock (12), > 5
            costPrice: 30000,
            sellPrice: 50000,
            wholesalePrice: const drift.Value(42000),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  group('Inventory Data & Cubit Enhancements', () {
    test('uses per-product minStock, populates wholesalePrice and categoryName', () async {
      await seedInventory();

      final details = await dataSource.getInventoryDetails(lowStockOnly: true);
      expect(details.length, 1);
      expect(details.first.minStock, 12);
      expect(details.first.wholesalePrice, 42000);
      expect(details.first.categoryName, 'بناطيل');

      final repoRes = await repo.getAllInventory();
      final items = repoRes.getOrElse(() => []);
      expect(items.length, 1);
      expect(items.first.minStock, 12);
      expect(items.first.wholesalePrice, 42000);
      expect(items.first.categoryName, 'بناطيل');
    });

    test('adjustStock updates quantity, logs real userId, and blocks negative stock', () async {
      await seedInventory();

      await cubit.adjustStock(
        variantId: 'var-1',
        qtyDelta: -2,
        reason: 'قطعتين تالفة',
        userId: 'manager-99',
      );

      final updated = await (db.select(db.productVariants)
            ..where((v) => v.id.equals('var-1')))
          .getSingle();
      expect(updated.quantity, 6);

      final logs = await cubit.getVariantLogs('var-1');
      expect(logs.length, 1);
      expect(logs.first.qtyDelta, -2);
      expect(logs.first.userId, 'manager-99');
      expect(logs.first.reason, 'قطعتين تالفة');

      // Over-deduction below 0 must throw
      await expectLater(
        cubit.adjustStock(
          variantId: 'var-1',
          qtyDelta: -10,
          reason: 'تجربة سالب',
          userId: 'manager-99',
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('Inventory Action Dialogs Widget Tests', () {
    testWidgets('adjustment dialog and movement history dialog render cleanly in RTL', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await seedInventory();

      final variant = VariantEntity(
        id: 'var-1',
        productId: 'prod-1',
        productCode: 'JNS-32',
        color: 'أزرق',
        size: '32',
        quantity: 8,
        costPrice: 30000,
        salePrice: 50000,
        wholesalePrice: 42000,
        minStock: 12,
        createdAt: DateTime(2026, 6, 15),
        productName: 'بنطلون جينز',
        categoryName: 'بناطيل',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Builder(
              builder: (context) => Scaffold(
                body: Row(
                  children: [
                    ElevatedButton(
                      onPressed: () => showInventoryAdjustmentDialog(
                        context,
                        item: variant,
                        cubit: cubit,
                        userId: 'manager-99',
                      ),
                      child: const Text('adjust'),
                    ),
                    ElevatedButton(
                      onPressed: () => showVariantMovementHistoryDialog(
                        context,
                        item: variant,
                        cubit: cubit,
                      ),
                      child: const Text('history'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('adjust'));
      await tester.pumpAndSettle();
      expect(find.text('تسوية رصيد المخزون'), findsOneWidget);
      expect(find.text('الرصيد الحالي: 8 قطعة'), findsOneWidget);

      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('history'));
      await tester.pumpAndSettle();
      expect(find.text('سجل حركات الصنف'), findsOneWidget);
    });
  });
}

