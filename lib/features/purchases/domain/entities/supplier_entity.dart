import 'package:equatable/equatable.dart';

class SupplierEntity extends Equatable {
  final String id;
  final String branchId;
  final String name;
  final String? phone;
  final String? companyName;
  final String? address;
  final int balance; // in piasters (positive = shop owes supplier)
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const SupplierEntity({
    required this.id,
    required this.branchId,
    required this.name,
    this.phone,
    this.companyName,
    this.address,
    required this.balance,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  double get balancePounds => balance / 100.0;
  String get formattedBalance => '${balancePounds.toStringAsFixed(2)} ج.م';

  SupplierEntity copyWith({
    String? id,
    String? branchId,
    String? name,
    String? phone,
    String? companyName,
    String? address,
    int? balance,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return SupplierEntity(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      companyName: companyName ?? this.companyName,
      address: address ?? this.address,
      balance: balance ?? this.balance,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        branchId,
        name,
        phone,
        companyName,
        address,
        balance,
        createdAt,
        updatedAt,
        deletedAt,
      ];
}

