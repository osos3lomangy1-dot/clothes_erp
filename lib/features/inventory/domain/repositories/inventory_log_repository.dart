import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/inventory_log_entity.dart';

abstract class InventoryLogRepository {
  Future<Either<Failure, List<InventoryLogEntity>>> getLogs();
}
