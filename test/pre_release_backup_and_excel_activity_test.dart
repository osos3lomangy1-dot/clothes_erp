import 'dart:io';

import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/services/excel_workbook_models.dart';
import 'package:clothes_erp/core/services/excel_workbook_service.dart';
import 'package:clothes_erp/core/services/google_drive_backup_service.dart';
import 'package:clothes_erp/core/services/local_backup_service.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/products/domain/entities/activity_type.dart';
import 'package:clothes_erp/features/settings/data/services/activity_settings_service.dart';
import 'package:clothes_erp/features/shifts/domain/entities/shift_entity.dart';
import 'package:clothes_erp/features/shifts/domain/repositories/shift_repository.dart';
import 'package:clothes_erp/features/shifts/presentation/cubits/shift_cubit.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/native.dart';
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

class _FakeShiftRepository implements ShiftRepository {
  @override
  Future<Either<Failure, bool>> isShiftsEnabled() async => const Right(true);

  @override
  Future<Either<Failure, ShiftEntity?>> getActiveShift() async =>
      const Right(null);

  @override
  Future<Either<Failure, List<ShiftEntity>>> getShiftHistory({
    int limit = 50,
  }) async => const Right([]);

  @override
  Future<Either<Failure, ShiftEntity>> closeShift({
    required int countedBalance,
    String? shiftId,
    required String userId,
  }) async {
    final now = DateTime(2026, 11, 25, 3, 0);
    return Right(
      ShiftEntity(
        id: shiftId ?? 'shift-1',
        branchId: 'branch-1',
        cashierId: userId,
        openingBalance: 10000,
        openedAt: now.subtract(const Duration(hours: 8)),
        closedAt: now,
        expectedBalance: countedBalance,
        countedBalance: countedBalance,
        difference: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SpyLocalBackupService extends LocalBackupService {
  int autoCalls = 0;
  _SpyLocalBackupService(super.db, super.gate);

  @override
  Future<BackupResult?> runAutoBackupIfDue({DateTime? now}) async {
    autoCalls++;
    return null;
  }
}

class _SpyDriveBackupService extends GoogleDriveBackupService {
  int driveAutoCalls = 0;
  _SpyDriveBackupService(super.localBackup, super.gate);

  @override
  Future<DriveBackupFile?> runAutoDriveBackupIfDue({DateTime? now}) async {
    driveAutoCalls++;
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sl = GetIt.instance;

  late AppDatabase db;
  late FeatureGate gate;
  late Directory tempDir;

  setUp(() async {
    await sl.reset();
    db = AppDatabase(NativeDatabase.memory());
    final authDs = _FakeAuthLocalDataSource();
    await authDs.cacheUser(
      UserModel(
        id: 'admin-1',
        name: 'المدير',
        email: 'admin@test.com',
        role: 'admin',
        isActive: true,
        createdAt: DateTime(2026, 11, 1),
      ),
    );
    gate = FeatureGate(db, authDs, TxWriter(db), _FakeBranchProvider());
    tempDir = await Directory.systemTemp.createTemp('bay3ah_prereal_');
  });

  tearDown(() async {
    await sl.reset();
    await db.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Pre-Release Auto-Backup & Excel Activity Type', () {
    test(
      'LocalBackupService.runOnCloseBackupSnapshot creates atomic daily snapshot and cleans temp file',
      () async {
        final backupService = LocalBackupService(
          db,
          gate,
          defaultBackupDirProvider: () async => tempDir,
        );

        final targetDate = DateTime(2026, 11, 25, 22, 30);
        final res1 = await backupService.runOnCloseBackupSnapshot(
          now: targetDate,
        );
        expect(res1, isNotNull);
        expect(res1!.filePath, endsWith('auto_backup_2026-11-25.sqlite'));
        expect(File(res1.filePath).existsSync(), isTrue);
        expect(res1.sizeBytes, greaterThan(0));

        // Second on-close run on same day updates snapshot cleanly without temp leftovers
        final res2 = await backupService.runOnCloseBackupSnapshot(
          now: targetDate,
        );
        expect(res2, isNotNull);
        final leftovers = tempDir
            .listSync()
            .where((e) => e.path.contains('_tmp.sqlite'))
            .toList();
        expect(leftovers, isEmpty);

        // Disabled auto backup skips snapshot
        await gate.setMeta(BackupMetaKeys.autoEnabled, '0', userId: 'admin-1');
        final resDisabled = await backupService.runOnCloseBackupSnapshot(
          now: targetDate,
        );
        expect(resDisabled, isNull);
      },
    );

    test(
      'ShiftCubit.closeShift triggers LocalBackupService and GoogleDriveBackupService auto-backups when registered',
      () async {
        final spyLocal = _SpyLocalBackupService(db, gate);
        final spyDrive = _SpyDriveBackupService(spyLocal, gate);
        sl.registerSingleton<LocalBackupService>(spyLocal);
        sl.registerSingleton<GoogleDriveBackupService>(spyDrive);

        final cubit = ShiftCubit(_FakeShiftRepository());
        addTearDown(cubit.close);

        final closed = await cubit.closeShift(
          countedBalance: 25000,
          userId: 'cashier-1',
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(closed, isTrue);
        expect(spyLocal.autoCalls, 1);
        expect(spyDrive.driveAutoCalls, 1);
      },
    );

    test(
      'ExcelWorkbookService.executeWorkbookImport assigns active store activityType and honors explicit override',
      () async {
        final activityService = ActivitySettingsService(db, gate);
        for (final act in ActivityType.values) {
          await gate.setMeta(
            'activity.${act.code}',
            act == ActivityType.homeLiving ? '1' : '0',
            userId: 'system',
          );
        }

        final excelService = ExcelWorkbookService(
          db,
          _FakeBranchProvider(),
          TxWriter(db),
          activitySettingsService: activityService,
        );

        await excelService.executeWorkbookImport(
          preview: const WorkbookImportPreview(
            newProducts: [
              MigrationProductRow(
                rowNumber: 2,
                productName: 'طقم حلل جرانيت',
                categoryName: 'أدوات المطبخ',
                sku: 'HW-1001',
                size: '10 قطع',
                color: 'أسود',
                costPricePiasters: 150000,
                sellPricePiasters: 220000,
                wholesalePricePiasters: 195000,
                quantity: 12,
                minStock: 2,
              ),
            ],
          ),
          userId: 'admin-1',
        );

        await excelService.executeWorkbookImport(
          preview: const WorkbookImportPreview(
            newProducts: [
              MigrationProductRow(
                rowNumber: 3,
                productName: 'وجبة برجر خاص',
                categoryName: 'البرجر',
                sku: 'RST-2001',
                size: '-',
                color: '-',
                costPricePiasters: 5000,
                sellPricePiasters: 12000,
                wholesalePricePiasters: 12000,
                quantity: 50,
                minStock: 5,
              ),
            ],
          ),
          userId: 'admin-1',
          defaultActivityType: ActivityType.restaurantsCafes.code,
        );

        final inserted = await db.select(db.products).get();
        final hw = inserted.firstWhere((p) => p.name == 'طقم حلل جرانيت');
        final rst = inserted.firstWhere((p) => p.name == 'وجبة برجر خاص');

        expect(hw.activityType, ActivityType.homeLiving.code);
        expect(rst.activityType, ActivityType.restaurantsCafes.code);
      },
    );
  });
}
