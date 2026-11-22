import 'package:equatable/equatable.dart';

class DeliveryCourierEntity extends Equatable {
  final String id;
  final String branchId;
  final String name;
  final String phone;
  final bool isActive;
  final String? vehicleType; // موتوسيكل، سيارة، عجلة، تروسيكل
  final String providerType; // 'in_house', 'shipping_company'
  final String? trackingUrlTemplate; // e.g. https://track.example.com?no={TRACKING}
  final int? defaultRatePiasters;
  final String? accountNumber;
  final DateTime createdAt;

  const DeliveryCourierEntity({
    required this.id,
    required this.branchId,
    required this.name,
    required this.phone,
    this.isActive = true,
    this.vehicleType,
    this.providerType = 'in_house',
    this.trackingUrlTemplate,
    this.defaultRatePiasters,
    this.accountNumber,
    required this.createdAt,
  });

  bool get isInHouse => providerType == 'in_house';
  bool get isShippingCompany => providerType == 'shipping_company';
  double? get defaultRate =>
      defaultRatePiasters != null ? defaultRatePiasters! / 100.0 : null;

  DeliveryCourierEntity copyWith({
    String? id,
    String? branchId,
    String? name,
    String? phone,
    bool? isActive,
    String? vehicleType,
    String? providerType,
    String? trackingUrlTemplate,
    int? defaultRatePiasters,
    String? accountNumber,
    DateTime? createdAt,
  }) {
    return DeliveryCourierEntity(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      isActive: isActive ?? this.isActive,
      vehicleType: vehicleType ?? this.vehicleType,
      providerType: providerType ?? this.providerType,
      trackingUrlTemplate: trackingUrlTemplate ?? this.trackingUrlTemplate,
      defaultRatePiasters: defaultRatePiasters ?? this.defaultRatePiasters,
      accountNumber: accountNumber ?? this.accountNumber,
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
        providerType,
        trackingUrlTemplate,
        defaultRatePiasters,
        accountNumber,
        createdAt,
      ];
}
