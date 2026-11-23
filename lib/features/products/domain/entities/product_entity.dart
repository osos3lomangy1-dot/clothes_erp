import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'activity_type.dart';

export 'activity_type.dart';

class RestaurantCulinaryData extends Equatable {
  final String? ingredients;
  final int? calories;
  final List<String> allergens;
  final int? prepTimeMinutes;
  final String? kitchenStation;
  final String? userDescription;
  final String? imagePath;

  const RestaurantCulinaryData({
    this.ingredients,
    this.calories,
    this.allergens = const [],
    this.prepTimeMinutes,
    this.kitchenStation,
    this.userDescription,
    this.imagePath,
  });

  bool get isEmpty =>
      (ingredients == null || ingredients!.trim().isEmpty) &&
      calories == null &&
      allergens.isEmpty &&
      prepTimeMinutes == null &&
      (kitchenStation == null || kitchenStation!.trim().isEmpty) &&
      (userDescription == null || userDescription!.trim().isEmpty) &&
      (imagePath == null || imagePath!.trim().isEmpty);

  bool get hasCulinaryInfo =>
      (ingredients != null && ingredients!.trim().isNotEmpty) ||
      calories != null ||
      allergens.isNotEmpty ||
      prepTimeMinutes != null ||
      (kitchenStation != null && kitchenStation!.trim().isNotEmpty) ||
      (imagePath != null && imagePath!.trim().isNotEmpty);

  Map<String, dynamic> toJson() => {
        if (ingredients != null && ingredients!.trim().isNotEmpty)
          'ingredients': ingredients!.trim(),
        if (calories != null) 'calories': calories,
        if (allergens.isNotEmpty) 'allergens': allergens,
        if (prepTimeMinutes != null) 'prepTimeMinutes': prepTimeMinutes,
        if (kitchenStation != null && kitchenStation!.trim().isNotEmpty)
          'kitchenStation': kitchenStation!.trim(),
        if (userDescription != null && userDescription!.trim().isNotEmpty)
          'userDescription': userDescription!.trim(),
        if (imagePath != null && imagePath!.trim().isNotEmpty)
          'imagePath': imagePath!.trim(),
      };

  factory RestaurantCulinaryData.fromJson(Map<String, dynamic> json) {
    return RestaurantCulinaryData(
      ingredients: json['ingredients'] as String?,
      calories: json['calories'] is num
          ? (json['calories'] as num).toInt()
          : int.tryParse(json['calories']?.toString() ?? ''),
      allergens: (json['allergens'] as List<dynamic>?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [],
      prepTimeMinutes: json['prepTimeMinutes'] is num
          ? (json['prepTimeMinutes'] as num).toInt()
          : int.tryParse(json['prepTimeMinutes']?.toString() ?? ''),
      kitchenStation: json['kitchenStation'] as String?,
      userDescription: json['userDescription'] as String?,
      imagePath: json['imagePath'] as String?,
    );
  }

  RestaurantCulinaryData copyWith({
    String? ingredients,
    int? calories,
    List<String>? allergens,
    int? prepTimeMinutes,
    String? kitchenStation,
    String? userDescription,
    String? imagePath,
  }) {
    return RestaurantCulinaryData(
      ingredients: ingredients ?? this.ingredients,
      calories: calories ?? this.calories,
      allergens: allergens ?? this.allergens,
      prepTimeMinutes: prepTimeMinutes ?? this.prepTimeMinutes,
      kitchenStation: kitchenStation ?? this.kitchenStation,
      userDescription: userDescription ?? this.userDescription,
      imagePath: imagePath ?? this.imagePath,
    );
  }

  static RestaurantCulinaryData parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const RestaurantCulinaryData();
    }
    final trimmed = raw.trim();
    try {
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          return RestaurantCulinaryData.fromJson(decoded);
        }
      }
      final markerStart = trimmed.indexOf('<!--culinary:');
      if (markerStart != -1) {
        final markerEnd = trimmed.indexOf('-->', markerStart);
        if (markerEnd != -1) {
          final jsonStr = trimmed.substring(markerStart + 13, markerEnd).trim();
          final decoded = jsonDecode(jsonStr);
          if (decoded is Map<String, dynamic>) {
            final userDesc = (trimmed.substring(0, markerStart) +
                    trimmed.substring(markerEnd + 3))
                .trim();
            return RestaurantCulinaryData.fromJson(decoded).copyWith(
              userDescription: userDesc.isNotEmpty ? userDesc : null,
            );
          }
        }
      }
    } catch (_) {}
    return RestaurantCulinaryData(userDescription: raw);
  }

  String toEncodedString() {
    if (!hasCulinaryInfo) {
      return userDescription ?? '';
    }
    return jsonEncode(toJson());
  }

  @override
  List<Object?> get props => [
        ingredients,
        calories,
        allergens,
        prepTimeMinutes,
        kitchenStation,
        userDescription,
        imagePath,
      ];
}

