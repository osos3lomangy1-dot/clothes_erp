import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/features/categories/data/datasources/category_local_data_source.dart';
import 'package:clothes_erp/features/products/data/datasources/product_local_data_source.dart';
import 'package:clothes_erp/features/products/data/repositories/product_repository_impl.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/products/domain/services/product_search_filter.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProductSearchFilter & Barcode/SKU Search Tests', () {
    final productA = ProductEntity(
      id: 'prod-a',
      name: 'T-Shirt Black',
      description: 'Cotton crewneck t-shirt',
      categoryId: 'cat-tops',
      categoryName: 'Tops',
      createdAt: DateTime.now(),
      variants: const [
        VariantSummary(
          id: 'var-a-m',
          sku: 'TS-BLK-M',
          color: 'Black',
          size: 'M',
          quantity: 10,
        ),
        VariantSummary(
          id: 'var-a-l',
          sku: 'TS-BLK-L',
          color: 'Black',
          size: 'L',
          quantity: 15,
        ),
      ],
    );

    final productB = ProductEntity(
      id: 'prod-b',
      name: 'Jeans Blue',
      description: 'Slim fit denim jeans',
      categoryId: 'cat-bottoms',
      categoryName: 'Bottoms',
      createdAt: DateTime.now(),
      variants: const [
        VariantSummary(
          id: 'var-b-32',
          sku: 'JN-BLU-32',
          color: 'Blue',
          size: '32',
          quantity: 5,
        ),
      ],
    );

    final productC = ProductEntity(
      id: 'prod-c',
      name: 'Plain Hat',
      description: 'Classic baseball cap',
      categoryId: 'cat-acc',
      categoryName: 'Accessories',
      createdAt: DateTime.now(),
      variants: const [
        VariantSummary(
          id: 'var-c-one',
          sku: 'HAT-ONE',
          color: 'White',
          size: 'Free',
          quantity: 8,
        ),
      ],
    );

    final allProducts = [productA, productB, productC];

    // 1. matches by exact SKU — 'TS-BLK-M' → A
    test('1. matches by exact SKU', () {
      final matches = allProducts
          .where((p) => ProductSearchFilter.matches(p, 'TS-BLK-M'))
          .toList();
      expect(matches.length, 1);
      expect(matches.first.id, 'prod-a');
    });

    // 2. matches by SKU prefix — 'TS-BLK' → A (count=1)
    test('2. matches by SKU prefix', () {
      final matches = allProducts
          .where((p) => ProductSearchFilter.matches(p, 'TS-BLK'))
          .toList();
      expect(matches.length, 1);
      expect(matches.first.id, 'prod-a');
    });

    // 3. matches by SKU exact (case-insensitive) — 'ts-blk-m' → A
    test('3. matches by SKU exact (case-insensitive)', () {
      final matches = allProducts
          .where((p) => ProductSearchFilter.matches(p, 'ts-blk-m'))
          .toList();
      expect(matches.length, 1);
      expect(matches.first.id, 'prod-a');
    });

    // 4. does NOT match by SKU partial middle — 'BLK' → empty (not a prefix)
    test('4. does NOT match by SKU partial middle', () {
      final matches = allProducts
          .where((p) => ProductSearchFilter.matches(p, 'BLK'))
          .toList();
      expect(matches, isEmpty);
    });

    // 5. matches by name partial — 'shirt' → A only
    test('5. matches by name partial', () {
      final matches = allProducts
          .where((p) => ProductSearchFilter.matches(p, 'shirt'))
          .toList();
      expect(matches.length, 1);
      expect(matches.first.id, 'prod-a');
    });

    // 6. matches by category partial — 'bottoms' → B only
    test('6. matches by category partial', () {
      final matches = allProducts
          .where((p) => ProductSearchFilter.matches(p, 'bottoms'))
          .toList();
      expect(matches.length, 1);
      expect(matches.first.id, 'prod-b');
    });

    // 7. multiple variants return product once — 'TS-BLK' → A count=1
    test('7. multiple variants return product once', () {
      final matches = allProducts
          .where((p) => ProductSearchFilter.matches(p, 'TS-BLK'))
          .toList();
      expect(matches.length, 1);
      expect(matches.first.name, 'T-Shirt Black');
    });

    // 8. empty query returns all — '' → count=3
    test('8. empty query returns all', () {
      final matches = allProducts
          .where((p) => ProductSearchFilter.matches(p, ''))
          .toList();
      expect(matches.length, 3);
    });

    // 9. no match — 'xyz' → empty
    test('9. no match returns empty list', () {
      final matches = allProducts
          .where((p) => ProductSearchFilter.matches(p, 'xyz'))
          .toList();
      expect(matches, isEmpty);
    });

    // 10. categoryName populated from DB — verify product.categoryName == 'Tops' for A
    test('10. categoryName populated from DB', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final bp = BranchProvider(db);
      final tx = TxWriter(db);
      final catDs = CategoryLocalDataSource(db, bp);
      final pds = ProductLocalDataSource(db, bp, tx);
      final repo = ProductRepositoryImpl(pds);

      addTearDown(() => db.close());

      // Seed DB
      await catDs.addCategory('Tops');
      final categories = await catDs.getCategories();
      final topsCategory = categories.firstWhere((c) => c.name == 'Tops');

      await pds.createProductWithVariants(
        name: 'T-Shirt Black',
        categoryId: topsCategory.id,
        description: 'Cotton crewneck',
        variants: const [
          VariantInput(
            sku: 'TS-BLK-M',
            color: 'Black',
            size: 'M',
            costPrice: 5000,
            sellPrice: 10000,
            quantity: 10,
          ),
        ],
      );

      final result = await repo.getProducts();
      expect(result.isRight(), isTrue);

      final product = result.getOrElse(() => []).first;
      expect(product.categoryName, 'Tops');

      // Also verify stream emits populated categoryName
      final streamed = (await repo.watchAllProducts().first).getOrElse(() => []).first;
      expect(streamed.categoryName, 'Tops');
    });

    // 11. variants loaded — verify product.variants.length == 2 for A
    test('11. variants loaded from DB repository', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final bp = BranchProvider(db);
      final tx = TxWriter(db);
      final catDs = CategoryLocalDataSource(db, bp);
      final pds = ProductLocalDataSource(db, bp, tx);
      final repo = ProductRepositoryImpl(pds);

      addTearDown(() => db.close());

      // Seed DB
      await catDs.addCategory('Tops');
      final categories = await catDs.getCategories();
      final topsCategory = categories.firstWhere((c) => c.name == 'Tops');

      await pds.createProductWithVariants(
        name: 'T-Shirt Black',
        categoryId: topsCategory.id,
        description: 'Cotton crewneck',
        variants: const [
          VariantInput(
            sku: 'TS-BLK-M',
            color: 'Black',
            size: 'M',
            costPrice: 5000,
            sellPrice: 10000,
            quantity: 10,
          ),
          VariantInput(
            sku: 'TS-BLK-L',
            color: 'Black',
            size: 'L',
            costPrice: 5500,
            sellPrice: 11000,
            quantity: 15,
          ),
        ],
      );

      final result = await repo.getProducts();
      final product = result.getOrElse(() => []).first;

      expect(product.variants.length, 2);
      expect(product.variants.map((v) => v.sku), containsAll(['TS-BLK-M', 'TS-BLK-L']));

      final streamed = (await repo.watchAllProducts().first).getOrElse(() => []).first;
      expect(streamed.variants.length, 2);
    });

    // 12. null/empty sku — seed product with empty sku, query 'anything' → no crash
    test('12. null or empty sku does not crash and handles gracefully', () {
      final productWithEmptySku = ProductEntity(
        id: 'prod-empty',
        name: 'Blank Item',
        description: '',
        categoryId: 'cat-misc',
        categoryName: 'Misc',
        createdAt: DateTime.now(),
        variants: const [
          VariantSummary(
            id: 'var-empty',
            sku: '',
            color: 'None',
            size: 'None',
            quantity: 0,
          ),
        ],
      );

      expect(() => ProductSearchFilter.matches(productWithEmptySku, 'anything'), returnsNormally);
      expect(ProductSearchFilter.matches(productWithEmptySku, 'anything'), isFalse);
      expect(ProductSearchFilter.matches(productWithEmptySku, ''), isTrue);
    });
  });
}
