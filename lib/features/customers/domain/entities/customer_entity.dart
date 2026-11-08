import 'package:equatable/equatable.dart';

class CustomerEntity extends Equatable {
  final String id;
  final String name;
  final String phone;
  final int loyaltyPoints;
  final int discountPercent;
  final String customerType; // 'retail', 'wholesale', 'vip'
  final DateTime createdAt;

  const CustomerEntity({
    required this.id,
    required this.name,
    required this.phone,
    this.loyaltyPoints = 0,
    this.discountPercent = 0,
    this.customerType = 'retail',
    required this.createdAt,
  });

  bool get isWholesale => customerType == 'wholesale';
  bool get isVip => customerType == 'vip';

  CustomerEntity copyWith({
    String? id,
    String? name,
    String? phone,
    int? loyaltyPoints,
    int? discountPercent,
    String? customerType,
    DateTime? createdAt,
  }) {
    return CustomerEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
      discountPercent: discountPercent ?? this.discountPercent,
      customerType: customerType ?? this.customerType,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        phone,
        loyaltyPoints,
        discountPercent,
        customerType,
        createdAt,
      ];
}
