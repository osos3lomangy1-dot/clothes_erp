import 'package:clothes_erp/core/constants/retail_sector.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/layout/main_layout.dart';
import 'package:clothes_erp/core/services/shortcut_settings_service.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/categories/domain/entities/category_entity.dart';
import 'package:clothes_erp/features/categories/presentation/cubits/category_cubit.dart';
import 'package:clothes_erp/features/categories/presentation/cubits/category_state.dart';
import 'package:clothes_erp/features/dashboard/presentation/cubits/dashboard_cubit.dart';
import 'package:clothes_erp/features/dashboard/presentation/cubits/dashboard_state.dart';
import 'package:clothes_erp/features/invoices/data/services/receipt_settings_service.dart';
import 'package:clothes_erp/features/invoices/domain/entities/receipt_config.dart';
import 'package:clothes_erp/features/invoices/presentation/screens/receipt_customizer_screen.dart';
import 'package:clothes_erp/features/invoices/presentation/widgets/thermal_receipt_live_preview.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/products/presentation/cubits/product_cubit.dart';
import 'package:clothes_erp/features/products/presentation/cubits/product_state.dart';
import 'package:clothes_erp/features/products/presentation/screens/product_list_screen.dart';
import 'package:clothes_erp/features/settings/data/services/activity_settings_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

