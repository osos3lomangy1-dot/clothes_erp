import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/layout/main_layout.dart';
import 'package:clothes_erp/core/services/rest_sync_service.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/inventory/data/datasources/inventory_local_data_source.dart';
import 'package:clothes_erp/features/product_variants/data/datasources/variant_local_data_source.dart';
import 'package:clothes_erp/features/products/data/datasources/product_local_data_source.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

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

class _FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _FakeAuthCubit(UserModel user) : super(AuthAuthenticated(user));
  @override
  Future<void> login(String email, String password) async {}
  @override
  Future<void> logout() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SpyRestSyncService implements RestSyncService {
  int startAutoSyncCalls = 0;
  int stopAutoSyncCalls = 0;

  @override
  void startAutoSync({Duration interval = const Duration(minutes: 5)}) {
    startAutoSyncCalls++;
  }

  @override
  void stopAutoSync() {
    stopAutoSyncCalls++;
  }

  @override
  Stream<bool> get isSyncingStream => Stream.value(false);
  @override
  Stream<int> watchPendingCount() => Stream.value(0);
  @override
  bool get isSyncing => false;
  @override
  Future<SyncResult> syncPendingData() async =>
      const SyncResult(total: 0, synced: 0, failed: 0);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StatefulCounterPage extends StatefulWidget {
  const _StatefulCounterPage();
  @override
  State<_StatefulCounterPage> createState() => _StatefulCounterPageState();
}

class _StatefulCounterPageState extends State<_StatefulCounterPage> {
  int count = 0;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => setState(() => count++),
          child: Text('العداد: $count'),
        ),
      ),
    );
  }
}

void main() {
  final sl = GetIt.instance;
  late AppDatabase db;
  late BranchProvider bp;
  late TxWriter tx;
  late ProductLocalDataSource pds;
  late VariantLocalDataSource vds;
  late InventoryLocalDataSource ids;
  late FeatureGate gate;
  late _SpyRestSyncService syncSpy;
  late UserModel adminUser;

  setUp(() async {
    await sl.reset();
    db = AppDatabase(NativeDatabase.memory());
    bp = BranchProvider(db);
    tx = TxWriter(db);
    pds = ProductLocalDataSource(db, bp, tx);
    vds = VariantLocalDataSource(db, bp, tx);
    ids = InventoryLocalDataSource(db, bp, tx);
    adminUser = UserModel(
      id: 'admin-1',
      name: 'Admin',
      email: 'admin@store.com',
      role: 'admin',
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
    );
    final authDs = _FakeAuthDs()..setUser(adminUser);
    gate = FeatureGate(db, authDs, tx, bp);
    syncSpy = _SpyRestSyncService();

    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<FeatureGate>(gate);
    sl.registerSingleton<RestSyncService>(syncSpy);
  });

  tearDown(() async {
    await db.close();
    await sl.reset();
  });

  group('Stocktake (Inventory Audit) Tests', () {
    test('commitStocktake updates only changed variants and logs stocktake movements', () async {
      await pds.createProduct(name: 'قميص قطن', categoryId: 'c1');
      final prod = (await pds.getProducts()).first;

      await vds.createVariant(
        productId: prod.id,
        sku: 'ST-1',
        color: 'أبيض',
        size: 'M',
        costPrice: 10000, // 100 EGP
        sellPrice: 20000,
        quantity: 10,
      );
      await vds.createVariant(
        productId: prod.id,
        sku: 'ST-2',
        color: 'أسود',
        size: 'L',
        costPrice: 15000, // 150 EGP
        sellPrice: 25000,
        quantity: 5,
      );
      await vds.createVariant(
        productId: prod.id,
        sku: 'ST-3',
        color: 'كحلي',
        size: 'XL',
        costPrice: 10000,
        sellPrice: 20000,
        quantity: 8,
      );

      final variants = await vds.getVariants(prod.id);
      final v1 = variants.firstWhere((v) => v.sku == 'ST-1');
      final v2 = variants.firstWhere((v) => v.sku == 'ST-2');
      final v3 = variants.firstWhere((v) => v.sku == 'ST-3');

      // v1: 10 -> 7 (-3 shortage, -30,000 piasters)
      // v2: 5 -> 7 (+2 surplus, +30,000 piasters)
      // v3: 8 -> 8 (no change)
      final res = await ids.commitStocktake(
        items: [
          StocktakeAdjustmentItem(variantId: v1.id, actualQuantity: 7),
          StocktakeAdjustmentItem(variantId: v2.id, actualQuantity: 7),
          StocktakeAdjustmentItem(variantId: v3.id, actualQuantity: 8),
        ],
        userId: 'admin-1',
        notes: 'جرد نوفمبر',
      );

      expect(res.adjustedCount, equals(2));
      expect(res.totalShortageUnits, equals(3));
      expect(res.totalSurplusUnits, equals(2));
      expect(res.netVarianceCostPiasters, equals(0)); // -3*10000 + 2*15000 = 0

      final updatedV1 = await vds.getVariantById(v1.id);
      final updatedV2 = await vds.getVariantById(v2.id);
      final updatedV3 = await vds.getVariantById(v3.id);

      expect(updatedV1!.quantity, equals(7));
      expect(updatedV2!.quantity, equals(7));
      expect(updatedV3!.quantity, equals(8));

      final stocktakeLogs = await (db.select(db.inventoryLogs)
            ..where((l) => l.type.equals('stocktake')))
          .get();
      expect(stocktakeLogs.length, equals(2));
      expect(stocktakeLogs.every((l) => l.refType == 'stocktake'), isTrue);
    });

    test('commitStocktake rejects negative actualQuantity', () async {
      await expectLater(
        ids.commitStocktake(
          items: const [StocktakeAdjustmentItem(variantId: 'v1', actualQuantity: -1)],
          userId: 'admin-1',
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('MainLayout Active-Item Guard & Optional Cloud Sync Tests', () {
    testWidgets('clicking already-active sidebar item does NOT reload page state', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: BlocProvider<AuthCubit>.value(
              value: _FakeAuthCubit(adminUser),
              child: const MainLayout(
                currentRoute: '/dashboard',
                child: _StatefulCounterPage(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Increment state on active page
      await tester.tap(find.text('العداد: 0'));
      await tester.pumpAndSettle();
      expect(find.text('العداد: 1'), findsOneWidget);

      // Tap already-active sidebar item 'لوحة التحكم'
      await tester.tap(find.text('لوحة التحكم'));
      await tester.pumpAndSettle();

      // State MUST remain preserved (page did NOT reload!)
      expect(find.text('العداد: 1'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('cloud sync is disabled by default and toggles live via FeatureGate', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: BlocProvider<AuthCubit>.value(
              value: _FakeAuthCubit(adminUser),
              child: const MainLayout(
                currentRoute: '/dashboard',
                child: Scaffold(body: Center(child: Text('محتوى'))),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default: cloud sync disabled -> hidden in sidebar & autoSync not started
      expect(find.text('السحابة متزامنة'), findsNothing);
      expect(syncSpy.startAutoSyncCalls, equals(0));

      // Enable cloud sync
      await gate.setMeta('sync.cloud_enabled', '1', userId: adminUser.id);
      await tester.pumpAndSettle();

      expect(find.text('السحابة متزامنة'), findsOneWidget);
      expect(syncSpy.startAutoSyncCalls, greaterThanOrEqualTo(1));

      // Disable cloud sync again
      await gate.setMeta('sync.cloud_enabled', '0', userId: adminUser.id);
      await tester.pumpAndSettle();

      expect(find.text('السحابة متزامنة'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
