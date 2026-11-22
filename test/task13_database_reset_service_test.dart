import 'dart:io';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/services/database_reset_service.dart';
import 'package:clothes_erp/core/services/local_backup_service.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/installments/data/services/manager_pin_service.dart';
import 'package:clothes_erp/features/products/data/datasources/product_local_data_source.dart';
import 'package:clothes_erp/features/settings/data/services/activity_settings_service.dart';
import 'package:clothes_erp/features/settings/presentation/cubits/settings_cubit.dart';
import 'package:clothes_erp/features/settings/presentation/screens/system_settings_screen.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

class _FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _FakeAuthCubit(UserModel user) : super(AuthAuthenticated(user));
  @override
  Future<void> login(String email, String password) async {}
  @override
  Future<void> logout() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBranchProvider implements BranchProvider {
  @override
  Future<String> getBranchId() async => 'default';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthDs implements AuthLocalDataSource {
  UserModel? _user;
  void setUser(UserModel? user) => _user = user;
  @override
  Future<void> cacheUser(UserModel user) async => _user = user;
  @override
  Future<UserModel?> getCachedUser() async => _user;
  @override
  Future<void> clearCache() async => _user = null;
}

class _FakeBackupService extends LocalBackupService {
  _FakeBackupService(super.db, super.featureGate);

  @override
  Future<BackupResult> createBackup({
    String? targetFilePath,
    String userId = 'system',
    bool updateMetadata = true,
  }) async {
    return BackupResult(
      filePath: 'E:/backups/test_backup.sqlite',
      sizeBytes: 1024,
      createdAt: DateTime.now(),
    );
  }
}

class _FakeSettingsCubit extends Cubit<SettingsState> implements SettingsCubit {
  _FakeSettingsCubit() : super(const SettingsState());

  @override
  void start() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FeatureGate featureGate;
  late _FakeBackupService backupService;
  late DatabaseResetService resetService;
  late ProductLocalDataSource productDs;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bay3ah_reset_test_');
    db = AppDatabase(NativeDatabase.memory());
    final authDs = _FakeAuthDs();
    final branchProvider = _FakeBranchProvider();
    final txWriter = TxWriter(db);
    featureGate = FeatureGate(db, authDs, txWriter, branchProvider);
    backupService = _FakeBackupService(db, featureGate);
    resetService = DatabaseResetService(db, backupService);
    productDs = ProductLocalDataSource(db, branchProvider, txWriter);

    // Register in GetIt for UI components
    final sl = GetIt.instance;
    sl.reset();
    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<FeatureGate>(featureGate);
    sl.registerSingleton<DatabaseResetService>(resetService);
    sl.registerSingleton<LocalBackupService>(backupService);
    sl.registerFactory<SettingsCubit>(() => _FakeSettingsCubit());
    sl.registerLazySingleton<ActivitySettingsService>(() => ActivitySettingsService(db, featureGate));
    sl.registerLazySingleton<ManagerPinService>(() => ManagerPinService(db, txWriter, branchProvider, authDs, featureGate));
  });

  tearDown(() async {
    await db.close();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
    GetIt.instance.reset();
  });

  group('Task 13: DatabaseResetService Unit Tests', () {
    test('verifyAdminPassword correctly verifies admin password and rejects invalid ones', () async {
      // 1. Fallback when table is empty
      expect(await resetService.verifyAdminPassword('admin'), isTrue);
      expect(await resetService.verifyAdminPassword('admin123'), isTrue);
      expect(await resetService.verifyAdminPassword('wrong_pass'), isFalse);

      // 2. Custom admin in DB
      await db.into(db.users).insert(UsersCompanion.insert(
        id: 'admin_custom',
        branchId: 'default',
        username: 'master',
        displayName: 'Master Admin',
        role: 'admin',
        passwordHash: 'hash_secret123',
        passwordSalt: 'salt',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      expect(await resetService.verifyAdminPassword('secret123'), isTrue);
      expect(await resetService.verifyAdminPassword('wrong'), isFalse);
    });

    test('purgeTestData purges transactions and resets balances while preserving products and users', () async {
      final now = DateTime.now();

      // Seed a user
      await db.into(db.users).insert(UsersCompanion.insert(
        id: 'admin_user',
        branchId: 'default',
        username: 'admin',
        displayName: 'Admin',
        role: 'admin',
        passwordHash: 'admin123',
        passwordSalt: 'salt',
        createdAt: now,
        updatedAt: now,
      ));

      // Seed a category & product & variant
      await db.into(db.categories).insert(CategoriesCompanion.insert(
        id: 'cat_1',
        branchId: 'default',
        name: 'الملابس الرجالي',
        createdAt: now,
        updatedAt: now,
      ));

      await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'prod_1',
        branchId: 'default',
        categoryId: 'cat_1',
        name: 'قميص تجريبي',
        createdAt: now,
        updatedAt: now,
      ));

      await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
        id: 'var_1',
        branchId: 'default',
        productId: 'prod_1',
        sku: 'SHIRT-01',
        color: 'أبيض',
        size: 'L',
        costPrice: 5000,
        sellPrice: 10000,
        quantity: const drift.Value(15),
        createdAt: now,
        updatedAt: now,
      ));

      // Seed customer with loyalty points
      await db.into(db.customers).insert(CustomersCompanion.insert(
        id: 'cust_1',
        branchId: 'default',
        name: 'عميل تجريبي',
        phone: '01000000000',
        loyaltyPoints: const drift.Value(250),
        createdAt: now,
        updatedAt: now,
      ));

      // Seed supplier with balance
      await db.into(db.suppliers).insert(SuppliersCompanion.insert(
        id: 'supp_1',
        branchId: 'default',
        name: 'مورد تجريبي',
        balance: const drift.Value(5000),
        createdAt: now,
        updatedAt: now,
      ));

      // Seed a shift
      await db.into(db.shifts).insert(ShiftsCompanion.insert(
        id: 'shift_1',
        branchId: 'default',
        cashierId: 'admin_user',
        openingBalance: 10000,
        openedAt: now,
        createdAt: now,
        updatedAt: now,
      ));

      // Seed a sale & sale item
      await db.into(db.sales).insert(SalesCompanion.insert(
        id: 'sale_1',
        branchId: 'default',
        shortRef: 'INV-001',
        cashierId: 'admin_user',
        subtotal: 10000,
        discountType: 'none',
        total: 10000,
        paymentMethod: 'cash',
        shiftId: const drift.Value('shift_1'),
        status: const drift.Value('completed'),
        date: now,
        createdAt: now,
        updatedAt: now,
      ));

      await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
        id: 'sale_item_1',
        branchId: 'default',
        saleId: 'sale_1',
        variantId: 'var_1',
        productName: 'قميص تجريبي',
        color: 'أبيض',
        size: 'L',
        qty: 1,
        priceSnapshot: 10000,
        costSnapshot: 5000,
        lineTotal: 10000,
        createdAt: now,
      ));

      // Execute purge with resetStock: true
      final result = await resetService.purgeTestData(
        userId: 'admin_user',
        resetStock: true,
      );

      expect(result.success, isTrue);
      expect(result.backupFilePath, contains('test_backup.sqlite'));

      // Check transactions are gone
      final salesCount = await db.select(db.sales).get();
      final saleItemsCount = await db.select(db.saleItems).get();
      final shiftsCount = await db.select(db.shifts).get();

      expect(salesCount, isEmpty);
      expect(saleItemsCount, isEmpty);
      expect(shiftsCount, isEmpty);

      // Check master data is preserved
      final products = await db.select(db.products).get();
      final users = await db.select(db.users).get();
      final categories = await db.select(db.categories).get();
      final customer = await (db.select(db.customers)..where((c) => c.id.equals('cust_1'))).getSingle();
      final supplier = await (db.select(db.suppliers)..where((s) => s.id.equals('supp_1'))).getSingle();
      final variant = await (db.select(db.productVariants)..where((v) => v.id.equals('var_1'))).getSingle();

      expect(products.length, equals(1));
      expect(users.length, equals(1));
      expect(categories.length, equals(1));
      expect(customer.loyaltyPoints, equals(0));
      expect(supplier.balance, equals(0));
      expect(variant.quantity, equals(0)); // resetStock was true
    });
  });

  group('Task 13: Product Force Delete by Admin Tests', () {
    test('softDeleteProduct rejects deletion without forceDeleteForAdmin when product has sales', () async {
      final now = DateTime.now();

      await db.into(db.categories).insert(CategoriesCompanion.insert(
        id: 'cat_test',
        branchId: 'default',
        name: 'أحذية',
        createdAt: now,
        updatedAt: now,
      ));

      await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'prod_sales',
        branchId: 'default',
        categoryId: 'cat_test',
        name: 'حذاء تجريبي',
        createdAt: now,
        updatedAt: now,
      ));

      await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
        id: 'var_sales',
        branchId: 'default',
        productId: 'prod_sales',
        sku: 'SHOE-01',
        color: 'أسود',
        size: '42',
        costPrice: 8000,
        sellPrice: 15000,
        createdAt: now,
        updatedAt: now,
      ));

      await db.into(db.sales).insert(SalesCompanion.insert(
        id: 'sale_demo',
        branchId: 'default',
        shortRef: 'INV-999',
        cashierId: 'c1',
        subtotal: 15000,
        discountType: 'none',
        total: 15000,
        paymentMethod: 'cash',
        status: const drift.Value('completed'),
        date: now,
        createdAt: now,
        updatedAt: now,
      ));

      await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
        id: 'si_demo',
        branchId: 'default',
        saleId: 'sale_demo',
        variantId: 'var_sales',
        productName: 'حذاء تجريبي',
        color: 'أسود',
        size: '42',
        qty: 1,
        priceSnapshot: 15000,
        costSnapshot: 8000,
        lineTotal: 15000,
        createdAt: now,
      ));

      // Without force: throws exception
      expect(
        () => productDs.softDeleteProduct('prod_sales', forceDeleteForAdmin: false),
        throwsA(isA<Exception>()),
      );

      // With forceDeleteForAdmin: true -> succeeds
      await productDs.softDeleteProduct(
        'prod_sales',
        forceDeleteForAdmin: true,
        userId: 'admin_1',
      );

      final deletedProduct = await (db.select(db.products)..where((p) => p.id.equals('prod_sales'))).getSingle();
      expect(deletedProduct.deletedAt, isNotNull);
    });
  });

  group('Task 13: Admin-Only System Settings Danger Zone Visibility', () {
    testWidgets('Danger Zone card is visible ONLY when user role is admin', (tester) async {
      tester.view.physicalSize = const Size(1280, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final adminUser = UserModel(
        id: 'admin_1',
        name: 'Master Admin',
        email: 'admin@bay3ah.com',
        role: 'admin',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>(
            create: (_) => _FakeAuthCubit(adminUser),
            child: const SystemSettingsScreen(initialCategory: 'backup'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('purge_test_data_button')), findsOneWidget);
      expect(find.text('منطقة العمليات المتقدمة للآدمن (تهيئة النظام وتصفير البيانات)'), findsNWidgets(2));
    });

    testWidgets('Danger Zone card is COMPLETELY HIDDEN when user role is manager', (tester) async {
      tester.view.physicalSize = const Size(1280, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final managerUser = UserModel(
        id: 'manager_1',
        name: 'Branch Manager',
        email: 'manager@bay3ah.com',
        role: 'manager',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>(
            create: (_) => _FakeAuthCubit(managerUser),
            child: const SystemSettingsScreen(initialCategory: 'backup'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('purge_test_data_button')), findsNothing);
      expect(find.text('منطقة العمليات المتقدمة للآدمن (تهيئة النظام وتصفير البيانات)'), findsNothing);
    });
  });
}
