import 'package:clothes_erp/features/categories/domain/entities/category_entity.dart';
import 'package:clothes_erp/features/categories/domain/repositories/category_repository.dart';
import 'package:clothes_erp/features/products/data/datasources/product_local_data_source.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/products/domain/repositories/product_repository.dart';

enum CulinaryStarterPackType {
  burgerDiner,
  specialtyCafe,
  pizzeriaAndPasta,
}

class CulinaryPackSeedResult {
  final int categoriesCreated;
  final int rawMaterialsCreated;
  final int mealsCreated;
  final int skippedCount;
  final List<String> messageLogs;

  const CulinaryPackSeedResult({
    required this.categoriesCreated,
    required this.rawMaterialsCreated,
    required this.mealsCreated,
    required this.skippedCount,
    required this.messageLogs,
  });

  int get totalItemsAdded => rawMaterialsCreated + mealsCreated;
}

class _RawMaterialSeedDef {
  final String name;
  final String category;
  final String purchaseUnit;
  final String baseUnit;
  final double conversionFactor;
  final double costPerBaseUnit;
  final int initialStock;

  const _RawMaterialSeedDef({
    required this.name,
    required this.category,
    required this.purchaseUnit,
    required this.baseUnit,
    required this.conversionFactor,
    required this.costPerBaseUnit,
    required this.initialStock,
  });
}

class _MealRecipeItemDef {
  final String rawMaterialName;
  final double quantity;
  final String unit;
  final double yieldLoss;

  const _MealRecipeItemDef({
    required this.rawMaterialName,
    required this.quantity,
    required this.unit,
    this.yieldLoss = 0.0,
  });
}

class _MealSeedDef {
  final String name;
  final String category;
  final double sellingPrice;
  final List<_MealRecipeItemDef> recipeItems;

  const _MealSeedDef({
    required this.name,
    required this.category,
    required this.sellingPrice,
    required this.recipeItems,
  });
}

class CulinaryStarterPackEngine {
  static String getPackTitle(CulinaryStarterPackType packType) {
    switch (packType) {
      case CulinaryStarterPackType.burgerDiner:
        return 'باقة برجر داينر';
      case CulinaryStarterPackType.specialtyCafe:
        return 'باقة مقهى ومشروبات مختصة';
      case CulinaryStarterPackType.pizzeriaAndPasta:
        return 'باقة بيتزا نابوليتانو وباستا';
    }
  }

  static String getPackDescription(CulinaryStarterPackType packType) {
    switch (packType) {
      case CulinaryStarterPackType.burgerDiner:
        return 'تشمل 8 خامات أساسية (لحم، بريوش، شيدر، صوصات، بطاطس، تغليف) مع 3 وجبات برجر وفرايز بمقادير دقيقة.';
      case CulinaryStarterPackType.specialtyCafe:
        return 'تشمل 5 خامات مختصة (بن كولومبي، حليب، سيرب فانيليا، ماتشا، أكواب دبل) مع 4 مشروبات ساخنة ومثلجة.';
      case CulinaryStarterPackType.pizzeriaAndPasta:
        return 'تشمل 7 خامات إيطالية (دقيق Tipo 00، موزاريلا، سان مارزانو، زيت زيتون، مكرونة، كريمة، علب) مع أطباق نابوليتانو وألفريدو.';
    }
  }

