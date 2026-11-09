// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:clothes_erp/core/database/app_database.dart' as _i110;
import 'package:clothes_erp/core/database/branch_provider.dart' as _i254;
import 'package:clothes_erp/core/database/tx_writer.dart' as _i874;
import 'package:clothes_erp/core/di/register_module.dart' as _i868;
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart'
    as _i526;
import 'package:clothes_erp/features/auth/data/datasources/auth_remote_data_source.dart'
    as _i1024;
import 'package:clothes_erp/features/auth/data/repositories/auth_repository_impl.dart'
    as _i1043;
import 'package:clothes_erp/features/auth/domain/repositories/auth_repository.dart'
    as _i689;
import 'package:clothes_erp/features/auth/domain/usecases/get_auth_status_usecase.dart'
    as _i1011;
import 'package:clothes_erp/features/auth/domain/usecases/login_usecase.dart'
    as _i443;
import 'package:clothes_erp/features/auth/domain/usecases/logout_usecase.dart'
    as _i661;
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart'
    as _i217;
import 'package:clothes_erp/features/auth/presentation/cubits/login_form_cubit.dart'
    as _i82;
import 'package:clothes_erp/features/categories/data/datasources/category_local_data_source.dart'
    as _i178;
import 'package:clothes_erp/features/categories/data/repositories/category_repository_impl.dart'
    as _i932;
import 'package:clothes_erp/features/categories/domain/repositories/category_repository.dart'
    as _i687;
import 'package:clothes_erp/features/categories/domain/usecases/add_category_usecase.dart'
    as _i745;
import 'package:clothes_erp/features/categories/domain/usecases/delete_category_usecase.dart'
    as _i544;
import 'package:clothes_erp/features/categories/domain/usecases/get_categories_usecase.dart'
    as _i368;
import 'package:clothes_erp/features/categories/domain/usecases/update_category_usecase.dart'
    as _i419;
import 'package:clothes_erp/features/categories/presentation/cubits/category_cubit.dart'
    as _i147;
import 'package:clothes_erp/features/categories/presentation/cubits/category_form_cubit.dart'
    as _i304;
import 'package:clothes_erp/features/customers/data/datasources/customers_local_data_source.dart'
    as _i548;
import 'package:clothes_erp/features/customers/data/repositories/customer_repository_impl.dart'
    as _i707;
import 'package:clothes_erp/features/customers/domain/repositories/customer_repository.dart'
    as _i610;
import 'package:clothes_erp/features/customers/presentation/cubits/customer_cubit.dart'
    as _i1043;
import 'package:clothes_erp/features/dashboard/data/datasources/dashboard_local_data_source.dart'
    as _i517;
import 'package:clothes_erp/features/dashboard/data/repositories/dashboard_repository_impl.dart'
    as _i729;
import 'package:clothes_erp/features/dashboard/domain/repositories/dashboard_repository.dart'
    as _i682;
import 'package:clothes_erp/features/dashboard/domain/usecases/get_dashboard_stats_usecase.dart'
    as _i1040;
import 'package:clothes_erp/features/dashboard/presentation/cubits/dashboard_cubit.dart'
    as _i774;
import 'package:clothes_erp/features/employees/data/datasources/employee_local_data_source.dart'
    as _i171;
import 'package:clothes_erp/features/employees/data/repositories/employee_repository_impl.dart'
    as _i466;
import 'package:clothes_erp/features/employees/domain/repositories/employee_repository.dart'
    as _i506;
import 'package:clothes_erp/features/employees/domain/usecases/add_employee_usecase.dart'
    as _i980;
import 'package:clothes_erp/features/employees/domain/usecases/delete_employee_usecase.dart'
    as _i712;
import 'package:clothes_erp/features/employees/domain/usecases/get_employees_usecase.dart'
    as _i248;
import 'package:clothes_erp/features/employees/domain/usecases/update_employee_status_usecase.dart'
    as _i500;
import 'package:clothes_erp/features/employees/domain/usecases/update_employee_usecase.dart'
    as _i188;
import 'package:clothes_erp/features/employees/presentation/cubits/employee_cubit.dart'
    as _i164;
import 'package:clothes_erp/features/employees/presentation/cubits/employee_form_cubit.dart'
    as _i361;
import 'package:clothes_erp/features/expenses/data/datasources/expenses_local_data_source.dart'
    as _i503;
