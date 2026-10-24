import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../entities/category_entity.dart';
import '../repositories/category_repository.dart';

@lazySingleton
class UpdateCategoryUseCase {
  final CategoryRepository repository;

  UpdateCategoryUseCase(this.repository);

  Future<Either<Failure, void>> call(CategoryEntity category) {
    return repository.updateCategory(category);
  }
}
