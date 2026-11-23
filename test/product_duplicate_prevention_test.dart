import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/core/utils/arabic_text_helper.dart';
import 'package:clothes_erp/features/categories/domain/entities/category_entity.dart';
import 'package:clothes_erp/features/categories/domain/repositories/category_repository.dart';
import 'package:clothes_erp/features/categories/domain/usecases/get_categories_usecase.dart';
import 'package:clothes_erp/features/products/data/datasources/product_local_data_source.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/products/domain/repositories/product_repository.dart';
import 'package:clothes_erp/features/products/domain/usecases/add_product_usecase.dart';
import 'package:clothes_erp/features/products/domain/usecases/update_product_usecase.dart';
import 'package:clothes_erp/features/products/presentation/cubits/product_form_cubit.dart';
import 'package:clothes_erp/features/products/presentation/cubits/product_form_state.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCategoryRepository implements CategoryRepository {
  final List<CategoryEntity> categories;
  FakeCategoryRepository(this.categories);

  @override
  Future<Either<Failure, void>> addCategory(CategoryEntity category) async => const Right(null);
  @override
  Future<Either<Failure, void>> deleteCategory(String id) async => const Right(null);
  @override
  Future<Either<Failure, List<CategoryEntity>>> getCategories() async => Right(categories);
  @override
  Future<Either<Failure, void>> updateCategory(CategoryEntity category) async => const Right(null);
  @override
  Future<Either<Failure, List<CategoryEntity>>> seedDefaultHospitalityCategories() async => Right(categories);
}

class FakeProductRepository implements ProductRepository {
  List<ProductEntity> products;
  bool addProductCalled = false;
  bool addWithVariantsCalled = false;

  FakeProductRepository(this.products);

  @override
  Future<Either<Failure, void>> addProduct(ProductEntity product) async {
    addProductCalled = true;
    products.add(product);
    return const Right(null);
  }

  @override
  Future<Either<Failure, String>> addProductWithVariants(
      ProductEntity product, List<VariantInput> variants) async {
    addWithVariantsCalled = true;
    products.add(product);
    return Right(product.id);
  }

  @override
  Future<Either<Failure, void>> deleteProduct(
    String id, {
    bool forceDeleteForAdmin = false,
    String? userId,
  }) async => const Right(null);

  @override
  Future<Either<Failure, List<ProductEntity>>> getProducts() async => Right(products);

  @override
  Future<Either<Failure, void>> updateProduct(ProductEntity product) async => const Right(null);

  @override
  Stream<Either<Failure, List<ProductEntity>>> watchAllProducts() => Stream.value(Right(products));
}

