import 'package:equatable/equatable.dart';

class PartnerEntity extends Equatable {
  final String id;
  final String name;
  final String? phone;
  final double percentage; // e.g. 50.0 for 50%
  final int capital; // in piasters
  final String? notes;
  final DateTime createdAt;

  const PartnerEntity({
    required this.id,
    required this.name,
    this.phone,
    required this.percentage,
    this.capital = 0,
    this.notes,
    required this.createdAt,
  });

  int calculateProfitShare(int netProfitPiasters) {
    if (netProfitPiasters <= 0) return 0;
    return ((netProfitPiasters * percentage) / 100.0).round();
  }

  PartnerEntity copyWith({
    String? id,
    String? name,
    String? phone,
    double? percentage,
    int? capital,
    String? notes,
    DateTime? createdAt,
  }) {
    return PartnerEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      percentage: percentage ?? this.percentage,
      capital: capital ?? this.capital,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'percentage': percentage,
        'capital': capital,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PartnerEntity.fromJson(Map<String, dynamic> json) => PartnerEntity(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String?,
        percentage: (json['percentage'] as num).toDouble(),
        capital: (json['capital'] as num?)?.toInt() ?? 0,
        notes: json['notes'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  @override
  List<Object?> get props => [id, name, phone, percentage, capital, notes, createdAt];
}

