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

  @override
  List<Object?> get props => [id, name, phone, loyaltyPoints, createdAt];
}
