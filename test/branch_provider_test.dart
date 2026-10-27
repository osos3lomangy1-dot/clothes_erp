import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';

void main() {
  test('first call creates and persists UUID', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final bp = BranchProvider(db);
    final id1 = await bp.getBranchId();
    expect(id1.isNotEmpty, true);
    final id2 = await bp.getBranchId();
    expect(id1, id2);
    final bp2 = BranchProvider(db);
    final id3 = await bp2.getBranchId();
    expect(id1, id3);
    await db.close();
  });
}
