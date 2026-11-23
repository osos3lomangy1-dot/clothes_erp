import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/arabic_text_helper.dart';
import '../../../categories/domain/repositories/category_repository.dart';
import '../../../categories/domain/usecases/get_categories_usecase.dart';
import '../../../product_variants/data/datasources/variant_local_data_source.dart';
import '../../data/datasources/product_local_data_source.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/usecases/add_product_usecase.dart';
import '../../domain/usecases/update_product_usecase.dart';
import '../../../settings/data/services/activity_settings_service.dart';
import 'product_form_state.dart';

@injectable
class ProductFormCubit extends Cubit<ProductFormState> {
  final AddProductUseCase _addProductUseCase;
  final UpdateProductUseCase _updateProductUseCase;
  final GetCategoriesUseCase _getCategoriesUseCase;
  final ProductRepository _productRepository;
  final VariantLocalDataSource? _variantLocalDataSource;

  ProductFormCubit(
    this._addProductUseCase,
    this._updateProductUseCase,
    this._getCategoriesUseCase,
    this._productRepository, {
    @ignoreParam VariantLocalDataSource? variantLocalDataSource,
  })  : _variantLocalDataSource = variantLocalDataSource,
        super(const ProductFormState());

  Future<Set<String>> _loadExistingSkus() async {
    try {
      final ds = _variantLocalDataSource ??
          (getIt.isRegistered<VariantLocalDataSource>()
              ? getIt<VariantLocalDataSource>()
              : null);
      if (ds == null) return const {};
      final variants = await ds.getAllVariants();
      return variants.map((v) => v.sku.trim().toLowerCase()).toSet();
    } catch (_) {
      return const {};
    }
  }

  Future<void> init(ProductEntity? product) async {
    emit(state.copyWith(status: ProductFormStatus.loading));

    final categoriesResult = await _getCategoriesUseCase();
    final productsResult = await _productRepository.getProducts();
    final existingSkus = await _loadExistingSkus();

    final existingProducts = productsResult.getOrElse(() => []);

    String defaultActivity = 'clothing';
    if (getIt.isRegistered<ActivitySettingsService>()) {
      try {
        final enabled = await getIt<ActivitySettingsService>().getEnabledActivities();
        if (enabled.isNotEmpty) {
          defaultActivity = enabled.first.code;
        }
      } catch (_) {}
    }

    await categoriesResult.fold(
      (failure) async => emit(state.copyWith(
        status: ProductFormStatus.error,
        errorMessage: failure.message,
      )),
      (categories) async {
        var cats = categories;
        if (cats.isEmpty && defaultActivity == 'restaurantsCafes') {
          if (getIt.isRegistered<CategoryRepository>()) {
            final seedRes = await getIt<CategoryRepository>().seedDefaultHospitalityCategories();
            cats = seedRes.getOrElse(() => cats);
          }
        }
        if (product != null) {
          emit(state.copyWith(
            name: product.name,
            description: product.description,
            categoryId: product.categoryId,
            categoryName: product.categoryName,
            minStock: product.minStock,
            activityType: product.activityType,
            warrantyPeriod: product.warrantyPeriod,
            brandOrModel: product.brandOrModel,
            isInstallmentEligible: product.isInstallmentEligible,
            createdAt: product.createdAt,
            updatedAt: product.updatedAt,
            categories: cats,
            existingProducts: existingProducts,
            existingSkus: existingSkus,
            isEdit: true,
            editingProductId: product.id,
            status: ProductFormStatus.initial,
          ));
        } else {
          final isHosp = defaultActivity == 'restaurantsCafes';
          final firstCat = (isHosp && cats.isNotEmpty) ? cats.first : null;
          emit(state.copyWith(
            activityType: defaultActivity,
            categoryId: firstCat?.id,
            categoryName: firstCat?.name,
            warrantyPeriod: null,
            brandOrModel: null,
            isInstallmentEligible: true,
            categories: cats,
            existingProducts: existingProducts,
            existingSkus: existingSkus,
            status: ProductFormStatus.initial,
          ));
        }
      },
    );
  }

