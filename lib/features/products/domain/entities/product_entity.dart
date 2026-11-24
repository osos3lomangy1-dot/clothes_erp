import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'activity_type.dart';

export 'activity_type.dart';

class RecipeItemData extends Equatable {
  final String rawMaterialId;
  final String rawMaterialName;
  final double quantityNeeded;
  final double yieldLossPercentage; // نسبة الفاقد الطبيعي بالطهي %
  final String unit; // كجم، لتر، حبة، علبة، جرام، مل

  const RecipeItemData({
    required this.rawMaterialId,
    required this.rawMaterialName,
    required this.quantityNeeded,
    this.yieldLossPercentage = 0.0,
    required this.unit,
  });

  /// Calculates consumed quantity including yield/cooking loss shrinkage.
  double effectiveQuantityNeeded([int mealCount = 1]) {
    return quantityNeeded * (1.0 + (yieldLossPercentage / 100.0)) * mealCount;
  }

  /// Calculates cost of this ingredient for a single meal given cost per base unit.
  double calculateIngredientCost(double costPerBaseUnit) {
    return effectiveQuantityNeeded(1) * costPerBaseUnit;
  }

  Map<String, dynamic> toJson() => {
        'rawMaterialId': rawMaterialId,
        'rawMaterialName': rawMaterialName,
        'quantityNeeded': quantityNeeded,
        'yieldLossPercentage': yieldLossPercentage,
        'unit': unit,
      };

  factory RecipeItemData.fromJson(Map<String, dynamic> json) => RecipeItemData(
        rawMaterialId: json['rawMaterialId'] as String? ?? '',
        rawMaterialName: json['rawMaterialName'] as String? ?? '',
        quantityNeeded: (json['quantityNeeded'] as num?)?.toDouble() ?? 0.0,
        yieldLossPercentage:
            (json['yieldLossPercentage'] as num?)?.toDouble() ?? 0.0,
        unit: json['unit'] as String? ?? 'حبة',
      );

  @override
  List<Object?> get props => [
        rawMaterialId,
        rawMaterialName,
        quantityNeeded,
        yieldLossPercentage,
        unit,
      ];
}

class PaidModifierData extends Equatable {
  final String name;
  final int pricePiasters;
  final String? rawMaterialId;
  final double? quantityNeeded;

  const PaidModifierData({
    required this.name,
    required this.pricePiasters,
    this.rawMaterialId,
    this.quantityNeeded,
  });

  double get pricePounds => pricePiasters / 100.0;

  Map<String, dynamic> toJson() => {
        'name': name,
        'pricePiasters': pricePiasters,
        if (rawMaterialId != null) 'rawMaterialId': rawMaterialId,
        if (quantityNeeded != null) 'quantityNeeded': quantityNeeded,
      };

  factory PaidModifierData.fromJson(Map<String, dynamic> json) =>
      PaidModifierData(
        name: json['name'] as String? ?? '',
        pricePiasters: (json['pricePiasters'] as num?)?.toInt() ?? 0,
        rawMaterialId: json['rawMaterialId'] as String?,
        quantityNeeded: (json['quantityNeeded'] as num?)?.toDouble(),
      );

  PaidModifierData copyWith({
    String? name,
    int? pricePiasters,
    String? rawMaterialId,
    double? quantityNeeded,
  }) {
    return PaidModifierData(
      name: name ?? this.name,
      pricePiasters: pricePiasters ?? this.pricePiasters,
      rawMaterialId: rawMaterialId ?? this.rawMaterialId,
      quantityNeeded: quantityNeeded ?? this.quantityNeeded,
    );
  }

  @override
  List<Object?> get props => [
        name,
        pricePiasters,
        rawMaterialId,
        quantityNeeded,
      ];
}

class RestaurantCulinaryData extends Equatable {
  final String? ingredients;
  final int? calories;
  final List<String> allergens;
  final int? prepTimeMinutes;
  final String? kitchenStation;
  final String? userDescription;
  final String? imagePath;
  final bool isRawMaterial;
  final String? purchaseUnit;
  final String? baseUnit;
  final double? conversionFactor;
  final int? packagingCostPiasters;
  final List<RecipeItemData> recipeItems;
  final String mealStockMode; // 'onDemand' or 'dailyBatch'
  final int? dailyBatchCount;
  final List<PaidModifierData> paidModifiers;

  const RestaurantCulinaryData({
    this.ingredients,
    this.calories,
    this.allergens = const [],
    this.prepTimeMinutes,
    this.kitchenStation,
    this.userDescription,
    this.imagePath,
    this.isRawMaterial = false,
    this.purchaseUnit,
    this.baseUnit,
    this.conversionFactor,
    this.packagingCostPiasters,
    this.recipeItems = const [],
    this.mealStockMode = 'onDemand',
    this.dailyBatchCount,
    this.paidModifiers = const [],
  });

