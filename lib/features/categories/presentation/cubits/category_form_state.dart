import 'package:equatable/equatable.dart';

enum CategoryFormStatus { initial, loading, success, error }

class CategoryFormState extends Equatable {
  final String name;
  final String description;
  final CategoryFormStatus status;
  final String? errorMessage;
  final bool isEdit;

  const CategoryFormState({
    this.name = '',
    this.description = '',
    this.status = CategoryFormStatus.initial,
    this.errorMessage,
    this.isEdit = false,
  });

  CategoryFormState copyWith({
    String? name,
    String? description,
    CategoryFormStatus? status,
    String? errorMessage,
    bool? isEdit,
  }) {
    return CategoryFormState(
      name: name ?? this.name,
      description: description ?? this.description,
      status: status ?? this.status,
      errorMessage: errorMessage,
      isEdit: isEdit ?? this.isEdit,
    );
  }

  @override
  List<Object?> get props => [name, description, status, errorMessage, isEdit];
}
