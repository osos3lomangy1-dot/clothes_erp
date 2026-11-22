import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/products/domain/entities/activity_type.dart';
import 'package:clothes_erp/features/settings/data/services/activity_settings_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthLocalDataSource implements AuthLocalDataSource {
  UserModel? _user;
  void setUser(UserModel? user) => _user = user;
  @override
  Future<void> cacheUser(UserModel user) async => _user = user;
  @override
  Future<UserModel?> getCachedUser() async => _user;
  @override
  Future<void> clearCache() async => _user = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Task 11.4 - Multi-Activity Matrix and Sectors', () {
    test('ActivitySector contains all 6 defined sectors', () {
      expect(ActivitySector.values.length, 6);
      expect(ActivitySector.fashion.code, 'fashion');
      expect(ActivitySector.tech.code, 'tech');
      expect(ActivitySector.food.code, 'food');
      expect(ActivitySector.hospitality.code, 'hospitality');
      expect(ActivitySector.healthKids.code, 'healthKids');
      expect(ActivitySector.generalHome.code, 'generalHome');
    });

    test('ActivityType contains exactly 18 activities mapped to 6 sectors', () {
      expect(ActivityType.values.length, 18);

      // 1. Fashion
      expect(ActivityType.clothing.sector, ActivitySector.fashion);
      expect(ActivityType.footwearBags.sector, ActivitySector.fashion);
      expect(ActivityType.accessoriesBeauty.sector, ActivitySector.fashion);
      expect(ActivityType.perfumesCosmetics.sector, ActivitySector.fashion);
      expect(ActivityType.watchesEyewear.sector, ActivitySector.fashion);

      // 2. Tech
      expect(ActivityType.electronicsMobiles.sector, ActivitySector.tech);
      expect(ActivityType.homeLiving.sector, ActivitySector.tech);

      // 3. Food
      expect(ActivityType.supermarketGroceries.sector, ActivitySector.food);
      expect(ActivityType.spicesNuts.sector, ActivitySector.food);
      expect(ActivityType.sweetsBakery.sector, ActivitySector.food);

      // 4. Hospitality
      expect(ActivityType.restaurantsCafes.sector, ActivitySector.hospitality);

      // 5. Health & Kids
      expect(ActivityType.kidsToys.sector, ActivitySector.healthKids);
      expect(ActivityType.pharmacySupplies.sector, ActivitySector.healthKids);
      expect(ActivityType.sportsFitness.sector, ActivitySector.healthKids);

      // 6. General & Home
      expect(ActivityType.bookstoreStationery.sector, ActivitySector.generalHome);
      expect(ActivityType.textilesDecor.sector, ActivitySector.generalHome);
      expect(ActivityType.petShop.sector, ActivitySector.generalHome);
      expect(ActivityType.general.sector, ActivitySector.generalHome);
    });

    test('Adaptive properties return accurate capability flags', () {
      // Matrix based vs single item
      expect(ActivityType.clothing.isMatrixBased, isTrue);
      expect(ActivityType.clothing.isSingleItem, isFalse);
      expect(ActivityType.footwearBags.isMatrixBased, isTrue);
      expect(ActivityType.sportsFitness.isMatrixBased, isTrue);
      expect(ActivityType.textilesDecor.isMatrixBased, isTrue);
      expect(ActivityType.electronicsMobiles.isMatrixBased, isFalse);
      expect(ActivityType.electronicsMobiles.isSingleItem, isTrue);

      // Warranty support
      expect(ActivityType.electronicsMobiles.supportsWarranty, isTrue);
      expect(ActivityType.homeLiving.supportsWarranty, isTrue);
      expect(ActivityType.watchesEyewear.supportsWarranty, isTrue);
      expect(ActivityType.clothing.supportsWarranty, isFalse);

      // Serial / IMEI support
      expect(ActivityType.electronicsMobiles.supportsIMEI, isTrue);
      expect(ActivityType.clothing.supportsIMEI, isFalse);

      // Weight support (scale / bulk / kg / gram)
      expect(ActivityType.supermarketGroceries.supportsWeight, isTrue);
      expect(ActivityType.spicesNuts.supportsWeight, isTrue);
      expect(ActivityType.sweetsBakery.supportsWeight, isTrue);
      expect(ActivityType.petShop.supportsWeight, isTrue);
      expect(ActivityType.clothing.supportsWeight, isFalse);

      // Expiry date support
      expect(ActivityType.perfumesCosmetics.supportsExpiry, isTrue);
      expect(ActivityType.supermarketGroceries.supportsExpiry, isTrue);
      expect(ActivityType.sweetsBakery.supportsExpiry, isTrue);
      expect(ActivityType.pharmacySupplies.supportsExpiry, isTrue);
      expect(ActivityType.petShop.supportsExpiry, isTrue);
      expect(ActivityType.clothing.supportsExpiry, isFalse);

      // Installment support
      expect(ActivityType.electronicsMobiles.supportsInstallment, isTrue);
      expect(ActivityType.homeLiving.supportsInstallment, isTrue);
      expect(ActivityType.watchesEyewear.supportsInstallment, isTrue);
      expect(ActivityType.general.supportsInstallment, isTrue);

      // Hospitality support
      expect(ActivityType.restaurantsCafes.isHospitality, isTrue);
      expect(ActivityType.clothing.isHospitality, isFalse);
    });

    test('ActivityType.fromString parses all canonical names and aliases', () {
      expect(ActivityType.fromString('clothing'), ActivityType.clothing);
      expect(ActivityType.fromString('clothes'), ActivityType.clothing);
      expect(ActivityType.fromString('fashion'), ActivityType.clothing);
      expect(ActivityType.fromString('apparel'), ActivityType.clothing);

      expect(ActivityType.fromString('footwear_bags'), ActivityType.footwearBags);
      expect(ActivityType.fromString('shoes_bags'), ActivityType.footwearBags);
      expect(ActivityType.fromString('footwearBags'), ActivityType.footwearBags);
      expect(ActivityType.fromString('shoes'), ActivityType.footwearBags);

      expect(ActivityType.fromString('accessories_beauty'), ActivityType.accessoriesBeauty);
      expect(ActivityType.fromString('jewelry'), ActivityType.accessoriesBeauty);

      expect(ActivityType.fromString('perfumes_cosmetics'), ActivityType.perfumesCosmetics);
      expect(ActivityType.fromString('perfumesCosmetics'), ActivityType.perfumesCosmetics);
      expect(ActivityType.fromString('perfumes'), ActivityType.perfumesCosmetics);

      expect(ActivityType.fromString('watches_eyewear'), ActivityType.watchesEyewear);
      expect(ActivityType.fromString('watchesEyewear'), ActivityType.watchesEyewear);
      expect(ActivityType.fromString('glasses'), ActivityType.watchesEyewear);

      expect(ActivityType.fromString('electronics_mobiles'), ActivityType.electronicsMobiles);
      expect(ActivityType.fromString('electronicsMobiles'), ActivityType.electronicsMobiles);
      expect(ActivityType.fromString('mobiles'), ActivityType.electronicsMobiles);

      expect(ActivityType.fromString('home_living'), ActivityType.homeLiving);
      expect(ActivityType.fromString('homeLiving'), ActivityType.homeLiving);

      expect(ActivityType.fromString('supermarket_groceries'), ActivityType.supermarketGroceries);
      expect(ActivityType.fromString('supermarketGroceries'), ActivityType.supermarketGroceries);

      expect(ActivityType.fromString('spices_nuts'), ActivityType.spicesNuts);
      expect(ActivityType.fromString('spicesNuts'), ActivityType.spicesNuts);

      expect(ActivityType.fromString('sweets_bakery'), ActivityType.sweetsBakery);
      expect(ActivityType.fromString('sweetsBakery'), ActivityType.sweetsBakery);

      expect(ActivityType.fromString('restaurants_cafes'), ActivityType.restaurantsCafes);
      expect(ActivityType.fromString('restaurantsCafes'), ActivityType.restaurantsCafes);
      expect(ActivityType.fromString('hospitality'), ActivityType.restaurantsCafes);

      expect(ActivityType.fromString('kids_toys'), ActivityType.kidsToys);
      expect(ActivityType.fromString('kidsToys'), ActivityType.kidsToys);

      expect(ActivityType.fromString('pharmacy_supplies'), ActivityType.pharmacySupplies);
      expect(ActivityType.fromString('pharmacySupplies'), ActivityType.pharmacySupplies);

      expect(ActivityType.fromString('sports_fitness'), ActivityType.sportsFitness);
      expect(ActivityType.fromString('sportsFitness'), ActivityType.sportsFitness);

      expect(ActivityType.fromString('bookstore_stationery'), ActivityType.bookstoreStationery);
      expect(ActivityType.fromString('bookstoreStationery'), ActivityType.bookstoreStationery);

      expect(ActivityType.fromString('textiles_decor'), ActivityType.textilesDecor);
      expect(ActivityType.fromString('textilesDecor'), ActivityType.textilesDecor);

      expect(ActivityType.fromString('pet_shop'), ActivityType.petShop);
      expect(ActivityType.fromString('petShop'), ActivityType.petShop);

      expect(ActivityType.fromString('general'), ActivityType.general);
      expect(ActivityType.fromString('unknown_val'), ActivityType.clothing);
      expect(ActivityType.fromString(null), ActivityType.clothing);
    });
  });

  group('Task 11.4 - ActivitySettingsService Operations', () {
    late AppDatabase db;
    late BranchProvider branchProvider;
    late _FakeAuthLocalDataSource auth;
    late FeatureGate featureGate;
    late ActivitySettingsService service;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      branchProvider = BranchProvider(db);
      auth = _FakeAuthLocalDataSource();
      auth.setUser(UserModel(
        id: 'admin-1',
        name: 'Admin',
        email: 'a@a.a',
        role: 'admin',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      ));
      featureGate = FeatureGate(db, auth, TxWriter(db), branchProvider);
      service = ActivitySettingsService(db, featureGate);
    });

    tearDown(() async {
      await db.close();
    });

    test('default enabled activities includes clothing when unconfigured', () async {
      final enabled = await service.getEnabledActivities();
      expect(enabled.contains(ActivityType.clothing), isTrue);
      expect(enabled.length, 18);
    });

    test('setAllActivities(false) keeps clothing enabled as safety fallback', () async {
      await service.setAllActivities(false, userId: 'test_user');
      final enabled = await service.getEnabledActivities();

      expect(enabled.length, 1);
      expect(enabled.first, ActivityType.clothing);
    });

    test('setAllActivities(true) enables all 18 activities', () async {
      await service.setAllActivities(false, userId: 'test_user');
      expect((await service.getEnabledActivities()).length, 1);

      await service.setAllActivities(true, userId: 'test_user');
      final allEnabled = await service.getEnabledActivities();
      expect(allEnabled.length, 18);
    });

    test('safety rule throws exception when trying to disable the last remaining activity', () async {
      await service.setAllActivities(false, userId: 'test_user');
      final enabled = await service.getEnabledActivities();
      expect(enabled.length, 1);
      expect(enabled.first, ActivityType.clothing);

      expect(
        () => service.setActivityEnabled(ActivityType.clothing, false, userId: 'test_user'),
        throwsA(isA<Exception>()),
      );
    });

    test('toggling individual activity works correctly', () async {
      await service.setActivityEnabled(ActivityType.restaurantsCafes, false, userId: 'test_user');
      expect(await service.isActivityEnabled(ActivityType.restaurantsCafes), isFalse);

      await service.setActivityEnabled(ActivityType.restaurantsCafes, true, userId: 'test_user');
      expect(await service.isActivityEnabled(ActivityType.restaurantsCafes), isTrue);
    });
  });
}
