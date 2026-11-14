import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/installments/data/repositories/installments_facade_impl.dart';
import 'package:clothes_erp/features/installments/data/services/manager_pin_service.dart';
import 'package:clothes_erp/features/installments/domain/entities/customer_installment_entity.dart';
import 'package:clothes_erp/features/installments/domain/facades/installments_facade.dart';
import 'package:clothes_erp/features/installments/domain/services/installment_calculator.dart';
import 'package:clothes_erp/features/installments/presentation/screens/record_payment_screen.dart';
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

void main() {
  final sl = GetIt.instance;
  late AppDatabase db;
  late FeatureGate gate;
  late FakeAuthLocalDataSource authDs;
  late TxWriter tx;
  late BranchProvider branch;
  late ManagerPinService pin;
  late InstallmentsFacade facade;
  late UserModel admin;
  late CustomerInstallmentEntity contract;

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

    facade = InstallmentsFacadeImpl(db, tx, branch, authDs, gate, pin);

    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<FeatureGate>(gate);
    sl.registerSingleton<InstallmentsFacade>(facade);

    await gate.setFeatureEnabled(FeatureKeys.installments, true, userId: admin.id);
    await pin.setPin(pin: '1234', userId: admin.id);

    // Seed customer
    await db.into(db.customers).insert(
      CustomersCompanion.insert(
        id: 'cust-pay',
        branchId: 'b1',
        name: 'عميل الدفع',
        phone: '0100000000',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    // Seed sale
    await db.into(db.sales).insert(
      SalesCompanion.insert(
        id: 'sale-pay',
        branchId: 'b1',
        shortRef: 'REFPAY',
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

    final res = await facade.createContract(
      saleId: 'sale-pay',
      customerId: 'cust-pay',
      totalPiasters: 50000,
      downPaymentPiasters: 0,
      interestBp: 0,
      interestModel: InstallmentInterestModel.fixed,
      durationMonths: 5,
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
        child: RecordPaymentScreen(contractId: contract.id),
      ),
    );
  }

  testWidgets('1. valid payment submission records payment successfully', (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('تسجيل دفعة قسط'), findsOneWidget);
    expect(find.text('500.00 ج.م'), findsOneWidget);

    // Enter amount: 100 EGP (10000 piasters)
    await tester.enterText(find.byType(TextField).first, '100');
    // Enter PIN: '1234'
    await tester.enterText(find.byType(TextField).last, '1234');
    await tester.pumpAndSettle();

    // Tap submit button
    await tester.ensureVisible(find.text('تأكيد تسجيل الدفعة'));
    await tester.tap(find.text('تأكيد تسجيل الدفعة'));
    await tester.pumpAndSettle();

    // Verify payment was recorded in database
    final payments = await db.select(db.installmentPayments).get();
    expect(payments.length, 1);
    expect(payments.first.amountPiasters, 10000);

    // Verify remaining is decreased in contract
    final updatedContract = await (db.select(db.customerInstallments)..where((t) => t.id.equals(contract.id))).getSingle();
    expect(updatedContract.remainingPiasters, 40000);
  });

  testWidgets('2. overpayment exceeding remaining amount is rejected with error', (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Enter amount exceeding remaining: 600 EGP (remaining is 500 EGP)
    await tester.enterText(find.byType(TextField).first, '600');
    await tester.enterText(find.byType(TextField).last, '1234');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('تأكيد تسجيل الدفعة'));
    await tester.tap(find.text('تأكيد تسجيل الدفعة'));
    await tester.pumpAndSettle();

    expect(find.text('المبلغ المدخل يتجاوز الرصيد المتبقي على العقد'), findsOneWidget);
  });

  testWidgets('3. wrong manager PIN is rejected with error', (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '50');
    // Enter wrong PIN: '9999'
    await tester.enterText(find.byType(TextField).last, '9999');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('تأكيد تسجيل الدفعة'));
    await tester.tap(find.text('تأكيد تسجيل الدفعة'));
    await tester.pumpAndSettle();

    expect(find.text('الرقم السري غير صحيح'), findsOneWidget);
  });
}
