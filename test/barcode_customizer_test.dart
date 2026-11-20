import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/barcode_printing/domain/models/barcode_config.dart';
import 'package:clothes_erp/features/barcode_printing/domain/models/barcode_label_item.dart';
import 'package:clothes_erp/features/barcode_printing/presentation/dialogs/barcode_print_dialog.dart';
import 'package:clothes_erp/features/barcode_printing/presentation/widgets/barcode_sticker_live_preview.dart';
import 'package:clothes_erp/features/barcode_printing/services/barcode_settings_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthLocalDataSource implements AuthLocalDataSource {
  UserModel? _user;
  @override
  Future<void> cacheUser(UserModel user) async => _user = user;
  @override
  Future<UserModel?> getCachedUser() async => _user;
  @override
  Future<void> clearCache() async => _user = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FeatureGate gate;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final authDs = _FakeAuthLocalDataSource();
    authDs.cacheUser(
      UserModel(
        id: 'admin',
        name: 'Admin',
        email: 'admin@system.com',
        role: 'admin',
        isActive: true,
        createdAt: DateTime.now(),
      ),
    );
    final txWriter = TxWriter(db);
    final branchProvider = BranchProvider(db);
    gate = FeatureGate(db, authDs, txWriter, branchProvider);
  });

  tearDown(() async {
    await db.close();
  });

  group('BarcodeConfig & BarcodeSettingsService', () {
    test('BarcodeConfig defaults and copyWith', () {
      final config = BarcodeConfig.defaults();
      expect(config.selectedSize, BarcodeLabelSize.roll50x30);
      expect(config.showStoreName, isTrue);
      expect(config.showProductName, isTrue);
      expect(config.showColorAndSize, isTrue);
      expect(config.showPrice, isTrue);
      expect(config.showBarcodeText, isTrue);

      final updated = config.copyWith(
        selectedSize: BarcodeLabelSize.roll38x25,
        storeName: 'متجر الأناقة',
        showPrice: false,
      );

      expect(updated.selectedSize, BarcodeLabelSize.roll38x25);
      expect(updated.storeName, 'متجر الأناقة');
      expect(updated.showPrice, isFalse);
      expect(updated.showStoreName, isTrue);
    });

    test('BarcodeConfig serialization and deserialization', () {
      const config = BarcodeConfig(
        selectedSize: BarcodeLabelSize.roll40x25,
        storeName: 'براند النخبة',
        showStoreName: false,
        showProductName: true,
        showColorAndSize: false,
        showPrice: true,
        showBarcodeText: true,
        defaultCopies: 3,
      );

      final jsonStr = config.toJson();
      final restored = BarcodeConfig.fromJson(jsonStr);

      expect(restored.selectedSize, BarcodeLabelSize.roll40x25);
      expect(restored.storeName, 'براند النخبة');
      expect(restored.showStoreName, isFalse);
      expect(restored.showColorAndSize, isFalse);
      expect(restored.defaultCopies, 3);
      expect(restored, equals(config));
    });

    test('BarcodeSettingsService save, load, and reset', () async {
      const customConfig = BarcodeConfig(
        selectedSize: BarcodeLabelSize.sheetA4,
        storeName: 'سوبر فاشون',
        showStoreName: true,
        showPrice: true,
        showColorAndSize: false,
      );

      await BarcodeSettingsService.save(customConfig, gate, userId: 'admin');
      expect(BarcodeSettingsService.current.selectedSize, BarcodeLabelSize.sheetA4);
      expect(BarcodeSettingsService.current.storeName, 'سوبر فاشون');

      // Reload
      await BarcodeSettingsService.loadFromFeatureGate(gate);
      expect(BarcodeSettingsService.current.selectedSize, BarcodeLabelSize.sheetA4);
      expect(BarcodeSettingsService.current.storeName, 'سوبر فاشون');
      expect(BarcodeSettingsService.current.showColorAndSize, isFalse);

      // Reset
      await BarcodeSettingsService.resetToDefaults(gate, userId: 'admin');
      expect(BarcodeSettingsService.current.selectedSize, BarcodeLabelSize.roll50x30);
    });
  });

  group('BarcodeStickerLivePreview Widget Tests', () {
    const sampleItem = BarcodeLabelItem(
      variantId: 'var-10',
      productName: 'بدلة كلاسيك رجالي',
      sku: '622998877665',
      color: 'رمادي غامق',
      size: '52',
      salePricePiasters: 120000,
      copies: 2,
    );

    testWidgets('renders all fields when enabled', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const config = BarcodeConfig(
        storeName: 'براند كلاسيك',
        showStoreName: true,
        showProductName: true,
        showColorAndSize: true,
        showPrice: true,
        showBarcodeText: true,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: BarcodeStickerLivePreview(
                config: config,
                sampleItem: sampleItem,
              ),
            ),
          ),
        ),
      );

      expect(find.text('معاينة الاستيكر'), findsOneWidget);
      expect(find.text('براند كلاسيك'), findsOneWidget);
      expect(find.text('بدلة كلاسيك رجالي'), findsOneWidget);
      expect(find.text('رمادي غامق • مقاس 52'), findsOneWidget);
      expect(find.text('1200.00 ج.م'), findsOneWidget);
      expect(find.text('622998877665'), findsOneWidget);
    });

    testWidgets('hides fields when toggled off', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const config = BarcodeConfig(
        storeName: 'براند كلاسيك',
        showStoreName: false,
        showProductName: false,
        showColorAndSize: false,
        showPrice: false,
        showBarcodeText: false,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: BarcodeStickerLivePreview(
                config: config,
                sampleItem: sampleItem,
              ),
            ),
          ),
        ),
      );

      expect(find.text('براند كلاسيك'), findsNothing);
      expect(find.text('بدلة كلاسيك رجالي'), findsNothing);
      expect(find.text('رمادي غامق • مقاس 52'), findsNothing);
      expect(find.text('1,200.00 ج.م'), findsNothing);
      expect(find.text('622998877665'), findsNothing);
    });
  });

  group('BarcodePrintDialog Widget Tests', () {
    const items = [
      BarcodeLabelItem(
        variantId: 'v1',
        productName: 'قميص أكسفورد',
        sku: '1001',
        color: 'أبيض',
        size: 'L',
        salePricePiasters: 35000,
        copies: 1,
      ),
      BarcodeLabelItem(
        variantId: 'v2',
        productName: 'بنطلون جبردين',
        sku: '1002',
        color: 'بيج',
        size: '32',
        salePricePiasters: 45000,
        copies: 2,
      ),
    ];

    testWidgets('renders dialog with 2-pane preview and items list', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BarcodePrintDialog(
              initialItems: items,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('طباعة ملصقات الباركود والأسعار'), findsOneWidget);
      expect(find.text('إجمالي الملصقات: 3 ملصق'), findsOneWidget);
      expect(find.text('قميص أكسفورد'), findsWidgets);
      expect(find.text('بنطلون جبردين'), findsWidgets);

      // Tap + button on first item to increase copies from 1 to 2
      final addButtons = find.byIcon(Icons.add_circle_outline);
      expect(addButtons, findsNWidgets(2));
      await tester.tap(addButtons.first);
      await tester.pumpAndSettle();

      expect(find.text('إجمالي الملصقات: 4 ملصق'), findsOneWidget);
    });
  });
}
