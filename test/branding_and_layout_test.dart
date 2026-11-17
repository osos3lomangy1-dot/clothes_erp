import 'package:clothes_erp/core/constants/app_colors.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/layout/main_layout.dart';
import 'package:clothes_erp/core/services/rest_sync_service.dart';
import 'package:clothes_erp/core/theme/app_branding.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
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

class _FakeRestSyncService implements RestSyncService {
  @override
  void startAutoSync({Duration interval = const Duration(minutes: 5)}) {}
  @override
  void stopAutoSync() {}
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

void main() {
  final sl = GetIt.instance;
  late AppDatabase db;
  late FeatureGate gate;
  late _FakeAuthDs authDs;
  late UserModel adminUser;

  setUp(() async {
    await sl.reset();
    AppBranding.apply(AppBrandingConfig.defaults);

    db = AppDatabase(NativeDatabase.memory());
    adminUser = UserModel(
      id: 'admin-1',
      name: 'Admin',
      email: 'admin@store.com',
      role: 'admin',
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
    );
    authDs = _FakeAuthDs()..setUser(adminUser);
    final txWriter = TxWriter(db);
    final branchProvider = BranchProvider(db);
    gate = FeatureGate(db, authDs, txWriter, branchProvider);

    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<FeatureGate>(gate);
    sl.registerSingleton<RestSyncService>(_FakeRestSyncService());
  });

  tearDown(() async {
    AppBranding.apply(AppBrandingConfig.defaults);
    await db.close();
    await sl.reset();
  });

  group('AppBranding Dynamic Name & Colors Tests', () {
    test('parseHexColor parses 6-digit and 8-digit hex strings accurately', () {
      expect(AppBranding.parseHexColor('#0D47A1'), equals(const Color(0xFF0D47A1)));
      expect(AppBranding.parseHexColor('00695c'), equals(const Color(0xFF00695C)));
      expect(AppBranding.parseHexColor('FF880E4F'), equals(const Color(0xFF880E4F)));
      expect(AppBranding.parseHexColor('invalid'), isNull);
    });

    test('save persists branding to app_meta, updates AppColors, and reloads cleanly', () async {
      const customPrimary = Color(0xFF0D47A1);
      const customSecondary = Color(0xFF1976D2);

      await AppBranding.save(
        gate,
        appName: 'متجر الأناقة',
        primaryColor: customPrimary,
        secondaryColor: customSecondary,
        userId: adminUser.id,
      );

      expect(AppBranding.current.appName, equals('متجر الأناقة'));
      expect(AppColors.primary, equals(customPrimary));
      expect(AppColors.primaryContainer, equals(customSecondary));

      // Reset in-memory state and verify reload from DB
      AppBranding.apply(AppBrandingConfig.defaults);
      expect(AppBranding.current.appName, equals('سيستم مبيعات'));

      await AppBranding.loadFromFeatureGate(gate);
      expect(AppBranding.current.appName, equals('متجر الأناقة'));
      expect(AppBranding.current.primaryColor, equals(customPrimary));
      expect(AppBranding.current.secondaryColor, equals(customSecondary));
      expect(AppColors.primary, equals(customPrimary));

      // Reset to defaults via API
      await AppBranding.resetToDefaults(gate, userId: adminUser.id);
      expect(AppBranding.current.appName, equals(AppBrandingConfig.defaults.appName));
      expect(AppColors.primary, equals(AppBrandingConfig.defaults.primaryColor));
    });
  });

  group('MainLayout Nested Navigation & Live Branding Tests', () {
    testWidgets('sub-page pushed via Navigator stays inside MainLayout with Sidebar visible',
        (tester) async {
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
              child: MainLayout(
                currentRoute: '/dashboard',
                child: Builder(
                  builder: (innerCtx) => Scaffold(
                    body: Center(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(innerCtx).push(
                            MaterialPageRoute(
                              builder: (_) => const Scaffold(
                                body: Center(child: Text('صفحة فرعية داخل اللايوت')),
                              ),
                            ),
                          );
                        },
                        child: const Text('فتح صفحة فرعية'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Sidebar & initial content are visible
      expect(find.text('سيستم مبيعات'), findsOneWidget);
      expect(find.text('لوحة التحكم'), findsOneWidget);
      expect(find.text('فتح صفحة فرعية'), findsOneWidget);

      // Push sub-page
      await tester.tap(find.text('فتح صفحة فرعية'));
      await tester.pumpAndSettle();

      // Sub-page is displayed AND Sidebar is STILL visible!
      expect(find.text('صفحة فرعية داخل اللايوت'), findsOneWidget);
      expect(find.text('لوحة التحكم'), findsOneWidget);
      expect(find.text('سيستم مبيعات'), findsOneWidget);

      // Live branding update immediately updates Sidebar title!
      AppBranding.apply(
        const AppBrandingConfig(
          appName: 'إمبراطورية الملابس',
          primaryColor: Color(0xFF00695C),
          secondaryColor: Color(0xFF00897B),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('إمبراطورية الملابس'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}

