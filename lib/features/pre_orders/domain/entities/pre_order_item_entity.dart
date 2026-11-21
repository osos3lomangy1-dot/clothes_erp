class PreOrderItemEntity {
  final String id;
  final String preOrderId;
  final String productName;
  final String? variantDescription;
  final int quantity;
  final int unitPricePiasters;
  final int totalPricePiasters;
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
    this.itemUrl,
    this.notes,
    this.transferredToInventory = false,
  });

  PreOrderItemEntity copyWith({
    String? id,
    String? preOrderId,
    String? productName,
    String? variantDescription,
    int? quantity,
    int? unitPricePiasters,
    int? totalPricePiasters,
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
      itemUrl: itemUrl ?? this.itemUrl,
      notes: notes ?? this.notes,
      transferredToInventory: transferredToInventory ?? this.transferredToInventory,
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
      itemUrl: map['item_url'] as String?,
      notes: map['notes'] as String?,
      transferredToInventory: (map['transferred_to_inventory'] as num?)?.toInt() == 1,
    );
  }
}
