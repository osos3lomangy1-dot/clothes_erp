import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/core/database/app_database.dart';

void main() {
  test('opens in-memory database', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect(db, isNotNull);
    await db.close();
  });
}
