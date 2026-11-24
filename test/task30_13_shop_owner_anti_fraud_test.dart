import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/services/local_backup_service.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/auth/presentation/widgets/manager_auth_dialog.dart';
import 'package:clothes_erp/features/categories/domain/entities/category_entity.dart';
import 'package:clothes_erp/features/categories/domain/repositories/category_repository.dart';
import 'package:clothes_erp/features/inventory/data/datasources/inventory_local_data_source.dart';
import 'package:clothes_erp/features/inventory/presentation/screens/blind_receive_screen.dart';
import 'package:clothes_erp/features/pos/domain/entities/sale_entity.dart';
import 'package:clothes_erp/features/pos/domain/repositories/pos_repository.dart';
import 'package:clothes_erp/features/pos/domain/usecases/create_sale_usecase.dart';
import 'package:clothes_erp/features/pos/presentation/cubits/pos_cubit.dart';
import 'package:clothes_erp/features/product_variants/data/datasources/variant_local_data_source.dart';
import 'package:clothes_erp/features/product_variants/domain/entities/variant_entity.dart';
import 'package:clothes_erp/features/product_variants/domain/repositories/variant_repository.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/products/domain/repositories/product_repository.dart';
import 'package:clothes_erp/features/returns/domain/entities/return_item_entity.dart';
import 'package:clothes_erp/features/returns/presentation/cubits/returns_cubit.dart';
import 'package:clothes_erp/features/returns/presentation/cubits/returns_state.dart';
import 'package:clothes_erp/features/returns/presentation/screens/return_screen.dart';
import 'package:clothes_erp/features/settings/data/services/activity_settings_service.dart';
import 'package:clothes_erp/features/settings/presentation/cubits/settings_cubit.dart';
import 'package:clothes_erp/features/settings/presentation/screens/system_settings_screen.dart';
import 'package:clothes_erp/features/settings/presentation/widgets/local_backup_card.dart';
import 'package:dartz/dartz.dart';
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

class _FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _FakeAuthCubit(UserModel user) : super(AuthAuthenticated(user));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeReturnsCubit extends Cubit<ReturnsState> implements ReturnsCubit {
  int processReturnCalls = 0;
  _FakeReturnsCubit(super.initialState);

  @override
  Future<void> init() async {}

  @override
  Future<bool> processReturn({
    required String reason,
    required String userId,
    String paymentMethod = 'cash',
  }) async {
    processReturnCalls++;
    return true;
  }

