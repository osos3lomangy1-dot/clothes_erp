import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/utils/logging.dart';
import '../../../product_variants/data/models/variant_model.dart';

abstract class InventoryRemoteDataSource {
  Future<List<VariantModel>> getAllInventory();
  Future<List<VariantModel>> getLowStockInventory();
}

@LazySingleton(as: InventoryRemoteDataSource)
class InventoryRemoteDataSourceImpl implements InventoryRemoteDataSource {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  InventoryRemoteDataSourceImpl();

  @override
  Future<List<VariantModel>> getAllInventory() async {
    if (!kEnableFirebase) return [];
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
    if (!kEnableFirebase) return [];
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