  Future<void> reloadCategories({String? selectCategoryId}) async {
    final categoriesResult = await _getCategoriesUseCase();
    categoriesResult.fold(
      (_) {},
      (categories) {
        String? catName;
        if (selectCategoryId != null) {
          final found = categories.where((c) => c.id == selectCategoryId);
          if (found.isNotEmpty) {
            catName = found.first.name;
          }
        }
        emit(state.copyWith(
          categories: categories,
          categoryId: selectCategoryId ?? state.categoryId,
          categoryName: catName ?? state.categoryName,
        ));
      },
    );
  }

  void onNameChanged(String value) {
    ProductEntity? exactMatch;
    final List<ProductEntity> similar = [];

    final cleanVal = value.trim();
    if (cleanVal.isNotEmpty) {
      for (final p in state.existingProducts) {
        if (state.isEdit && p.id == state.editingProductId) continue;

        if (ArabicTextHelper.isExactMatch(cleanVal, p.name)) {
          exactMatch = p;
        } else if (ArabicTextHelper.isSimilar(cleanVal, p.name)) {
          similar.add(p);
        }
      }
    }

    emit(state.copyWith(
      name: value,
      exactDuplicateProduct: exactMatch,
      similarProducts: similar,
      clearExactDuplicate: exactMatch == null,
    ));
  }

  void onDescriptionChanged(String value) {
    emit(state.copyWith(description: value));
  }

  void onMinStockChanged(int value) {
    emit(state.copyWith(minStock: value));
  }

  void onCategoryChanged(String id, String name) {
    emit(state.copyWith(categoryId: id, categoryName: name));
  }

  Future<void> onActivityTypeChanged(String type) async {
    if (type == 'restaurantsCafes') {
      var cats = state.categories;
      if (cats.isEmpty && getIt.isRegistered<CategoryRepository>()) {
        final seedRes = await getIt<CategoryRepository>().seedDefaultHospitalityCategories();
        cats = seedRes.getOrElse(() => cats);
      }
      final firstCat = cats.isNotEmpty ? cats.first : null;
      emit(state.copyWith(
        activityType: type,
        categories: cats,
        categoryId: (state.categoryId == null || state.categoryId!.isEmpty) ? firstCat?.id : state.categoryId,
        categoryName: (state.categoryName == null || state.categoryName!.isEmpty) ? firstCat?.name : state.categoryName,
      ));
      return;
    }
    emit(state.copyWith(activityType: type));
  }

  void onWarrantyPeriodChanged(String? val) {
    emit(state.copyWith(warrantyPeriod: val));
  }

  void onBrandOrModelChanged(String? val) {
    emit(state.copyWith(brandOrModel: val));
  }

  void onInstallmentEligibleChanged(bool val) {
    emit(state.copyWith(isInstallmentEligible: val));
  }

  Future<void> submit(String? id) async {
    if (state.name.trim().isEmpty || state.categoryId == null) {
      emit(state.copyWith(
        status: ProductFormStatus.error,
        errorMessage: 'اسم المنتج والتصنيف مطلوبان',
      ));
      return;
    }

    // Duplicate check
    final cleanName = state.name.trim();
    final duplicate = state.exactDuplicateProduct ??
        state.existingProducts.cast<ProductEntity?>().firstWhere(
              (p) =>
                  p != null &&
                  p.id != id &&
                  ArabicTextHelper.isExactMatch(cleanName, p.name),
              orElse: () => null,
            );

    if (duplicate != null) {
      emit(state.copyWith(
        status: ProductFormStatus.error,
        exactDuplicateProduct: duplicate,
        errorMessage:
            'عفواً، يوجد منتج مسجل بالفعل بهذا الاسم ("${duplicate.name}"). لا يمكن تكرار إضافة المنتج.',
      ));
      return;
    }

    emit(state.copyWith(status: ProductFormStatus.loading));

    final now = DateTime.now();
    final product = ProductEntity(
      id: id ?? '',
      name: cleanName,
      description: state.description,
      categoryId: state.categoryId!,
      categoryName: state.categoryName!,
      minStock: state.minStock,
      activityType: state.activityType,
      warrantyPeriod: state.warrantyPeriod,
      brandOrModel: state.brandOrModel,
      isInstallmentEligible: state.isInstallmentEligible,
      createdAt: state.isEdit && state.createdAt != null ? state.createdAt! : now,
      updatedAt: now,
    );

    final result = state.isEdit
        ? await _updateProductUseCase(product)
        : await _addProductUseCase(product);

    result.fold(
      (failure) => emit(state.copyWith(
        status: ProductFormStatus.error,
        errorMessage: failure.message,
      )),
      (_) => emit(state.copyWith(status: ProductFormStatus.success)),
    );
  }

