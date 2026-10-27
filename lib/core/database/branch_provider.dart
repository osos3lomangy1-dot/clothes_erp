import 'package:uuid/uuid.dart';
import '../database/app_database.dart';

class BranchProvider {
  final AppDatabase _db;
  final _uuid = const Uuid();

  BranchProvider(this._db);

  Future<String> getBranchId() async {
    final row = await (_db.select(_db.appMeta)..where((t) => t.key.equals('branch_id'))).getSingleOrNull();
    if (row != null) return row.value;
    final newId = _uuid.v4();
    await _db.into(_db.appMeta).insert(AppMetaCompanion.insert(
      key: 'branch_id',
      value: newId,
      updatedAt: DateTime.now(),
    ));
    return newId;
  }
}