import 'package:clothes_erp/features/expenses/data/repositories/expense_repository_impl.dart'
    as _i868;
import 'package:clothes_erp/features/expenses/domain/repositories/expense_repository.dart'
    as _i351;
import 'package:clothes_erp/features/expenses/presentation/cubits/expenses_cubit.dart'
    as _i773;
import 'package:clothes_erp/features/inventory/data/datasources/inventory_local_data_source.dart'
    as _i1019;
import 'package:clothes_erp/features/inventory/data/datasources/inventory_remote_data_source.dart'
    as _i303;
import 'package:clothes_erp/features/inventory/data/repositories/inventory_log_repository_impl.dart'
    as _i284;
import 'package:clothes_erp/features/inventory/data/repositories/inventory_repository_impl.dart'
    as _i351;
import 'package:clothes_erp/features/inventory/domain/repositories/inventory_log_repository.dart'
    as _i861;
import 'package:clothes_erp/features/inventory/domain/repositories/inventory_repository.dart'
    as _i898;
import 'package:clothes_erp/features/inventory/domain/usecases/get_all_inventory_usecase.dart'
    as _i926;
import 'package:clothes_erp/features/inventory/domain/usecases/get_low_stock_usecase.dart'
    as _i232;
import 'package:clothes_erp/features/inventory/presentation/cubits/inventory_cubit.dart'
    as _i779;
import 'package:clothes_erp/features/inventory/presentation/cubits/inventory_log_cubit.dart'
    as _i94;
import 'package:clothes_erp/features/partners/data/datasources/partners_local_data_source.dart'
    as _i556;
import 'package:clothes_erp/features/partners/data/repositories/partner_repository_impl.dart'
    as _i859;
import 'package:clothes_erp/features/partners/domain/repositories/partner_repository.dart'
    as _i971;
import 'package:clothes_erp/features/partners/presentation/cubits/partners_cubit.dart'
    as _i638;
import 'package:clothes_erp/features/pos/data/datasources/pos_local_data_source.dart'
    as _i926;
import 'package:clothes_erp/features/pos/data/repositories/pos_repository_impl.dart'
    as _i762;
import 'package:clothes_erp/features/pos/domain/repositories/pos_repository.dart'
    as _i862;
import 'package:clothes_erp/features/pos/domain/usecases/create_sale_usecase.dart'
    as _i747;
import 'package:clothes_erp/features/pos/presentation/cubits/pos_cubit.dart'
    as _i403;
import 'package:clothes_erp/features/product_variants/data/datasources/variant_local_data_source.dart'
    as _i577;
import 'package:clothes_erp/features/product_variants/data/repositories/variant_repository_impl.dart'
    as _i780;
import 'package:clothes_erp/features/product_variants/domain/repositories/variant_repository.dart'
    as _i77;
import 'package:clothes_erp/features/product_variants/domain/usecases/add_variant_usecase.dart'
    as _i202;
import 'package:clothes_erp/features/product_variants/domain/usecases/delete_variant_usecase.dart'
    as _i333;
import 'package:clothes_erp/features/product_variants/domain/usecases/get_variants_usecase.dart'
    as _i56;
import 'package:clothes_erp/features/product_variants/domain/usecases/update_variant_usecase.dart'
    as _i1031;
import 'package:clothes_erp/features/product_variants/presentation/cubits/variant_cubit.dart'
    as _i348;
import 'package:clothes_erp/features/product_variants/presentation/cubits/variant_form_cubit.dart'
    as _i624;
import 'package:clothes_erp/features/products/data/datasources/product_local_data_source.dart'
    as _i878;
import 'package:clothes_erp/features/products/data/repositories/product_repository_impl.dart'
    as _i492;
import 'package:clothes_erp/features/products/domain/repositories/product_repository.dart'
    as _i758;
import 'package:clothes_erp/features/products/domain/usecases/add_product_usecase.dart'
    as _i87;
import 'package:clothes_erp/features/products/domain/usecases/delete_product_usecase.dart'
    as _i592;
import 'package:clothes_erp/features/products/domain/usecases/get_products_usecase.dart'
    as _i423;
import 'package:clothes_erp/features/products/domain/usecases/update_product_usecase.dart'
    as _i287;
import 'package:clothes_erp/features/products/presentation/cubits/product_cubit.dart'
    as _i137;
