import 'dart:io';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/services/local_backup_service.dart';
import 'package:clothes_erp/core/services/store_profile_service.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/auth/presentation/screens/login_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

class _TestBranchProvider implements BranchProvider {
  @override
  Future<String> getBranchId() async => 'main_branch';
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
  _FakeAuthCubit() : super(AuthUnauthenticated());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory tempRoot;
  late Directory supportDir;
  late Directory docsDir;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('bay3ah_task33_');
    supportDir = Directory('${tempRoot.path}/support')..createSync(recursive: true);
    docsDir = Directory('${tempRoot.path}/docs')..createSync(recursive: true);
  });

  tearDown(() async {
    if (tempRoot.existsSync()) {
      try {
        await tempRoot.delete(recursive: true);
      } catch (_) {}
    }
  });

  group('Task 33: Multi-Store / Multi-Profile Isolated Workspaces', () {
    test('StoreProfileService preserves default clothes_erp.sqlite and isolates new profiles & backups', () async {
      final svc = StoreProfileService.withProviders(
        supportDirProvider: () async => supportDir,
        docsDirProvider: () async => docsDir,
      );
      await svc.init();

      expect(svc.activeProfileId, 'default');
      expect(svc.profiles.length, 1);
      final defaultDb = await svc.activeDbFile();
      expect(defaultDb.path, endsWith('clothes_erp.sqlite'));
      final defaultBackupDir = await svc.activeBackupDirectory();
      expect(defaultBackupDir.path, endsWith('SalesSystemBackups'));

      // Create second store profile
      final restaurantProfile = await svc.createProfile(
        name: 'مطعم البركة',
        activityLabel: 'مطاعم وكافيهات',
      );
      expect(svc.profiles.length, 2);
      final p2Db = await svc.dbFileFor(restaurantProfile.id);
      expect(p2Db.path, contains('profiles'));
      expect(p2Db.path, endsWith('store.sqlite'));

      final p2BackupDir = await svc.backupDirectoryFor(restaurantProfile.id);
      expect(p2BackupDir.path, contains('profiles'));
      expect(p2BackupDir.path, contains(restaurantProfile.id));

      // Switch active profile & verify persistence across restart
      await svc.setActiveProfile(restaurantProfile.id);
      final svcReloaded = StoreProfileService.withProviders(
        supportDirProvider: () async => supportDir,
        docsDirProvider: () async => docsDir,
      );
      await svcReloaded.init();
      expect(svcReloaded.activeProfileId, restaurantProfile.id);
      expect(svcReloaded.activeProfile.name, 'مطعم البركة');
      expect(svcReloaded.profiles.length, 2);
    });

    test('Complete isolation of data, users, settings, and local backups between two profiles', () async {
      final svc = StoreProfileService.withProviders(
        supportDirProvider: () async => supportDir,
        docsDirProvider: () async => docsDir,
      );
      await svc.init();
      final p2 = await svc.createProfile(name: 'سوبر ماركت النور');

      final dbFile1 = await svc.dbFileFor('default');
      final dbFile2 = await svc.dbFileFor(p2.id);

      final db1 = AppDatabase(NativeDatabase(dbFile1));
      final db2 = AppDatabase(NativeDatabase(dbFile2));
      addTearDown(() async {
        await db1.close();
        await db2.close();
      });

      final now = DateTime.now();
      final bp = _TestBranchProvider();
      final authDs = _FakeAuthLocalDataSource();
      await authDs.cacheUser(UserModel(
        id: 'admin_1',
        name: 'Admin',
        email: 'admin@test.com',
        role: 'admin',
        isActive: true,
        createdAt: now,
      ));

      // Seed Profile 1 (Apparel)
      final fg1 = FeatureGate(db1, authDs, TxWriter(db1), bp);
      await fg1.setMeta('app.branding.name', 'متجر الأزياء الملكي', userId: 'admin_1');
      await db1.into(db1.users).insert(UsersCompanion.insert(
        id: 'u_store1',
        branchId: 'main_branch',
        username: 'apparel_admin',
        displayName: 'مدير الأزياء',
        passwordHash: 'hash_1111',
        passwordSalt: 'salt',
        role: 'admin',
        createdAt: now,
        updatedAt: now,
      ));
      await db1.into(db1.categories).insert(CategoriesCompanion.insert(
        id: 'c1',
        branchId: 'main_branch',
        name: 'ملابس رجالي',
        createdAt: now,
        updatedAt: now,
      ));
      await db1.into(db1.products).insert(ProductsCompanion.insert(
        id: 'prod_1',
        branchId: 'main_branch',
        name: 'قميص قطن',
        categoryId: 'c1',
        createdAt: now,
        updatedAt: now,
      ));

      // Seed Profile 2 (Supermarket)
      final fg2 = FeatureGate(db2, authDs, TxWriter(db2), bp);
      await fg2.setMeta('app.branding.name', 'سوبر ماركت النور', userId: 'admin_1');
      await db2.into(db2.users).insert(UsersCompanion.insert(
        id: 'u_store2',
        branchId: 'main_branch',
        username: 'market_admin',
        displayName: 'مدير السوبرماركت',
        passwordHash: 'hash_2222',
        passwordSalt: 'salt',
        role: 'admin',
        createdAt: now,
        updatedAt: now,
      ));

      // Verify 100% isolation
      final users1 = await db1.select(db1.users).get();
      final users2 = await db2.select(db2.users).get();
      expect(users1.map((u) => u.username), ['apparel_admin']);
      expect(users2.map((u) => u.username), ['market_admin']);

      final prods1 = await db1.select(db1.products).get();
      final prods2 = await db2.select(db2.products).get();
      expect(prods1.length, 1);
      expect(prods2, isEmpty);

      expect(await fg1.getMeta('app.branding.name'), 'متجر الأزياء الملكي');
      expect(await fg2.getMeta('app.branding.name'), 'سوبر ماركت النور');

      // Verify isolated backups
      final backupDir1 = await svc.backupDirectoryFor('default');
      final backupDir2 = await svc.backupDirectoryFor(p2.id);
      final backupSvc1 = LocalBackupService(
        db1,
        fg1,
        defaultBackupDirProvider: () async => backupDir1,
        liveDbFileProvider: () async => dbFile1,
      );
      final backupSvc2 = LocalBackupService(
        db2,
        fg2,
        defaultBackupDirProvider: () async => backupDir2,
        liveDbFileProvider: () async => dbFile2,
      );

      await backupSvc1.createBackup(userId: 'admin_1');
      await backupSvc2.createBackup(userId: 'admin_1');

      final list1 = await backupSvc1.listBackups();
      final list2 = await backupSvc2.listBackups();
      expect(list1.length, 1);
      expect(list2.length, 1);
      expect(
        File(list1.first.path).parent.path,
        isNot(equals(File(list2.first.path).parent.path)),
      );
    });

    testWidgets('LoginScreen displays active profile badge and opens Store Profiles switcher dialog', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final sl = GetIt.instance;
      await sl.reset();
      addTearDown(() async => sl.reset());

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: BlocProvider<AuthCubit>.value(
              value: _FakeAuthCubit(),
              child: const LoginScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login_active_profile_badge')), findsOneWidget);
      expect(find.byKey(const Key('login_switch_profile_btn')), findsOneWidget);

      await tester.tap(find.byKey(const Key('login_switch_profile_btn')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('store_profiles_dialog')), findsOneWidget);
      expect(find.byKey(const Key('add_new_store_profile_btn')), findsOneWidget);
    });
  });
}
