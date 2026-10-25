import 'package:excel/excel.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ExcelService {
  Future<void> exportProducts() async {
    final excel = Excel.createExcel();
    final sheet = excel['Products'];

    sheet.appendRow([
      TextCellValue('Product Name'),
      TextCellValue('Category'),
      TextCellValue('Color'),
      TextCellValue('Size'),
      TextCellValue('Barcode'),
      TextCellValue('Quantity'),
      TextCellValue('Sale Price'),
      TextCellValue('Cost Price'),
    ]);

    final productsSnap = await FirebaseFirestore.instance.collection('products').get();
    for (final productDoc in productsSnap.docs) {
      final productData = productDoc.data();
      final variantsSnap = await FirebaseFirestore.instance
          .collection('product_variants')
          .where('productId', isEqualTo: productDoc.id)
          .get();
      for (final variantDoc in variantsSnap.docs) {
        final v = variantDoc.data();
        sheet.appendRow([
          TextCellValue(productData['name'] ?? ''),
          TextCellValue(productData['category'] ?? ''),
          TextCellValue(v['color'] ?? ''),
          TextCellValue(v['size'] ?? ''),
          TextCellValue(v['barcode'] ?? ''),
          IntCellValue((v['quantity'] as num?)?.toInt() ?? 0),
          DoubleCellValue((v['salePrice'] as num?)?.toDouble() ?? 0.0),
          DoubleCellValue((v['costPrice'] as num?)?.toDouble() ?? 0.0),
        ]);
      }
    }

    // Save file (platform-specific handling would go here)
    // For simplicity, we just print a message
    // In a real app, use path_provider to save to device
  }
}