import 'package:clothes_erp/features/products/presentation/cubits/product_form_cubit.dart'
    as _i548;
import 'package:clothes_erp/features/reports/data/datasources/reports_local_data_source.dart'
    as _i1045;
import 'package:clothes_erp/features/reports/data/repositories/reports_repository_impl.dart'
    as _i333;
import 'package:clothes_erp/features/reports/domain/repositories/reports_repository.dart'
    as _i633;
import 'package:clothes_erp/features/reports/domain/usecases/get_sales_report_usecase.dart'
    as _i957;
import 'package:clothes_erp/features/reports/presentation/cubits/reports_cubit.dart'
    as _i119;
import 'package:clothes_erp/features/returns/data/datasources/returns_local_data_source.dart'
    as _i207;
import 'package:clothes_erp/features/returns/data/repositories/returns_repository_impl.dart'
    as _i198;
import 'package:clothes_erp/features/returns/domain/repositories/returns_repository.dart'
    as _i681;
import 'package:clothes_erp/features/returns/domain/usecases/get_recent_sales_usecase.dart'
    as _i828;
import 'package:clothes_erp/features/returns/domain/usecases/process_return_usecase.dart'
    as _i881;
import 'package:clothes_erp/features/returns/presentation/cubits/returns_cubit.dart'
    as _i74;
import 'package:cloud_firestore/cloud_firestore.dart' as _i974;
import 'package:firebase_auth/firebase_auth.dart' as _i59;
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as _i558;
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;