  /// Cost per base unit in piasters: purchase price / conversion factor.
  double costPerBaseUnit(int purchasePricePiasters) {
    final factor = conversionFactor ?? 1.0;
    if (factor <= 0) return purchasePricePiasters.toDouble();
    return purchasePricePiasters / factor;
  }

  /// Formats raw material stock in dual smart display (e.g. "14,250 جم (يعادل 14.25 كجم)").
  String formatDualQuantity(num quantityInBaseUnits) {
    final qty = quantityInBaseUnits.toDouble();
    final bUnit = (baseUnit != null && baseUnit!.trim().isNotEmpty)
        ? baseUnit!.trim()
        : 'قطعة';
    final pUnit = purchaseUnit?.trim();
    final factor = (conversionFactor != null && conversionFactor! > 0)
        ? conversionFactor!
        : 1.0;

    if (pUnit != null && pUnit.isNotEmpty && factor > 1.0) {
      if (bUnit.contains('جرام') || bUnit.contains('جم')) {
        final kg = qty / 1000.0;
        final kgStr = kg.toStringAsFixed(kg.truncateToDouble() == kg ? 0 : 2);
        return '${_formatNumber(qty)} $bUnit (يعادل $kgStr كجم)';
      }
      if (bUnit.contains('مل')) {
        final liters = qty / 1000.0;
        final literStr = liters
            .toStringAsFixed(liters.truncateToDouble() == liters ? 0 : 2);
        return '${_formatNumber(qty)} $bUnit (يعادل $literStr لتر)';
      }
      final packages = qty / factor;
      final pkgStr = packages
          .toStringAsFixed(packages.truncateToDouble() == packages ? 0 : 1);
      return '${_formatNumber(qty)} $bUnit (يعادل $pkgStr $pUnit)';
    }

    if (bUnit.contains('جرام') || bUnit.contains('جم')) {
      if (qty >= 1000) {
        final kg = qty / 1000.0;
        final kgStr = kg.toStringAsFixed(kg.truncateToDouble() == kg ? 0 : 2);
        return '${_formatNumber(qty)} $bUnit (يعادل $kgStr كجم)';
      }
    } else if (bUnit.contains('مل')) {
      if (qty >= 1000) {
        final liters = qty / 1000.0;
        final literStr = liters
            .toStringAsFixed(liters.truncateToDouble() == liters ? 0 : 2);
        return '${_formatNumber(qty)} $bUnit (يعادل $literStr لتر)';
      }
    }

    return '${_formatNumber(qty)} $bUnit';
  }

  static String _formatNumber(num n) {
    final isInt = n.truncateToDouble() == n;
    final intVal = isInt ? n.toInt() : null;
    if (intVal != null) {
      final s = intVal.toString();
      final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
      return s.replaceAllMapped(reg, (m) => '${m[1]},');
    }
    final fixed = n.toStringAsFixed(2);
    final parts = fixed.split('.');
    final whole = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return '$whole.${parts[1]}';
  }

  bool get isEmpty =>
      (ingredients == null || ingredients!.trim().isEmpty) &&
      calories == null &&
      allergens.isEmpty &&
      prepTimeMinutes == null &&
      (kitchenStation == null || kitchenStation!.trim().isEmpty) &&
      (userDescription == null || userDescription!.trim().isEmpty) &&
      (imagePath == null || imagePath!.trim().isEmpty) &&
      !isRawMaterial &&
      (purchaseUnit == null || purchaseUnit!.trim().isEmpty) &&
      (baseUnit == null || baseUnit!.trim().isEmpty) &&
      conversionFactor == null &&
      packagingCostPiasters == null &&
      recipeItems.isEmpty &&
      mealStockMode == 'onDemand' &&
      dailyBatchCount == null &&
      paidModifiers.isEmpty;

