import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/failures.dart';
import '../entities/return_item_entity.dart';
import '../repositories/returns_repository.dart';

@lazySingleton
class ProcessReturnUseCase {
  final ReturnsRepository _repository;

  ProcessReturnUseCase(this._repository);

  Future<Either<Failure, void>> call({
    required String saleId,
    required List<ReturnItemEntity> items,
    required String reason,
    required String userId,
    String paymentMethod = 'cash',
  }) {
    return _repository.processReturn(
      saleId: saleId,
      items: items,
      reason: reason,
      userId: userId,
      paymentMethod: paymentMethod,
    );
  }
}

