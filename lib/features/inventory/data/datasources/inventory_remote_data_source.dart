import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/utils/logging.dart';
import '../../../product_variants/data/models/variant_model.dart';

abstract class InventoryRemoteDataSource {
  Future<List<VariantModel>> getAllInventory();
  Future<List<VariantModel>> getLowStockInventory();
}

@LazySingleton(as: InventoryRemoteDataSource)
class InventoryRemoteDataSourceImpl implements InventoryRemoteDataSource {
  final FirebaseFirestore _firestore;

  InventoryRemoteDataSourceImpl(this._firestore);

  @override
  Future<List<VariantModel>> getAllInventory() async {
    try {
      final snapshot = await _firestore.collection('product_variants').orderBy('quantity', descending: false).get();
      Logging.info('Fetched ${snapshot.docs.length} variants for inventory');
      return snapshot.docs.map((doc) => VariantModel.fromFirestore(doc.data(), doc.id)).toList();
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<List<VariantModel>> getLowStockInventory() async {
    try {
      final snapshot = await _firestore.collection('product_variants').get();
      return snapshot.docs
          .map((doc) => VariantModel.fromFirestore(doc.data(), doc.id))
          .where((variant) => variant.quantity <= variant.minStock)
          .toList();
    } catch (e) {
      throw ServerException(e.toString());
    }
  }
}
