import 'package:equatable/equatable.dart';

class CustomerEntity extends Equatable {
  final String id;
  final String name;
  final String phone;
  final int loyaltyPoints;
  final int discountPercent;
  final String customerType; // 'retail', 'wholesale', 'vip'
  final int creditLimit; // in piasters (0 = unconstrained)
  final DateTime createdAt;

  const CustomerEntity({
    required this.id,
    required this.name,
    required this.phone,
    this.loyaltyPoints = 0,
    this.discountPercent = 0,
    this.customerType = 'retail',
    this.creditLimit = 0,
    required this.createdAt,
  });

  bool get isWholesale => customerType == 'wholesale';
  bool get isVip => customerType == 'vip';
  bool get isBlacklisted => customerType == 'blacklisted';

  CustomerEntity copyWith({
    String? id,
    String? name,
    String? phone,
    int? loyaltyPoints,
    int? discountPercent,
    String? customerType,
    int? creditLimit,
    DateTime? createdAt,
  }) {
    return CustomerEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
      discountPercent: discountPercent ?? this.discountPercent,
      customerType: customerType ?? this.customerType,
      creditLimit: creditLimit ?? this.creditLimit,
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
        creditLimit,
        createdAt,
      ];
}
