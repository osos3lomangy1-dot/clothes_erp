import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'injection.config.dart';
import '../../features/auth/data/datasources/auth_local_data_source.dart';
import '../../features/customers/data/services/customer_ledger_service.dart';
import '../../features/delivery/data/datasources/delivery_local_data_source.dart';
import '../../features/delivery/data/repositories/delivery_repository_impl.dart';
import '../../features/delivery/domain/repositories/delivery_repository.dart';
import '../../features/delivery/presentation/cubits/delivery_cubit.dart';
import '../../features/pre_orders/data/datasources/pre_orders_local_data_source.dart';
import '../../features/pre_orders/data/repositories/pre_orders_repository_impl.dart';
import '../../features/pre_orders/domain/repositories/pre_orders_repository.dart';
import '../../features/pre_orders/presentation/cubits/pre_orders_cubit.dart';
import '../../features/employees/domain/repositories/employee_repository.dart';
import '../../features/employees/presentation/cubits/cashier_payroll_cubit.dart';
import '../../features/installments/data/services/manager_pin_service.dart';
import '../../features/reports/data/repositories/smart_inventory_repository_impl.dart';
import '../../features/reports/domain/repositories/smart_inventory_repository.dart';
import '../../features/reports/presentation/cubits/smart_inventory_cubit.dart';
import '../../features/settings/data/services/activity_settings_service.dart';
import '../../features/settings/presentation/cubits/settings_cubit.dart';
import '../../features/pre_orders/data/services/telegram_bot_service.dart';
import '../database/app_database.dart';
import '../database/branch_provider.dart';
import '../database/tx_writer.dart';
import '../features/feature_gate.dart';
import '../services/database_reset_service.dart';
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
  if (!getIt.isRegistered<CustomerLedgerService>()) {
    getIt.registerLazySingleton<CustomerLedgerService>(
      () => CustomerLedgerService(getIt<AppDatabase>()),
    );
  }
  if (!getIt.isRegistered<SmartInventoryRepository>()) {
    getIt.registerLazySingleton<SmartInventoryRepository>(
      () => SmartInventoryRepositoryImpl(getIt<AppDatabase>()),
    );
  }
  if (!getIt.isRegistered<SmartInventoryCubit>()) {
    getIt.registerFactory<SmartInventoryCubit>(
      () => SmartInventoryCubit(getIt<SmartInventoryRepository>()),
    );
  }
  if (!getIt.isRegistered<DeliveryLocalDataSource>()) {
    getIt.registerLazySingleton<DeliveryLocalDataSource>(
      () => DeliveryLocalDataSourceImpl(
        getIt<AppDatabase>(),
        getIt<BranchProvider>(),
      ),
    );
  }
  if (!getIt.isRegistered<DeliveryRepository>()) {
    getIt.registerLazySingleton<DeliveryRepository>(
      () => DeliveryRepositoryImpl(getIt<DeliveryLocalDataSource>()),
    );
  }
  if (!getIt.isRegistered<DeliveryCubit>()) {
    getIt.registerFactory<DeliveryCubit>(
      () => DeliveryCubit(
        getIt<DeliveryRepository>(),
        getIt<BranchProvider>(),
      ),
    );
  }
  if (!getIt.isRegistered<PreOrdersLocalDataSource>()) {
    getIt.registerLazySingleton<PreOrdersLocalDataSource>(
      () => PreOrdersLocalDataSourceImpl(
        getIt<AppDatabase>(),
        getIt<BranchProvider>(),
      ),
    );
  }
  if (!getIt.isRegistered<PreOrdersRepository>()) {
    getIt.registerLazySingleton<PreOrdersRepository>(
      () => PreOrdersRepositoryImpl(getIt<PreOrdersLocalDataSource>()),
    );
  }
  if (!getIt.isRegistered<PreOrdersCubit>()) {
    getIt.registerFactory<PreOrdersCubit>(
      () => PreOrdersCubit(getIt<PreOrdersRepository>()),
    );
  }
  if (!getIt.isRegistered<ActivitySettingsService>()) {
    getIt.registerLazySingleton<ActivitySettingsService>(
      () => ActivitySettingsService(getIt<AppDatabase>(), getIt<FeatureGate>()),
    );
  }
  if (!getIt.isRegistered<TelegramBotService>()) {
    getIt.registerLazySingleton<TelegramBotService>(
      () => TelegramBotService(getIt<AppDatabase>(), getIt<FeatureGate>()),
    );
  }
  if (!getIt.isRegistered<DatabaseResetService>()) {
    getIt.registerLazySingleton<DatabaseResetService>(
      () => DatabaseResetService(
        getIt<AppDatabase>(),
        getIt<LocalBackupService>(),
      ),
    );
  }
}
