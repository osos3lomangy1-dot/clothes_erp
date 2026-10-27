import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/exceptions.dart';
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
    try {
      final snapshot = await _firestore
          .collection('product_variants')
          .where('productId', isEqualTo: productId)
          .orderBy('createdAt', descending: true)
          .get();
      return snapshot.docs.map((doc) => VariantModel.fromFirestore(doc.data(), doc.id)).toList();
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> addVariant(VariantModel variant) async {
    try {
      final existing = await _firestore
          .collection('product_variants')
          .where('productCode', isEqualTo: variant.productCode)
          .get();

      if (existing.docs.isNotEmpty) {
        throw ServerException('Product code already exists');
      }

      await _firestore.collection('product_variants').add(variant.toFirestore());
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> updateVariant(VariantModel variant) async {
    try {
      await _firestore.collection('product_variants').doc(variant.id).update(variant.toFirestore());
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> deleteVariant(String id) async {
    try {
      await _firestore.collection('product_variants').doc(id).delete();
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<List<VariantModel>> searchVariants(String query) async {
    try {
      final snapshot = await _firestore
          .collection('product_variants')
          .where('productCode', isGreaterThanOrEqualTo: query.toUpperCase())
          .where('productCode', isLessThanOrEqualTo: '${query.toUpperCase()}\uf8ff')
          .get();
      return snapshot.docs.map((doc) => VariantModel.fromFirestore(doc.data(), doc.id)).toList();
    } catch (e) {
      throw ServerException(e.toString());
    }
  }
}