class _FakeBranchProvider implements BranchProvider {
  @override
  Future<String> getBranchId() async => 'branch-1';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

class _FakeDashboardCubit extends Cubit<DashboardState>
    implements DashboardCubit {
  _FakeDashboardCubit() : super(const DashboardState());
  @override
  Future<void> loadStats({bool silent = false}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProductCubit extends Cubit<ProductState> implements ProductCubit {
  _FakeProductCubit([List<ProductEntity> products = const []])
    : super(ProductLoaded(products));
  @override
  Future<void> getProducts() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCategoryCubit extends Cubit<CategoryState>
    implements CategoryCubit {
  _FakeCategoryCubit([List<CategoryEntity> categories = const []])
    : super(CategoryLoaded(categories));
  @override
  Future<void> getCategories() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sl = GetIt.instance;

  late AppDatabase db;
  late FeatureGate featureGate;
  late ActivitySettingsService activityService;
  late ShortcutSettingsService shortcutService;
  late _FakeAuthCubit authCubit;

  setUp(() async {
    await sl.reset();
    db = AppDatabase(NativeDatabase.memory());
    final authLocalDs = _FakeAuthLocalDataSource();
    final adminUser = UserModel(
      id: 'admin-1',
      name: 'المدير العام',
      email: 'admin@test.com',
      role: 'admin',
      isActive: true,
      createdAt: DateTime(2026, 11, 1),
    );
    await authLocalDs.cacheUser(adminUser);
    authCubit = _FakeAuthCubit(adminUser);

    featureGate = FeatureGate(
      db,
      authLocalDs,
      TxWriter(db),
      _FakeBranchProvider(),
    );
    activityService = ActivitySettingsService(db, featureGate);
    shortcutService = ShortcutSettingsService(db);

    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<FeatureGate>(featureGate);
    sl.registerSingleton<ActivitySettingsService>(activityService);
    sl.registerSingleton<ShortcutSettingsService>(shortcutService);
    sl.registerSingleton<AuthCubit>(authCubit);
    sl.registerFactory<DashboardCubit>(() => _FakeDashboardCubit());
    sl.registerFactory<ProductCubit>(() => _FakeProductCubit());
    sl.registerFactory<CategoryCubit>(() => _FakeCategoryCubit());

    ReceiptSettingsService.notifier.value = ReceiptConfig.defaults;
  });

  tearDown(() async {
    await db.close();
  });

  group('Task 34: Sidebar Cleanup, Sector Receipts, Products & Activity Guard', () {
    testWidgets(
      'MainLayout sidebar does not show barcode printing item in retail mode',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await featureGate.setFeatureEnabled(
          FeatureKeys.inventory,
          true,
          userId: 'system',
        );
        await featureGate.setMeta(
          RetailSector.metaKey,
          RetailSector.apparel,
          userId: 'system',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider<AuthCubit>.value(
              value: authCubit,
              child: const MainLayout(
                currentRoute: '/dashboard',
                child: Scaffold(body: Text('لوحة التحكم')),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('طباعة الباركود والملصقات'), findsNothing);

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
      },
    );

    testWidgets(
      'ReceiptCustomizerScreen hides hospitality template button in houseware mode and shows dynamic slogan',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await featureGate.setMeta(
          RetailSector.metaKey,
          RetailSector.houseware,
          userId: 'system',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider<AuthCubit>.value(
              value: authCubit,
              child: const Directionality(
                textDirection: TextDirection.rtl,
                child: ReceiptCustomizerScreen(),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('apply_hospitality_template_btn')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('apply_hospitality_template_body_btn')),
          findsNothing,
        );
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is InputDecorator &&
                (w.decoration.labelText?.contains(
                      'أجود الأدوات المنزلية والمفروشات العصرية',
                    ) ??
                    false),
          ),
          findsOneWidget,
        );
        expect(find.textContaining('طقم حلل جرانيت تركي'), findsOneWidget);
        expect(find.textContaining('مفرش سرير قطن'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
      },
    );

    testWidgets(
      'ThermalReceiptLivePreview adapts sample items for electronics, supermarket, apparel, and hospitality',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    ThermalReceiptLivePreview(
                      config: ReceiptConfig.defaults,
                      enabledActivities: [ActivityType.electronicsMobiles],
                    ),
                    ThermalReceiptLivePreview(
                      config: ReceiptConfig.defaults,
                      sectorMode: RetailSector.supermarket,
                    ),
                    ThermalReceiptLivePreview(
                      config: ReceiptConfig.defaults,
                      sectorMode: RetailSector.hospitality,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.textContaining('هاتف ذكي برو 256 جيجا'), findsOneWidget);
        expect(find.textContaining('أرز مصري 1 كجم'), findsOneWidget);
        expect(find.textContaining('وجبة برجر لحم مدخن'), findsOneWidget);
      },
    );

    testWidgets(
      'ProductListScreen in houseware mode adapts subtitle and button labels away from sizes/colors',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await featureGate.setMeta(
          RetailSector.metaKey,
          RetailSector.houseware,
          userId: 'system',
        );
        final sampleProduct = ProductEntity(
          id: 'p-hw-1',
          name: 'طقم حلل جرانيت',
          description: 'طقم أدوات منزلية',
          categoryId: 'cat-1',
          categoryName: 'أدوات المطبخ',
          createdAt: DateTime(2026, 11, 1),
          updatedAt: DateTime(2026, 11, 1),
        );

        await sl.unregister<ProductCubit>();
        sl.registerFactory<ProductCubit>(
          () => _FakeProductCubit([sampleProduct]),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider<AuthCubit>.value(
              value: authCubit,
              child: const Directionality(
                textDirection: TextDirection.rtl,
                child: ProductListScreen(),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.text('إدارة الأقسام والأصناف والأسعار والمخزون في مكان واحد'),
          findsOneWidget,
        );
        expect(find.text('الأنواع / الموديلات'), findsOneWidget);
        expect(find.text('المقاسات والألوان'), findsNothing);

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
      },
    );

    test(
      'ActivitySettingsService blocks mixing restaurantsCafes with retail activities while allowing compatible retail activities',
      () async {
        // Configure as pure houseware + textiles retail
        for (final act in ActivityType.values) {
          await featureGate.setMeta(
            'activity.${act.code}',
            (act == ActivityType.homeLiving ||
                    act == ActivityType.textilesDecor)
                ? '1'
                : '0',
            userId: 'system',
          );
        }
        final enabledRetail = await activityService.getEnabledActivities();
        expect(
          enabledRetail,
          containsAll([ActivityType.homeLiving, ActivityType.textilesDecor]),
        );

        // Compatible retail activity (electronicsMobiles) should succeed
        await activityService.setActivityEnabled(
          ActivityType.electronicsMobiles,
          true,
          userId: 'admin-1',
        );
        final afterCompat = await activityService.getEnabledActivities();
        expect(afterCompat, contains(ActivityType.electronicsMobiles));

        // Mixing restaurantsCafes with retail must throw clear multi-store message
        await expectLater(
          () => activityService.setActivityEnabled(
            ActivityType.restaurantsCafes,
            true,
            userId: 'admin-1',
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('تبديل المتجر'),
            ),
          ),
        );
      },
    );
  });
}
