import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'injection.config.dart';
import '../../features/employees/domain/repositories/employee_repository.dart';
import '../../features/employees/presentation/cubits/cashier_payroll_cubit.dart';

final getIt = GetIt.instance;

@InjectableInit()
Future<void> configureDependencies() async {
  getIt.init();
  if (!getIt.isRegistered<CashierPayrollCubit>()) {
    getIt.registerFactory<CashierPayrollCubit>(
      () => CashierPayrollCubit(getIt<EmployeeRepository>()),
    );
  }
}