  @override
  Future<void> loadReturnsHistory() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestVariantRepo implements VariantRepository {
  final List<VariantEntity> items;
  _TestVariantRepo(this.items);
  @override
  Stream<Either<Failure, List<VariantEntity>>> watchAllVariants() =>
      Stream.value(Right(items));
  @override
  Future<Either<Failure, List<VariantEntity>>> getAllVariants() async =>
      Right(items);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestCategoryRepo implements CategoryRepository {
  @override
  Future<Either<Failure, List<CategoryEntity>>> getCategories() async =>
      const Right([]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestProductRepo implements ProductRepository {
  @override
  Future<Either<Failure, List<ProductEntity>>> getProducts() async =>
      const Right([]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocalBackupService implements LocalBackupService {
  @override
  Future<LocalBackupConfig> loadConfig() async => const LocalBackupConfig(
        autoEnabled: false,
        directoryPath: '',
        retentionCount: 5,
      );

  @override
  Future<List<BackupFileInfo>> listBackups({String? directoryPath}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPosRepo implements PosRepository {
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
    tx = TxWriter(db);
    branchProvider = _TestBranchProvider();
  });

  tearDown(() async {
    await db.close();
  });

  group('Addendum 30.13: ManagerAuthHelper Credential Verification', () {
    test('Rejects hardcoded bypass ("admin" / "123456") and cashier credentials; accepts real active admin/manager', () async {
      final now = DateTime.now();

      await db.into(db.users).insert(UsersCompanion.insert(
        id: 'u_admin',
        branchId: branchId,
        username: 'boss',
        displayName: 'صاحب المحل',
        passwordHash: 'hash_Boss@99',
        passwordSalt: 'salt',
        pinHash: const Value('hash_4321'),
        role: 'admin',
        isActive: const Value(true),
        createdAt: now,
        updatedAt: now,
      ));

      await db.into(db.users).insert(UsersCompanion.insert(
        id: 'u_cashier',
        branchId: branchId,
        username: 'cashier1',
        displayName: 'كاشير',
        passwordHash: 'hash_123456',
        passwordSalt: 'salt',
        role: 'cashier',
        isActive: const Value(true),
        createdAt: now,
        updatedAt: now,
      ));

      await db.into(db.users).insert(UsersCompanion.insert(
        id: 'u_inactive_mgr',
        branchId: branchId,
        username: 'oldmgr',
        displayName: 'مدير معطل',
        passwordHash: 'hash_oldpass',
        passwordSalt: 'salt',
        role: 'manager',
        isActive: const Value(false),
        createdAt: now,
        updatedAt: now,
      ));

      expect(await ManagerAuthHelper.verifyManagerCredentials('admin', db: db), isFalse);
      expect(await ManagerAuthHelper.verifyManagerCredentials('123456', db: db), isFalse);
      expect(await ManagerAuthHelper.verifyManagerCredentials('oldpass', db: db), isFalse);
      expect(await ManagerAuthHelper.verifyManagerCredentials('Boss@99', db: db), isTrue);
      expect(await ManagerAuthHelper.verifyManagerCredentials('4321', db: db), isTrue);
    });
  });

  group('Addendum 30.13: Official Price Update & Cache Sync', () {
    test('VariantLocalDataSource updates sellPrice and PosCubit updates cache without touching old SaleItems', () async {
      final now = DateTime.now();
      final variantDs = VariantLocalDataSource(db, branchProvider, tx);

      await db.into(db.categories).insert(CategoriesCompanion.insert(
        id: 'cat1',
        branchId: branchId,
        name: 'ملابس',
        createdAt: now,
        updatedAt: now,
      ));
      await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'p1',
        branchId: branchId,
        name: 'قميص قطن',
        categoryId: 'cat1',
        createdAt: now,
        updatedAt: now,
      ));
      await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
        id: 'v1',
        branchId: branchId,
        productId: 'p1',
        sku: 'SH-1',
        color: 'أبيض',
        size: 'L',
        quantity: const Value(10),
        costPrice: 15000,
        sellPrice: 25000,
        createdAt: now,
        updatedAt: now,
      ));

      // Old historical sale at 250.00 EGP
      await db.into(db.sales).insert(SalesCompanion.insert(
        id: 'old_sale',
        branchId: branchId,
        shortRef: 'OLD1',
        cashierId: 'c1',
        subtotal: 25000,
        discountType: 'none',
        total: 25000,
        paymentMethod: 'cash',
        date: now.subtract(const Duration(days: 2)),
        createdAt: now,
        updatedAt: now,
      ));
      await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
        id: 'old_si',
        branchId: branchId,
        saleId: 'old_sale',
        variantId: 'v1',
        productName: 'قميص قطن',
        color: 'أبيض',
        size: 'L',
        qty: 1,
        priceSnapshot: 25000,
        costSnapshot: 15000,
        lineTotal: 25000,
        createdAt: now,
      ));

      await variantDs.updateVariant(
        'v1',
        sku: 'SH-1',
        color: 'أبيض',
        size: 'L',
        sellPrice: 30000,
        userId: 'admin_1',
      );

      final updatedVariant = await variantDs.getVariantById('v1');
      expect(updatedVariant?.sellPrice, 30000);

      final oldSaleItem = await (db.select(db.saleItems)
            ..where((si) => si.id.equals('old_si')))
          .getSingle();
      expect(oldSaleItem.priceSnapshot, 25000);

      final posCubit = PosCubit(
        CreateSaleUseCase(_TestPosRepo()),
        _TestVariantRepo([
          VariantEntity(
            id: 'v1',
            productId: 'p1',
            productCode: 'SH-1',
            productName: 'قميص قطن',
            color: 'أبيض',
            size: 'L',
            quantity: 10,
            minStock: 5,
            costPrice: 15000,
            salePrice: 25000,
            createdAt: now,
          ),
        ]),
        _TestCategoryRepo(),
        _TestProductRepo(),
        _TestPosRepo(),
      );
      await posCubit.init();
      await Future<void>.delayed(Duration.zero);
      posCubit.updateVariantSalePriceInCache('v1', 30000);
      expect(posCubit.state.filteredVariants.first.salePrice, 30000);
      await posCubit.close();
    });
  });

