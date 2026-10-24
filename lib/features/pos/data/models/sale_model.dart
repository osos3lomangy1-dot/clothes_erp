import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/sale_entity.dart';
import 'sale_item_model.dart';

class SaleModel extends SaleEntity {
  const SaleModel({
    required super.id,
    required super.items,
    required super.totalAmount,
    required super.paymentMethod,
    required super.cashierId,
    required super.cashierName,
    required super.timestamp,
    super.syncStatus,
  });

  SaleModel copyWith({
    String? id,
    List<SaleItemModel>? items,
    double? totalAmount,
    String? paymentMethod,
    String? cashierId,
    String? cashierName,
    DateTime? timestamp,
    String? syncStatus,
  }) {
    return SaleModel(
      id: id ?? this.id,
      items: items ?? this.items,
      totalAmount: totalAmount ?? this.totalAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      cashierId: cashierId ?? this.cashierId,
      cashierName: cashierName ?? this.cashierName,
      timestamp: timestamp ?? this.timestamp,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  factory SaleModel.fromJson(Map<String, dynamic> json) {
    return SaleModel(
      id: json['id'] ?? '',
      items: (json['items'] as List?)
              ?.map((item) => SaleItemModel.fromJson(item))
              .toList() ??
          [],
      totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: json['paymentMethod'] ?? '',
      cashierId: json['cashierId'] ?? '',
      cashierName: json['cashierName'] ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      syncStatus: json['syncStatus'] ?? 'pendingSync',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'items': items.map((item) => (item as SaleItemModel).toJson()).toList(),
      'totalAmount': totalAmount,
      'paymentMethod': paymentMethod,
      'cashierId': cashierId,
      'cashierName': cashierName,
      'timestamp': timestamp.toIso8601String(),
      'syncStatus': syncStatus,
    };
  }

  factory SaleModel.fromFirestore(
    Map<String, dynamic> data,
    String documentId,
  ) {
    return SaleModel(
      id: documentId,
      items: (data['items'] as List?)
              ?.map((item) => SaleItemModel.fromJson(item))
              .toList() ??
          [],
      totalAmount: (data['totalAmount'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: data['paymentMethod'] ?? '',
      cashierId: data['cashierId'] ?? '',
      cashierName: data['cashierName'] ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      syncStatus: data['syncStatus'] ?? 'synced',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'items': items.map((item) => (item as SaleItemModel).toJson()).toList(),
      'totalAmount': totalAmount,
      'paymentMethod': paymentMethod,
      'cashierId': cashierId,
      'cashierName': cashierName,
      'timestamp': Timestamp.fromDate(timestamp),
      'syncStatus': syncStatus,
    };
  }

  factory SaleModel.fromEntity(SaleEntity entity) {
    return SaleModel(
      id: entity.id,
      items: entity.items
          .map((item) => SaleItemModel.fromEntity(item))
          .toList(),
      totalAmount: entity.totalAmount,
      paymentMethod: entity.paymentMethod,
      cashierId: entity.cashierId,
      cashierName: entity.cashierName,
      timestamp: entity.timestamp,
      syncStatus: entity.syncStatus,
    );
  }
}
