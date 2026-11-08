import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/database/tx_writer.dart';

abstract class CustomersLocalDataSource {
  Future<List<Customer>> getCustomers({String? search});
  Future<Customer?> getCustomerById(String id);
  Future<Customer?> getCustomerByPhone(String phone);
  Future<void> addCustomer({
    required String name,
    required String phone,
    int loyaltyPoints = 0,
    int discountPercent = 0,
    String customerType = 'retail',
    String userId = 'system',
  });
  Future<void> updateCustomer({
    required String id,
    required String name,
    required String phone,
    int? loyaltyPoints,
    int? discountPercent,
    String? customerType,
    String userId = 'system',
  });
  Future<void> softDeleteCustomer(String id, {String userId = 'system'});
}

@LazySingleton(as: CustomersLocalDataSource)
class CustomersLocalDataSourceImpl implements CustomersLocalDataSource {
  final AppDatabase _db;
  final BranchProvider _branchProvider;
  final TxWriter _tx;
  final _uuid = const Uuid();

  CustomersLocalDataSourceImpl(this._db, this._branchProvider, this._tx);

  Future<String> _branchId() => _branchProvider.getBranchId();

  @override
  Future<List<Customer>> getCustomers({String? search}) async {
    var query = _db.select(_db.customers)..where((c) => c.deletedAt.isNull());
    if (search != null && search.trim().isNotEmpty) {
      final s = search.trim();
      query = query..where((c) => c.name.contains(s) | c.phone.contains(s));
    }
    query = query..orderBy([(c) => OrderingTerm.desc(c.createdAt)]);
    return query.get();
  }

  @override
  Future<Customer?> getCustomerById(String id) async {
    return (_db.select(_db.customers)
          ..where((c) => c.id.equals(id) & c.deletedAt.isNull()))
        .getSingleOrNull();
  }

  @override
  Future<Customer?> getCustomerByPhone(String phone) async {
    return (_db.select(_db.customers)
          ..where((c) => c.phone.equals(phone) & c.deletedAt.isNull()))
        .getSingleOrNull();
  }

  @override
  Future<void> addCustomer({
    required String name,
    required String phone,
    int loyaltyPoints = 0,
    int discountPercent = 0,
    String customerType = 'retail',
    String userId = 'system',
  }) async {
    if (name.trim().isEmpty) throw Exception('Customer name is required');
    if (phone.trim().isEmpty) throw Exception('Customer phone is required');

    final now = DateTime.now();
    final id = _uuid.v4();
    final branchId = await _branchId();

    await _tx.write(
      writeFn: () async {
        await _db.into(_db.customers).insert(CustomersCompanion.insert(
          id: id,
          branchId: branchId,
          name: name.trim(),
          phone: phone.trim(),
          loyaltyPoints: Value(loyaltyPoints),
          discountPercent: Value(discountPercent),
          customerType: Value(customerType),
          createdAt: now,
          updatedAt: now,
        ));
      },
      branchId: branchId,
      entity: 'customer',
      entityId: id,
      operation: 'insert',
      userId: userId,
    );
  }

  @override
  Future<void> updateCustomer({
    required String id,
    required String name,
    required String phone,
    int? loyaltyPoints,
    int? discountPercent,
    String? customerType,
    String userId = 'system',
  }) async {
    if (name.trim().isEmpty) throw Exception('Customer name is required');
    if (phone.trim().isEmpty) throw Exception('Customer phone is required');

    final now = DateTime.now();
    final branchId = await _branchId();

    await _tx.write(
      writeFn: () async {
        await (_db.update(_db.customers)..where((c) => c.id.equals(id))).write(
          CustomersCompanion(
            name: Value(name.trim()),
            phone: Value(phone.trim()),
            loyaltyPoints: loyaltyPoints != null ? Value(loyaltyPoints) : const Value.absent(),
            discountPercent: discountPercent != null ? Value(discountPercent) : const Value.absent(),
            customerType: customerType != null ? Value(customerType) : const Value.absent(),
            updatedAt: Value(now),
          ),
        );
      },
      branchId: branchId,
      entity: 'customer',
      entityId: id,
      operation: 'update',
      userId: userId,
    );
  }

  @override
  Future<void> softDeleteCustomer(String id, {String userId = 'system'}) async {
    final now = DateTime.now();
    final branchId = await _branchId();

    await _tx.write(
      writeFn: () async {
        await (_db.update(_db.customers)..where((c) => c.id.equals(id))).write(
          CustomersCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      },
      branchId: branchId,
      entity: 'customer',
      entityId: id,
      operation: 'delete',
      userId: userId,
    );
  }
}
