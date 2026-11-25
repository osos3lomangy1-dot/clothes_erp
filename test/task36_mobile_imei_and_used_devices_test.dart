import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sq;

import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/di/injection.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/services/store_presets_engine.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/inventory/data/datasources/inventory_local_data_source.dart';
import 'package:clothes_erp/features/inventory/data/services/device_serial_service.dart';
import 'package:clothes_erp/features/inventory/presentation/widgets/used_device_intake_dialog.dart';
import 'package:clothes_erp/features/invoices/domain/entities/invoice_details_entity.dart';
import 'package:clothes_erp/features/invoices/domain/entities/invoice_item_details_entity.dart';
import 'package:clothes_erp/features/invoices/presentation/services/receipt_pdf_service.dart';
import 'package:clothes_erp/features/pos/data/datasources/pos_local_data_source.dart';
import 'package:clothes_erp/features/pos/domain/entities/payment_split.dart';
import 'package:clothes_erp/features/products/domain/entities/activity_type.dart';
import 'package:clothes_erp/features/returns/data/datasources/returns_local_data_source.dart';
import 'package:clothes_erp/features/returns/domain/entities/return_item_entity.dart';
import 'package:clothes_erp/features/settings/data/services/activity_settings_service.dart';

class _FakeAuthLocalDataSource implements AuthLocalDataSource {
  @override
  Future<void> cacheUser(UserModel user) async {}

  @override
  Future<void> clearCache() async {}

  @override
  Future<UserModel?> getCachedUser() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BranchProvider bp;
  late TxWriter tx;
  late FeatureGate featureGate;
  late ActivitySettingsService activityService;
  late InventoryLocalDataSource invDs;
  late DeviceSerialService serialService;
  late PosLocalDataSource posDs;
  late ReturnsLocalDataSourceImpl returnsDs;
  const branchId = 'branch_main';

  setUp(() async {
    await getIt.reset();
    db = AppDatabase(NativeDatabase.memory());
    bp = BranchProvider(db);
    tx = TxWriter(db);
    featureGate = FeatureGate(db, _FakeAuthLocalDataSource(), tx, bp);
    activityService = ActivitySettingsService(db, featureGate);
    invDs = InventoryLocalDataSource(db, bp, tx);
    serialService = DeviceSerialService(db, bp, tx);
    posDs = PosLocalDataSource(db, bp, tx, invDs);
    returnsDs = ReturnsLocalDataSourceImpl(db, bp, tx, invDs);

    getIt.registerSingleton<AppDatabase>(db);
    getIt.registerSingleton<BranchProvider>(bp);
    getIt.registerSingleton<TxWriter>(tx);
    getIt.registerSingleton<FeatureGate>(featureGate);
    getIt.registerSingleton<ActivitySettingsService>(activityService);
    getIt.registerSingleton<DeviceSerialService>(serialService);
  });

  tearDown(() async {
    featureGate.dispose();
    await db.close();
    await getIt.reset();
  });