  bool get hasCulinaryInfo =>
      (ingredients != null && ingredients!.trim().isNotEmpty) ||
      calories != null ||
      allergens.isNotEmpty ||
      prepTimeMinutes != null ||
      (kitchenStation != null && kitchenStation!.trim().isNotEmpty) ||
      (imagePath != null && imagePath!.trim().isNotEmpty) ||
      isRawMaterial ||
      (purchaseUnit != null && purchaseUnit!.trim().isNotEmpty) ||
      (baseUnit != null && baseUnit!.trim().isNotEmpty) ||
      conversionFactor != null ||
      packagingCostPiasters != null ||
      recipeItems.isNotEmpty ||
      mealStockMode != 'onDemand' ||
      dailyBatchCount != null ||
      paidModifiers.isNotEmpty;

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
        if (isRawMaterial) 'isRawMaterial': true,
        if (purchaseUnit != null && purchaseUnit!.trim().isNotEmpty)
          'purchaseUnit': purchaseUnit!.trim(),
        if (baseUnit != null && baseUnit!.trim().isNotEmpty)
          'baseUnit': baseUnit!.trim(),
        if (conversionFactor != null) 'conversionFactor': conversionFactor,
        if (packagingCostPiasters != null)
          'packagingCostPiasters': packagingCostPiasters,
        if (recipeItems.isNotEmpty)
          'recipeItems': recipeItems.map((e) => e.toJson()).toList(),
        if (mealStockMode != 'onDemand') 'mealStockMode': mealStockMode,
        if (dailyBatchCount != null) 'dailyBatchCount': dailyBatchCount,
        if (paidModifiers.isNotEmpty)
          'paidModifiers': paidModifiers.map((e) => e.toJson()).toList(),
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
      isRawMaterial: json['isRawMaterial'] as bool? ?? false,
      purchaseUnit: json['purchaseUnit'] as String?,
      baseUnit: json['baseUnit'] as String?,
      conversionFactor: (json['conversionFactor'] as num?)?.toDouble(),
      packagingCostPiasters: json['packagingCostPiasters'] is num
          ? (json['packagingCostPiasters'] as num).toInt()
          : int.tryParse(json['packagingCostPiasters']?.toString() ?? ''),
      recipeItems: (json['recipeItems'] as List<dynamic>?)
              ?.map((e) => RecipeItemData.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      mealStockMode: json['mealStockMode'] as String? ?? 'onDemand',
      dailyBatchCount: json['dailyBatchCount'] is num
          ? (json['dailyBatchCount'] as num).toInt()
          : int.tryParse(json['dailyBatchCount']?.toString() ?? ''),
      paidModifiers: (json['paidModifiers'] as List<dynamic>?)
              ?.map((e) => PaidModifierData.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
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
    bool? isRawMaterial,
    String? purchaseUnit,
    String? baseUnit,
    double? conversionFactor,
    int? packagingCostPiasters,
    List<RecipeItemData>? recipeItems,
    String? mealStockMode,
    int? dailyBatchCount,
    List<PaidModifierData>? paidModifiers,
  }) {
    return RestaurantCulinaryData(
      ingredients: ingredients ?? this.ingredients,
      calories: calories ?? this.calories,
      allergens: allergens ?? this.allergens,
      prepTimeMinutes: prepTimeMinutes ?? this.prepTimeMinutes,
      kitchenStation: kitchenStation ?? this.kitchenStation,
      userDescription: userDescription ?? this.userDescription,
      imagePath: imagePath ?? this.imagePath,
      isRawMaterial: isRawMaterial ?? this.isRawMaterial,
      purchaseUnit: purchaseUnit ?? this.purchaseUnit,
      baseUnit: baseUnit ?? this.baseUnit,
      conversionFactor: conversionFactor ?? this.conversionFactor,
      packagingCostPiasters:
          packagingCostPiasters ?? this.packagingCostPiasters,
      recipeItems: recipeItems ?? this.recipeItems,
      mealStockMode: mealStockMode ?? this.mealStockMode,
      dailyBatchCount: dailyBatchCount ?? this.dailyBatchCount,
      paidModifiers: paidModifiers ?? this.paidModifiers,
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
        isRawMaterial,
        purchaseUnit,
        baseUnit,
        conversionFactor,
        packagingCostPiasters,
        recipeItems,
        mealStockMode,
        dailyBatchCount,
        paidModifiers,
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
  bool get isRestaurantRawMaterial => culinaryData.isRawMaterial;
  String? get restaurantPurchaseUnit => culinaryData.purchaseUnit;
  String? get restaurantBaseUnit => culinaryData.baseUnit;
  double get restaurantConversionFactor =>
      culinaryData.conversionFactor ?? 1.0;
  int? get restaurantPackagingCostPiasters =>
      culinaryData.packagingCostPiasters;
  double costPerBaseUnit(int purchasePricePiasters) =>
      culinaryData.costPerBaseUnit(purchasePricePiasters);
  String formatDualQuantity(num quantityInBaseUnits) =>
      culinaryData.formatDualQuantity(quantityInBaseUnits);
  List<RecipeItemData> get restaurantRecipeItems => culinaryData.recipeItems;
  String get mealStockMode => culinaryData.mealStockMode;
  int? get dailyBatchCount => culinaryData.dailyBatchCount;
  bool get isDailyBatch => mealStockMode == 'dailyBatch';
  List<PaidModifierData> get paidModifiers => culinaryData.paidModifiers;
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
