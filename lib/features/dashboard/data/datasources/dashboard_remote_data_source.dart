import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../product_variants/data/models/variant_model.dart';

abstract class DashboardRemoteDataSource {
  Future<Map<String, dynamic>> getDashboardStats();
}

@LazySingleton(as: DashboardRemoteDataSource)
class DashboardRemoteDataSourceImpl implements DashboardRemoteDataSource {
  final FirebaseFirestore _firestore;

  DashboardRemoteDataSourceImpl(this._firestore);

  @override
  Future<Map<String, dynamic>> getDashboardStats() async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // Query today's sales
      final salesSnapshot = await _firestore
          .collection('sales')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('date', isLessThan: Timestamp.fromDate(endOfDay))
          .get();

      double todaySales = 0.0;
      for (final doc in salesSnapshot.docs) {
        final data = doc.data();
        todaySales += (data['total'] as num?)?.toDouble() ?? 0.0;
      }
      final todayTransactions = salesSnapshot.docs.length;

      // Query low stock variants
      final variantsSnapshot = await _firestore.collection('product_variants').get();
      final lowStockVariants = variantsSnapshot.docs
          .map((doc) => VariantModel.fromFirestore(doc.data(), doc.id))
          .where((v) => v.quantity <= v.minStock)
          .toList();

      return {
        'todaySales': todaySales,
        'todayTransactions': todayTransactions,
        'lowStockVariants': lowStockVariants,
      };
    } catch (e) {
      throw ServerException(e.toString());
    }
  }
}