extension GetItInjectableX on _i174.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(this, environment, environmentFilter);
    final registerModule = _$RegisterModule();
    gh.lazySingleton<_i558.FlutterSecureStorage>(
      () => registerModule.secureStorage,
    );
    gh.lazySingleton<_i110.AppDatabase>(() => registerModule.appDatabase);
    gh.lazySingleton<_i526.AuthLocalDataSource>(
      () => _i526.AuthLocalDataSourceImpl(gh<_i558.FlutterSecureStorage>()),
    );
    gh.lazySingleton<_i303.InventoryRemoteDataSource>(
      () => _i303.InventoryRemoteDataSourceImpl(gh<_i974.FirebaseFirestore>()),
    );
    gh.lazySingleton<_i861.InventoryLogRepository>(
      () => _i284.InventoryLogRepositoryImpl(gh<_i974.FirebaseFirestore>()),
    );
    gh.factory<_i94.InventoryLogCubit>(
      () => _i94.InventoryLogCubit(gh<_i861.InventoryLogRepository>()),
    );
    gh.lazySingleton<_i517.DashboardLocalDataSource>(
      () => _i517.DashboardLocalDataSourceImpl(gh<_i110.AppDatabase>()),
    );
    gh.factory<_i254.BranchProvider>(
      () => _i254.BranchProvider(gh<_i110.AppDatabase>()),
    );
    gh.lazySingleton<_i1045.ReportsLocalDataSource>(
      () => _i1045.ReportsLocalDataSourceImpl(gh<_i110.AppDatabase>()),
    );
    gh.lazySingleton<_i556.PartnersLocalDataSource>(
      () => _i556.PartnersLocalDataSourceImpl(gh<_i110.AppDatabase>()),
    );
    gh.lazySingleton<_i1024.AuthRemoteDataSource>(
      () => _i1024.AuthRemoteDataSourceImpl(
        gh<_i59.FirebaseAuth>(),
        gh<_i974.FirebaseFirestore>(),
      ),
    );
    gh.lazySingleton<_i178.CategoryLocalDataSource>(
      () => _i178.CategoryLocalDataSource(
        gh<_i110.AppDatabase>(),
        gh<_i254.BranchProvider>(),
      ),
    );
    gh.lazySingleton<_i689.AuthRepository>(
      () => _i1043.AuthRepositoryImpl(
        gh<_i1024.AuthRemoteDataSource>(),
        gh<_i526.AuthLocalDataSource>(),
        gh<_i110.AppDatabase>(),
      ),
    );
    gh.factory<_i874.TxWriter>(() => _i874.TxWriter(gh<_i110.AppDatabase>()));
    gh.lazySingleton<_i1011.GetAuthStatusUseCase>(
      () => _i1011.GetAuthStatusUseCase(gh<_i689.AuthRepository>()),
    );
    gh.lazySingleton<_i443.LoginUseCase>(
      () => _i443.LoginUseCase(gh<_i689.AuthRepository>()),
    );
    gh.lazySingleton<_i661.LogoutUseCase>(
      () => _i661.LogoutUseCase(gh<_i689.AuthRepository>()),
    );
    gh.lazySingleton<_i682.DashboardRepository>(
      () => _i729.DashboardRepositoryImpl(gh<_i517.DashboardLocalDataSource>()),
    );
    gh.lazySingleton<_i971.PartnerRepository>(
      () => _i859.PartnerRepositoryImpl(gh<_i556.PartnersLocalDataSource>()),
    );
    gh.lazySingleton<_i1040.GetDashboardStatsUseCase>(
      () => _i1040.GetDashboardStatsUseCase(gh<_i682.DashboardRepository>()),
    );
    gh.lazySingleton<_i633.ReportsRepository>(
      () => _i333.ReportsRepositoryImpl(gh<_i1045.ReportsLocalDataSource>()),
    );
    gh.factory<_i217.AuthCubit>(
      () => _i217.AuthCubit(
        gh<_i443.LoginUseCase>(),
        gh<_i661.LogoutUseCase>(),
        gh<_i1011.GetAuthStatusUseCase>(),
        gh<_i110.AppDatabase>(),
      ),
    );
    gh.factory<_i82.LoginFormCubit>(
      () => _i82.LoginFormCubit(gh<_i217.AuthCubit>()),
    );
    gh.factory<_i774.DashboardCubit>(
      () => _i774.DashboardCubit(gh<_i1040.GetDashboardStatsUseCase>()),
    );
    gh.lazySingleton<_i957.GetSalesReportUseCase>(
      () => _i957.GetSalesReportUseCase(gh<_i633.ReportsRepository>()),
    );
    gh.lazySingleton<_i503.ExpensesLocalDataSource>(
      () => _i503.ExpensesLocalDataSourceImpl(
        gh<_i110.AppDatabase>(),
        gh<_i254.BranchProvider>(),
        gh<_i874.TxWriter>(),
      ),
    );
    gh.lazySingleton<_i1019.InventoryLocalDataSource>(
      () => _i1019.InventoryLocalDataSource(
        gh<_i110.AppDatabase>(),
        gh<_i254.BranchProvider>(),
        gh<_i874.TxWriter>(),
      ),
    );
    gh.lazySingleton<_i577.VariantLocalDataSource>(
      () => _i577.VariantLocalDataSource(
        gh<_i110.AppDatabase>(),
        gh<_i254.BranchProvider>(),
        gh<_i874.TxWriter>(),
      ),
    );
    gh.lazySingleton<_i878.ProductLocalDataSource>(
      () => _i878.ProductLocalDataSource(
        gh<_i110.AppDatabase>(),
        gh<_i254.BranchProvider>(),
        gh<_i874.TxWriter>(),
      ),
    );
    gh.lazySingleton<_i687.CategoryRepository>(
      () => _i932.CategoryRepositoryImpl(gh<_i178.CategoryLocalDataSource>()),
    );
    gh.lazySingleton<_i898.InventoryRepository>(
      () =>
          _i351.InventoryRepositoryImpl(gh<_i1019.InventoryLocalDataSource>()),
    );
    gh.lazySingleton<_i171.EmployeeLocalDataSource>(
      () => _i171.EmployeeLocalDataSourceImpl(
        gh<_i110.AppDatabase>(),
        gh<_i254.BranchProvider>(),
        gh<_i874.TxWriter>(),
      ),
    );
    gh.lazySingleton<_i548.CustomersLocalDataSource>(
      () => _i548.CustomersLocalDataSourceImpl(
        gh<_i110.AppDatabase>(),
        gh<_i254.BranchProvider>(),
        gh<_i874.TxWriter>(),
      ),
    );
    gh.lazySingleton<_i351.ExpenseRepository>(
      () => _i868.ExpenseRepositoryImpl(gh<_i503.ExpensesLocalDataSource>()),
    );
    gh.lazySingleton<_i758.ProductRepository>(
      () => _i492.ProductRepositoryImpl(gh<_i878.ProductLocalDataSource>()),
    );
    gh.lazySingleton<_i77.VariantRepository>(
      () => _i780.VariantRepositoryImpl(gh<_i577.VariantLocalDataSource>()),
    );
    gh.lazySingleton<_i610.CustomerRepository>(
      () => _i707.CustomerRepositoryImpl(gh<_i548.CustomersLocalDataSource>()),
    );
    gh.factory<_i638.PartnersCubit>(
      () => _i638.PartnersCubit(gh<_i971.PartnerRepository>()),
    );
    gh.lazySingleton<_i202.AddVariantUseCase>(
      () => _i202.AddVariantUseCase(gh<_i77.VariantRepository>()),
    );
    gh.lazySingleton<_i333.DeleteVariantUseCase>(
      () => _i333.DeleteVariantUseCase(gh<_i77.VariantRepository>()),
    );
    gh.lazySingleton<_i56.GetVariantsUseCase>(
      () => _i56.GetVariantsUseCase(gh<_i77.VariantRepository>()),
    );
    gh.lazySingleton<_i1031.UpdateVariantUseCase>(
      () => _i1031.UpdateVariantUseCase(gh<_i77.VariantRepository>()),
    );
    gh.lazySingleton<_i926.GetAllInventoryUseCase>(
      () => _i926.GetAllInventoryUseCase(gh<_i898.InventoryRepository>()),
    );
    gh.lazySingleton<_i232.GetLowStockUseCase>(
      () => _i232.GetLowStockUseCase(gh<_i898.InventoryRepository>()),
    );
    gh.factory<_i119.ReportsCubit>(
      () => _i119.ReportsCubit(gh<_i957.GetSalesReportUseCase>()),
    );
    gh.factory<_i1043.CustomerCubit>(
      () => _i1043.CustomerCubit(gh<_i610.CustomerRepository>()),
    );
    gh.lazySingleton<_i926.PosLocalDataSource>(
      () => _i926.PosLocalDataSource(
        gh<_i110.AppDatabase>(),
        gh<_i254.BranchProvider>(),
        gh<_i874.TxWriter>(),
        gh<_i1019.InventoryLocalDataSource>(),
      ),
    );
    gh.lazySingleton<_i87.AddProductUseCase>(
      () => _i87.AddProductUseCase(gh<_i758.ProductRepository>()),
    );
    gh.lazySingleton<_i592.DeleteProductUseCase>(
      () => _i592.DeleteProductUseCase(gh<_i758.ProductRepository>()),
    );
    gh.lazySingleton<_i423.GetProductsUseCase>(
      () => _i423.GetProductsUseCase(gh<_i758.ProductRepository>()),
    );
    gh.lazySingleton<_i287.UpdateProductUseCase>(
      () => _i287.UpdateProductUseCase(gh<_i758.ProductRepository>()),
    );
    gh.lazySingleton<_i207.ReturnsLocalDataSource>(
      () => _i207.ReturnsLocalDataSourceImpl(
        gh<_i110.AppDatabase>(),
        gh<_i254.BranchProvider>(),
        gh<_i874.TxWriter>(),
        gh<_i1019.InventoryLocalDataSource>(),
      ),
    );
    gh.lazySingleton<_i745.AddCategoryUseCase>(
      () => _i745.AddCategoryUseCase(gh<_i687.CategoryRepository>()),
    );
    gh.lazySingleton<_i544.DeleteCategoryUseCase>(
      () => _i544.DeleteCategoryUseCase(gh<_i687.CategoryRepository>()),
    );
    gh.lazySingleton<_i368.GetCategoriesUseCase>(
      () => _i368.GetCategoriesUseCase(gh<_i687.CategoryRepository>()),
    );
    gh.lazySingleton<_i419.UpdateCategoryUseCase>(
      () => _i419.UpdateCategoryUseCase(gh<_i687.CategoryRepository>()),
    );
    gh.factory<_i147.CategoryCubit>(
      () => _i147.CategoryCubit(
        gh<_i368.GetCategoriesUseCase>(),
        gh<_i544.DeleteCategoryUseCase>(),
      ),
    );
    gh.factory<_i624.VariantFormCubit>(
      () => _i624.VariantFormCubit(
        gh<_i202.AddVariantUseCase>(),
        gh<_i1031.UpdateVariantUseCase>(),
      ),
    );
    gh.lazySingleton<_i506.EmployeeRepository>(
      () => _i466.EmployeeRepositoryImpl(gh<_i171.EmployeeLocalDataSource>()),
    );
    gh.factory<_i304.CategoryFormCubit>(
      () => _i304.CategoryFormCubit(
        gh<_i745.AddCategoryUseCase>(),
        gh<_i419.UpdateCategoryUseCase>(),
      ),
    );
    gh.factory<_i348.VariantCubit>(
      () => _i348.VariantCubit(
        gh<_i56.GetVariantsUseCase>(),
        gh<_i333.DeleteVariantUseCase>(),
      ),
    );
    gh.lazySingleton<_i681.ReturnsRepository>(
      () => _i198.ReturnsRepositoryImpl(gh<_i207.ReturnsLocalDataSource>()),
    );
    gh.lazySingleton<_i862.PosRepository>(
      () => _i762.PosRepositoryImpl(gh<_i926.PosLocalDataSource>()),
    );
    gh.factory<_i779.InventoryCubit>(
      () => _i779.InventoryCubit(
        gh<_i926.GetAllInventoryUseCase>(),
        gh<_i232.GetLowStockUseCase>(),
        gh<_i1019.InventoryLocalDataSource>(),
      ),
    );
    gh.factory<_i773.ExpensesCubit>(
      () => _i773.ExpensesCubit(gh<_i351.ExpenseRepository>()),
    );
    gh.factory<_i548.ProductFormCubit>(
      () => _i548.ProductFormCubit(
        gh<_i87.AddProductUseCase>(),
        gh<_i287.UpdateProductUseCase>(),
        gh<_i368.GetCategoriesUseCase>(),
        gh<_i758.ProductRepository>(),
      ),
    );
    gh.factory<_i137.ProductCubit>(
      () => _i137.ProductCubit(
        gh<_i423.GetProductsUseCase>(),
        gh<_i592.DeleteProductUseCase>(),
      ),
    );
    gh.lazySingleton<_i980.AddEmployeeUseCase>(
      () => _i980.AddEmployeeUseCase(gh<_i506.EmployeeRepository>()),
    );
    gh.lazySingleton<_i712.DeleteEmployeeUseCase>(
      () => _i712.DeleteEmployeeUseCase(gh<_i506.EmployeeRepository>()),
    );
    gh.lazySingleton<_i248.GetEmployeesUseCase>(
      () => _i248.GetEmployeesUseCase(gh<_i506.EmployeeRepository>()),
    );
    gh.lazySingleton<_i500.UpdateEmployeeStatusUseCase>(
      () => _i500.UpdateEmployeeStatusUseCase(gh<_i506.EmployeeRepository>()),
    );
    gh.lazySingleton<_i188.UpdateEmployeeUseCase>(
      () => _i188.UpdateEmployeeUseCase(gh<_i506.EmployeeRepository>()),
    );
    gh.factory<_i164.EmployeeCubit>(
      () => _i164.EmployeeCubit(
        gh<_i248.GetEmployeesUseCase>(),
        gh<_i980.AddEmployeeUseCase>(),
        gh<_i188.UpdateEmployeeUseCase>(),
        gh<_i500.UpdateEmployeeStatusUseCase>(),
        gh<_i712.DeleteEmployeeUseCase>(),
      ),
    );
    gh.lazySingleton<_i747.CreateSaleUseCase>(
      () => _i747.CreateSaleUseCase(gh<_i862.PosRepository>()),
    );
    gh.factory<_i361.EmployeeFormCubit>(
      () => _i361.EmployeeFormCubit(gh<_i980.AddEmployeeUseCase>()),
    );
    gh.lazySingleton<_i828.GetRecentSalesUseCase>(
      () => _i828.GetRecentSalesUseCase(gh<_i681.ReturnsRepository>()),
    );
    gh.lazySingleton<_i881.ProcessReturnUseCase>(
      () => _i881.ProcessReturnUseCase(gh<_i681.ReturnsRepository>()),
    );
    gh.factory<_i403.PosCubit>(
      () => _i403.PosCubit(
        gh<_i747.CreateSaleUseCase>(),
        gh<_i77.VariantRepository>(),
        gh<_i687.CategoryRepository>(),
        gh<_i758.ProductRepository>(),
        gh<_i862.PosRepository>(),
      ),
    );
    gh.factory<_i74.ReturnsCubit>(
      () => _i74.ReturnsCubit(
        gh<_i828.GetRecentSalesUseCase>(),
        gh<_i881.ProcessReturnUseCase>(),
      ),
    );
    return this;
  }
}

class _$RegisterModule extends _i868.RegisterModule {}
