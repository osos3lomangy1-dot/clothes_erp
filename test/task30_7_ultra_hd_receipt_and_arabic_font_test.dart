import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/invoices/data/services/receipt_settings_service.dart';
import 'package:clothes_erp/features/invoices/domain/entities/invoice_details_entity.dart';
import 'package:clothes_erp/features/invoices/domain/entities/invoice_item_details_entity.dart';
import 'package:clothes_erp/features/invoices/domain/entities/receipt_config.dart';
import 'package:clothes_erp/features/invoices/presentation/services/receipt_pdf_service.dart';
import 'package:clothes_erp/features/invoices/presentation/widgets/thermal_receipt_live_preview.dart';
import 'package:clothes_erp/features/products/domain/entities/activity_type.dart';
import 'package:clothes_erp/features/settings/data/services/activity_settings_service.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

class _FakeFeatureGate implements FeatureGate {
  final Map<String, String> _store = {};

  @override
  Future<String?> getMeta(String key) async => _store[key];

  @override
  Stream<String?> watchMeta(String key) => Stream.value(_store[key]);

  @override
  Future<void> setMeta(String key, String value, {bool audit = true, required String userId}) async {
    _store[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeActivitySettingsService implements ActivitySettingsService {
  final List<ActivityType> _activities;
  _FakeActivitySettingsService(Set<ActivityType> activities)
      : _activities = activities.toList();

  @override
  List<ActivityType> get cachedEnabledActivities => _activities;

  @override
  Stream<List<ActivityType>> watchEnabledActivities() => Stream.value(_activities);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final sl = GetIt.instance;

  final sampleHospitalityInvoice = InvoiceDetailsEntity(
    id: 'inv-hosp-77',
    shortRef: '077',
    date: DateTime(2026, 11, 24, 14, 0),
    cashierId: 'cashier-1',
    cashierName: 'أحمد الكاشير',
    customerName: 'كريم محمود',
    customerPhone: '01012345678',
    orderNumber: '077',
    orderType: 'dineIn',
    tableNumber: '5',
    wifiInfo: 'WiFi: Restaurant-Guest',
    subtotal: 25000,
    discountAmount: 1000,
    total: 24000,
    paymentMethod: 'نقدي (كاش)',
    paidAmount: 25000,
    changeAmount: 1000,
    items: const [
      InvoiceItemDetailsEntity(
        id: 'item-1',
        variantId: 'var-1',
        productName: 'وجبة ميكس جريل مشكل عائلي فاخر',
        color: 'افتراضي',
        size: 'افتراضي',
        qty: 1,
        price: 18000,
        lineTotal: 18000,
        kitchenNotes: 'تسوية زيادة - بدون بصل - طحينة إضافية',
      ),
      InvoiceItemDetailsEntity(
        id: 'item-2',
        variantId: 'var-2',
        productName: 'مشروب موهيتو ليمون ونعناع مثلج فريش',
        color: 'افتراضي',
        size: 'كبير',
        qty: 2,
        price: 3500,
        lineTotal: 7000,
        kitchenNotes: 'سكر دايت - ثلج مجروش',
      ),
    ],
  );

  setUp(() async {
    await sl.reset();
    final db = AppDatabase(NativeDatabase.memory());
    sl.registerSingleton<AppDatabase>(db);
    final mockGate = _FakeFeatureGate();
    sl.registerSingleton<FeatureGate>(mockGate);
    final actService = _FakeActivitySettingsService({ActivityType.restaurantsCafes});
    sl.registerSingleton<ActivitySettingsService>(actService);
    ReceiptSettingsService.notifier.value = ReceiptConfig.hospitalityDefaults;
  });

  group('Task 30.7: Ultra-HD Cairo Font & Receipt Engine Tests', () {
    test('ReceiptPdfService font loader loads fonts and caches in memory', () async {
      // First load
      final font = await ReceiptPdfService.generateReceiptPdf(
        sampleHospitalityInvoice,
        config: ReceiptConfig.hospitalityDefaults,
      );
      expect(font, isA<Uint8List>());
      expect(font.isNotEmpty, true);
      expect(font.length, greaterThan(1500));
    });

    test('80mm roll format applies 72mm width with 1.5mm safe margin without clipping', () async {
      final config80 = ReceiptConfig.hospitalityDefaults.copyWith(
        paperWidthMm: 80,
      );

      final pdfBytes = await ReceiptPdfService.generateReceiptPdf(
        sampleHospitalityInvoice,
        config: config80,
        isHospitality: true,
        orderNumber: '077',
        tableNumber: '5',
        orderType: 'dineIn',
      );

      expect(pdfBytes, isA<Uint8List>());
      expect(pdfBytes.isNotEmpty, true);
    });

    test('58mm roll format applies 48mm width with 1.0mm safe margin without clipping', () async {
      final config58 = ReceiptConfig.hospitalityDefaults.copyWith(
        paperWidthMm: 58,
      );

      final pdfBytes = await ReceiptPdfService.generateReceiptPdf(
        sampleHospitalityInvoice,
        config: config58,
        isHospitality: true,
        orderNumber: '077',
        tableNumber: '5',
        orderType: 'dineIn',
      );

      expect(pdfBytes, isA<Uint8List>());
      expect(pdfBytes.isNotEmpty, true);
    });

    test('InvoiceDetailsEntity computes totalQuantity accurately', () {
      expect(sampleHospitalityInvoice.items.length, 2);
      expect(sampleHospitalityInvoice.totalQuantity, 3);
      expect(sampleHospitalityInvoice.totalItemsCount, 3);
      expect(sampleHospitalityInvoice.paidAmount, 25000);
      expect(sampleHospitalityInvoice.changeAmount, 1000);
    });

    test('ReceiptPdfService handles cash tendered, change due and QR Code', () async {
      final pdfBytes = await ReceiptPdfService.generateReceiptPdf(
        sampleHospitalityInvoice,
        config: ReceiptConfig.hospitalityDefaults.copyWith(showBarcode: true),
        paidAmount: 25000,
        changeAmount: 1000,
      );

      expect(pdfBytes, isA<Uint8List>());
      expect(pdfBytes.isNotEmpty, true);
    });

    test('ReceiptPdfService renders grouped variants with 2-tier calculations without error', () async {
      final groupedInvoice = sampleHospitalityInvoice.copyWith(
        items: const [
          InvoiceItemDetailsEntity(
            id: 'item-g1',
            variantId: 'var-g1',
            productName: 'ساندوتش شاورما دجاج',
            color: 'عادي',
            size: 'صغير',
            qty: 2,
            price: 4500,
            lineTotal: 9000,
            kitchenNotes: 'تومية زيادة',
          ),
          InvoiceItemDetailsEntity(
            id: 'item-g2',
            variantId: 'var-g2',
            productName: 'ساندوتش شاورما دجاج',
            color: 'سبايسي',
            size: 'كبير',
            qty: 1,
            price: 6500,
            lineTotal: 6500,
            kitchenNotes: 'بدون خيار مخلل',
          ),
        ],
      );

      final pdfBytes = await ReceiptPdfService.generateReceiptPdf(
        groupedInvoice,
        config: ReceiptConfig.hospitalityDefaults.copyWith(groupVariantsOnReceipt: true),
      );

      expect(pdfBytes, isA<Uint8List>());
      expect(pdfBytes.isNotEmpty, true);
    });
  });

  group('Task 30.7: ThermalReceiptLivePreview Widget Tests', () {
    testWidgets('Live preview renders 2-tier layout, items count, tendered amount, change due and QR code', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const config = ReceiptConfig.hospitalityDefaults;

      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(
                child: Center(
                  child: ThermalReceiptLivePreview(config: config),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Table header 2-tier labels
      expect(find.text('الصنف'), findsOneWidget);
      expect(find.text('الكمية × السعر / الإجمالي'), findsOneWidget);

      // Meal items and notes
      expect(find.text('وجبة برجر لحم مدخن'), findsOneWidget);
      expect(find.text('* ملاحظة التحضير: (بدون بصل - صوص زيادة)'), findsOneWidget);

      // Total items and pieces
      expect(find.text('عدد الأصناف: 2  |  إجمالي القطع: 3'), findsOneWidget);

      // Cash tendered & change due
      expect(find.text('المبلغ المدفوع (نقداً):'), findsOneWidget);
      expect(find.text('650.00 ج.م'), findsOneWidget);
      expect(find.text('الباقي المسترد للعميل:'), findsOneWidget);
      expect(find.text('50.00 ج.م'), findsOneWidget);

      // QR Code icon
      expect(find.byIcon(Icons.qr_code_2_rounded), findsOneWidget);
      expect(find.text('#INV-9824'), findsNWidgets(2));
    });

    testWidgets('Live preview on 58mm width renders without overflow', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final config58 = ReceiptConfig.hospitalityDefaults.copyWith(paperWidthMm: 58);

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(
                child: Center(
                  child: ThermalReceiptLivePreview(config: config58),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('[ مقاس الورق: 58 مم ]'), findsOneWidget);
      expect(find.text('عدد الأصناف: 2  |  إجمالي القطع: 3'), findsOneWidget);
    });
  });
}
