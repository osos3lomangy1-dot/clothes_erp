import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/inventory_log_entity.dart';
import '../../domain/repositories/inventory_log_repository.dart';

@LazySingleton(as: InventoryLogRepository)
class InventoryLogRepositoryImpl implements InventoryLogRepository {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  InventoryLogRepositoryImpl();

  @override
  Future<Either<Failure, List<InventoryLogEntity>>> getLogs() async {
    if (!kEnableFirebase) {
      return const Right([]);
    }
    try {
      final snapshot = await _firestore
          .collection('inventory_logs')
          .orderBy('date', descending: true)
          .get();
      final logs = snapshot.docs.map((doc) {
        final data = doc.data();
        return InventoryLogEntity(
          id: doc.id,
          productId: data['productId'] ?? '',
          variantId: data['variantId'],
          type: data['type'] ?? 'out',
          quantity: data['quantity'] ?? 0,
          date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
          userId: data['userId'] ?? '',
        );
      }).toList();
      return Right(logs);
    } on FirebaseException catch (e) {
      return Left(ServerFailure(e.message ?? 'Firebase error'));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
