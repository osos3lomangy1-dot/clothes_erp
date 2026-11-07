import 'package:equatable/equatable.dart';

class CustomerEntity extends Equatable {
  final String id;
  final String name;
  final String phone;
  final int loyaltyPoints;
  final DateTime createdAt;

  const CustomerEntity({
    required this.id,
    required this.name,
    required this.phone,
    this.loyaltyPoints = 0,
    required this.createdAt,
  });

  CustomerEntity copyWith({
    String? id,
    String? name,
    String? phone,
    int? loyaltyPoints,
    DateTime? createdAt,
  }) {
    return CustomerEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [id, name, phone, loyaltyPoints, createdAt];
}
