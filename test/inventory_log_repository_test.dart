import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/features/inventory/data/repositories/inventory_log_repository_impl.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late InventoryLogRepositoryImpl repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = InventoryLogRepositoryImpl(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('1. getLogs returns empty list when table has no entries', () async {
    final result = await repo.getLogs();
    expect(result.isRight(), isTrue);
    result.fold(
      (failure) => fail('expected Right, got $failure'),
      (logs) => expect(logs, isEmpty),
    );
  });

  test('2. getLogs returns entries ordered by createdAt desc with correct mapping', () async {
    final t1 = DateTime(2026, 1, 1, 10, 0);
    final t2 = DateTime(2026, 1, 2, 10, 0);

    await db.into(db.inventoryLogs).insert(
      InventoryLogsCompanion.insert(
        id: 'log-1',
        branchId: 'b1',
        variantId: 'v1',
        type: 'sale',
        qtyDelta: -3,
        refType: 'sale',
        userId: 'u1',
        createdAt: t1,
      ),
    );

    await db.into(db.inventoryLogs).insert(
      InventoryLogsCompanion.insert(
        id: 'log-2',
        branchId: 'b1',
        variantId: 'v2',
        type: 'receive',
        qtyDelta: 5,
        refType: 'purchase',
        userId: 'u2',
        createdAt: t2,
      ),
    );

    final result = await repo.getLogs();
    expect(result.isRight(), isTrue);
    result.fold(
      (failure) => fail('expected Right, got $failure'),
      (logs) {
        expect(logs.length, 2);
        expect(logs[0].id, 'log-2');
        expect(logs[0].variantId, 'v2');
        expect(logs[0].type, 'receive');
        expect(logs[0].quantity, 5);
        expect(logs[0].userId, 'u2');

        expect(logs[1].id, 'log-1');
        expect(logs[1].variantId, 'v1');
        expect(logs[1].type, 'sale');
        expect(logs[1].quantity, 3);
        expect(logs[1].userId, 'u1');
      },
    );
  });

  test('3. getLogs joins with Products, ProductVariants, and Users to populate names and sizes', () async {
    final now = DateTime.now();

    // 1. Seed user
    await db.into(db.users).insert(
      UsersCompanion.insert(
        id: 'user-emp-1',
        branchId: 'b1',
        username: 'ahmed_ali',
        displayName: 'أحمد علي',
        role: 'employee',
        passwordHash: 'hash',
        passwordSalt: 'salt',
        createdAt: now,
        updatedAt: now,
      ),
    );

    // 2. Seed category & product
    await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        id: 'cat-1',
        branchId: 'b1',
        name: 'قمصان',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await db.into(db.products).insert(
      ProductsCompanion.insert(
        id: 'prod-shirt',
        branchId: 'b1',
        name: 'قميص أكسفورد كلاسيك',
        categoryId: 'cat-1',
        createdAt: now,
        updatedAt: now,
      ),
    );

    // 3. Seed variant
    await db.into(db.productVariants).insert(
      ProductVariantsCompanion.insert(
        id: 'var-xl-blue',
        branchId: 'b1',
        productId: 'prod-shirt',
        sku: 'SHIRT-XL-BLU',
        color: 'أزرق',
        size: 'XL',
        costPrice: 15000,
        sellPrice: 25000,
        createdAt: now,
        updatedAt: now,
      ),
    );

    // 4. Seed log
    await db.into(db.inventoryLogs).insert(
      InventoryLogsCompanion.insert(
        id: 'log-join-1',
        branchId: 'b1',
        variantId: 'var-xl-blue',
        type: 'receive',
        qtyDelta: 20,
        refType: 'purchase',
        userId: 'user-emp-1',
        createdAt: now,
      ),
    );

    final res = await repo.getLogs();
    expect(res.isRight(), isTrue);
    final logs = res.getOrElse(() => []);
    expect(logs.length, 1);
    final log = logs.first;

    expect(log.id, 'log-join-1');
    expect(log.productName, 'قميص أكسفورد كلاسيك');
    expect(log.variantSize, 'XL');
    expect(log.variantColor, 'أزرق');
    expect(log.userName, 'أحمد علي');
    expect(log.quantity, 20);
    expect(log.type, 'receive');
  });

  test('4. getLogs falls back gracefully when variant, product, or user is null/missing', () async {
    final now = DateTime.now();

    await db.into(db.inventoryLogs).insert(
      InventoryLogsCompanion.insert(
        id: 'log-orphan',
        branchId: 'b1',
        variantId: 'deleted-var-id',
        type: 'adjustment',
        qtyDelta: -1,
        refType: 'manual',
        userId: 'deleted-user-id',
        createdAt: now,
      ),
    );

    final res = await repo.getLogs();
    expect(res.isRight(), isTrue);
    final logs = res.getOrElse(() => []);
    expect(logs.length, 1);
    final log = logs.first;

    expect(log.id, 'log-orphan');
    expect(log.productName, isNull);
    expect(log.variantSize, isNull);
    expect(log.variantColor, isNull);
    expect(log.userName, 'deleted-user-id'); // fallback to raw userId
    expect(log.quantity, 1);
  });
}
