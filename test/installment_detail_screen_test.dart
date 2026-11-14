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
import 'package:clothes_erp/features/installments/domain/entities/customer_installment_entity.dart';
import 'package:clothes_erp/features/installments/domain/facades/installments_facade.dart';
import 'package:clothes_erp/features/installments/domain/services/installment_calculator.dart';
import 'package:clothes_erp/features/installments/presentation/screens/installment_detail_screen.dart';
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
  Future<Either<Failure, List<CustomerEntity>>> getCustomers({
    String? search,
  }) async => Right(customers);
  @override
  Future<Either<Failure, CustomerEntity?>> getCustomerById(String id) async {
    final match = customers.where((c) => c.id == id).firstOrNull;
    return Right(match);
  }

  @override
  Future<Either<Failure, void>> addCustomer(CustomerEntity customer) async =>
      const Right(null);
  @override
  Future<Either<Failure, void>> updateCustomer(CustomerEntity customer) async =>
      const Right(null);
  @override
  Future<Either<Failure, void>> deleteCustomer(String id) async =>
      const Right(null);
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
  late CustomerInstallmentEntity contract;

  setUp(() async {
    await sl.reset();
    db = AppDatabase(NativeDatabase.memory());
    authDs = FakeAuthLocalDataSource();
    admin = UserModel(
      id: 'admin-1',
      name: 'Admin',
      email: 'a@a.a',
      role: 'admin',
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
    );
    authDs.setUser(admin);

    tx = TxWriter(db);
    branch = BranchProvider(db);
    gate = FeatureGate(db, authDs, tx, branch);
    pin = ManagerPinService(db, tx, branch, authDs, gate);
    customerRepo = FakeCustomerRepository();

    facade = InstallmentsFacadeImpl(db, tx, branch, authDs, gate, pin);

    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<FeatureGate>(gate);
    sl.registerSingleton<InstallmentsFacade>(facade);
    sl.registerSingleton<CustomerRepository>(customerRepo);

    await gate.setFeatureEnabled(
      FeatureKeys.installments,
      true,
      userId: admin.id,
    );
    await pin.setPin(pin: '1234', userId: admin.id);

    // Seed customer
    customerRepo.customers = [
      CustomerEntity(
        id: 'c10',
        name: 'طارق علي',
        phone: '01234567890',
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'c10',
            branchId: 'b1',
            name: 'طارق علي',
            phone: '01234567890',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );

    // Seed sale
    await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            id: 's10',
            branchId: 'b1',
            shortRef: 'REF10',
            cashierId: admin.id,
            subtotal: 60000,
            discountType: 'none',
            total: 60000,
            paymentMethod: 'installment',
            date: DateTime.now(),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );

    // Create contract with down payment
    final res = await facade.createContract(
      saleId: 's10',
      customerId: 'c10',
      totalPiasters: 60000,
      downPaymentPiasters: 12000,
      interestBp: 0,
      interestModel: InstallmentInterestModel.fixed,
      durationMonths: 6,
      startDate: DateTime.now(),
      pin: '1234',
    );
    contract = res.getOrElse(() => throw Exception());
  });

  tearDown(() async {
    await db.close();
    await sl.reset();
  });

  Widget buildTestWidget() {
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: InstallmentDetailScreen(contractId: contract.id),
      ),
    );
  }

  testWidgets(
    '1. renders header card with contract financial summary and status',
    (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('طارق علي'), findsOneWidget);
      expect(find.text('عقد نشط'), findsOneWidget);
      expect(find.text('إجمالي العقد'), findsOneWidget);
      expect(find.text('600.00 ج.م'), findsOneWidget);
      expect(find.text('الدفعة المقدمة'), findsOneWidget);
      expect(find.text('120.00 ج.م'), findsWidgets);
    },
  );

  testWidgets('2. renders schedule table with calculated installments', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('جدول الأقساط والاستحقاقات'), findsOneWidget);
    expect(find.text('تاريخ الاستحقاق'), findsWidgets);
    expect(find.text('#'), findsOneWidget);
  });

  testWidgets('3. renders payments list with down payment recorded', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('سجل الدفعات والمتحصلات'), findsOneWidget);
    expect(find.text('دفعة مقدمة'), findsOneWidget);
    expect(find.text('120.00 ج.م'), findsWidgets);
  });

  testWidgets('4. shows action buttons when contract is active', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('تسجيل دفعة جديدة'), findsOneWidget);
    expect(find.text('إلغاء العقد'), findsOneWidget);
  });

  testWidgets('5. correctly marks installment as paid after payment is recorded', (
    tester,
  ) async {
    await facade.recordPayment(
      contractId: contract.id,
      amountPiasters: 8000,
      paymentMethod: 'cash',
      pin: '1234',
    );

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('مدفوع'), findsWidgets);
    expect(find.text('200.00 ج.م'), findsOneWidget);
    expect(find.text('400.00 ج.م'), findsOneWidget);
  });
}
