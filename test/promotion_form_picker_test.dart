import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/features/categories/domain/entities/category_entity.dart';
import 'package:clothes_erp/features/categories/domain/repositories/category_repository.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/products/domain/repositories/product_repository.dart';
import 'package:clothes_erp/features/promotions/presentation/widgets/category_picker_dialog.dart';
import 'package:clothes_erp/features/promotions/presentation/widgets/product_picker_dialog.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeProductRepo implements ProductRepository {
  @override
  Future<Either<Failure, List<ProductEntity>>> getProducts() async {
    return Right([
      ProductEntity(
        id: 'p1',
        name: 'Product 1',
        description: 'Desc 1',
        categoryId: 'c1',
        categoryName: 'Cat 1',
        createdAt: DateTime(2025, 1, 1),
        variants: const [
          VariantSummary(
            id: 'v1',
            sku: 'SKU-001',
            color: 'Red',
            size: 'L',
            quantity: 10,
          ),
        ],
      ),
      ProductEntity(
        id: 'p2',
        name: 'Product 2',
        description: 'Desc 2',
        categoryId: 'c2',
        categoryName: 'Cat 2',
        createdAt: DateTime(2025, 1, 1),
        variants: const [
          VariantSummary(
            id: 'v2',
            sku: 'SKU-002',
            color: 'Blue',
            size: 'M',
            quantity: 5,
          ),
        ],
      ),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCategoryRepo implements CategoryRepository {
  @override
  Future<Either<Failure, List<CategoryEntity>>> getCategories() async {
    return Right([
      CategoryEntity(
        id: 'c1',
        name: 'Cat 1',
        description: 'Category 1 Desc',
        createdAt: DateTime(2025, 1, 1),
      ),
      CategoryEntity(
        id: 'c2',
        name: 'Cat 2',
        description: 'Category 2 Desc',
        createdAt: DateTime(2025, 1, 1),
      ),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('1. ProductPickerDialog shows CheckboxListTile items', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ProductPickerDialog(repository: _FakeProductRepo()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    expect(find.text('Product 1'), findsOneWidget);
    expect(find.text('Product 2'), findsOneWidget);
  });

  testWidgets('2. ProductPickerDialog multi-select updates count chip', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ProductPickerDialog(repository: _FakeProductRepo()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    expect(find.text('1 محدد'), findsOneWidget);

    await tester.tap(find.byType(CheckboxListTile).at(1));
    await tester.pump();
    expect(find.text('2 محدد'), findsOneWidget);
  });

  testWidgets('3. CategoryPickerDialog shows checkboxes', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: CategoryPickerDialog(repository: _FakeCategoryRepo()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    expect(find.text('Cat 1'), findsOneWidget);
    expect(find.text('Cat 2'), findsOneWidget);
  });

  testWidgets('4. ProductPickerDialog filters by name', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ProductPickerDialog(repository: _FakeProductRepo()),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Product 1');
    await tester.pump();
    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, 'Product 1'), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, 'Product 2'), findsNothing);
  });
}
