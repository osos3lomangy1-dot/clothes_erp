import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/di/injection.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/products/domain/entities/activity_type.dart';
import 'package:clothes_erp/features/settings/data/services/activity_settings_service.dart';
import 'package:clothes_erp/features/settings/presentation/cubits/settings_cubit.dart';
import 'package:clothes_erp/features/settings/presentation/screens/system_settings_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthLocalDataSource implements AuthLocalDataSource {
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final adminUser = UserModel(
    id: 'admin-1',
    name: 'مدير النظام',
    email: 'admin@system.local',
    role: 'admin',
    isActive: true,
    createdAt: DateTime(2026, 1, 1),
  );

  group('Task 11.5 - Smart Store Presets Definition Tests', () {
    test('StorePreset contains all 6 commercial presets', () {
      expect(StorePreset.values.length, 6);
      expect(StorePreset.fashion.code, 'fashion');
      expect(StorePreset.electronics.code, 'electronics');
      expect(StorePreset.grocery.code, 'grocery');
      expect(StorePreset.hospitality.code, 'hospitality');
      expect(StorePreset.pharmacy.code, 'pharmacy');
      expect(StorePreset.custom.code, 'custom');
    });

    test('StorePreset icons and target activities match exact business requirements', () {
      // 1. Fashion
      expect(StorePreset.fashion.icon, Icons.checkroom_rounded);
      expect(StorePreset.fashion.activities, {
        ActivityType.clothing,
        ActivityType.footwearBags,
        ActivityType.accessoriesBeauty,
        ActivityType.perfumesCosmetics,
        ActivityType.watchesEyewear,
      });
      expect(StorePreset.fashion.enableInstallments, isFalse);

      // 2. Electronics
      expect(StorePreset.electronics.icon, Icons.devices_rounded);
      expect(StorePreset.electronics.activities, {
        ActivityType.electronicsMobiles,
        ActivityType.homeLiving,
      });
      expect(StorePreset.electronics.enableInstallments, isTrue);

      // 3. Grocery
      expect(StorePreset.grocery.icon, Icons.local_grocery_store_outlined);
      expect(StorePreset.grocery.activities, {
        ActivityType.supermarketGroceries,
        ActivityType.spicesNuts,
        ActivityType.sweetsBakery,
      });
      expect(StorePreset.grocery.enableInstallments, isFalse);

      // 4. Hospitality
      expect(StorePreset.hospitality.icon, Icons.restaurant_rounded);
      expect(StorePreset.hospitality.activities, {
        ActivityType.restaurantsCafes,
      });
      expect(StorePreset.hospitality.enableInstallments, isFalse);

      // 5. Pharmacy
      expect(StorePreset.pharmacy.icon, Icons.medical_services_outlined);
      expect(StorePreset.pharmacy.activities, {
        ActivityType.pharmacySupplies,
        ActivityType.perfumesCosmetics,
        ActivityType.kidsToys,
      });
      expect(StorePreset.pharmacy.enableInstallments, isFalse);

      // 6. Custom
      expect(StorePreset.custom.icon, Icons.tune_rounded);
      expect(StorePreset.custom.activities.length, equals(18));
    });

    test('StorePreset.detect accurately detects preset from active activity set', () {
      expect(StorePreset.detect(StorePreset.fashion.activities), StorePreset.fashion);
      expect(StorePreset.detect(StorePreset.electronics.activities), StorePreset.electronics);
      expect(StorePreset.detect(StorePreset.grocery.activities), StorePreset.grocery);
      expect(StorePreset.detect(StorePreset.hospitality.activities), StorePreset.hospitality);
      expect(StorePreset.detect(StorePreset.pharmacy.activities), StorePreset.pharmacy);

      // Mixed / Custom
      expect(StorePreset.detect({ActivityType.clothing}), StorePreset.custom);
      expect(StorePreset.detect({ActivityType.clothing, ActivityType.homeLiving}), StorePreset.custom);
      expect(StorePreset.detect(ActivityType.values.toSet()), StorePreset.custom);
    });
  });

  group('Task 11.5 - ActivitySettingsService applyStorePreset Operations', () {
    late AppDatabase db;
    late BranchProvider branchProvider;
    late _FakeAuthLocalDataSource auth;
    late FeatureGate featureGate;
    late ActivitySettingsService service;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      branchProvider = BranchProvider(db);
      auth = _FakeAuthLocalDataSource();
      auth.setUser(adminUser);
      featureGate = FeatureGate(db, auth, TxWriter(db), branchProvider);
      service = ActivitySettingsService(db, featureGate);
    });

    tearDown(() async {
      await db.close();
    });

    test('applying fashion preset enables only fashion activities', () async {
      await service.applyStorePreset(StorePreset.fashion, userId: 'admin-1');
      final enabled = await service.getEnabledActivities();

      expect(enabled.toSet(), StorePreset.fashion.activities);
      expect(StorePreset.detect(enabled.toSet()), StorePreset.fashion);
    });

    test('applying electronics preset enables electronics and enables installments', () async {
      await service.setInstallmentsEnabled(false, userId: 'admin-1');
      expect(await service.isInstallmentsEnabled(), isFalse);

      await service.applyStorePreset(StorePreset.electronics, userId: 'admin-1');
      final enabled = await service.getEnabledActivities();

      expect(enabled.toSet(), StorePreset.electronics.activities);
      expect(StorePreset.detect(enabled.toSet()), StorePreset.electronics);
      expect(await service.isInstallmentsEnabled(), isTrue);
    });

    test('applying grocery preset enables grocery, spices, and bakery', () async {
      await service.applyStorePreset(StorePreset.grocery, userId: 'admin-1');
      final enabled = await service.getEnabledActivities();

      expect(enabled.toSet(), StorePreset.grocery.activities);
      expect(StorePreset.detect(enabled.toSet()), StorePreset.grocery);
    });

    test('applying hospitality preset enables restaurantsCafes', () async {
      await service.applyStorePreset(StorePreset.hospitality, userId: 'admin-1');
      final enabled = await service.getEnabledActivities();

      expect(enabled.toSet(), StorePreset.hospitality.activities);
      expect(StorePreset.detect(enabled.toSet()), StorePreset.hospitality);
    });

    test('applying pharmacy preset enables pharmacy, cosmetics, and toys', () async {
      await service.applyStorePreset(StorePreset.pharmacy, userId: 'admin-1');
      final enabled = await service.getEnabledActivities();

      expect(enabled.toSet(), StorePreset.pharmacy.activities);
      expect(StorePreset.detect(enabled.toSet()), StorePreset.pharmacy);
    });
  });

  group('Task 11.5 - UI Widgets & Presets Bar Integration Tests', () {
    late AppDatabase db;
    late BranchProvider branchProvider;
    late _FakeAuthLocalDataSource auth;
    late FeatureGate featureGate;
    late ActivitySettingsService service;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      branchProvider = BranchProvider(db);
      auth = _FakeAuthLocalDataSource();
      auth.setUser(adminUser);
      featureGate = FeatureGate(db, auth, TxWriter(db), branchProvider);
      service = ActivitySettingsService(db, featureGate);

      if (getIt.isRegistered<AppDatabase>()) getIt.unregister<AppDatabase>();
      if (getIt.isRegistered<FeatureGate>()) getIt.unregister<FeatureGate>();
      if (getIt.isRegistered<ActivitySettingsService>()) getIt.unregister<ActivitySettingsService>();
      if (getIt.isRegistered<SettingsCubit>()) getIt.unregister<SettingsCubit>();

      getIt.registerSingleton<AppDatabase>(db);
      getIt.registerSingleton<FeatureGate>(featureGate);
      getIt.registerSingleton<ActivitySettingsService>(service);
      getIt.registerFactory<SettingsCubit>(() => SettingsCubit(featureGate));
    });

    tearDown(() async {
      if (getIt.isRegistered<AppDatabase>()) getIt.unregister<AppDatabase>();
      if (getIt.isRegistered<FeatureGate>()) getIt.unregister<FeatureGate>();
      if (getIt.isRegistered<ActivitySettingsService>()) getIt.unregister<ActivitySettingsService>();
      if (getIt.isRegistered<SettingsCubit>()) getIt.unregister<SettingsCubit>();
      await db.close();
    });

    testWidgets('SystemSettingsScreen renders all 6 preset cards and allows 1-click preset switching',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
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
              child: const SystemSettingsScreen(initialCategory: 'activities'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check all 6 presets are displayed
      expect(find.byKey(const Key('store_preset_fashion')), findsOneWidget);
      expect(find.byKey(const Key('store_preset_electronics')), findsOneWidget);
      expect(find.byKey(const Key('store_preset_grocery')), findsOneWidget);
      expect(find.byKey(const Key('store_preset_hospitality')), findsOneWidget);
      expect(find.byKey(const Key('store_preset_pharmacy')), findsOneWidget);
      expect(find.byKey(const Key('store_preset_custom')), findsOneWidget);

      // Tap on Electronics preset
      await tester.tap(find.byKey(const Key('store_preset_electronics')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify SnackBar
      expect(find.text('تم تطبيق قالب معرض أجهزة وإلكترونيات بنجاح!'), findsOneWidget);

      // Verify in service
      final enabled = await service.getEnabledActivities();
      expect(enabled.toSet(), StorePreset.electronics.activities);
      expect(await service.isInstallmentsEnabled(), isTrue);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