void main() {
  group('ArabicTextHelper Unit Tests', () {
    test('normalizes Alef, Yaa, Taa-Marbuta, and strips Tashkeel', () {
      expect(ArabicTextHelper.normalize('  أَحْمَد  '), equals('احمد'));
      expect(ArabicTextHelper.normalize('قميص كلاسيك أبيض'), equals('قميص كلاسيك ابيض'));
      expect(ArabicTextHelper.normalize('بدلة رجالى كحلى'), equals('بدله رجالي كحلي'));
      expect(ArabicTextHelper.normalize('تيشيرت   قطن   ١٠٠٪'), equals('تيشيرت قطن ١٠٠٪'));
    });

    test('isExactMatch detects duplicates across Arabic variations', () {
      expect(ArabicTextHelper.isExactMatch('قميص أبيض', 'قميص ابيض'), isTrue);
      expect(ArabicTextHelper.isExactMatch('بدلة رجالى', 'بدله رجالي'), isTrue);
      expect(ArabicTextHelper.isExactMatch('بنطلون جينز', 'بنطلون قماش'), isFalse);
    });

    test('isSimilar detects substring and word overlap', () {
      expect(ArabicTextHelper.isSimilar('قميص بولو', 'قميص بولو رجالي أحمر'), isTrue);
      expect(ArabicTextHelper.isSimilar('بدلة كلاسيك كحلي', 'بدلة كلاسيك سوداء'), isTrue);
      expect(ArabicTextHelper.isSimilar('ساعة يد', 'فستان سهرة'), isFalse);
    });
  });

  group('ProductLocalDataSource Duplicate Prevention DB Tests', () {
    late AppDatabase db;
    late BranchProvider bp;
    late TxWriter tx;
    late ProductLocalDataSource pds;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      bp = BranchProvider(db);
      tx = TxWriter(db);
      pds = ProductLocalDataSource(db, bp, tx);
    });

    tearDown(() async => await db.close());

    test('createProduct rejects exact duplicate name', () async {
      await pds.createProduct(name: 'قميص كلاسيك أبيض', categoryId: 'cat-1');

      expect(
        () => pds.createProduct(name: 'قميص كلاسيك أبيض', categoryId: 'cat-1'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('يوجد منتج مسجل بالفعل'))),
      );
    });

    test('createProduct rejects duplicate with Arabic normalization variations', () async {
      await pds.createProduct(name: 'قميص كلاسيك أبيض', categoryId: 'cat-1');

      // Attempting to create without Hamza
      expect(
        () => pds.createProduct(name: 'قميص كلاسيك ابيض', categoryId: 'cat-1'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('يوجد منتج مسجل بالفعل'))),
      );
    });

    test('createProductWithVariants rejects duplicate name', () async {
      await pds.createProduct(name: 'بنطلون جينز أزرق', categoryId: 'cat-1');

      expect(
        () => pds.createProductWithVariants(
          name: 'بنطلون جينز ازرق',
          categoryId: 'cat-1',
          variants: [
            VariantInput(sku: 'SKU-1', color: 'أزرق', size: '32', costPrice: 100, sellPrice: 200, quantity: 5),
          ],
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('يوجد منتج مسجل بالفعل'))),
      );
    });

    test('updateProduct rejects changing name to existing product name', () async {
      await pds.createProduct(name: 'تيشيرت بولو أحمر', categoryId: 'cat-1');
      await pds.createProduct(name: 'تيشيرت بولو أبيض', categoryId: 'cat-1');

      final products = await pds.getProducts();
      final prod2 = products.firstWhere((p) => p.name == 'تيشيرت بولو أبيض');

      expect(
        () => pds.updateProduct(prod2.id, name: 'تيشيرت بولو احمر'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('يوجد منتج آخر مسجل بالفعل'))),
      );
    });
  });

  group('ProductFormCubit Duplicate Prevention Tests', () {
    late ProductFormCubit cubit;
    late FakeProductRepository fakeProductRepo;
    late FakeCategoryRepository fakeCategoryRepo;

    final existingProduct1 = ProductEntity(
      id: 'prod-1',
      name: 'قميص كلاسيك أبيض',
      description: 'قطن مصري',
      categoryId: 'cat-1',
      categoryName: 'قمصان',
      createdAt: DateTime(2026, 1, 1),
    );

    final existingProduct2 = ProductEntity(
      id: 'prod-2',
      name: 'بنطلون جينز كحلي',
      description: 'سليم فيت',
      categoryId: 'cat-2',
      categoryName: 'بناطيل',
      createdAt: DateTime(2026, 1, 1),
    );

    final mockCategories = <CategoryEntity>[
      CategoryEntity(id: 'cat-1', name: 'قمصان', description: '', createdAt: DateTime(2026, 1, 1)),
      CategoryEntity(id: 'cat-2', name: 'بناطيل', description: '', createdAt: DateTime(2026, 1, 1)),
    ];

    setUp(() {
      fakeProductRepo = FakeProductRepository([existingProduct1, existingProduct2]);
      fakeCategoryRepo = FakeCategoryRepository(mockCategories);

      final addProductUseCase = AddProductUseCase(fakeProductRepo);
      final updateProductUseCase = UpdateProductUseCase(fakeProductRepo);
      final getCategoriesUseCase = GetCategoriesUseCase(fakeCategoryRepo);

      cubit = ProductFormCubit(
        addProductUseCase,
        updateProductUseCase,
        getCategoriesUseCase,
        fakeProductRepo,
      );
    });

    tearDown(() {
      cubit.close();
    });

    test('init loads existing products and categories', () async {
      await cubit.init(null);
      expect(cubit.state.categories.length, equals(2));
      expect(cubit.state.existingProducts.length, equals(2));
    });

    test('onNameChanged detects exact duplicate with Arabic normalization', () async {
      await cubit.init(null);

      // User types 'قميص كلاسيك ابيض' (without Hamza)
      cubit.onNameChanged('قميص كلاسيك ابيض');

      expect(cubit.state.hasDuplicate, isTrue);
      expect(cubit.state.exactDuplicateProduct?.id, equals('prod-1'));
    });

    test('onNameChanged detects similar products', () async {
      await cubit.init(null);

      // User types 'قميص كلاسيك كحلي' -> shares 'قميص' and 'كلاسيك'
      cubit.onNameChanged('قميص كلاسيك كحلي');

      expect(cubit.state.hasDuplicate, isFalse);
      expect(cubit.state.hasSimilar, isTrue);
      expect(cubit.state.similarProducts.any((p) => p.id == 'prod-1'), isTrue);
    });

    test('submit blocks saving when duplicate product exists', () async {
      await cubit.init(null);
      cubit.onCategoryChanged('cat-1', 'قمصان');
      cubit.onNameChanged('قميص كلاسيك ابيض');

      await cubit.submit(null);

      expect(cubit.state.status, equals(ProductFormStatus.error));
      expect(cubit.state.errorMessage, contains('لا يمكن تكرار إضافة المنتج'));
      expect(fakeProductRepo.addProductCalled, isFalse);
    });

    test('submitWithVariants blocks saving when duplicate product exists', () async {
      await cubit.init(null);
      cubit.onCategoryChanged('cat-1', 'قمصان');
      cubit.onNameChanged('قميص كلاسيك ابيض');

      await cubit.submitWithVariants(
        id: null,
        variants: [
          VariantInput(sku: 'SKU-M', color: 'أبيض', size: 'M', costPrice: 100, sellPrice: 200, quantity: 1),
        ],
      );

      expect(cubit.state.status, equals(ProductFormStatus.error));
      expect(cubit.state.errorMessage, contains('لا يمكن تكرار إضافة المنتج'));
      expect(fakeProductRepo.addWithVariantsCalled, isFalse);
    });

    test('edit mode ignores current editing product when checking duplicate', () async {
      // Editing existingProduct1
      await cubit.init(existingProduct1);

      // Typing the same name of the product being edited
      cubit.onNameChanged('قميص كلاسيك أبيض');

      expect(cubit.state.hasDuplicate, isFalse);
    });
  });
}
