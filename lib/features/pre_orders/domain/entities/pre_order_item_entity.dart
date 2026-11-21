class PreOrderItemEntity {
  final String id;
  final String preOrderId;
  final String productName;
  final String? variantDescription;
  final int quantity;
  final int unitPricePiasters;
  final int totalPricePiasters;
  final int costPricePiasters; // تكلفة المندوب / سعر الجملة للقطعة
  final int commissionPiasters; // عمولة التاجر للقطعة
  final String? itemUrl;
  final String? notes;
  final bool transferredToInventory;

  const PreOrderItemEntity({
    required this.id,
    required this.preOrderId,
    required this.productName,
    this.variantDescription,
    this.quantity = 1,
    required this.unitPricePiasters,
    required this.totalPricePiasters,
    this.costPricePiasters = 0,
    this.commissionPiasters = 0,
    this.itemUrl,
    this.notes,
    this.transferredToInventory = false,
  });

  /// إجمالي تكلفة المندوب للصنف بالكامل = تكلفة القطعة * الكمية
  int get totalCostPiasters => costPricePiasters * quantity;

  /// إجمالي صافي ربح التاجر للصنف = (سعر البيع - سعر التكلفة) * الكمية
  int get totalProfitPiasters =>
      (unitPricePiasters - costPricePiasters) * quantity;

  PreOrderItemEntity copyWith({
    String? id,
    String? preOrderId,
    String? productName,
    String? variantDescription,
    int? quantity,
    int? unitPricePiasters,
    int? totalPricePiasters,
    int? costPricePiasters,
    int? commissionPiasters,
    String? itemUrl,
    String? notes,
    bool? transferredToInventory,
  }) {
    return PreOrderItemEntity(
      id: id ?? this.id,
      preOrderId: preOrderId ?? this.preOrderId,
      productName: productName ?? this.productName,
      variantDescription: variantDescription ?? this.variantDescription,
      quantity: quantity ?? this.quantity,
      unitPricePiasters: unitPricePiasters ?? this.unitPricePiasters,
      totalPricePiasters: totalPricePiasters ?? this.totalPricePiasters,
      costPricePiasters: costPricePiasters ?? this.costPricePiasters,
      commissionPiasters: commissionPiasters ?? this.commissionPiasters,
      itemUrl: itemUrl ?? this.itemUrl,
      notes: notes ?? this.notes,
      transferredToInventory:
          transferredToInventory ?? this.transferredToInventory,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pre_order_id': preOrderId,
      'product_name': productName,
      'variant_description': variantDescription,
      'quantity': quantity,
      'unit_price_piasters': unitPricePiasters,
      'total_price_piasters': totalPricePiasters,
      'cost_price_piasters': costPricePiasters,
      'commission_piasters': commissionPiasters,
      'item_url': itemUrl,
      'notes': notes,
      'transferred_to_inventory': transferredToInventory ? 1 : 0,
    };
  }

  factory PreOrderItemEntity.fromMap(Map<String, dynamic> map) {
    return PreOrderItemEntity(
      id: map['id'] as String,
      preOrderId: map['pre_order_id'] as String,
      productName: map['product_name'] as String,
      variantDescription: map['variant_description'] as String?,
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      unitPricePiasters: (map['unit_price_piasters'] as num?)?.toInt() ?? 0,
      totalPricePiasters: (map['total_price_piasters'] as num?)?.toInt() ?? 0,
      costPricePiasters: (map['cost_price_piasters'] as num?)?.toInt() ?? 0,
      commissionPiasters: (map['commission_piasters'] as num?)?.toInt() ?? 0,
      itemUrl: map['item_url'] as String?,
      notes: map['notes'] as String?,
      transferredToInventory:
          (map['transferred_to_inventory'] as num?)?.toInt() == 1,
    );
  }
}
