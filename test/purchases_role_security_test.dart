import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/purchases/data/datasources/purchases_local_data_source.dart';
import 'package:clothes_erp/features/purchases/data/repositories/purchases_repository_impl.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuthLocalDataSource implements AuthLocalDataSource {
  UserModel? _user;

  void setUser(UserModel? user) {
    _user = user;
  }

  @override
  Future<void> cacheUser(UserModel user) async {
    _user = user;
  }

  @override
  Future<UserModel?> getCachedUser() async {
    return _user;
  }

  @override
  Future<void> clearCache() async {
    _user = null;
  }
}

void main() {
  late AppDatabase db;
  late BranchProvider branchProvider;
  late PurchasesLocalDataSource localDataSource;
  late FakeAuthLocalDataSource fakeAuth;
  late PurchasesRepositoryImpl repository;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    branchProvider = BranchProvider(db);
    localDataSource = PurchasesLocalDataSourceImpl(db, branchProvider);
    fakeAuth = FakeAuthLocalDataSource();
    repository = PurchasesRepositoryImpl(localDataSource, fakeAuth);
  });

  tearDown(() async {
    await db.close();
  });

  group('Purchases & Suppliers Security Defense in Depth', () {
    test('Cashier is blocked from getSuppliers with AuthFailure', () async {
      fakeAuth.setUser(UserModel(
        id: 'cashier-1',
        name: 'كاشير المحل',
        email: 'cashier@pos.local',
        role: 'cashier',
        isActive: true,
        createdAt: DateTime.now(),
      ));

      final result = await repository.getSuppliers();
      expect(result.isLeft(), true);
      result.fold(
        (failure) {
          expect(failure, isA<AuthFailure>());
          expect(failure.message, contains('ليس لديك صلاحية'));
        },
        (_) => fail('Should not allow cashier to get suppliers'),
      );
    });

    test('Cashier is blocked from addSupplier with AuthFailure', () async {
      fakeAuth.setUser(UserModel(
        id: 'cashier-1',
        name: 'كاشير المحل',
        email: 'cashier@pos.local',
        role: 'cashier',
        isActive: true,
        createdAt: DateTime.now(),
      ));

      final result = await repository.addSupplier(name: 'مورد جديد');
      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<AuthFailure>()),
        (_) => fail('Should not allow cashier to add supplier'),
      );
    });

    test('Cashier is blocked from getPurchases with AuthFailure', () async {
      fakeAuth.setUser(UserModel(
        id: 'cashier-1',
        name: 'كاشير المحل',
        email: 'cashier@pos.local',
        role: 'cashier',
        isActive: true,
        createdAt: DateTime.now(),
      ));

      final result = await repository.getPurchases();
      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<AuthFailure>()),
        (_) => fail('Should not allow cashier to get purchases'),
      );
    });

    test('Cashier is blocked from createPurchaseInvoice with AuthFailure', () async {
      fakeAuth.setUser(UserModel(
        id: 'cashier-1',
        name: 'كاشير المحل',
        email: 'cashier@pos.local',
        role: 'cashier',
        isActive: true,
        createdAt: DateTime.now(),
      ));

      final result = await repository.createPurchaseInvoice(
        supplierId: 'sup-1',
        purchaseDate: DateTime.now(),
        paidAmount: 0,
        items: [],
        userId: 'cashier-1',
      );
      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<AuthFailure>()),
        (_) => fail('Should not allow cashier to create purchase invoice'),
      );
    });

    test('Cashier is blocked from addSupplierPayment with AuthFailure', () async {
      fakeAuth.setUser(UserModel(
        id: 'cashier-1',
        name: 'كاشير المحل',
        email: 'cashier@pos.local',
        role: 'cashier',
        isActive: true,
        createdAt: DateTime.now(),
      ));

      final result = await repository.addSupplierPayment(
        supplierId: 'sup-1',
        amount: 1000,
        paymentDate: DateTime.now(),
        paymentMethod: 'cash',
        userId: 'cashier-1',
      );
      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<AuthFailure>()),
        (_) => fail('Should not allow cashier to pay supplier'),
      );
    });

    test('Admin is allowed to access and operate on suppliers and purchases', () async {
      fakeAuth.setUser(UserModel(
        id: 'admin-1',
        name: 'المدير العام',
        email: 'admin@pos.local',
        role: 'admin',
        isActive: true,
        createdAt: DateTime.now(),
      ));

      final addResult = await repository.addSupplier(
        name: 'شركة النسيج الممتاز',
        phone: '01099998888',
      );
      expect(addResult.isRight(), true);

      final listResult = await repository.getSuppliers();
      expect(listResult.isRight(), true);
      listResult.fold(
        (_) => fail('Should not fail for admin'),
        (suppliers) => expect(suppliers.length, 1),
      );
    });
  });
}
