import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../entities/category_entity.dart';
import '../repositories/category_repository.dart';

@lazySingleton
class AddCategoryUseCase {
  final CategoryRepository repository;

  AddCategoryUseCase(this.repository);

  Future<Either<Failure, void>> call(CategoryEntity category) {
    return repository.addCategory(category);
  }
}
