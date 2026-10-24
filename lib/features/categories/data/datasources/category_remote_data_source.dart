import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/exceptions.dart';
import '../models/category_model.dart';

abstract class CategoryRemoteDataSource {
  Future<List<CategoryModel>> getCategories();
  Future<void> addCategory(CategoryModel category);
  Future<void> updateCategory(CategoryModel category);
  Future<void> deleteCategory(String id);
}

@LazySingleton(as: CategoryRemoteDataSource)
class CategoryRemoteDataSourceImpl implements CategoryRemoteDataSource {
  final FirebaseFirestore _firestore;

  CategoryRemoteDataSourceImpl(this._firestore);

  @override
  Future<List<CategoryModel>> getCategories() async {
    try {
      final snapshot = await _firestore.collection('categories').orderBy('createdAt', descending: true).get();
      return snapshot.docs.map((doc) => CategoryModel.fromFirestore(doc.data(),doc.id)).toList();
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> addCategory(CategoryModel category) async {
    try {
      await _firestore.collection('categories').add(category.toFirestore());
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> updateCategory(CategoryModel category) async {
    try {
      await _firestore.collection('categories').doc(category.id).update(category.toFirestore());
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> deleteCategory(String id) async {
    try {
      await _firestore.collection('categories').doc(id).delete();
    } catch (e) {
      throw ServerException(e.toString());
    }
  }
}
