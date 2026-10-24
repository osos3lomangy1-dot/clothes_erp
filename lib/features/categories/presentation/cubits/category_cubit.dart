import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../domain/usecases/get_categories_usecase.dart';
import '../../domain/usecases/delete_category_usecase.dart';
import 'category_state.dart';

@injectable
class CategoryCubit extends Cubit<CategoryState> {
  final GetCategoriesUseCase _getCategoriesUseCase;
  final DeleteCategoryUseCase _deleteCategoryUseCase;

  CategoryCubit(
    this._getCategoriesUseCase,
    this._deleteCategoryUseCase,
  ) : super(CategoryInitial());

  Future<void> getCategories() async {
    emit(CategoryLoading());
    final result = await _getCategoriesUseCase();
    result.fold(
      (failure) => emit(CategoryError(failure.message)),
      (categories) {
        if (categories.isEmpty) {
          emit(CategoryEmpty());
        } else {
          emit(CategoryLoaded(categories));
        }
      },
    );
  }

  Future<void> deleteCategory(String id) async {
    final result = await _deleteCategoryUseCase(id);
    result.fold(
      (failure) => emit(CategoryError(failure.message)),
      (_) => getCategories(),
    );
  }
}
