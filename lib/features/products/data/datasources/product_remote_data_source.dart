import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/exceptions.dart';
import '../models/product_model.dart';

abstract class ProductRemoteDataSource {
  Future<List<ProductModel>> getProducts();
  Future<void> addProduct(ProductModel product);
  Future<void> updateProduct(ProductModel product);
  Future<void> deleteProduct(String id);
}

@LazySingleton(as: ProductRemoteDataSource)
class ProductRemoteDataSourceImpl implements ProductRemoteDataSource {
  final FirebaseFirestore _firestore;

  ProductRemoteDataSourceImpl(this._firestore);

  @override
  Future<List<ProductModel>> getProducts() async {
    try {
      final snapshot = await _firestore.collection('products').orderBy('createdAt', descending: true).get();
      return snapshot.docs.map((doc) => ProductModel.fromFirestore(doc.data(),doc.id)).toList();
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> addProduct(ProductModel product) async {
    try {
      await _firestore.collection('products').add(product.toFirestore());
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> updateProduct(ProductModel product) async {
    try {
      await _firestore.collection('products').doc(product.id).update(product.toFirestore());
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> deleteProduct(String id) async {
    try {
      await _firestore.collection('products').doc(id).delete();
    } catch (e) {
      throw ServerException(e.toString());
    }
  }
}
