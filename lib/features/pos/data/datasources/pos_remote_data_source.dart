import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';
import '../models/sale_model.dart';

abstract class PosRemoteDataSource {
  Future<void> createSale(SaleModel sale);
}

@LazySingleton(as: PosRemoteDataSource)
class PosRemoteDataSourceImpl implements PosRemoteDataSource {
  final FirebaseFirestore _firestore;

  PosRemoteDataSourceImpl(this._firestore);

  @override
  Future<void> createSale(SaleModel sale) async {
    final batch = _firestore.batch();

    // 1. Create Sale Document
    final saleRef = _firestore.collection('sales').doc();
    batch.set(saleRef, sale.toFirestore());

    // 2. Update Variant Quantities
    for (final item in sale.items) {
      final variantRef = _firestore.collection('variants').doc(item.variantId);
      batch.update(variantRef, {
        'quantity': FieldValue.increment(-item.quantity),
      });
    }

    await batch.commit();
  }
}