class VariantSummary extends Equatable {
  final String id;
  final String sku; // serves as barcode/SKU/productCode
  final String color;
  final String size;
  final int quantity;

  const VariantSummary({
    required this.id,
    required this.sku,
    required this.color,
    required this.size,
    required this.quantity,
  });

  @override
  List<Object?> get props => [id, sku, color, size, quantity];
}

class ProductEntity extends Equatable {
  final String id;
  final String name;
  final String description;
  final String categoryId;
  final String categoryName;
  final List<String>? images;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int minStock;
  final bool isActive;
  final List<VariantSummary> variants;

  // --- محرك تعدد الأنشطة والخصائص التكيفية (Task 8.6 & Task 18) ---
  final String activityType; // clothing, footwearBags, accessoriesBeauty, homeLiving, general
  final String? warrantyPeriod;
  final String? brandOrModel;
  final bool isInstallmentEligible;
  final String sellMode; // 'piece', 'meter'
  final String unit; // 'piece', 'meter', 'cm', 'kg'
  final String? rollWidth;

  const ProductEntity({
    required this.id,
    required this.name,
    required this.description,
    required this.categoryId,
    required this.categoryName,
    this.images,
    required this.createdAt,
    this.updatedAt,
    this.minStock = 5,
    this.isActive = true,
    this.variants = const [],
    this.activityType = 'clothing',
    this.warrantyPeriod,
    this.brandOrModel,
    this.isInstallmentEligible = true,
    this.sellMode = 'piece',
    this.unit = 'piece',
    this.rollWidth,
  });

  ActivityType get activityTypeEnum => ActivityType.fromString(activityType);

  RestaurantCulinaryData get culinaryData =>
      RestaurantCulinaryData.parse(description);

  String? get ingredients => culinaryData.ingredients;
  int? get calories => culinaryData.calories;
  List<String> get allergens => culinaryData.allergens;
  int? get prepTimeMinutes => culinaryData.prepTimeMinutes;
  String? get kitchenStation => culinaryData.kitchenStation;
  String? get foodImagePath => culinaryData.imagePath;
  String get cleanDescription {
    final parsed = culinaryData;
    if (parsed.hasCulinaryInfo) {
      return parsed.userDescription ?? '';
    }
    return description;
  }

  ProductEntity copyWith({
    String? id,
    String? name,
    String? description,
    String? categoryId,
    String? categoryName,
    List<String>? images,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? minStock,
    bool? isActive,
    List<VariantSummary>? variants,
    String? activityType,
    String? warrantyPeriod,
    String? brandOrModel,
    bool? isInstallmentEligible,
    String? sellMode,
    String? unit,
    String? rollWidth,
  }) {
    return ProductEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      images: images ?? this.images,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      minStock: minStock ?? this.minStock,
      isActive: isActive ?? this.isActive,
      variants: variants ?? this.variants,
      activityType: activityType ?? this.activityType,
      warrantyPeriod: warrantyPeriod ?? this.warrantyPeriod,
      brandOrModel: brandOrModel ?? this.brandOrModel,
      isInstallmentEligible:
          isInstallmentEligible ?? this.isInstallmentEligible,
      sellMode: sellMode ?? this.sellMode,
      unit: unit ?? this.unit,
      rollWidth: rollWidth ?? this.rollWidth,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        categoryId,
        categoryName,
        images,
        createdAt,
        updatedAt,
        minStock,
        isActive,
        variants,
        activityType,
        warrantyPeriod,
        brandOrModel,
        isInstallmentEligible,
        sellMode,
        unit,
        rollWidth,
      ];
}
