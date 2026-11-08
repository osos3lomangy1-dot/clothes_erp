import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/core/database/app_database.dart';

void main() {
  test('opens in-memory database', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect(db, isNotNull);
    final variants = await db.select(db.productVariants).get();
    expect(variants, isEmpty);
    await db.close();
  });

  test('beforeOpen auto-heals missing wholesale_price on existing databases', () async {
    final tempFile = File('${Directory.systemTemp.path}/test_upgrade_${DateTime.now().millisecondsSinceEpoch}.db');
    if (tempFile.existsSync()) tempFile.deleteSync();

    try {
      // 1. Simulate an old database without wholesale_price column
      var db = AppDatabase(NativeDatabase(tempFile));
      // Trigger creation
      await db.customSelect('SELECT 1').get();
      // Drop the column to simulate old schema
      await db.customStatement('ALTER TABLE product_variants DROP COLUMN wholesale_price');

      // Verify it is dropped
      final infoBefore = await db.customSelect('PRAGMA table_info(product_variants)').get();
      expect(infoBefore.any((r) => r.data['name'] == 'wholesale_price'), false);
      await db.close();

      // 2. Open with AppDatabase again (simulating app restart on user machine)
      db = AppDatabase(NativeDatabase(tempFile));
      // Any query will trigger beforeOpen
      final variants = await db.select(db.productVariants).get();
      expect(variants, isEmpty);

      // Verify wholesale_price was automatically added
      final infoAfter = await db.customSelect('PRAGMA table_info(product_variants)').get();
      expect(infoAfter.any((r) => r.data['name'] == 'wholesale_price'), true);

      await db.close();
    } finally {
      if (tempFile.existsSync()) tempFile.deleteSync();
    }
  });
}
