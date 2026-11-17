import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/features/product_variants/data/datasources/variant_local_data_source.dart';
import 'package:clothes_erp/features/product_variants/domain/entities/variant_entity.dart';
import 'package:clothes_erp/features/product_variants/domain/repositories/variant_repository.dart';
import 'package:clothes_erp/features/product_variants/domain/usecases/add_variant_usecase.dart';
import 'package:clothes_erp/features/product_variants/domain/usecases/update_variant_usecase.dart';
import 'package:clothes_erp/features/product_variants/presentation/cubits/variant_form_cubit.dart';
import 'package:clothes_erp/features/product_variants/presentation/cubits/variant_form_state.dart';
import 'package:clothes_erp/features/products/data/datasources/product_local_data_source.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeVariantRepository implements VariantRepository {
  bool addCalled = false;
  bool updateCalled = false;

  @override
  Future<Either<Failure, void>> addVariant(VariantEntity variant) async {
    addCalled = true;
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> deleteVariant(String id) async => const Right(null);

  @override
  Future<Either<Failure, List<VariantEntity>>> getVariants(String productId) async =>
      const Right([]);

  @override
  Future<Either<Failure, List<VariantEntity>>> getAllVariants() async => const Right([]);

  @override
  Future<Either<Failure, List<VariantEntity>>> searchVariants(String query) async =>
      const Right([]);

  @override
  Stream<Either<Failure, List<VariantEntity>>> watchAllVariants() =>
      Stream.value(const Right([]));

  @override
  Future<Either<Failure, void>> updateVariant(VariantEntity variant) async {
    updateCalled = true;
    return const Right(null);
  }

  @override
  Stream<Either<Failure, List<VariantEntity>>> watchVariants(String productId) =>
      Stream.value(const Right([]));
}

void main() {
  late AppDatabase db;
  late BranchProvider bp;
  late TxWriter tx;
  late ProductLocalDataSource pds;
  late VariantLocalDataSource vds;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    bp = BranchProvider(db);
    tx = TxWriter(db);
    pds = ProductLocalDataSource(db, bp, tx);
    vds = VariantLocalDataSource(db, bp, tx);
  });

  tearDown(() async => await db.close());

  group('SKU Duplicate Prevention — Database Layer', () {
    test('createVariant rejects exact, case-insensitive, and whitespace-padded duplicate SKUs', () async {
      await pds.createProduct(name: 'قميص بولو', categoryId: 'c1');
      final prod = (await pds.getProducts()).first;

      await vds.createVariant(
        productId: prod.id,
        sku: 'SKU-100',
        color: 'أسود',
        size: 'M',
        costPrice: 10000,
        sellPrice: 20000,
      );

      // Exact duplicate
      await expectLater(
        vds.createVariant(
          productId: prod.id,
          sku: 'SKU-100',
          color: 'أبيض',
          size: 'L',
          costPrice: 10000,
          sellPrice: 20000,
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('لا يمكن تكرار الأكواد'))),
      );

      // Case-insensitive + whitespace duplicate
      await expectLater(
        vds.createVariant(
          productId: prod.id,
          sku: '  sku-100  ',
          color: 'أزرق',
          size: 'XL',
          costPrice: 10000,
          sellPrice: 20000,
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('لا يمكن تكرار الأكواد'))),
      );
    });

    test('updateVariant rejects changing SKU to an existing SKU, allows keeping own SKU', () async {
      await pds.createProduct(name: 'بنطلون كلاسيك', categoryId: 'c1');
      final prod = (await pds.getProducts()).first;

      await vds.createVariant(
        productId: prod.id,
        sku: 'PNT-01',
        color: 'أسود',
        size: '32',
        costPrice: 10000,
        sellPrice: 20000,
      );
      await vds.createVariant(
        productId: prod.id,
        sku: 'PNT-02',
        color: 'كحلي',
        size: '34',
        costPrice: 10000,
        sellPrice: 20000,
      );

      final variants = await vds.getVariants(prod.id);
      final v2 = variants.firstWhere((v) => v.sku == 'PNT-02');

      // Keeping own SKU succeeds
      await vds.updateVariant(v2.id, sku: 'PNT-02', sellPrice: 25000);

      // Changing to v1's SKU (case-insensitive) fails
      await expectLater(
        vds.updateVariant(v2.id, sku: 'pnt-01'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('لا يمكن تكرار الأكواد'))),
      );
    });

    test('createProductWithVariants rejects duplicate SKUs within batch and against existing DB SKUs', () async {
      // 1. Duplicate within same batch
      await expectLater(
        pds.createProductWithVariants(
          name: 'جاكيت شتوي',
          categoryId: 'c1',
          variants: [
            VariantInput(sku: 'JKT-1', color: 'أسود', size: 'M', costPrice: 10000, sellPrice: 20000, quantity: 5),
            VariantInput(sku: ' jkt-1 ', color: 'بني', size: 'L', costPrice: 10000, sellPrice: 20000, quantity: 5),
          ],
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('مكرر أكثر من مرة'))),
      );

      // 2. Create first product cleanly
      await pds.createProductWithVariants(
        name: 'جاكيت شتوي',
        categoryId: 'c1',
        variants: [
          VariantInput(sku: 'JKT-1', color: 'أسود', size: 'M', costPrice: 10000, sellPrice: 20000, quantity: 5),
        ],
      );

      // 3. Second product reusing JKT-1 (case-insensitive) fails
      await expectLater(
        pds.createProductWithVariants(
          name: 'سويتشيرت قطن',
          categoryId: 'c1',
          variants: [
            VariantInput(sku: 'jkt-1', color: 'رمادي', size: 'L', costPrice: 10000, sellPrice: 20000, quantity: 3),
          ],
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('لا يمكن تكرار الأكواد'))),
      );
    });
  });

  group('SKU Duplicate Prevention — VariantFormCubit', () {
    test('detects duplicate SKU in real-time and blocks submit', () async {
      await pds.createProduct(name: 'تيشيرت', categoryId: 'c1');
      final prod = (await pds.getProducts()).first;
      await vds.createVariant(
        productId: prod.id,
        sku: 'TSH-999',
        color: 'أبيض',
        size: 'M',
        costPrice: 5000,
        sellPrice: 10000,
      );

      final fakeRepo = _FakeVariantRepository();
      final cubit = VariantFormCubit(
        AddVariantUseCase(fakeRepo),
        UpdateVariantUseCase(fakeRepo),
        variantLocalDataSource: vds,
      );

      await cubit.init(null);
      cubit.onColorChanged('أسود');
      cubit.onSizeChanged('L');
      cubit.onProductCodeChanged('tsh-999');

      expect(cubit.state.hasDuplicateSku, isTrue);

      await cubit.submit(id: null, productId: prod.id);
      expect(cubit.state.status, equals(VariantFormStatus.error));
      expect(cubit.state.errorMessage, contains('لا يمكن تكرار الأكواد'));
      expect(fakeRepo.addCalled, isFalse);

      await cubit.close();
    });
  });
}