  Future<void> submitWithVariants({
    String? id,
    required List<VariantInput> variants,
  }) async {
    if (state.name.trim().isEmpty || state.categoryId == null) {
      emit(state.copyWith(
        status: ProductFormStatus.error,
        errorMessage: 'اسم المنتج والتصنيف مطلوبان',
      ));
      return;
    }

    if (!state.isEdit && variants.isEmpty) {
      emit(state.copyWith(
        status: ProductFormStatus.error,
        errorMessage: 'يرجى إضافة مقاس واحد على الأقل في جدول المقاسات',
      ));
      return;
    }

    // Duplicate check
    final cleanName = state.name.trim();
    final duplicate = state.exactDuplicateProduct ??
        state.existingProducts.cast<ProductEntity?>().firstWhere(
              (p) =>
                  p != null &&
                  p.id != id &&
                  ArabicTextHelper.isExactMatch(cleanName, p.name),
              orElse: () => null,
            );

    if (duplicate != null) {
      emit(state.copyWith(
        status: ProductFormStatus.error,
        exactDuplicateProduct: duplicate,
        errorMessage:
            'عفواً، يوجد منتج مسجل بالفعل بهذا الاسم ("${duplicate.name}"). لا يمكن تكرار إضافة المنتج.',
      ));
      return;
    }

    if (!state.isEdit) {
      final seenSkus = <String>{};
      for (final v in variants) {
        final cleanSku = v.sku.trim();
        final lower = cleanSku.toLowerCase();
        if (cleanSku.isEmpty) {
          emit(state.copyWith(
            status: ProductFormStatus.error,
            errorMessage: 'كود المنتج (SKU) مطلوب لكل مقاس',
          ));
          return;
        }
        if (!seenSkus.add(lower)) {
          emit(state.copyWith(
            status: ProductFormStatus.error,
            errorMessage: 'عفواً، الكود ("$cleanSku") مكرر أكثر من مرة داخل جدول المقاسات.',
          ));
          return;
        }
        if (state.existingSkus.contains(lower)) {
          emit(state.copyWith(
            status: ProductFormStatus.error,
            errorMessage: 'عفواً، الكود ("$cleanSku") مسجل بالفعل في النظام لصنف آخر. لا يمكن تكرار الأكواد.',
          ));
          return;
        }
      }
    }

    emit(state.copyWith(status: ProductFormStatus.loading));

    final now = DateTime.now();
    final product = ProductEntity(
      id: id ?? '',
      name: cleanName,
      description: state.description,
      categoryId: state.categoryId!,
      categoryName: state.categoryName ?? '',
      minStock: state.minStock,
      activityType: state.activityType,
      warrantyPeriod: state.warrantyPeriod,
      brandOrModel: state.brandOrModel,
      isInstallmentEligible: state.isInstallmentEligible,
      createdAt: state.isEdit && state.createdAt != null ? state.createdAt! : now,
      updatedAt: now,
    );

    if (state.isEdit) {
      final result = await _updateProductUseCase(product);
      result.fold(
        (failure) => emit(state.copyWith(
          status: ProductFormStatus.error,
          errorMessage: failure.message,
        )),
        (_) => emit(state.copyWith(status: ProductFormStatus.success)),
      );
    } else {
      final result =
          await _productRepository.addProductWithVariants(product, variants);
      result.fold(
        (failure) => emit(state.copyWith(
          status: ProductFormStatus.error,
          errorMessage: failure.message,
        )),
        (_) => emit(state.copyWith(status: ProductFormStatus.success)),
      );
    }
  }
}
