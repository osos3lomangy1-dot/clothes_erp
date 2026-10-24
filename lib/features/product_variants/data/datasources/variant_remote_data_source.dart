import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';
import '../models/variant_model.dart';

abstract class VariantRemoteDataSource {
  Future<List<VariantModel>> getVariants(String productId);
  Future<void> addVariant(VariantModel variant);
  Future<void> updateVariant(VariantModel variant);
  Future<void> deleteVariant(String id);
  Future<List<VariantModel>> searchVariants(String query);
}

@LazySingleton(as: VariantRemoteDataSource)
class VariantRemoteDataSourceImpl implements VariantRemoteDataSource {
  final FirebaseFirestore _firestore;

  VariantRemoteDataSourceImpl(this._firestore);

  @override
  Future<List<VariantModel>> getVariants(String productId) async {
    final snapshot = await _firestore
        .collection('variants')
        .where('productId', isEqualTo: productId)
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs.map((doc) => VariantModel.fromFirestore(doc.data(),doc.id)).toList();
  }

  @override
  Future<void> addVariant(VariantModel variant) async {
    final existing = await _firestore
        .collection('variants')
        .where('productCode', isEqualTo: variant.productCode)
        .get();
    
    if (existing.docs.isNotEmpty) {
      throw Exception('Product code already exists');
    }

    await _firestore.collection('variants').add(variant.toFirestore());
  }

  @override
  Future<void> updateVariant(VariantModel variant) async {
    await _firestore.collection('variants').doc(variant.id).update(variant.toFirestore());
  }

  @override
  Future<void> deleteVariant(String id) async {
    await _firestore.collection('variants').doc(id).delete();
  }

  @override
  Future<List<VariantModel>> searchVariants(String query) async {
    final snapshot = await _firestore
        .collection('variants')
        .where('productCode', isGreaterThanOrEqualTo: query.toUpperCase())
        .where('productCode', isLessThanOrEqualTo: '${query.toUpperCase()}\uf8ff')
        .get();
    return snapshot.docs.map((doc) => VariantModel.fromFirestore(doc.data(),doc.id)).toList();
  }
}
