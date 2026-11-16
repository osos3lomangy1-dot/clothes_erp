import '../entities/product_entity.dart';

class ProductSearchFilter {
  static bool matches(ProductEntity product, String rawQuery) {
    final q = rawQuery.trim();
    if (q.isEmpty) return true;
    final qLower = q.toLowerCase();

    if (product.name.toLowerCase().contains(qLower)) return true;
    if (product.categoryName.toLowerCase().contains(qLower)) return true;
    if (product.description.toLowerCase().contains(qLower)) return true;

    for (final v in product.variants) {
      final sku = v.sku.trim();
      final skuLower = sku.toLowerCase();
      // Exact SKU match
      if (skuLower == qLower) return true;
      // SKU prefix match (case-insensitive)
      if (skuLower.startsWith(qLower)) return true;
      // Barcode exact (after trim) — same field `sku`
      if (sku == q) return true;
    }

    return false;
  }
}
