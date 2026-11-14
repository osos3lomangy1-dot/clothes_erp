import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/customers/data/datasources/customers_local_data_source.dart';
import 'package:clothes_erp/features/customers/data/repositories/customer_repository_impl.dart';
import 'package:clothes_erp/features/customers/domain/entities/customer_entity.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

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
  late AppDatabase db;
  late BranchProvider bp;
  late TxWriter tx;
  late FeatureGate gate;
  late CustomerRepositoryImpl repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    bp = BranchProvider(db);
    tx = TxWriter(db);
    final auth = FakeAuthLocalDataSource()
      ..setUser(UserModel(
        id: 'admin-1',
        name: 'Admin',
        email: 'a@a.a',
        role: 'admin',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      ));
    gate = FeatureGate(db, auth, tx, bp);
    repo = CustomerRepositoryImpl(CustomersLocalDataSourceImpl(db, bp, tx), gate);
  });

  tearDown(() async {
    await db.close();
  });

  Future<CustomerEntity> seedCustomer({int loyaltyPoints = 5}) async {
    await repo.addCustomer(CustomerEntity(
      id: '',
      name: 'Cust',
      phone: '0100',
      loyaltyPoints: loyaltyPoints == 0 ? 0 : 0, // create with 0, adjust via DB when needed
      createdAt: DateTime(2026, 1, 1),
    ));
    final list = (await repo.getCustomers()).getOrElse(() => []);
    final c = list.first;
    if (loyaltyPoints != 0) {
      await gate.setFeatureEnabled(FeatureKeys.loyalty, true, userId: 'admin-1');
      await repo.updateCustomer(c.copyWith(loyaltyPoints: loyaltyPoints));
      await gate.setFeatureEnabled(FeatureKeys.loyalty, false, userId: 'admin-1');
      return (await repo.getCustomerById(c.id)).getOrElse(() => null)!;
    }
    return c;
  }

  test('manual loyalty point adjustment is rejected when loyalty feature is disabled', () async {
    final existing = await seedCustomer(loyaltyPoints: 5);
    final res = await repo.updateCustomer(existing.copyWith(loyaltyPoints: 10));
    expect(res.isLeft(), true);
    res.fold((f) => expect(f, isA<FeatureDisabledFailure>()), (_) => fail('should fail'));
    final after = (await repo.getCustomerById(existing.id)).getOrElse(() => null)!;
    expect(after.loyaltyPoints, 5);
  });

  test('manual loyalty point adjustment succeeds when loyalty feature is enabled', () async {
    final existing = await seedCustomer(loyaltyPoints: 5);
    await gate.setFeatureEnabled(FeatureKeys.loyalty, true, userId: 'admin-1');
    final res = await repo.updateCustomer(existing.copyWith(loyaltyPoints: 12));
    expect(res.isRight(), true);
    final after = (await repo.getCustomerById(existing.id)).getOrElse(() => null)!;
    expect(after.loyaltyPoints, 12);
  });

  test('customer update that does not change loyalty points is not gated', () async {
    final existing = await seedCustomer(loyaltyPoints: 5);
    final res = await repo.updateCustomer(existing.copyWith(name: 'Cust 2'));
    expect(res.isRight(), true);
    final after = (await repo.getCustomerById(existing.id)).getOrElse(() => null)!;
    expect(after.name, 'Cust 2');
    expect(after.loyaltyPoints, 5);
  });

  test('customer create with non-zero loyalty points is rejected when loyalty feature is disabled', () async {
    final res = await repo.addCustomer(CustomerEntity(
      id: '',
      name: 'Loyal',
      phone: '0999',
      loyaltyPoints: 3,
      createdAt: DateTime(2026, 1, 1),
    ));
    expect(res.isLeft(), true);
    res.fold((f) => expect(f, isA<FeatureDisabledFailure>()), (_) => fail('should fail'));
    final list = (await repo.getCustomers()).getOrElse(() => []);
    expect(list.where((c) => c.phone == '0999').isEmpty, true);
  });
}
