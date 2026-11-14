import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/inventory_log_entity.dart';
import '../../domain/repositories/inventory_log_repository.dart';

@LazySingleton(as: InventoryLogRepository)
class InventoryLogRepositoryImpl implements InventoryLogRepository {
  final AppDatabase _db;

  InventoryLogRepositoryImpl(this._db);

  @override
  Future<Either<Failure, List<InventoryLogEntity>>> getLogs() async {
    try {
      final query = _db.select(_db.inventoryLogs).join([
        leftOuterJoin(
          _db.productVariants,
          _db.productVariants.id.equalsExp(_db.inventoryLogs.variantId),
        ),
        leftOuterJoin(
          _db.products,
          _db.products.id.equalsExp(_db.productVariants.productId),
        ),
        leftOuterJoin(
          _db.users,
          _db.users.id.equalsExp(_db.inventoryLogs.userId),
        ),
      ])
        ..orderBy([
          OrderingTerm(
            expression: _db.inventoryLogs.createdAt,
            mode: OrderingMode.desc,
          ),
        ]);

      final rows = await query.get();

      final logs = rows.map((row) {
        final log = row.readTable(_db.inventoryLogs);
        final variant = row.readTableOrNull(_db.productVariants);
        final product = row.readTableOrNull(_db.products);
        final user = row.readTableOrNull(_db.users);

        return InventoryLogEntity(
          id: log.id,
          productId: variant?.productId ?? log.variantId,
          variantId: log.variantId,
          productName: product?.name,
          variantSize: variant?.size,
          variantColor: variant?.color,
          userName: user?.displayName ?? user?.username ?? log.userId,
          type: log.type,
          quantity: log.qtyDelta.abs(),
          date: log.createdAt,
          userId: log.userId,
        );
      }).toList();

      return Right(logs);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }
}
