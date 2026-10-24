import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/usecases/add_category_usecase.dart';
import '../../domain/usecases/update_category_usecase.dart';
import 'category_form_state.dart';

@injectable
class CategoryFormCubit extends Cubit<CategoryFormState> {
  final AddCategoryUseCase _addCategoryUseCase;
  final UpdateCategoryUseCase _updateCategoryUseCase;

  CategoryFormCubit(
    this._addCategoryUseCase,
    this._updateCategoryUseCase,
  ) : super(const CategoryFormState());

  void init(CategoryEntity? category) {
    if (category != null) {
      emit(state.copyWith(
        name: category.name,
        description: category.description,
        isEdit: true,
      ));
    }
  }

  void onNameChanged(String value) {
    emit(state.copyWith(name: value));
  }

  void onDescriptionChanged(String value) {
    emit(state.copyWith(description: value));
  }

  Future<void> submit(String? id) async {
    if (state.name.isEmpty) {
      emit(state.copyWith(
        status: CategoryFormStatus.error,
        errorMessage: 'Name is required',
      ));
      return;
    }

    emit(state.copyWith(status: CategoryFormStatus.loading));

    final category = CategoryEntity(
      id: id ?? '',
      name: state.name,
      description: state.description,
      createdAt: DateTime.now(),
    );

    final result = state.isEdit
        ? await _updateCategoryUseCase(category)
        : await _addCategoryUseCase(category);

    result.fold(
      (failure) => emit(state.copyWith(
        status: CategoryFormStatus.error,
        errorMessage: failure.message,
      )),
      (_) => emit(state.copyWith(status: CategoryFormStatus.success)),
    );
  }
}
