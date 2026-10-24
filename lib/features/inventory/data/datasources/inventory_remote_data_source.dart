import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';
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
    final snapshot = await _firestore.collection('variants').orderBy('quantity', descending: false).get();
    return snapshot.docs.map((doc) => VariantModel.fromFirestore(doc.data(),doc.id)).toList();
  }

  @override
  Future<List<VariantModel>> getLowStockInventory() async {
    // Note: Firestore doesn't support comparing two fields in a single query (quantity <= minStock) 
    // without a composite index or extra field. For MVP, we fetch all and filter in memory, 
    // or suggest adding a 'isLowStock' flag.
    // Given the "Keep code simple" rule, we'll fetch all and filter.
    final snapshot = await _firestore.collection('variants').get();
    return snapshot.docs
        .map((doc) => VariantModel.fromFirestore(doc.data(),doc.id))
        .where((variant) => variant.quantity <= variant.minStock)
        .toList();
  }
}
