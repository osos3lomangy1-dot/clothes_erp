import '../entities/sale_item_entity.dart';

class KitchenOrderTicketService {
  static String generateKitchenOrderTicket({
    required String orderType,
    required String? tableNumber,
    required String invoiceNumber,
    required DateTime date,
    required List<SaleItemEntity> items,
    String? cashierName,
  }) {
    final buffer = StringBuffer();
    final typeLabel = switch (orderType) {
      'dineIn' => 'صالة (طاولة: ${tableNumber ?? "1"})',
      'delivery' => 'توصيل / دليفري',
      _ => 'تيك أواي / سفري',
    };

    buffer.writeln('================================');
    buffer.writeln('      بون تحضير المطبخ (KOT)     ');
    buffer.writeln('================================');
    buffer.writeln('نوع الطلب : $typeLabel');
    buffer.writeln('رقم الطلب : $invoiceNumber');
    buffer.writeln('التاريخ   : ${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}');
    if (cashierName != null && cashierName.isNotEmpty) {
      buffer.writeln('الكاشير   : $cashierName');
    }
    buffer.writeln('--------------------------------');
    buffer.writeln('الأصناف والكميات المطلوبة:');
    buffer.writeln('--------------------------------');

    for (int i = 0; i < items.length; i++) {
      final it = items[i];
      final qty = it.formattedQuantity;
      buffer.writeln('${i + 1}. [ $qty x ] ${it.productName}');
      if (it.kitchenNotes != null && it.kitchenNotes!.trim().isNotEmpty) {
        buffer.writeln('   استثناءات: ${it.kitchenNotes!.trim()}');
      }
    }

    buffer.writeln('================================');
    buffer.writeln('تنبيه: بون تشغيلي داخلي للتحضير فقط');
    buffer.writeln('================================');
    return buffer.toString();
  }
}

