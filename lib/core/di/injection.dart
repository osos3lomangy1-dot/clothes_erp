import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'injection.config.dart';
import '../../features/auth/data/datasources/auth_local_data_source.dart';
import '../../features/employees/domain/repositories/employee_repository.dart';
import '../../features/employees/presentation/cubits/cashier_payroll_cubit.dart';
import '../../features/installments/data/services/manager_pin_service.dart';
import '../../features/settings/presentation/cubits/settings_cubit.dart';
import '../database/app_database.dart';
import '../database/branch_provider.dart';
import '../database/tx_writer.dart';
import '../features/feature_gate.dart';
import '../services/excel_workbook_service.dart';
import '../services/google_drive_backup_service.dart';
import '../services/local_backup_service.dart';

final getIt = GetIt.instance;

@InjectableInit()
Future<void> configureDependencies() async {
  getIt.init();
  if (!getIt.isRegistered<CashierPayrollCubit>()) {
    getIt.registerFactory<CashierPayrollCubit>(
      () => CashierPayrollCubit(getIt<EmployeeRepository>()),
    );
  }
  if (!getIt.isRegistered<FeatureGate>()) {
    getIt.registerLazySingleton<FeatureGate>(
      () => FeatureGate(
        getIt<AppDatabase>(),
        getIt<AuthLocalDataSource>(),
        getIt<TxWriter>(),
        getIt<BranchProvider>(),
      ),
    );
  }
  if (!getIt.isRegistered<ManagerPinService>()) {
    getIt.registerLazySingleton<ManagerPinService>(
      () => ManagerPinService(
        getIt<AppDatabase>(),
        getIt<TxWriter>(),
        getIt<BranchProvider>(),
        getIt<AuthLocalDataSource>(),
        getIt<FeatureGate>(),
      ),
    );
  }
  if (!getIt.isRegistered<SettingsCubit>()) {
    getIt.registerFactory<SettingsCubit>(() => SettingsCubit(getIt<FeatureGate>()));
  }
  if (!getIt.isRegistered<LocalBackupService>()) {
    getIt.registerLazySingleton<LocalBackupService>(
      () => LocalBackupService(
        getIt<AppDatabase>(),
        getIt<FeatureGate>(),
      ),
    );
  }
  if (!getIt.isRegistered<GoogleDriveBackupService>()) {
    getIt.registerLazySingleton<GoogleDriveBackupService>(
      () => GoogleDriveBackupService(
        getIt<LocalBackupService>(),
        getIt<FeatureGate>(),
      ),
    );
  }
  if (!getIt.isRegistered<ExcelWorkbookService>()) {
    getIt.registerLazySingleton<ExcelWorkbookService>(
      () => ExcelWorkbookService(
        getIt<AppDatabase>(),
        getIt<BranchProvider>(),
        getIt<TxWriter>(),
      ),
    );
  }
}