  static List<_RawMaterialSeedDef> _getRawMaterials(CulinaryStarterPackType packType) {
    switch (packType) {
      case CulinaryStarterPackType.burgerDiner:
        return const [
          _RawMaterialSeedDef(
            name: 'لحم بقري مفروم',
            category: 'خامات ومستلزمات المطبخ',
            purchaseUnit: 'كرتونة 10 كجم',
            baseUnit: 'جرام',
            conversionFactor: 10000,
            costPerBaseUnit: 0.35,
            initialStock: 50000,
          ),
          _RawMaterialSeedDef(
            name: 'خبز كيزر بريوش',
            category: 'خامات ومستلزمات المطبخ',
            purchaseUnit: 'كيس 12 قطعة',
            baseUnit: 'قطعة',
            conversionFactor: 12,
            costPerBaseUnit: 6.0,
            initialStock: 240,
          ),
          _RawMaterialSeedDef(
            name: 'جبن شيدر أحمر شرائح',
            category: 'خامات ومستلزمات المطبخ',
            purchaseUnit: 'باكت 84 شريحة',
            baseUnit: 'شريحة',
            conversionFactor: 84,
            costPerBaseUnit: 3.5,
            initialStock: 500,
          ),
          _RawMaterialSeedDef(
            name: 'صوص بيج تيستي',
            category: 'خامات ومستلزمات المطبخ',
            purchaseUnit: 'جركن 4 كجم',
            baseUnit: 'جرام',
            conversionFactor: 4000,
            costPerBaseUnit: 0.12,
            initialStock: 12000,
          ),
          _RawMaterialSeedDef(
            name: 'بطاطس نصف مقلية',
            category: 'خامات ومستلزمات المطبخ',
            purchaseUnit: 'كيس 2.5 كجم',
            baseUnit: 'جرام',
            conversionFactor: 2500,
            costPerBaseUnit: 0.05,
            initialStock: 25000,
          ),
          _RawMaterialSeedDef(
            name: 'زيت تحمير وقلي',
            category: 'خامات ومستلزمات المطبخ',
            purchaseUnit: 'جركن 18 لتر',
            baseUnit: 'ملليلتر',
            conversionFactor: 18000,
            costPerBaseUnit: 0.09,
            initialStock: 36000,
          ),
          _RawMaterialSeedDef(
            name: 'علبة كرتون برجر',
            category: 'خامات ومستلزمات المطبخ',
            purchaseUnit: 'باكت 100 قطعة',
            baseUnit: 'قطعة',
            conversionFactor: 100,
            costPerBaseUnit: 4.0,
            initialStock: 500,
          ),
          _RawMaterialSeedDef(
            name: 'باكيت ورق بطاطس',
            category: 'خامات ومستلزمات المطبخ',
            purchaseUnit: 'باكت 250 قطعة',
            baseUnit: 'قطعة',
            conversionFactor: 250,
            costPerBaseUnit: 1.5,
            initialStock: 1000,
          ),
        ];

      case CulinaryStarterPackType.specialtyCafe:
        return const [
          _RawMaterialSeedDef(
            name: 'بن حبوب كولومبي مختص',
            category: 'خامات ومستلزمات البار',
            purchaseUnit: 'كيس 1 كجم',
            baseUnit: 'جرام',
            conversionFactor: 1000,
            costPerBaseUnit: 0.90,
            initialStock: 10000,
          ),
          _RawMaterialSeedDef(
            name: 'حليب بقر كامل الدسم',
            category: 'خامات ومستلزمات البار',
            purchaseUnit: 'كرتونة 12 لتر',
            baseUnit: 'ملليلتر',
            conversionFactor: 12000,
            costPerBaseUnit: 0.04,
            initialStock: 24000,
          ),
          _RawMaterialSeedDef(
            name: 'سيرب فانيليا مركز',
            category: 'خامات ومستلزمات البار',
            purchaseUnit: 'زجاجة 1 لتر',
            baseUnit: 'ملليلتر',
            conversionFactor: 1000,
            costPerBaseUnit: 0.35,
            initialStock: 5000,
          ),
          _RawMaterialSeedDef(
            name: 'مسحوق ماتشا ياباني',
            category: 'خامات ومستلزمات البار',
            purchaseUnit: 'عبوة 500 جرام',
            baseUnit: 'جرام',
            conversionFactor: 500,
            costPerBaseUnit: 2.50,
            initialStock: 1500,
          ),
          _RawMaterialSeedDef(
            name: 'كوب ورقي دبل 12 أونص مع الغطاء والماسك',
            category: 'خامات ومستلزمات البار',
            purchaseUnit: 'كرتونة 500 قطعة',
            baseUnit: 'قطعة',
            conversionFactor: 500,
            costPerBaseUnit: 3.50,
            initialStock: 1000,
          ),
        ];

      case CulinaryStarterPackType.pizzeriaAndPasta:
        return const [
          _RawMaterialSeedDef(
            name: 'دقيق إيطالي Tipo 00',
            category: 'خامات ومستلزمات المطبخ',
            purchaseUnit: 'شيكارة 25 كجم',
            baseUnit: 'جرام',
            conversionFactor: 2500,
            costPerBaseUnit: 0.05,
            initialStock: 50000,
          ),
          _RawMaterialSeedDef(
            name: 'جبن موزاريلا طبيعي',
            category: 'خامات ومستلزمات المطبخ',
            purchaseUnit: 'قالب 2.5 كجم',
            baseUnit: 'جرام',
            conversionFactor: 2500,
            costPerBaseUnit: 0.28,
            initialStock: 20000,
          ),
          _RawMaterialSeedDef(
            name: 'صلصة طماطم سان مارزانو',
            category: 'خامات ومستلزمات المطبخ',
            purchaseUnit: 'علبة 2.5 كجم',
            baseUnit: 'جرام',
            conversionFactor: 2500,
            costPerBaseUnit: 0.08,
            initialStock: 15000,
          ),
          _RawMaterialSeedDef(
            name: 'زيت زيتون بكر ممتاز',
            category: 'خامات ومستلزمات المطبخ',
            purchaseUnit: 'جركن 5 لتر',
            baseUnit: 'ملليلتر',
            conversionFactor: 5000,
            costPerBaseUnit: 0.45,
            initialStock: 10000,
          ),
          _RawMaterialSeedDef(
            name: 'مكرونة بيني',
            category: 'خامات ومستلزمات المطبخ',
            purchaseUnit: 'شيكارة 10 كجم',
            baseUnit: 'جرام',
            conversionFactor: 10000,
            costPerBaseUnit: 0.06,
            initialStock: 30000,
          ),
          _RawMaterialSeedDef(
            name: 'كريمة طهي حيواني',
            category: 'خامات ومستلزمات المطبخ',
            purchaseUnit: 'كرتونة 1 لتر',
            baseUnit: 'ملليلتر',
            conversionFactor: 1000,
            costPerBaseUnit: 0.22,
            initialStock: 12000,
          ),
          _RawMaterialSeedDef(
            name: 'كرتونة بيتزا 30 سم',
            category: 'خامات ومستلزمات المطبخ',
            purchaseUnit: 'باكت 100 قطعة',
            baseUnit: 'قطعة',
            conversionFactor: 100,
            costPerBaseUnit: 6.50,
            initialStock: 500,
          ),
        ];
    }
  }

