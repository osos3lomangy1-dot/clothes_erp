import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/di/injection.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/features/auth/domain/entities/user_entity.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/inventory/data/datasources/inventory_local_data_source.dart';
import 'package:clothes_erp/features/inventory/presentation/cubits/goods_receipt_cubit.dart';
import 'package:clothes_erp/features/inventory/presentation/screens/blind_receive_screen.dart';
import 'package:clothes_erp/features/product_variants/data/datasources/variant_local_data_source.dart';
import 'package:clothes_erp/features/product_variants/domain/entities/variant_entity.dart';
import 'package:clothes_erp/features/product_variants/domain/repositories/variant_repository.dart';
import 'package:clothes_erp/features/product_variants/domain/usecases/add_variant_usecase.dart';
import 'package:clothes_erp/features/product_variants/domain/usecases/update_variant_usecase.dart';
import 'package:clothes_erp/features/product_variants/presentation/cubits/variant_form_cubit.dart';
import 'package:clothes_erp/features/product_variants/presentation/screens/variant_form_screen.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeVariantRepository implements VariantRepository {
  @override
  Future<Either<Failure, void>> addVariant(VariantEntity variant) async => const Right(null);

  @override
  Future<Either<Failure, void>> deleteVariant(String id) async => const Right(null);

  @override
  Future<Either<Failure, List<VariantEntity>>> getVariants(String productId) async => const Right([]);

  @override
  Future<Either<Failure, List<VariantEntity>>> getAllVariants() async => const Right([]);

  @override
  Future<Either<Failure, List<VariantEntity>>> searchVariants(String query) async => const Right([]);

  @override
  Stream<Either<Failure, List<VariantEntity>>> watchAllVariants() => Stream.value(const Right([]));

  @override
  Future<Either<Failure, void>> updateVariant(VariantEntity variant) async => const Right(null);

  @override
  Stream<Either<Failure, List<VariantEntity>>> watchVariants(String productId) => Stream.value(const Right([]));
}

