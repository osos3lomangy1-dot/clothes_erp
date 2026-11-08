import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/features/customers/data/datasources/customers_local_data_source.dart';

void main() {
  late AppDatabase db;
  late BranchProvider bp;
  late TxWriter tx;
  late CustomersLocalDataSourceImpl dataSource;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    bp = BranchProvider(db);
    tx = TxWriter(db);
    dataSource = CustomersLocalDataSourceImpl(db, bp, tx);
  });

  tearDown(() async {
    await db.close();
  });

  group('CustomersLocalDataSource', () {
    test('addCustomer inserts record and logs transaction via TxWriter', () async {
      await dataSource.addCustomer(
        name: 'Ahmed Hassan',
        phone: '01012345678',
        loyaltyPoints: 100,
        userId: 'admin_1',
      );

      final customers = await dataSource.getCustomers();
      expect(customers.length, 1);
      final c = customers.first;
      expect(c.name, 'Ahmed Hassan');
      expect(c.phone, '01012345678');
      expect(c.loyaltyPoints, 100);
      expect(c.deletedAt, isNull);

      // Verify TxWriter audit logs & sync queue
      final logs = await db.select(db.auditLogs).get();
      expect(logs.length, 1);
      expect(logs.first.entity, 'customer');
      expect(logs.first.action, 'insert');
      expect(logs.first.userId, 'admin_1');

      final queue = await db.select(db.syncQueue).get();
      expect(queue.length, 1);
      expect(queue.first.entity, 'customer');
      expect(queue.first.operation, 'insert');
    });

    test('updateCustomer updates name, phone, and loyaltyPoints', () async {
      await dataSource.addCustomer(
        name: 'Sara Omar',
        phone: '01122334455',
        loyaltyPoints: 50,
      );

      final initial = (await dataSource.getCustomers()).first;

      await dataSource.updateCustomer(
        id: initial.id,
        name: 'Sara Ali',
        phone: '01199887766',
        loyaltyPoints: 120,
        userId: 'cashier_2',
      );

      final updated = await dataSource.getCustomerById(initial.id);
      expect(updated, isNotNull);
      expect(updated!.name, 'Sara Ali');
      expect(updated.phone, '01199887766');
      expect(updated.loyaltyPoints, 120);

      // Verify audit logs
      final updateLog = await (db.select(db.auditLogs)..where((l) => l.action.equals('update'))).getSingle();
      expect(updateLog.entityId, initial.id);
      expect(updateLog.userId, 'cashier_2');
    });

    test('softDeleteCustomer marks record deleted and excludes from getCustomers', () async {
      await dataSource.addCustomer(
        name: 'Mohamed Tarek',
        phone: '01234567890',
      );

      final customer = (await dataSource.getCustomers()).first;

      await dataSource.softDeleteCustomer(customer.id, userId: 'admin_1');

      final activeList = await dataSource.getCustomers();
      expect(activeList, isEmpty);

      final byId = await dataSource.getCustomerById(customer.id);
      expect(byId, isNull);

      // Directly checking Drift database reveals soft-deleted record
      final rawRecord = await (db.select(db.customers)..where((c) => c.id.equals(customer.id))).getSingle();
      expect(rawRecord.deletedAt, isNotNull);

      // Verify audit logs & sync queue
      final deleteLog = await (db.select(db.auditLogs)..where((l) => l.action.equals('delete'))).getSingle();
      expect(deleteLog.entityId, customer.id);
      expect(deleteLog.userId, 'admin_1');
    });

    test('search filters customers by name or phone', () async {
      await dataSource.addCustomer(name: 'Ali Youssef', phone: '01011111111');
      await dataSource.addCustomer(name: 'Mona Zaki', phone: '01022222222');
      await dataSource.addCustomer(name: 'Youssef Nabil', phone: '01033333333');

      // Search by name
      final nameMatches = await dataSource.getCustomers(search: 'Youssef');
      expect(nameMatches.length, 2);
      expect(nameMatches.map((c) => c.name), containsAll(['Ali Youssef', 'Youssef Nabil']));

      // Search by phone
      final phoneMatches = await dataSource.getCustomers(search: '2222');
      expect(phoneMatches.length, 1);
      expect(phoneMatches.first.name, 'Mona Zaki');

      // Search not found
      final emptyMatches = await dataSource.getCustomers(search: 'NonExistent');
      expect(emptyMatches, isEmpty);
    });

    test('addCustomer and updateCustomer support discountPercent and customerType perks', () async {
      await dataSource.addCustomer(
        name: 'Tarek Wholesale',
        phone: '01555555555',
        loyaltyPoints: 300,
        discountPercent: 15,
        customerType: 'wholesale',
      );

      final cust = (await dataSource.getCustomers()).first;
      expect(cust.discountPercent, 15);
      expect(cust.customerType, 'wholesale');

      await dataSource.updateCustomer(
        id: cust.id,
        name: 'Tarek VIP',
        phone: '01555555555',
        discountPercent: 20,
        customerType: 'vip',
      );

      final updated = await dataSource.getCustomerById(cust.id);
      expect(updated!.discountPercent, 20);
      expect(updated.customerType, 'vip');
    });
  });
}