  static List<_MealSeedDef> _getMeals(CulinaryStarterPackType packType) {
    switch (packType) {
      case CulinaryStarterPackType.burgerDiner:
        return const [
          _MealSeedDef(
            name: 'سنجل كلاسيك برجر',
            category: 'وجبات البرجر',
            sellingPrice: 110.0,
            recipeItems: [
              _MealRecipeItemDef(
                rawMaterialName: 'لحم بقري مفروم',
                quantity: 150,
                unit: 'جرام',
                yieldLoss: 15.0,
              ),
              _MealRecipeItemDef(
                rawMaterialName: 'خبز كيزر بريوش',
                quantity: 1,
                unit: 'قطعة',
                yieldLoss: 0.0,
              ),
              _MealRecipeItemDef(
                rawMaterialName: 'جبن شيدر أحمر شرائح',
                quantity: 1,
                unit: 'شريحة',
                yieldLoss: 0.0,
              ),
              _MealRecipeItemDef(
                rawMaterialName: 'صوص بيج تيستي',
                quantity: 30,
                unit: 'جرام',
                yieldLoss: 0.0,
              ),
              _MealRecipeItemDef(
                rawMaterialName: 'علبة كرتون برجر',
                quantity: 1,
                unit: 'قطعة',
                yieldLoss: 0.0,
              ),
            ],
          ),
          _MealSeedDef(
            name: 'دبل تشيز برجر',
            category: 'وجبات البرجر',
            sellingPrice: 165.0,
            recipeItems: [
              _MealRecipeItemDef(
                rawMaterialName: 'لحم بقري مفروم',
                quantity: 300,
                unit: 'جرام',
                yieldLoss: 15.0,
              ),
              _MealRecipeItemDef(
                rawMaterialName: 'خبز كيزر بريوش',
                quantity: 1,
                unit: 'قطعة',
                yieldLoss: 0.0,
              ),
              _MealRecipeItemDef(
                rawMaterialName: 'جبن شيدر أحمر شرائح',
                quantity: 2,
                unit: 'شريحة',
                yieldLoss: 0.0,
              ),
              _MealRecipeItemDef(
                rawMaterialName: 'صوص بيج تيستي',
                quantity: 45,
                unit: 'جرام',
                yieldLoss: 0.0,
              ),
              _MealRecipeItemDef(
                rawMaterialName: 'علبة كرتون برجر',
                quantity: 1,
                unit: 'قطعة',
                yieldLoss: 0.0,
              ),
            ],
          ),
          _MealSeedDef(
            name: 'فارم فرايز بطاطس',
            category: 'أطباق جانبية ومقبلات',
            sellingPrice: 40.0,
            recipeItems: [
              _MealRecipeItemDef(
                rawMaterialName: 'بطاطس نصف مقلية',
                quantity: 180,
                unit: 'جرام',
                yieldLoss: 10.0,
              ),
              _MealRecipeItemDef(
                rawMaterialName: 'زيت تحمير وقلي',
                quantity: 30,
                unit: 'ملليلتر',
                yieldLoss: 20.0,
              ),
              _MealRecipeItemDef(
                rawMaterialName: 'باكيت ورق بطاطس',
                quantity: 1,
                unit: 'قطعة',
                yieldLoss: 0.0,
              ),
            ],
          ),
        ];

      case CulinaryStarterPackType.specialtyCafe:
        return const [
          _MealSeedDef(
            name: 'دبل إسبريسو',
            category: 'مشروبات ساخنة',
            sellingPrice: 55.0,
            recipeItems: [
              _MealRecipeItemDef(
                rawMaterialName: 'بن حبوب كولومبي مختص',
                quantity: 18,
                unit: 'جرام',
                yieldLoss: 5.0,
              ),
              _MealRecipeItemDef(
                rawMaterialName: 'كوب ورقي دبل 12 أونص مع الغطاء والماسك',
                quantity: 1,
                unit: 'قطعة',
                yieldLoss: 0.0,
              ),
            ],
          ),
          _MealSeedDef(
            name: 'فلات وايت',
            category: 'مشروبات ساخنة',
            sellingPrice: 85.0,
            recipeItems: [
              _MealRecipeItemDef(
                rawMaterialName: 'بن حبوب كولومبي مختص',
                quantity: 18,
                unit: 'جرام',
                yieldLoss: 5.0,
              ),
              _MealRecipeItemDef(
                rawMaterialName: 'حليب بقر كامل الدسم',
                quantity: 160,
                unit: 'ملليلتر',
                yieldLoss: 10.0,
              ),
              _MealRecipeItemDef(
                rawMaterialName: 'كوب ورقي دبل 12 أونص مع الغطاء والماسك',
                quantity: 1,
                unit: 'قطعة',
                yieldLoss: 0.0,
              ),
            ],
          ),
          _MealSeedDef(
            name: 'آيس سبانش لاتيه',
            category: 'مشروبات باردة ومثلجة',
            sellingPrice: 95.0,
            recipeItems: [
              _MealRecipeItemDef(
                rawMaterialName: 'بن حبوب كولومبي مختص',
                quantity: 18,
                unit: 'جرام',
                yieldLoss: 5.0,
              ),
              _MealRecipeItemDef(
                rawMaterialName: 'حليب بقر كامل الدسم',
                quantity: 180,
                unit: 'ملليلتر',
                yieldLoss: 5.0,
              ),
              _MealRecipeItemDef(
                rawMaterialName: 'سيرب فانيليا مركز',
                quantity: 25,
                unit: 'ملليلتر',
                yieldLoss: 0.0,
              ),
              _MealRecipeItemDef(
                rawMaterialName: 'كوب ورقي دبل 12 أونص مع الغطاء والماسك',
                quantity: 1,
                unit: 'قطعة',
                yieldLoss: 0.0,
              ),
            ],
          ),
          _MealSeedDef(
            name: 'آيس ماتشا لاتيه',
            category: 'مشروبات باردة ومثلجة',
            sellingPrice: 110.0,
            recipeItems: [
              _MealRecipeItemDef(
                rawMaterialName: 'مسحوق ماتشا ياباني',
                quantity: 6,
                unit: 'جرام',
                yieldLoss: 0.0,
              ),
              _MealRecipeItemDef(
                rawMaterialName: 'حليب بقر كامل الدسم',
                quantity: 200,
                unit: 'ملليلتر',
                yieldLoss: 5.0,
              ),
              _MealRecipeItemDef(
                rawMaterialName: 'سيرب فانيليا مركز',
                quantity: 20,
                unit: 'ملليلتر',
                yieldLoss: 0.0,
              ),
              _MealRecipeItemDef(
                rawMaterialName: 'كوب ورقي دبل 12 أونص مع الغطاء والماسك',
                quantity: 1,
                unit: 'قطعة',
                yieldLoss: 0.0,
              ),
            ],
          ),
        ];

      case CulinaryStarterPackType.pizzeriaAndPasta:
        return const [
          _MealSeedDef(
            name: 'بيتزا مارجريتا نابوليتانو',
            category: 'بيتزا نابوليتانو',
            sellingPrice: 140.0,
            recipeItems: [
              _MealRecipeItemDef(
                rawMaterialName: 'دقيق إيطالي Tipo 00',
                quantity: 220,
                unit: 'جرام',
                yieldLoss: 5.0,
              ),
              _MealRecipeItemDef(
                rawMaterialName: 'صلصة طماطم سان مارزانو',
                quantity: 90,
                unit: 'جرام',
                yieldLoss: 0.0,
              ),
              _MealRecipeItemDef(
                rawMaterialName: 'جبن موزاريلا طبيعي',
                quantity: 120,
                unit: 'جرام',
                yieldLoss: 5.0,
              ),
              _MealRecipeItemDef(
                rawMaterialName: 'زيت زيتون بكر ممتاز',
                quantity: 15,
                unit: 'ملليلتر',
                yieldLoss: 0.0,
              ),
              _MealRecipeItemDef(
                rawMaterialName: 'كرتونة بيتزا 30 سم',
                quantity: 1,
                unit: 'قطعة',
                yieldLoss: 0.0,
              ),
            ],
          ),
          _MealSeedDef(
            name: 'باستا بيني ألفريدو دجاج',
            category: 'أطباق الباستا',
            sellingPrice: 130.0,
            recipeItems: [
              _MealRecipeItemDef(
                rawMaterialName: 'مكرونة بيني',
                quantity: 160,
                unit: 'جرام',
                yieldLoss: 10.0,
              ),
              _MealRecipeItemDef(
                rawMaterialName: 'كريمة طهي حيواني',
                quantity: 120,
                unit: 'ملليلتر',
                yieldLoss: 10.0,
              ),
              _MealRecipeItemDef(
                rawMaterialName: 'جبن موزاريلا طبيعي',
                quantity: 40,
                unit: 'جرام',
                yieldLoss: 0.0,
              ),
              _MealRecipeItemDef(
                rawMaterialName: 'زيت زيتون بكر ممتاز',
                quantity: 15,
                unit: 'ملليلتر',
                yieldLoss: 0.0,
              ),
            ],
          ),
        ];
    }
  }

