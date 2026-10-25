import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/sale_entity.dart';
import 'sale_item_model.dart';

class SaleModel extends SaleEntity {
  const SaleModel({
    required super.id,
    required super.date,
    required super.cashierId,
    super.cashierName,
    required super.items,
    super.subtotal,
    super.discount,
    super.total,
    required super.paymentMethod,
    super.customerId,
    super.syncStatus,
  });

  SaleModel copyWith({
    String? id,
    DateTime? date,
    String? cashierId,
    String? cashierName,
    List<SaleItemModel>? items,
    double? subtotal,
    double? discount,
    double? total,
    String? paymentMethod,
    String? customerId,
    String? syncStatus,
  }) {
    return SaleModel(
      id: id ?? this.id,
      date: date ?? this.date,
      cashierId: cashierId ?? this.cashierId,
      cashierName: cashierName ?? this.cashierName,
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      discount: discount ?? this.discount,
      total: total ?? this.total,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      customerId: customerId ?? this.customerId,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  factory SaleModel.fromJson(Map<String, dynamic> json) {
    return SaleModel(
      id: json['id'] ?? '',
      date: json['date'] != null ? DateTime.parse(json['date']) : DateTime.now(),
      items: (json['items'] as List?)
              ?.map((item) => SaleItemModel.fromJson(item))
              .toList() ??
          [],
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      discount: (json['discount'] as num?)?.toDouble() ?? 0.0,
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: json['paymentMethod'] ?? 'cash',
      cashierId: json['cashierId'] ?? '',
      cashierName: json['cashierName'] ?? '',
      customerId: json['customerId'],
      syncStatus: json['syncStatus'] ?? 'pendingSync',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'items': items.map((item) => (item as SaleItemModel).toJson()).toList(),
      'subtotal': subtotal,
      'discount': discount,
      'total': total,
      'paymentMethod': paymentMethod,
      'cashierId': cashierId,
      'cashierName': cashierName,
      'customerId': customerId,
      'syncStatus': syncStatus,
    };
  }

  factory SaleModel.fromFirestore(
    Map<String, dynamic> data,
    String documentId,
  ) {
    return SaleModel(
      id: documentId,
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      items: (data['items'] as List?)
              ?.map((item) => SaleItemModel.fromJson(item))
              .toList() ??
          [],
      subtotal: (data['subtotal'] as num?)?.toDouble() ?? 0.0,
      discount: (data['discount'] as num?)?.toDouble() ?? 0.0,
      total: (data['total'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: data['paymentMethod'] ?? 'cash',
      cashierId: data['cashierId'] ?? '',
      cashierName: data['cashierName'] ?? '',
      customerId: data['customerId'],
      syncStatus: data['syncStatus'] ?? 'synced',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'date': Timestamp.fromDate(date),
      'items': items.map((item) => (item as SaleItemModel).toJson()).toList(),
      'subtotal': subtotal,
      'discount': discount,
      'total': total,
      'paymentMethod': paymentMethod,
      'cashierId': cashierId,
      'cashierName': cashierName,
      'customerId': customerId,
      'syncStatus': syncStatus,
    };
  }

  factory SaleModel.fromEntity(SaleEntity entity) {
    return SaleModel(
      id: entity.id,
      date: entity.date,
      cashierId: entity.cashierId,
      cashierName: entity.cashierName,
      items: entity.items
          .map((item) => SaleItemModel.fromEntity(item))
          .toList(),
      subtotal: entity.subtotal,
      discount: entity.discount,
      total: entity.total,
      paymentMethod: entity.paymentMethod,
      customerId: entity.customerId,
      syncStatus: entity.syncStatus,
    );
  }
}
