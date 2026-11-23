import '../../../products/domain/entities/product_entity.dart';
import '../entities/sale_item_entity.dart';

class KitchenOrderTicketService {
  static String generateKitchenOrderTicket({
    required String orderType,
    required String? tableNumber,
    required String invoiceNumber,
    required DateTime date,
    required List<SaleItemEntity> items,
    String? cashierName,
    Map<String, ProductEntity>? productMap,
    Map<String, RestaurantCulinaryData>? culinaryMap,
  }) {
    final buffer = StringBuffer();
    final typeLabel = switch (orderType) {
      'dineIn' => 'صالة (طاولة: ${tableNumber ?? "1"})',
      'delivery' => 'توصيل / دليفري',
      _ => 'تيك أواي / سفري',
    };

    // Aggregate culinary metadata across order
    int? maxPrepTime;
    final Set<String> stations = {};
    final Set<String> orderAllergens = {};

    for (final it in items) {
      final cul = culinaryMap?[it.productId] ??
          culinaryMap?[it.variantId] ??
          (it.productId != null && productMap != null
              ? productMap[it.productId]?.culinaryData
              : null);
      if (cul != null) {
        if (cul.prepTimeMinutes != null && cul.prepTimeMinutes! > 0) {
          if (maxPrepTime == null || cul.prepTimeMinutes! > maxPrepTime) {
            maxPrepTime = cul.prepTimeMinutes;
          }
        }
        if (cul.kitchenStation != null && cul.kitchenStation!.trim().isNotEmpty) {
          stations.add(cul.kitchenStation!.trim());
        }
        orderAllergens.addAll(cul.allergens);
      }
    }

    buffer.writeln('================================');
    buffer.writeln('      بون تحضير المطبخ (KOT)     ');
    buffer.writeln('================================');
    buffer.writeln('نوع الطلب : $typeLabel');
    buffer.writeln('رقم الطلب : $invoiceNumber');
    buffer.writeln('التاريخ   : ${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}');
    if (cashierName != null && cashierName.isNotEmpty) {
      buffer.writeln('الكاشير   : $cashierName');
    }
    if (stations.isNotEmpty) {
      buffer.writeln('محطة التحضير : ${stations.join(' - ')}');
    }
    if (maxPrepTime != null) {
      buffer.writeln('وقت التحضير   : $maxPrepTime دقيقة (تقديري)');
    }
    if (orderAllergens.isNotEmpty) {
      buffer.writeln('تنبيه حساسية  : ${orderAllergens.join('، ')}');
    }
    buffer.writeln('--------------------------------');
    buffer.writeln('الأصناف والكميات المطلوبة:');
    buffer.writeln('--------------------------------');

    for (int i = 0; i < items.length; i++) {
      final it = items[i];
      final qty = it.formattedQuantity;
      buffer.writeln('${i + 1}. [ $qty x ] ${it.productName}');
      final cul = culinaryMap?[it.productId] ??
          culinaryMap?[it.variantId] ??
          (it.productId != null && productMap != null
              ? productMap[it.productId]?.culinaryData
              : null);
      if (cul != null) {
        if (cul.kitchenStation != null && cul.kitchenStation!.trim().isNotEmpty) {
          buffer.writeln('   محطة التحضير: ${cul.kitchenStation!.trim()}');
        }
        if (cul.prepTimeMinutes != null && cul.prepTimeMinutes! > 0) {
          buffer.writeln('   وقت التجهيز: ${cul.prepTimeMinutes} دقيقة');
        }
        if (cul.allergens.isNotEmpty) {
          buffer.writeln('   تحذير حساسية: ${cul.allergens.join('، ')}');
        }
      }
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