  static Future<CulinaryPackSeedResult> seedStarterPack({
    required CulinaryStarterPackType packType,
    required ProductRepository productRepository,
    required CategoryRepository categoryRepository,
    String userId = 'admin',
    bool skipIfExists = true,
  }) async {
    int categoriesCreated = 0;
    int rawMaterialsCreated = 0;
    int mealsCreated = 0;
    int skippedCount = 0;
    final List<String> logs = [];

    // 1. Fetch existing categories and products
    final catRes = await categoryRepository.getCategories();
    final List<CategoryEntity> existingCategories = catRes.fold((_) => [], (c) => List.from(c));

    final prodRes = await productRepository.getProducts();
    final List<ProductEntity> existingProducts = prodRes.fold((_) => [], (p) => List.from(p));

    final rawDefs = _getRawMaterials(packType);
    final mealDefs = _getMeals(packType);

    // 2. Ensure all needed categories exist
    final neededCatNames = <String>{
      for (final r in rawDefs) r.category,
      for (final m in mealDefs) m.category,
    };

    final Map<String, CategoryEntity> categoryMap = {};

    for (final catName in neededCatNames) {
      CategoryEntity? matched = existingCategories.cast<CategoryEntity?>().firstWhere(
            (c) => c?.name.trim().toLowerCase() == catName.trim().toLowerCase(),
            orElse: () => null,
          );

      if (matched == null) {
        final newId = 'cat_${DateTime.now().microsecondsSinceEpoch}_${categoryMap.length}';
        final newCat = CategoryEntity(
          id: newId,
          name: catName,
          description: 'قسم $catName لنشاط المطاعم والكافيهات',
          createdAt: DateTime.now(),
        );
        await categoryRepository.addCategory(newCat);
        existingCategories.add(newCat);
        categoryMap[catName] = newCat;
        categoriesCreated++;
        logs.add('تم إنشاء قسم جديد: $catName');
      } else {
        categoryMap[catName] = matched;
      }
    }

    // 3. Create or match Raw Materials
    final Map<String, ProductEntity> rawMaterialsByName = {};

    for (int i = 0; i < rawDefs.length; i++) {
      final rDef = rawDefs[i];
      ProductEntity? matched = existingProducts.cast<ProductEntity?>().firstWhere(
            (p) => p?.name.trim().toLowerCase() == rDef.name.trim().toLowerCase(),
            orElse: () => null,
          );

      if (matched != null && skipIfExists) {
        rawMaterialsByName[rDef.name] = matched;
        skippedCount++;
        logs.add('تخطي المادة الخام لوجودها مسبقاً: ${rDef.name}');
        continue;
      }

      final cat = categoryMap[rDef.category] ?? existingCategories.first;
      final rawId = 'raw_${DateTime.now().microsecondsSinceEpoch}_$i';

      final culData = RestaurantCulinaryData(
        isRawMaterial: true,
        purchaseUnit: rDef.purchaseUnit,
        baseUnit: rDef.baseUnit,
        conversionFactor: rDef.conversionFactor,
      );

      final product = ProductEntity(
        id: rawId,
        name: rDef.name,
        description: culData.toEncodedString(),
        categoryId: cat.id,
        categoryName: cat.name,
        createdAt: DateTime.now(),
        activityType: ActivityType.restaurantsCafes.name,
      );

      final costPiasters = (rDef.costPerBaseUnit * 100).round();
      final variant = VariantInput(
        sku: 'RAW-${DateTime.now().millisecondsSinceEpoch % 1000000}-$i',
        color: '-',
        size: '-',
        costPrice: costPiasters,
        sellPrice: 0,
        quantity: rDef.initialStock,
      );

      await productRepository.addProductWithVariants(product, [variant]);
      existingProducts.add(product);
      rawMaterialsByName[rDef.name] = product;
      rawMaterialsCreated++;
      logs.add('تم إضافة مادة خام: ${rDef.name} (رصيد: ${rDef.initialStock} ${rDef.baseUnit})');
    }

    // 4. Create Meals with BOM linkages
    for (int j = 0; j < mealDefs.length; j++) {
      final mDef = mealDefs[j];
      ProductEntity? matched = existingProducts.cast<ProductEntity?>().firstWhere(
            (p) => p?.name.trim().toLowerCase() == mDef.name.trim().toLowerCase(),
            orElse: () => null,
          );

      if (matched != null && skipIfExists) {
        skippedCount++;
        logs.add('تخطي الوجبة لوجودها مسبقاً: ${mDef.name}');
        continue;
      }

      final cat = categoryMap[mDef.category] ?? existingCategories.first;
      final mealId = 'meal_${DateTime.now().microsecondsSinceEpoch}_$j';

      final List<RecipeItemData> bomItems = [];
      int estimatedCostPiasters = 0;

      for (final rItem in mDef.recipeItems) {
        final rawProd = rawMaterialsByName[rItem.rawMaterialName];
        final rawId = rawProd?.id ?? 'raw_placeholder';
        bomItems.add(
          RecipeItemData(
            rawMaterialId: rawId,
            rawMaterialName: rItem.rawMaterialName,
            quantityNeeded: rItem.quantity,
            unit: rItem.unit,
            yieldLossPercentage: rItem.yieldLoss,
          ),
        );

        final rawDef = rawDefs.cast<_RawMaterialSeedDef?>().firstWhere(
              (d) => d?.name == rItem.rawMaterialName,
              orElse: () => null,
            );
        if (rawDef != null) {
          final unitCostPiasters = (rawDef.costPerBaseUnit * 100).round();
          estimatedCostPiasters += (unitCostPiasters * rItem.quantity).round();
        }
      }

      final culData = RestaurantCulinaryData(
        isRawMaterial: false,
        mealStockMode: 'onDemand',
        recipeItems: bomItems,
      );

      final product = ProductEntity(
        id: mealId,
        name: mDef.name,
        description: culData.toEncodedString(),
        categoryId: cat.id,
        categoryName: cat.name,
        createdAt: DateTime.now(),
        activityType: ActivityType.restaurantsCafes.name,
      );

      final sellPricePiasters = (mDef.sellingPrice * 100).round();
      final variant = VariantInput(
        sku: 'REST-${DateTime.now().millisecondsSinceEpoch % 1000000}-$j',
        color: '-',
        size: '-',
        costPrice: estimatedCostPiasters,
        sellPrice: sellPricePiasters,
        quantity: 999,
      );

      await productRepository.addProductWithVariants(product, [variant]);
      existingProducts.add(product);
      mealsCreated++;
      logs.add('تم إنشاء وجبة: ${mDef.name} (سعر: ${mDef.sellingPrice} ج.م مع ${bomItems.length} مقادير BOM)');
    }

    return CulinaryPackSeedResult(
      categoriesCreated: categoriesCreated,
      rawMaterialsCreated: rawMaterialsCreated,
      mealsCreated: mealsCreated,
      skippedCount: skippedCount,
      messageLogs: logs,
    );
  }
}
