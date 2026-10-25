import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/errors/exceptions.dart';
import '../models/sale_model.dart';

abstract class PosRemoteDataSource {
  Future<SaleModel> createSale(SaleModel sale);
}

@LazySingleton(as: PosRemoteDataSource)
class PosRemoteDataSourceImpl implements PosRemoteDataSource {
  final FirebaseFirestore _firestore;

  PosRemoteDataSourceImpl(this._firestore);

  @override
  Future<SaleModel> createSale(SaleModel sale) async {
    try {
      final batch = _firestore.batch();

      // 1. Create Sale Document
      final saleRef = _firestore.collection('sales').doc();
      sale = SaleModel(
        id: saleRef.id,
        date: sale.date,
        cashierId: sale.cashierId,
        cashierName: sale.cashierName,
        items: sale.items,
        subtotal: sale.subtotal,
        discount: sale.discount,
        total: sale.total,
        paymentMethod: sale.paymentMethod,
        customerId: sale.customerId,
        syncStatus: sale.syncStatus,
      );
      batch.set(saleRef, sale.toFirestore());

      // 2. Update Variant Quantities + inventory_logs
      for (final item in sale.items) {
        final variantRef = _firestore.collection('variants').doc(item.variantId);
        batch.update(variantRef, {
          'quantity': FieldValue.increment(-item.quantity),
        });

        // 3. Create inventory_log entry
        final logRef = _firestore.collection('inventory_logs').doc();
        batch.set(logRef, {
          'productId': item.variantId,
          'type': 'out',
          'quantity': item.quantity,
          'date': Timestamp.fromDate(DateTime.now()),
          'userId': sale.cashierId,
        });
      }

      await batch.commit();
      return sale;
    } catch (e) {
      throw ServerException(e.toString());
    }
  }
}
