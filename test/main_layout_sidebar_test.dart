import 'dart:async';

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
import 'package:drift/drift.dart' hide Column;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

class FakeAuthLocalDataSource implements AuthLocalDataSource {
  UserModel? _user;
  void setUser(UserModel? user) => _user = user;
  @override
  Future<void> cacheUser(UserModel user) async => _user = user;
  @override
  Future<UserModel?> getCachedUser() async => _user;
  @override
  Future<void> clearCache() async => _user = null;
}

class FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  FakeAuthCubit(UserModel user) : super(AuthAuthenticated(user));
  @override
  Future<void> login(String email, String password) async {}
  @override
  Future<void> logout() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRestSyncService implements RestSyncService {
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
  Future<SyncResult> syncPendingData() async => const SyncResult(total: 0, synced: 0, failed: 0);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final sl = GetIt.instance;
  late AppDatabase db;
  late FeatureGate featureGate;
  late FakeAuthLocalDataSource authDs;
  late FakeRestSyncService syncService;
  late UserModel adminUser;

  setUp(() async {
    await sl.reset();
    db = AppDatabase(NativeDatabase.memory());
    authDs = FakeAuthLocalDataSource();
    adminUser = UserModel(
      id: 'admin-1',
      name: 'Admin User',
      email: 'admin@store.com',
      role: 'admin',
      isActive: true,
      createdAt: DateTime.now(),
    );
    authDs.setUser(adminUser);

    final txWriter = TxWriter(db);
    final branchProvider = BranchProvider(db);
    featureGate = FeatureGate(db, authDs, txWriter, branchProvider);
    syncService = FakeRestSyncService();

    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<FeatureGate>(featureGate);
    sl.registerSingleton<RestSyncService>(syncService);
  });

  tearDown(() async {
    await db.close();
    await sl.reset();
  });

  Widget buildTestWidget() {
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: BlocProvider<AuthCubit>.value(
          value: FakeAuthCubit(adminUser),
          child: const MainLayout(
            currentRoute: '/dashboard',
            child: Scaffold(body: Center(child: Text('محتوى لوحة التحكم'))),
          ),
        ),
      ),
    );
  }

  testWidgets('sidebar entry is hidden when feature.installments is disabled', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // installments feature is disabled by default
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('التقسيط'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('sidebar entry is visible when feature.installments is enabled', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // Enable installments feature
    await featureGate.setFeatureEnabled(FeatureKeys.installments, true, userId: adminUser.id);

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('التقسيط'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('sidebar entry remains visible when feature.installments is disabled but active contracts exist in DB', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // Seed an active contract in DB
    final now = DateTime.now();
    await db.into(db.customerInstallments).insert(
      CustomerInstallmentsCompanion.insert(
        id: 'ci_active_1',
        branchId: 'default',
        customerId: 'cust_1',
        saleId: 'sale_1',
        totalPiasters: 50000,
        principalPiasters: 50000,
        interestBp: 0,
        monthlyAmountPiasters: 10000,
        remainingPiasters: 25000,
        durationMonths: 5,
        startDate: now,
        endDate: now.add(const Duration(days: 150)),
        status: const Value('active'),
        createdBy: 'admin',
        createdAt: now,
        updatedAt: now,
      ),
    );

    // Feature is disabled, but active contract exists -> 'التقسيط' should remain visible
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('التقسيط'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