  Future<void> seedPhoneAndAccessory({
    int phoneQty = 2,
    int accessoryQty = 5,
  }) async {
    final now = DateTime.now();
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: 'cat_mob',
            branchId: branchId,
            name: 'موبايلات',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: 'prod_iphone',
            branchId: branchId,
            name: 'iPhone 15 Pro',
            categoryId: 'cat_mob',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            id: 'var_iphone',
            branchId: branchId,
            productId: 'prod_iphone',
            sku: 'IPH15P-256',
            color: 'تيتانيوم',
            size: '256GB',
            quantity: Value(phoneQty),
            costPrice: 4000000,
            sellPrice: 4500000,
            createdAt: now,
            updatedAt: now,
          ),
        );

    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: 'prod_case',
            branchId: branchId,
            name: 'جراب حماية',
            categoryId: 'cat_mob',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            id: 'var_case',
            branchId: branchId,
            productId: 'prod_case',
            sku: 'CASE-01',
            color: 'أسود',
            size: 'قياسي',
            quantity: Value(accessoryQty),
            costPrice: 5000,
            sellPrice: 15000,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  group('Task 36: FeatureGate & StorePresetsEngine Isolation', () {
    test(
      'mobileImeiUsed defaults to false and is enabled only for electronics',
      () async {
        expect(
          await featureGate.isEnabled(FeatureKeys.mobileImeiUsed),
          isFalse,
        );

        await StorePresetsEngine.applyPreset(
          preset: StorePreset.electronics,
          featureGate: featureGate,
          activityService: activityService,
          userId: 'system',
        );
        expect(await featureGate.isEnabled(FeatureKeys.mobileImeiUsed), isTrue);

        await StorePresetsEngine.applyPreset(
          preset: StorePreset.fashion,
          featureGate: featureGate,
          activityService: activityService,
          userId: 'system',
        );
        expect(
          await featureGate.isEnabled(FeatureKeys.mobileImeiUsed),
          isFalse,
        );
      },
    );
  });

  group('Task 36: Schema v12 Migration & DeviceSerialService', () {
    test(
      'AppDatabase schemaVersion is >= 12 and migrateToV12 upgrades v11 DB safely',
      () async {
        expect(db.schemaVersion, greaterThanOrEqualTo(12));

        // Build an in-memory v11 database with minimal sale_items table and migrate it
        final raw = sq.sqlite3.openInMemory();
        raw.execute('''
        CREATE TABLE sale_items (
          id TEXT PRIMARY KEY NOT NULL,
          branch_id TEXT NOT NULL,
          sale_id TEXT NOT NULL,
          variant_id TEXT NOT NULL,
          qty INTEGER NOT NULL,
          unit_price INTEGER NOT NULL,
          line_total INTEGER NOT NULL
        );
      ''');
        final v11Db = AppDatabase(NativeDatabase.opened(raw));
        final m = v11Db.createMigrator();
        await v11Db.migrateToV12(m);

        final serialCols = raw.select(
          'PRAGMA table_info(device_serial_units);',
        );
        expect(serialCols.any((r) => r['name'] == 'imei'), isTrue);
        expect(
          serialCols.any((r) => r['name'] == 'seller_national_id'),
          isTrue,
        );

        final saleItemCols = raw.select('PRAGMA table_info(sale_items);');
        expect(saleItemCols.any((r) => r['name'] == 'imei'), isTrue);
        expect(
          saleItemCols.any((r) => r['name'] == 'device_condition'),
          isTrue,
        );

        await v11Db.close();
      },
    );

    test(
      'Registers 2 IMEIs for same variant, rejects duplicates, validates 14-digit ID',
      () async {
        await seedPhoneAndAccessory(phoneQty: 2);

        await serialService.registerSerialUnits(
          variantId: 'var_iphone',
          imeis: ['356789012345001', '356789012345002'],
          condition: 'new',
          buyPricePiasters: 4000000,
        );

        final units = await serialService.getInStockUnitsForVariant(
          'var_iphone',
        );
        expect(units.length, 2);
        expect(
          units.map((u) => u.imei),
          containsAll(['356789012345001', '356789012345002']),
        );

        // Duplicate IMEI rejection
        await expectLater(
          serialService.registerSerialUnits(
            variantId: 'var_iphone',
            imeis: ['356789012345001'],
          ),
          throwsException,
        );

        // Invalid National ID rejection (must be 14 digits when provided)
        expect(
          () => DeviceSerialService.validateOptionalNationalId('12345'),
          throwsException,
        );
        expect(
          () =>
              DeviceSerialService.validateOptionalNationalId('29901011234567'),
          returnsNormally,
        );
      },
    );

    test(
      'registerUsedOrTradeInDevice saves seller info, increments stock, and logs expense',
      () async {
        await seedPhoneAndAccessory(phoneQty: 1);

        final res = await serialService.registerUsedOrTradeInDevice(
          variantId: 'var_iphone',
          productName: 'iPhone 15 Pro',
          imei: '356789012345999',
          condition: 'used',
          batteryHealth: 89,
          notes: 'نظيف بدون خدوش',
          sellerName: 'أحمد محمود',
          sellerNationalId: '29901011234567',
          sellerPhone: '01012345678',
          buyPricePiasters: 3200000,
          deductFromDrawer: true,
        );

        expect(res.imei, '356789012345999');
        expect(res.condition, 'used');

        final unit = await serialService.findInStockByImei('356789012345999');
        expect(unit, isNotNull);
        expect(unit!.batteryHealth, 89);
        expect(unit.sellerName, 'أحمد محمود');
        expect(unit.sellerNationalId, '29901011234567');
        expect(unit.buyPrice, 3200000);

        final variant = await (db.select(
          db.productVariants,
        )..where((t) => t.id.equals('var_iphone'))).getSingle();
        expect(variant.quantity, 2);

        final expenses = await db.select(db.expenses).get();
        expect(expenses.length, 1);
        expect(expenses.first.amount, 3200000);
      },
    );
  });

  group('Task 36: UsedDeviceIntakeDialog Widget & Shortcuts', () {
    testWidgets(
      'UsedDeviceIntakeDialog saves via Ctrl+S and rejects invalid 14-digit ID',
      (tester) async {
        await seedPhoneAndAccessory(phoneQty: 0);

        UsedDeviceIntakeResult? dialogResult;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    dialogResult = await UsedDeviceIntakeDialog.show(context);
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('used_device_imei_field')),
          '359999000011112',
        );
        await tester.enterText(
          find.byKey(const Key('used_device_battery_field')),
          '87',
        );
        await tester.enterText(
          find.byKey(const Key('used_device_buy_price_field')),
          '25000',
        );
        await tester.enterText(
          find.byKey(const Key('used_device_seller_name_field')),
          'محمد علي',
        );
        await tester.enterText(
          find.byKey(const Key('used_device_national_id_field')),
          '29505051234567',
        );
        await tester.pump();

        // Trigger Ctrl+S shortcut
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();

        expect(dialogResult, isNotNull);
        expect(dialogResult!.imei, '359999000011112');
        expect(dialogResult!.buyPricePiasters, 2500000);

        final unit = await serialService.findInStockByImei('359999000011112');
        expect(unit, isNotNull);
        expect(unit!.sellerNationalId, '29505051234567');
      },
    );
  });

  group('Task 36: POS Sale, Receipt PDF & Return Verification', () {
    test(
      'Sells serialized phone + untracked accessory, generates PDF, verifies & returns IMEI',
      () async {
        await featureGate.setFeatureEnabled(
          FeatureKeys.mobileImeiUsed,
          true,
          userId: 'system',
        );
        await seedPhoneAndAccessory(phoneQty: 2, accessoryQty: 5);

        await serialService.registerSerialUnits(
          variantId: 'var_iphone',
          imeis: ['351111222233331', '351111222233332'],
          condition: 'used',
          buyPricePiasters: 3500000,
        );

        final saleId = await posDs.checkout(
          items: [
            {
              'variantId': 'var_iphone',
              'name': 'iPhone 15 Pro',
              'size': '256GB',
              'color': 'تيتانيوم',
              'qty': 1,
              'price': 4200000,
              'cost': 3500000,
              'discount': 0,
              'imei': '351111222233331',
              'deviceCondition': 'used',
            },
            {
              'variantId': 'var_case',
              'name': 'جراب حماية',
              'size': 'قياسي',
              'color': 'أسود',
              'qty': 1,
              'price': 15000,
              'cost': 5000,
              'discount': 0,
            },
          ],
          total: 4215000,
          cashierId: 'admin',
          paymentMethod: 'cash',
          splits: const [PaymentSplit(method: 'cash', amountPiasters: 4215000)],
        );

        // Verify serialized unit is marked sold
        final soldUnit = await (db.select(
          db.deviceSerialUnits,
        )..where((t) => t.imei.equals('351111222233331'))).getSingle();
        expect(soldUnit.status, 'sold');
        expect(soldUnit.saleId, saleId);

        // Second IMEI remains in_stock
        final inStockUnits = await serialService.getInStockUnitsForVariant(
          'var_iphone',
        );
        expect(inStockUnits.map((u) => u.imei).toList(), ['351111222233332']);

        // Verify SaleItems persisted IMEI
        final saleItems = await (db.select(
          db.saleItems,
        )..where((t) => t.saleId.equals(saleId))).get();
        final phoneSaleItem = saleItems.firstWhere(
          (s) => s.variantId == 'var_iphone',
        );
        final caseSaleItem = saleItems.firstWhere(
          (s) => s.variantId == 'var_case',
        );
        expect(phoneSaleItem.imei, '351111222233331');
        expect(phoneSaleItem.deviceCondition, 'used');
        expect(caseSaleItem.imei, isNull);

        // Verify Receipt PDF generation succeeds with IMEI & condition
        final pdfBytes = await ReceiptPdfService.generateReceiptPdf(
          InvoiceDetailsEntity(
            id: saleId,
            shortRef: 'INV-36',
            date: DateTime.now(),
            cashierId: 'admin',
            subtotal: 4215000,
            total: 4215000,
            paymentMethod: 'cash',
            items: const [
              InvoiceItemDetailsEntity(
                id: 'ii_phone',
                variantId: 'var_iphone',
                productName: 'iPhone 15 Pro',
                size: '256GB',
                color: 'تيتانيوم',
                qty: 1,
                price: 4200000,
                lineTotal: 4200000,
                imei: '351111222233331',
                deviceCondition: 'used',
              ),
              InvoiceItemDetailsEntity(
                id: 'ii_case',
                variantId: 'var_case',
                productName: 'جراب حماية',
                size: 'قياسي',
                color: 'أسود',
                qty: 1,
                price: 15000,
                lineTotal: 15000,
              ),
            ],
          ),
        );
        expect(pdfBytes.length, greaterThan(500));

        // Verify IMEI mismatch rejection
        await expectLater(
          serialService.verifyAndReturnByImei(
            saleId: saleId,
            imei: '999999999999999',
          ),
          throwsException,
        );

        // Process return through ReturnsLocalDataSourceImpl (restores stock + device status)
        await returnsDs.processReturn(
          saleId: saleId,
          items: [
            ReturnItemEntity(
              saleItemId: phoneSaleItem.id,
              variantId: 'var_iphone',
              productName: 'iPhone 15 Pro',
              qty: 1,
              refundUnitPrice: 4200000,
            ),
            ReturnItemEntity(
              saleItemId: caseSaleItem.id,
              variantId: 'var_case',
              productName: 'جراب حماية',
              qty: 1,
              refundUnitPrice: 15000,
            ),
          ],
          reason: 'استرجاع تجريبي',
          userId: 'admin',
        );

        final restoredUnit = await (db.select(
          db.deviceSerialUnits,
        )..where((t) => t.imei.equals('351111222233331'))).getSingle();
        expect(restoredUnit.status, 'in_stock');
        expect(restoredUnit.saleId, isNull);
      },
    );
  });
}
