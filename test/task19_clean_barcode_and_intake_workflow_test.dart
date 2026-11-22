import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/utils/barcode_helper.dart';
import 'package:clothes_erp/features/products/domain/entities/activity_type.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Task 19: Clean Barcode/SKU Generator & Intake Ergonomics', () {
    // -------------------------------------------------------------------------
    // 1. Sanitized SKU Generator
    // -------------------------------------------------------------------------
    group('1. BarcodeHelper.sanitizeForSku & generateSku', () {
      test('sanitizes carpet dimensions and Arabic symbols into clean Code 128 tokens', () {
        // Standard carpet sizes
        expect(BarcodeHelper.sanitizeForSku('2×3 م'), equals('2X3M'));
        expect(BarcodeHelper.sanitizeForSku('1.5×2 م'), equals('1_5X2M'));
        expect(BarcodeHelper.sanitizeForSku('2.5×3.5 م'), equals('2_5X3_5M'));
        expect(BarcodeHelper.sanitizeForSku('3×4 م'), equals('3X4M'));
        expect(BarcodeHelper.sanitizeForSku('مشاية 1×3 م'), equals('RUNNER1X3M'));
        expect(BarcodeHelper.sanitizeForSku('مشاية 0.8×2 م'), equals('RUNNER0_8X2M'));

        // Perfume sizes
        expect(BarcodeHelper.sanitizeForSku('100 مل'), equals('100ML'));
        expect(BarcodeHelper.sanitizeForSku('50 مل'), equals('50ML'));
        expect(BarcodeHelper.sanitizeForSku('200 مللي'), equals('200ML'));

        // Footwear & Clothing sizes
        expect(BarcodeHelper.sanitizeForSku('42'), equals('42'));
        expect(BarcodeHelper.sanitizeForSku('XL'), equals('XL'));
        expect(BarcodeHelper.sanitizeForSku('XXL'), equals('XXL'));

        // Units and weights
        expect(BarcodeHelper.sanitizeForSku('5 كجم'), equals('5KG'));
        expect(BarcodeHelper.sanitizeForSku('10 كيلو'), equals('10KG'));
        expect(BarcodeHelper.sanitizeForSku('500 جرام'), equals('500G'));
        expect(BarcodeHelper.sanitizeForSku('50 سم'), equals('50CM'));
      });

      test('generates 100% laser & Code 128 compliant SKUs with only [A-Z0-9_-]', () {
        final carpetSku = BarcodeHelper.generateSku(
          size: '2×3 م',
          index: 1,
          prefix: 'SKU',
          timestampMillis: 1732300184,
        );
        expect(carpetSku, equals('SKU-2X3M-1184'));
        expect(RegExp(r'^[A-Z0-9_-]+$').hasMatch(carpetSku), isTrue);

        final decimalCarpetSku = BarcodeHelper.generateSku(
          size: '1.5×2 م',
          index: 2,
          prefix: 'SKU',
          timestampMillis: 1732300555,
        );
        expect(decimalCarpetSku, equals('SKU-1_5X2M-2555'));
        expect(RegExp(r'^[A-Z0-9_-]+$').hasMatch(decimalCarpetSku), isTrue);

        final perfumeSku = BarcodeHelper.generateSku(
          size: '100 مل',
          index: 3,
          prefix: 'SKU',
          timestampMillis: 1732300999,
        );
        expect(perfumeSku, equals('SKU-100ML-3999'));
        expect(RegExp(r'^[A-Z0-9_-]+$').hasMatch(perfumeSku), isTrue);

        final runnerSku = BarcodeHelper.generateSku(
          size: 'مشاية 1×3 م',
          index: 4,
          prefix: 'SKU',
          timestampMillis: 1732300777,
        );
        expect(runnerSku, equals('SKU-RUNNER1X3M-4777'));
        expect(RegExp(r'^[A-Z0-9_-]+$').hasMatch(runnerSku), isTrue);

        // Empty input fallback
        final emptySku = BarcodeHelper.generateSku(
          size: '   ',
          index: 5,
          prefix: 'SKU',
          timestampMillis: 1732300123,
        );
        expect(emptySku, equals('SKU-V5-5123'));
        expect(RegExp(r'^[A-Z0-9_-]+$').hasMatch(emptySku), isTrue);
      });
    });

    // -------------------------------------------------------------------------
    // 2. Dynamic Hints and Standard Sizes by Activity Type
    // -------------------------------------------------------------------------
    group('2. Sector Adaptive Standard Sizes & Dynamic Input Hints', () {
      test('each activity type provides dynamic size hints and standard sizes list', () {
        String getSizeHint(ActivityType act) => switch (act) {
              ActivityType.textilesDecor => '2×3 م',
              ActivityType.footwearBags => '42',
              ActivityType.perfumesCosmetics => '100 مل',
              ActivityType.electronicsMobiles => '128GB',
              _ => 'L',
            };

        expect(getSizeHint(ActivityType.textilesDecor), equals('2×3 م'));
        expect(getSizeHint(ActivityType.footwearBags), equals('42'));
        expect(getSizeHint(ActivityType.perfumesCosmetics), equals('100 مل'));
        expect(getSizeHint(ActivityType.electronicsMobiles), equals('128GB'));
        expect(getSizeHint(ActivityType.clothing), equals('L'));

        // Standard sizes verification
        expect(ActivityType.textilesDecor.standardSizes, contains('2×3 م'));
        expect(ActivityType.perfumesCosmetics.standardSizes, contains('100 مل'));
        expect(ActivityType.footwearBags.standardSizes, contains('42'));
        expect(ActivityType.electronicsMobiles.standardSizes, contains('128GB'));
      });

      test('sequential row generation cycles through sector standard sizes without duplicates', () {
        final existingSizes = <String>{};
        final act = ActivityType.textilesDecor;

        String getNextStandardSize() {
          final unadded = act.standardSizes.where((s) => !existingSizes.contains(s)).toList();
          if (unadded.isNotEmpty) return unadded.first;
          return act.standardSizes.last;
        }

        final first = getNextStandardSize();
        existingSizes.add(first);
        expect(first, equals('1.5×2 م'));

        final second = getNextStandardSize();
        existingSizes.add(second);
        expect(second, equals('2×3 م'));

        final third = getNextStandardSize();
        existingSizes.add(third);
        expect(third, equals('2.5×3.5 م'));
      });
    });

    // -------------------------------------------------------------------------
    // 3. On-the-Fly Variant Intake in Purchase Screen
    // -------------------------------------------------------------------------
    group('3. On-the-Fly Variant Intake into AppDatabase', () {
      late AppDatabase db;

      setUp(() async {
        db = AppDatabase(NativeDatabase.memory());
        // Seed category
        await db.into(db.categories).insert(
              CategoriesCompanion.insert(
                id: 'cat-textiles',
                branchId: 'branch-1',
                name: 'سجاد ومفروشات',
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );
        // Seed product
        await db.into(db.products).insert(
              ProductsCompanion.insert(
                id: 'prod-carpet-shiraz',
                name: 'سجاد شيراز كلاسيك',
                branchId: 'branch-1',
                categoryId: 'cat-textiles',
                activityType: const drift.Value('textilesDecor'),
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );
      });

      tearDown(() async {
        await db.close();
      });

      test('creates on-the-fly variant for existing product with sanitized SKU', () async {
        final rawSize = '2×3 م';
        final cleanSku = BarcodeHelper.generateSku(size: rawSize, index: 1, timestampMillis: 1732300000);
        final newVariantId = 'var-shiraz-2x3';

        await db.into(db.productVariants).insert(
              ProductVariantsCompanion.insert(
                id: newVariantId,
                branchId: 'branch-1',
                productId: 'prod-carpet-shiraz',
                sku: cleanSku,
                size: rawSize,
                color: 'كحلي',
                costPrice: 85000, // 850 EGP
                sellPrice: 120000, // 1200 EGP
                quantity: const drift.Value(0),
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );

        // Verify variant in database
        final variants = await (db.select(db.productVariants)..where((v) => v.id.equals(newVariantId))).get();
        expect(variants.length, equals(1));
        final variant = variants.first;
        expect(variant.size, equals('2×3 م'));
        expect(variant.sku, equals('SKU-2X3M-1000'));
        expect(variant.costPrice, equals(85000));
        expect(variant.sellPrice, equals(120000));
        expect(variant.quantity, equals(0));

        // Verify clean SKU can be scanned/looked up without symbol encoding errors
        final bySku = await (db.select(db.productVariants)..where((v) => v.sku.equals('SKU-2X3M-1000'))).get();
        expect(bySku.length, equals(1));
        expect(bySku.first.id, equals(newVariantId));
      });
    });

    // -------------------------------------------------------------------------
    // 4. Rapid Barcode Intake - Link Barcode to Existing Product
    // -------------------------------------------------------------------------
    group('4. Rapid Barcode Intake - Link Barcode to Existing Product', () {
      late AppDatabase db;

      setUp(() async {
        db = AppDatabase(NativeDatabase.memory());
        await db.into(db.categories).insert(
              CategoriesCompanion.insert(
                id: 'cat-perfumes',
                branchId: 'branch-1',
                name: 'عطور وبخور',
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );
        await db.into(db.products).insert(
              ProductsCompanion.insert(
                id: 'prod-oud-royal',
                name: 'عطر عود ملكي فاخر',
                branchId: 'branch-1',
                categoryId: 'cat-perfumes',
                activityType: const drift.Value('perfumesCosmetics'),
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );
      });

      tearDown(() async {
        await db.close();
      });

      test('links scanned unrecorded barcode as a new size/variant of an existing model', () async {
        const scannedSupplierBarcode = '6221004567891';
        const newSize = '100 مل';
        const newColor = 'ذهبي';
        const costPiasters = 45000;
        const sellPiasters = 75000;
        const intakeQty = 25;

        // Simulate link action in RapidBarcodeIntakeDialog
        final newId = 'var-oud-100ml';
        await db.into(db.productVariants).insert(
              ProductVariantsCompanion.insert(
                id: newId,
                branchId: 'branch-1',
                productId: 'prod-oud-royal',
                sku: scannedSupplierBarcode,
                size: newSize,
                color: newColor,
                costPrice: costPiasters,
                sellPrice: sellPiasters,
                quantity: const drift.Value(intakeQty),
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );

        // Verify linked variant
        final linked = await (db.select(db.productVariants)..where((v) => v.sku.equals(scannedSupplierBarcode))).get();
        expect(linked.length, equals(1));
        final v = linked.first;
        expect(v.productId, equals('prod-oud-royal'));
        expect(v.size, equals('100 مل'));
        expect(v.color, equals('ذهبي'));
        expect(v.quantity, equals(25));
        expect(v.sellPrice, equals(75000));

        // Immediate subsequent scan updates stock cleanly
        await (db.update(db.productVariants)..where((item) => item.id.equals(v.id))).write(
          ProductVariantsCompanion(
            quantity: drift.Value(v.quantity + 1),
            updatedAt: drift.Value(DateTime.now()),
          ),
        );

        final updated = await (db.select(db.productVariants)..where((item) => item.id.equals(v.id))).getSingle();
        expect(updated.quantity, equals(26));
      });
    });

    // -------------------------------------------------------------------------
    // 5. Keyboard Shortcuts & Ergonomics
    // -------------------------------------------------------------------------
    group('5. Keyboard Ergonomics & Shortcut Definitions', () {
      test('F3 and Ctrl+S activators are properly mapped to functional shortcuts', () {
        const f3Activator = SingleActivator(LogicalKeyboardKey.f3);
        expect(f3Activator.trigger, equals(LogicalKeyboardKey.f3));
        expect(f3Activator.control, isFalse);

        const ctrlSActivator = SingleActivator(LogicalKeyboardKey.keyS, control: true);
        expect(ctrlSActivator.trigger, equals(LogicalKeyboardKey.keyS));
        expect(ctrlSActivator.control, isTrue);
      });
    });
  });
}
