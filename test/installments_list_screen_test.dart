import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/customers/domain/entities/customer_entity.dart';
import 'package:clothes_erp/features/customers/domain/repositories/customer_repository.dart';
import 'package:clothes_erp/features/installments/data/repositories/installments_facade_impl.dart';
import 'package:clothes_erp/features/installments/data/services/manager_pin_service.dart';
import 'package:clothes_erp/features/installments/domain/facades/installments_facade.dart';
import 'package:clothes_erp/features/installments/domain/services/installment_calculator.dart';
import 'package:clothes_erp/features/installments/presentation/cubits/installments_list_cubit.dart';
import 'package:clothes_erp/features/installments/presentation/screens/installments_list_screen.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
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

class FakeCustomerRepository implements CustomerRepository {
  List<CustomerEntity> customers = [];
  @override
  Future<Either<Failure, List<CustomerEntity>>> getCustomers({String? search}) async => Right(customers);
  @override
  Future<Either<Failure, CustomerEntity?>> getCustomerById(String id) async {
    final match = customers.where((c) => c.id == id).firstOrNull;
    return Right(match);
  }
  @override
  Future<Either<Failure, void>> addCustomer(CustomerEntity customer) async => const Right(null);
  @override
  Future<Either<Failure, void>> updateCustomer(CustomerEntity customer) async => const Right(null);
  @override
  Future<Either<Failure, void>> deleteCustomer(String id) async => const Right(null);
}

void main() {
  final sl = GetIt.instance;
  late AppDatabase db;
  late FeatureGate gate;
  late FakeAuthLocalDataSource authDs;
  late TxWriter tx;
  late BranchProvider branch;
  late ManagerPinService pin;
  late InstallmentsFacade facade;
  late FakeCustomerRepository customerRepo;
  late UserModel admin;

  setUp(() async {
    await sl.reset();
    db = AppDatabase(NativeDatabase.memory());
    authDs = FakeAuthLocalDataSource();
    admin = UserModel(id: 'admin-1', name: 'Admin', email: 'a@a.a', role: 'admin', isActive: true, createdAt: DateTime(2026, 1, 1));
    authDs.setUser(admin);

    tx = TxWriter(db);
    branch = BranchProvider(db);
    gate = FeatureGate(db, authDs, tx, branch);
    pin = ManagerPinService(db, tx, branch, authDs, gate);
    customerRepo = FakeCustomerRepository();

    facade = InstallmentsFacadeImpl(db, tx, branch, authDs, gate, pin);

    // Register GetIt singletons
    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<FeatureGate>(gate);
    sl.registerSingleton<InstallmentsFacade>(facade);
    sl.registerSingleton<CustomerRepository>(customerRepo);
    sl.registerFactory<InstallmentsListCubit>(() => InstallmentsListCubit(facade, customerRepo));

    // Enable feature and set PIN
    await gate.setFeatureEnabled(FeatureKeys.installments, true, userId: admin.id);
    await pin.setPin(pin: '1234', userId: admin.id);
  });

  tearDown(() async {
    await db.close();
    await sl.reset();
  });

  Widget buildTestWidget() {
    return const MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: InstallmentsListScreen(),
      ),
    );
  }

  testWidgets('1. renders empty state when no contracts exist', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('إدارة عقود التقسيط'), findsOneWidget);
    expect(find.text('لا توجد عقود تقسيط مسجلة حتى الآن'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('2. renders list of contracts when contracts exist', (tester) async {
    // Seed customer
    customerRepo.customers = [
      CustomerEntity(id: 'c1', name: 'محمود أحمد', phone: '01012345678', createdAt: DateTime(2026, 1, 1)),
    ];

    // Seed sale in db
    await db.into(db.sales).insert(
      SalesCompanion.insert(
        id: 's1',
        branchId: 'b1',
        shortRef: 'REF1',
        cashierId: admin.id,
        subtotal: 100000,
        discountType: 'none',
        total: 100000,
        paymentMethod: 'installment',
        date: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    // Seed customer in db
    await db.into(db.customers).insert(
      CustomersCompanion.insert(
        id: 'c1',
        branchId: 'b1',
        name: 'محمود أحمد',
        phone: '01012345678',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    // Create contract
    await facade.createContract(
      saleId: 's1',
      customerId: 'c1',
      totalPiasters: 100000,
      downPaymentPiasters: 20000,
      interestBp: 0,
      interestModel: InstallmentInterestModel.fixed,
      durationMonths: 6,
      startDate: DateTime.now(),
      pin: '1234',
    );

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('محمود أحمد'), findsOneWidget);
    expect(find.text('نشط'), findsWidgets);
    expect(find.text('المدة: 6 شهور'), findsOneWidget);
  });

  testWidgets('3. filters contracts by status when filter chip is selected', (tester) async {
    customerRepo.customers = [
      CustomerEntity(id: 'c1', name: 'عميل 1', phone: '0101', createdAt: DateTime(2026, 1, 1)),
    ];

    await db.into(db.sales).insert(
      SalesCompanion.insert(
        id: 's2',
        branchId: 'b1',
        shortRef: 'REF2',
        cashierId: admin.id,
        subtotal: 50000,
        discountType: 'none',
        total: 50000,
        paymentMethod: 'installment',
        date: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    await db.into(db.customers).insert(
      CustomersCompanion.insert(
        id: 'c1',
        branchId: 'b1',
        name: 'عميل 1',
        phone: '0101',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    await facade.createContract(
      saleId: 's2',
      customerId: 'c1',
      totalPiasters: 50000,
      downPaymentPiasters: 0,
      interestBp: 0,
      interestModel: InstallmentInterestModel.fixed,
      durationMonths: 6,
      startDate: DateTime.now(),
      pin: '1234',
    );

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('عميل 1'), findsOneWidget);

    // Tap on 'مكتمل' filter chip
    await tester.tap(find.text('مكتمل'));
    await tester.pumpAndSettle();

    // Since this contract is active, under 'مكتمل' filter it should show empty
    expect(find.text('لا توجد عقود مطابقة للبحث'), findsOneWidget);
  });
}
