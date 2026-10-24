import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';
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
    final snapshot = await _firestore.collection('categories').orderBy('createdAt', descending: true).get();
    return snapshot.docs.map((doc) => CategoryModel.fromFirestore(doc.data(),doc.id)).toList();
  }

  @override
  Future<void> addCategory(CategoryModel category) async {
    await _firestore.collection('categories').add(category.toFirestore());
  }

  @override
  Future<void> updateCategory(CategoryModel category) async {
    await _firestore.collection('categories').doc(category.id).update(category.toFirestore());
  }

  @override
  Future<void> deleteCategory(String id) async {
    await _firestore.collection('categories').doc(id).delete();
  }
}
