import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/customer_entity.dart';

class CustomerModel extends CustomerEntity {
  const CustomerModel({
    required super.id,
    required super.name,
    required super.phone,
    super.loyaltyPoints,
    required super.createdAt,
  });

  factory CustomerModel.fromFirestore(Map<String, dynamic> data, String documentId) {
    return CustomerModel(
      id: documentId,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      loyaltyPoints: data['loyaltyPoints'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'phone': phone,
      'loyaltyPoints': loyaltyPoints,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