  group('Addendum 30.13: ReturnScreen Manager Approval & BlindReceiveScreen Cost Hiding', () {
    testWidgets('ReturnScreen requires real manager approval when cashier has managerPinProtection enabled', (tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.now();
      await db.into(db.users).insert(UsersCompanion.insert(
        id: 'u_admin',
        branchId: branchId,
        username: 'boss',
        displayName: 'المدير',
        passwordHash: 'hash_SecRet#1',
        passwordSalt: 'salt',
        role: 'admin',
        isActive: const Value(true),
        createdAt: now,
        updatedAt: now,
      ));

      final authDs = _FakeAuthLocalDataSource();
      await authDs.cacheUser(
        UserModel(
          id: 'u_admin',
          name: 'المدير',
          email: 'boss@test.com',
          role: 'admin',
          isActive: true,
          createdAt: now,
        ),
      );
      final featureGate = FeatureGate(db, authDs, tx, branchProvider);
      await featureGate.setFeatureEnabled(
        FeatureKeys.managerPinProtection,
        true,
        userId: 'u_admin',
      );

      final sl = GetIt.instance;
      await sl.reset();
      sl.registerSingleton<AppDatabase>(db);
      sl.registerSingleton<FeatureGate>(featureGate);
      addTearDown(() async => sl.reset());

      final sale = SaleEntity(
        id: 's1',
        date: now,
        cashierId: 'c1',
        cashierName: 'كاشير',
        items: const [],
        subtotal: 10000,
        discount: 0,
        total: 10000,
        paymentMethod: 'cash',
      );
      final fakeReturnsCubit = _FakeReturnsCubit(
        ReturnsState(
          selectedSale: sale,
          returnItems: const [
            ReturnItemEntity(
              saleItemId: 'si1',
              variantId: 'v1',
              productName: 'حذاء رياضي',
              color: 'أسود',
              size: '42',
              maxQty: 1,
              qty: 1,
              refundUnitPrice: 10000,
            ),
          ],
        ),
      );
      sl.registerFactory<ReturnsCubit>(() => fakeReturnsCubit);

      final cashierAuth = _FakeAuthCubit(
        UserModel(
          id: 'c1',
          name: 'كاشير',
          email: 'cashier@test.com',
          role: 'cashier',
          isActive: true,
          createdAt: now,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: BlocProvider<AuthCubit>.value(
              value: cashierAuth,
              child: const ReturnScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('تأكيد وإتمام المرتجع'));
      await tester.pumpAndSettle();

      // Manager approval dialog must appear; processReturn not called yet
      expect(find.byKey(const Key('manager_void_dialog')), findsOneWidget);
      expect(fakeReturnsCubit.processReturnCalls, 0);

      // Wrong password rejected
      await tester.enterText(
        find.byKey(const Key('manager_void_password_field')),
        '123456',
      );
      await tester.tap(find.byKey(const Key('manager_void_confirm_btn')));
      await tester.pumpAndSettle();
      expect(fakeReturnsCubit.processReturnCalls, 0);
      expect(find.byKey(const Key('manager_void_dialog')), findsOneWidget);

      // Real manager password accepted
      await tester.enterText(
        find.byKey(const Key('manager_void_password_field')),
        'SecRet#1',
      );
      await tester.tap(find.byKey(const Key('manager_void_confirm_btn')));
      await tester.pumpAndSettle();
      expect(fakeReturnsCubit.processReturnCalls, 1);
    });

    testWidgets('BlindReceiveScreen hides cost price column from cashier', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.now();
      await db.into(db.categories).insert(CategoriesCompanion.insert(
        id: 'cat1',
        branchId: branchId,
        name: 'أحذية',
        createdAt: now,
        updatedAt: now,
      ));
      await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'p1',
        branchId: branchId,
        name: 'كوتشي أبيض',
        categoryId: 'cat1',
        createdAt: now,
        updatedAt: now,
      ));
      await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
        id: 'v1',
        branchId: branchId,
        productId: 'p1',
        sku: 'SHOE-1',
        color: 'أبيض',
        size: '42',
        quantity: const Value(5),
        costPrice: 30000,
        sellPrice: 45000,
        createdAt: now,
        updatedAt: now,
      ));

      final inventoryDs = InventoryLocalDataSource(db, branchProvider, tx);
      final sl = GetIt.instance;
      await sl.reset();
      sl.registerSingleton<AppDatabase>(db);
      sl.registerSingleton<InventoryLocalDataSource>(inventoryDs);
      addTearDown(() async => sl.reset());

      final cashierAuth = _FakeAuthCubit(
        UserModel(
          id: 'c1',
          name: 'كاشير',
          email: 'cashier@test.com',
          role: 'cashier',
          isActive: true,
          createdAt: now,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: BlocProvider<AuthCubit>.value(
              value: cashierAuth,
              child: const BlindReceiveScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Add item via search field
      await tester.enterText(find.byType(TextField).first, 'SHOE-1');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('كوتشي أبيض'), findsWidgets);
      expect(find.text('سعر الشراء'), findsNothing);
      expect(find.byKey(const Key('edit_cost_price_btn_v1')), findsNothing);
    });
  });

  group('Addendum 30.13 (Items 6 & 7): Super Admin PIN Gate & Restore Restriction', () {
    testWidgets('Super Admin PIN locks StorePreset switching in SystemSettingsScreen until unlocked', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.now();
      final authDs = _FakeAuthLocalDataSource();
      await authDs.cacheUser(
        UserModel(
          id: 'u_admin',
          name: 'المدير',
          email: 'boss@test.com',
          role: 'admin',
          isActive: true,
          createdAt: now,
        ),
      );
      final featureGate = FeatureGate(db, authDs, tx, branchProvider);
      final activityService = ActivitySettingsService(db, featureGate);
      await featureGate.setMeta(
        ManagerAuthHelper.superAdminPinMetaKey,
        '9988',
        userId: 'u_admin',
      );

      final sl = GetIt.instance;
      await sl.reset();
      sl.registerSingleton<AppDatabase>(db);
      sl.registerSingleton<FeatureGate>(featureGate);
      sl.registerSingleton<ActivitySettingsService>(activityService);
      sl.registerFactory<SettingsCubit>(() => SettingsCubit(featureGate));
      addTearDown(() async => sl.reset());

      final adminAuth = _FakeAuthCubit(
        UserModel(
          id: 'u_admin',
          name: 'المدير',
          email: 'boss@test.com',
          role: 'admin',
          isActive: true,
          createdAt: now,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: BlocProvider<AuthCubit>.value(
              value: adminAuth,
              child: const SystemSettingsScreen(initialCategory: 'activities'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('store_preset_electronics')));
      await tester.pumpAndSettle();

      // Super Admin PIN dialog must appear
      expect(find.byKey(const Key('super_admin_pin_dialog')), findsOneWidget);

      // Wrong PIN rejected
      await tester.enterText(find.byKey(const Key('super_admin_pin_field')), '0000');
      await tester.tap(find.byKey(const Key('super_admin_pin_confirm_btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('super_admin_pin_dialog')), findsOneWidget);

      // Correct Super Admin PIN unlocks & applies preset
      await tester.enterText(find.byKey(const Key('super_admin_pin_field')), '9988');
      await tester.tap(find.byKey(const Key('super_admin_pin_confirm_btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('super_admin_pin_dialog')), findsNothing);
      expect(find.text('تم تطبيق قالب معرض أجهزة وإلكترونيات بنجاح!'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('LocalBackupCard blocks restore for non-admin (cashier) role', (tester) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.now();
      final sl = GetIt.instance;
      await sl.reset();
      sl.registerSingleton<AppDatabase>(db);
      sl.registerSingleton<LocalBackupService>(_FakeLocalBackupService());
      addTearDown(() async => sl.reset());

      final cashierAuth = _FakeAuthCubit(
        UserModel(
          id: 'c1',
          name: 'كاشير',
          email: 'cashier@test.com',
          role: 'cashier',
          isActive: true,
          createdAt: now,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: BlocProvider<AuthCubit>.value(
                value: cashierAuth,
                child: const SingleChildScrollView(
                  child: LocalBackupCard(userId: 'c1'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('backup_restore_btn')));
      await tester.pumpAndSettle();

      expect(
        find.text('استعادة النسخة الاحتياطية متاحة لمدير النظام (Admin) فقط'),
        findsOneWidget,
      );
    });
  });
}
