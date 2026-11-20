import 'package:equatable/equatable.dart';

class DeliveryCourierEntity extends Equatable {
  final String id;
  final String branchId;
  final String name;
  final String phone;
  final bool isActive;
  final String? vehicleType; // موتوسيكل، سيارة، عجلة، تروسيكل
  final DateTime createdAt;

  const DeliveryCourierEntity({
    required this.id,
    required this.branchId,
    required this.name,
    required this.phone,
    this.isActive = true,
    this.vehicleType,
    required this.createdAt,
  });

  DeliveryCourierEntity copyWith({
    String? id,
    String? branchId,
    String? name,
    String? phone,
    bool? isActive,
    String? vehicleType,
    DateTime? createdAt,
  }) {
    return DeliveryCourierEntity(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      isActive: isActive ?? this.isActive,
      vehicleType: vehicleType ?? this.vehicleType,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        branchId,
        name,
        phone,
        isActive,
        vehicleType,
        createdAt,
      ];
}

