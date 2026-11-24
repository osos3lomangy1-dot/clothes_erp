import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../entities/product_entity.dart';

enum FoodCostRating {
  excellent,
  acceptable,
  high,
}

class FoodCostAnalysis {
  final double totalRecipeCostPiasters;
  final int packagingCostPiasters;
  final double totalCostPiasters;
  final int salePricePiasters;
  final double foodCostPercentage;
  final double profitMarginPercentage;
  final FoodCostRating rating;
  final String ratingLabel;
  final Color badgeColor;
  final Color badgeTextColor;

  const FoodCostAnalysis({
    required this.totalRecipeCostPiasters,
    required this.packagingCostPiasters,
    required this.totalCostPiasters,
    required this.salePricePiasters,
    required this.foodCostPercentage,
    required this.profitMarginPercentage,
    required this.rating,
    required this.ratingLabel,
    required this.badgeColor,
    required this.badgeTextColor,
  });

  static String formatPercent(double val) {
    if (val.truncateToDouble() == val) {
      return val.toInt().toString();
    }
    return val.toStringAsFixed(1);
  }

  String get summaryText {
    final fcStr = formatPercent(foodCostPercentage);
    final pmStr = formatPercent(profitMarginPercentage);
    switch (rating) {
      case FoodCostRating.excellent:
        return 'تكلفة ممتازة: $fcStr% | هامش ربح: $pmStr%';
      case FoodCostRating.acceptable:
        return 'تكلفة مقبولة: $fcStr% | هامش ربح: $pmStr%';
      case FoodCostRating.high:
        return 'تكلفة مرتفعة: $fcStr% - مراجعة التسعير';
    }
  }
}

class FoodCostCalculator {
  const FoodCostCalculator._();

  static double calculateTotalRecipeCostPiasters({
    required List<RecipeItemData> recipeItems,
    required Map<String, dynamic> rawMaterialUnitCostsPiasters,
  }) {
    double totalRecipeCost = 0.0;
    for (final item in recipeItems) {
      final val = rawMaterialUnitCostsPiasters[item.rawMaterialId];
      final double unitCost = (val is num) ? val.toDouble() : 0.0;
      totalRecipeCost += item.calculateIngredientCost(unitCost);
    }
    return totalRecipeCost;
  }

  static FoodCostAnalysis calculate({
    required List<RecipeItemData> recipeItems,
    required Map<String, double> rawMaterialUnitCostsPiasters,
    required int salePricePiasters,
    int packagingCostPiasters = 0,
  }) {
    final double totalRecipeCost = calculateTotalRecipeCostPiasters(
      recipeItems: recipeItems,
      rawMaterialUnitCostsPiasters: rawMaterialUnitCostsPiasters,
    );

    final totalCost = totalRecipeCost + packagingCostPiasters;
    final double rawPercentage = salePricePiasters > 0
        ? (totalCost / salePricePiasters) * 100.0
        : 0.0;
    final double foodCostPercentage =
        double.parse(rawPercentage.toStringAsFixed(4));
    final double profitMargin =
        double.parse((100.0 - foodCostPercentage).toStringAsFixed(4));

    final FoodCostRating rating;
    final String ratingLabel;
    final Color badgeColor;
    final Color badgeTextColor;

    if (foodCostPercentage <= 32.0) {
      rating = FoodCostRating.excellent;
      ratingLabel = 'ممتازة';
      badgeColor = AppColors.successContainer;
      badgeTextColor = AppColors.success;
    } else if (foodCostPercentage <= 35.0) {
      rating = FoodCostRating.acceptable;
      ratingLabel = 'مقبولة';
      badgeColor = AppColors.surfaceContainer;
      badgeTextColor = AppColors.onSurfaceVariant;
    } else {
      rating = FoodCostRating.high;
      ratingLabel = 'مرتفعة';
      badgeColor = AppColors.warningContainer;
      badgeTextColor = AppColors.warning;
    }

    return FoodCostAnalysis(
      totalRecipeCostPiasters: totalRecipeCost,
      packagingCostPiasters: packagingCostPiasters,
      totalCostPiasters: totalCost,
      salePricePiasters: salePricePiasters,
      foodCostPercentage: foodCostPercentage,
      profitMarginPercentage: profitMargin,
      rating: rating,
      ratingLabel: ratingLabel,
      badgeColor: badgeColor,
      badgeTextColor: badgeTextColor,
    );
  }
}
