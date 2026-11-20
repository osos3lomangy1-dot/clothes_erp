import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/smart_inventory_entities.dart';

abstract class SmartInventoryRepository {
  Future<Either<Failure, List<ReorderSuggestionEntity>>> getReorderSuggestions({int days = 30});
  Future<Either<Failure, List<DeadStockItemEntity>>> getDeadStock({int dormantDays = 60});
  Future<Either<Failure, List<StockMovementCardItemEntity>>> getStockMovementCard(String variantId);
  Future<Either<Failure, List<({String id, String label, String sku})>>> getVariantsForCardPicker();
}