class _FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _FakeAuthCubit()
      : super(AuthAuthenticated(
          UserEntity(
            id: 'user-1',
            name: 'المشرف',
            email: 'admin@bay3ah.com',
            role: 'admin',
            isActive: true,
            createdAt: DateTime.now(),
          ),
        ));

  @override
  Future<void> login(String email, String password) async {}
  @override
  Future<void> logout() async {}
  @override
  Future<bool> switchCashierWithPin({
    required String usernameOrId,
    required String pin,
  }) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _FakeAuthCubit authCubit;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    authCubit = _FakeAuthCubit();

    if (getIt.isRegistered<AppDatabase>()) {
      await getIt.unregister<AppDatabase>();
    }
    getIt.registerSingleton<AppDatabase>(db);

    final bp = BranchProvider(db);
    final tx = TxWriter(db);

    if (getIt.isRegistered<GoodsReceiptCubit>()) {
      await getIt.unregister<GoodsReceiptCubit>();
    }
    final invDs = InventoryLocalDataSource(db, bp, tx);
    getIt.registerFactory<GoodsReceiptCubit>(() => GoodsReceiptCubit(invDs));

    if (getIt.isRegistered<VariantFormCubit>()) {
      await getIt.unregister<VariantFormCubit>();
    }
    final fakeRepo = _FakeVariantRepository();
    final vds = VariantLocalDataSource(db, bp, tx);
    getIt.registerFactory<VariantFormCubit>(
      () => VariantFormCubit(
        AddVariantUseCase(fakeRepo),
        UpdateVariantUseCase(fakeRepo),
        variantLocalDataSource: vds,
      ),
    );

    // Seed test category and product
    await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            id: 'cat-fashion',
            branchId: 'branch-1',
            name: 'ملابس',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );

    await db.into(db.products).insert(
          ProductsCompanion.insert(
            id: 'prod-shirt-101',
            branchId: 'branch-1',
            categoryId: 'cat-fashion',
            name: 'قميص أكسفورد رجالي',
            activityType: const drift.Value('clothing'),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
  });

  tearDown(() async {
    await db.close();
    if (getIt.isRegistered<AppDatabase>()) {
      await getIt.unregister<AppDatabase>();
    }
    if (getIt.isRegistered<GoodsReceiptCubit>()) {
      await getIt.unregister<GoodsReceiptCubit>();
    }
    if (getIt.isRegistered<VariantFormCubit>()) {
      await getIt.unregister<VariantFormCubit>();
    }
  });

  Widget buildTestWidget(Widget child) {
    return BlocProvider<AuthCubit>.value(
      value: authCubit,
      child: MaterialApp(
        home: child,
      ),
    );
  }

  group('Task 23: On-the-Fly Variant Intake in Goods Receipt & Size Chips', () {
    testWidgets('1. BlindReceiveScreen displays add variant button in AppBar and opens intake dialog',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestWidget(const BlindReceiveScreen()));
      await tester.pumpAndSettle();

      // Verify the AppBar action button exists
      final addVariantBtn = find.byKey(const Key('blind_receive_add_variant_btn'));
      expect(addVariantBtn, findsOneWidget);
      expect(find.text('إضافة مقاس لصنف مسجل'), findsOneWidget);

      // Tap the button to open dialog
      await tester.tap(addVariantBtn);
      await tester.pumpAndSettle();

      // Verify dialog opened with required fields
      expect(find.text('إضافة مقاس جديد لصنف مسجل في الشحنة'), findsOneWidget);
      expect(find.byKey(const Key('select_existing_product_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('new_variant_size_field')), findsOneWidget);
      expect(find.byKey(const Key('new_variant_color_field')), findsOneWidget);
      expect(find.byKey(const Key('new_variant_cost_field')), findsOneWidget);
      expect(find.byKey(const Key('new_variant_sell_field')), findsOneWidget);
      expect(find.byKey(const Key('new_variant_qty_field')), findsOneWidget);
      expect(find.byKey(const Key('confirm_add_new_variant_btn')), findsOneWidget);

      // Verify sector size chips for clothing are present
      expect(find.byKey(const Key('shipment_size_chip_S')), findsOneWidget);
      expect(find.byKey(const Key('shipment_size_chip_XL')), findsOneWidget);
      expect(find.byKey(const Key('shipment_size_chip_3XL')), findsOneWidget);

      // Tap chip '3XL' to set size
      await tester.tap(find.byKey(const Key('shipment_size_chip_3XL')));
      await tester.pumpAndSettle();

      final sizeField = tester.widget<TextField>(find.byKey(const Key('new_variant_size_field')));
      expect(sizeField.controller?.text, equals('3XL'));

      // Enter quantity and confirm
      await tester.enterText(find.byKey(const Key('new_variant_qty_field')), '15');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('confirm_add_new_variant_btn')));
      await tester.pumpAndSettle();

      // Verify line was added to shipment table
      expect(find.text('قميص أكسفورد رجالي'), findsWidgets);
      expect(find.textContaining('3XL'), findsWidgets);
      expect(find.textContaining('15'), findsWidgets);

      // Verify database has new variant inserted with sanitized SKU
      final variants = await db.select(db.productVariants).get();
      expect(variants.length, equals(1));
      expect(variants.first.size, equals('3XL'));
      expect(variants.first.sku, contains('3XL'));
      expect(RegExp(r'^[A-Z0-9_-]+$').hasMatch(variants.first.sku), isTrue);
    });

    testWidgets('2. Search dialog contains button to add new variant on-the-fly',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Insert an initial variant so search dialog has data to open
      await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: 'var-shirt-s',
              branchId: 'branch-1',
              productId: 'prod-shirt-101',
              sku: 'SKU-SHIRT-S',
              size: 'S',
              color: 'أبيض',
              costPrice: 5000,
              sellPrice: 10000,
              quantity: const drift.Value(5),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );

      await tester.pumpWidget(buildTestWidget(const BlindReceiveScreen()));
      await tester.pumpAndSettle();

      // Click search button
      final searchBtn = find.widgetWithText(ElevatedButton, 'بحث واختيار من القائمة');
      expect(searchBtn, findsOneWidget);
      await tester.tap(searchBtn);
      await tester.pumpAndSettle();

      // Verify search dialog add variant button exists
      final searchAddBtn = find.byKey(const Key('search_dialog_add_variant_btn'));
      expect(searchAddBtn, findsOneWidget);

      // Tap search add button - it should dismiss search and open add variant dialog
      await tester.tap(searchAddBtn);
      await tester.pumpAndSettle();

      expect(find.text('إضافة مقاس جديد لصنف مسجل في الشحنة'), findsOneWidget);
      expect(find.byKey(const Key('confirm_add_new_variant_btn')), findsOneWidget);
    });

    testWidgets('3. VariantFormScreen displays adaptive size chips and autogenerates clean SKU',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final product = ProductEntity(
        id: 'prod-shirt-101',
        name: 'قميص أكسفورد رجالي',
        description: 'قميص قطن رجالي ممتاز',
        categoryId: 'cat-fashion',
        categoryName: 'ملابس',
        activityType: 'clothing',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        buildTestWidget(VariantFormScreen(product: product)),
      );
      await tester.pumpAndSettle();

      // Verify clothing size chips are rendered
      expect(find.byKey(const Key('size_chip_S')), findsOneWidget);
      expect(find.byKey(const Key('size_chip_M')), findsOneWidget);
      expect(find.byKey(const Key('size_chip_L')), findsOneWidget);
      expect(find.byKey(const Key('size_chip_XL')), findsOneWidget);
      expect(find.byKey(const Key('size_chip_2XL')), findsOneWidget);
      expect(find.byKey(const Key('size_chip_Free Size')), findsOneWidget);

      // Verify dimension tool button is present
      expect(find.byKey(const Key('variant_dimension_tool_btn')), findsOneWidget);

      // Tap size chip '2XL'
      await tester.tap(find.byKey(const Key('size_chip_2XL')));
      await tester.pumpAndSettle();

      // Verify size field was populated
      expect(find.widgetWithText(TextFormField, '2XL'), findsOneWidget);

      // Verify clean SKU was autogenerated with sanitized Code 128 format
      final skuFinder = find.byWidgetPredicate(
        (w) => w is TextFormField && (w.controller?.text.startsWith('SKU-2XL') ?? false),
      );
      expect(skuFinder, findsOneWidget);
    });

    testWidgets('4. Dimension tool generates formatted meters size and clean SKU',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final carpetProduct = ProductEntity(
        id: 'prod-carpet-shiraz',
        name: 'سجاد شيراز يدوي',
        description: 'سجاد إيراني كلاسيك',
        categoryId: 'cat-textiles',
        categoryName: 'مفروشات',
        activityType: 'textilesDecor',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        buildTestWidget(VariantFormScreen(product: carpetProduct)),
      );
      await tester.pumpAndSettle();

      // Verify carpet chips are rendered for textilesDecor
      expect(find.byKey(const Key('size_chip_2×3 م')), findsOneWidget);
      expect(find.byKey(const Key('size_chip_1.5×2 م')), findsOneWidget);
      expect(find.byKey(const Key('size_chip_مشاية 1×3 م')), findsOneWidget);

      // Tap dimension tool button
      await tester.tap(find.byKey(const Key('variant_dimension_tool_btn')));
      await tester.pumpAndSettle();

      // Verify dimension dialog opened
      expect(find.text('تحديد المقاس بالأمتار (مفروشات وسجاد)'), findsOneWidget);
      expect(find.byKey(const Key('dimension_width_field')), findsOneWidget);
      expect(find.byKey(const Key('dimension_length_field')), findsOneWidget);
      expect(find.byKey(const Key('confirm_dimension_btn')), findsOneWidget);

      // Enter dimensions 1.8 x 2.7
      await tester.enterText(find.byKey(const Key('dimension_width_field')), '1.8');
      await tester.enterText(find.byKey(const Key('dimension_length_field')), '2.7');
      await tester.pumpAndSettle();

      // Confirm
      await tester.tap(find.byKey(const Key('confirm_dimension_btn')));
      await tester.pumpAndSettle();

      // Verify size field populated with '1.8×2.7 م'
      expect(find.widgetWithText(TextFormField, '1.8×2.7 م'), findsOneWidget);

      // Verify sanitized clean SKU generated with '1_8X2_7M'
      final skuFinder = find.byWidgetPredicate(
        (w) => w is TextFormField && (w.controller?.text.contains('1_8X2_7M') ?? false),
      );
      expect(skuFinder, findsOneWidget);
    });
  });
}
