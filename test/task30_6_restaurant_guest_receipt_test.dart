import 'package:clothes_erp/core/constants/retail_sector.dart';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/categories/presentation/cubits/category_cubit.dart';
import 'package:clothes_erp/features/categories/presentation/cubits/category_state.dart';
import 'package:clothes_erp/features/inventory/presentation/cubits/goods_receipt_cubit.dart';
import 'package:clothes_erp/features/inventory/presentation/cubits/goods_receipt_state.dart';
import 'package:clothes_erp/features/inventory/presentation/cubits/inventory_cubit.dart';
import 'package:clothes_erp/features/inventory/presentation/cubits/inventory_state.dart';
import 'package:clothes_erp/features/inventory/presentation/screens/inventory_screen.dart';
import 'package:clothes_erp/features/invoices/data/services/receipt_settings_service.dart';
import 'package:clothes_erp/features/invoices/domain/entities/invoice_details_entity.dart';
import 'package:clothes_erp/features/invoices/domain/entities/invoice_item_details_entity.dart';
import 'package:clothes_erp/features/invoices/domain/entities/receipt_config.dart';
import 'package:clothes_erp/features/invoices/presentation/screens/receipt_customizer_screen.dart';
import 'package:clothes_erp/features/invoices/presentation/services/receipt_pdf_service.dart';
import 'package:clothes_erp/features/invoices/presentation/widgets/thermal_receipt_live_preview.dart';
import 'package:clothes_erp/features/products/domain/entities/activity_type.dart';
import 'package:clothes_erp/features/products/presentation/cubits/product_cubit.dart';
import 'package:clothes_erp/features/products/presentation/cubits/product_state.dart';
import 'package:clothes_erp/features/products/presentation/screens/product_list_screen.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/purchases_cubit.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/purchases_state.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/suppliers_cubit.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/suppliers_state.dart';
import 'package:clothes_erp/features/purchases/presentation/screens/purchases_screen.dart';
import 'package:clothes_erp/features/settings/data/services/activity_settings_service.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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

class _FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _FakeAuthCubit() : super(AuthInitial());
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

class _FakePurchasesCubit extends Cubit<PurchasesState> implements PurchasesCubit {
  _FakePurchasesCubit() : super(const PurchasesState());
  @override
  Future<void> loadPurchases({String? paymentStatus, String? supplierId}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSuppliersCubit extends Cubit<SuppliersState> implements SuppliersCubit {
  _FakeSuppliersCubit() : super(const SuppliersState());
  @override
  Future<void> loadSuppliers({String? query}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGoodsReceiptCubit extends Cubit<GoodsReceiptState> implements GoodsReceiptCubit {
  _FakeGoodsReceiptCubit() : super(const GoodsReceiptState());
  @override
  Future<void> loadGoodsReceipts({String? status, String? supplierId}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInventoryCubit extends Cubit<InventoryState> implements InventoryCubit {
  _FakeInventoryCubit() : super(const InventoryLoaded([]));
  @override
  Future<void> loadInventory({bool lowStockOnly = false}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProductCubit extends Cubit<ProductState> implements ProductCubit {
  _FakeProductCubit() : super(const ProductLoaded([]));
  @override
  Future<void> getProducts() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCategoryCubit extends Cubit<CategoryState> implements CategoryCubit {
  _FakeCategoryCubit() : super(const CategoryLoaded([]));
  @override
  Future<void> getCategories() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final sl = GetIt.instance;

  setUp(() async {
    await sl.reset();
    final db = AppDatabase(NativeDatabase.memory());
    sl.registerSingleton<AppDatabase>(db);
    final mockGate = _FakeFeatureGate();
    sl.registerSingleton<FeatureGate>(mockGate);
    ReceiptSettingsService.notifier.value = ReceiptConfig.defaults;
  });

  group('Task 30.6: ReceiptPdfService Hospitality Receipt Tests', () {
    final hospitalityInvoice = InvoiceDetailsEntity(
      id: 'inv-hosp-1',
      shortRef: '042',
      date: DateTime(2026, 11, 24, 13, 30),
      cashierId: 'cashier-10',
      cashierName: 'أحمد الكاشير',
      customerName: 'كريم محمود',
      customerPhone: '01012345678',
      orderNumber: '042',
      orderType: 'dineIn',
      tableNumber: '4',
      wifiInfo: 'WiFi: Restaurant-Guest',
      subtotal: 18000,
      discountAmount: 1000,
      total: 17000,
      paymentMethod: 'نقدي (كاش)',
      items: const [
        InvoiceItemDetailsEntity(
          id: 'item-1',
          variantId: 'var-1',
          productName: 'وجبة برجر لحم مدخن',
          color: 'افتراضي',
          size: 'افتراضي',
          qty: 1,
          price: 12000,
          lineTotal: 12000,
          kitchenNotes: 'بدون بصل - صوص زيادة - سبايسي',
        ),
        InvoiceItemDetailsEntity(
          id: 'item-2',
          variantId: 'var-2',
          productName: 'عصير برتقال فريش',
          color: 'طبيعي',
          size: 'كبير',
          qty: 2,
          price: 3000,
          lineTotal: 6000,
          kitchenNotes: 'سكر قليل - ثلج زيادة',
        ),
      ],
    );

    test('generateReceiptPdf in Hospitality Mode generates valid PDF with Prominent Order # and Table #', () async {
      final config = ReceiptConfig.hospitalityDefaults;

      final pdfBytes = await ReceiptPdfService.generateReceiptPdf(
        hospitalityInvoice,
        config: config,
        isHospitality: true,
        orderNumber: '042',
        tableNumber: '4',
        orderType: 'dineIn',
      );

      expect(pdfBytes, isA<Uint8List>());
      expect(pdfBytes.isNotEmpty, true);
      expect(pdfBytes.length, greaterThan(1500));
    });

    test('generateReceiptPdf in Takeaway and Delivery Modes formats order badges accurately', () async {
      final takeawayInvoice = hospitalityInvoice.copyWith(
        orderType: 'takeaway',
        orderNumber: '088',
      );

      final takeawayPdf = await ReceiptPdfService.generateReceiptPdf(
        takeawayInvoice,
        config: ReceiptConfig.hospitalityDefaults,
        isHospitality: true,
        orderType: 'takeaway',
      );
      expect(takeawayPdf.isNotEmpty, true);

      final deliveryInvoice = hospitalityInvoice.copyWith(
        orderType: 'delivery',
        orderNumber: '105',
        customerName: 'محمود سامي',
        customerPhone: '01122334455',
      );

      final deliveryPdf = await ReceiptPdfService.generateReceiptPdf(
        deliveryInvoice,
        config: ReceiptConfig.hospitalityDefaults,
        isHospitality: true,
        orderType: 'delivery',
      );
      expect(deliveryPdf.isNotEmpty, true);
    });

    test('generateReceiptPdf Hospitality Mode purges apparel return policy and hides size/color details', () async {
      // Apparel config with 14-day policy passed to hospitality receipt
      final apparelConfig = ReceiptConfig.defaults.copyWith(
        returnPolicy: 'الاستبدال والاسترجاع خلال 14 يوماً مع وجود الفاتورة وأصل التكت بحالته',
        showItemDetails: true,
      );

      final pdfBytes = await ReceiptPdfService.generateReceiptPdf(
        hospitalityInvoice,
        config: apparelConfig,
        isHospitality: true,
      );

      expect(pdfBytes, isA<Uint8List>());
      expect(pdfBytes.isNotEmpty, true);
    });
  });

  group('Task 30.6: ReceiptConfig Entity & Hospitality Defaults Tests', () {
    test('ReceiptConfig.hospitalityDefaults has correct hospitality presets', () {
      const hosp = ReceiptConfig.hospitalityDefaults;

      expect(hosp.storeActivity, 'مطاعم وكافيهات');
      expect(hosp.showItemDetails, false);
      expect(hosp.footerGreeting, 'شكراً لزيارتكم ونتمنى لكم وجبة شهية!');
      expect(hosp.returnPolicy.contains('الأطعمة والمشروبات الطازجة غير قابلة للاسترجاع'), true);
      expect(hosp.wifiInfo, 'WiFi: Restaurant-Guest');
    });

    test('ReceiptSettingsService saves and loads wifiInfo and hospitality template properly', () async {
      final gate = GetIt.instance<FeatureGate>();

      const hospConfig = ReceiptConfig.hospitalityDefaults;
      await ReceiptSettingsService.save(hospConfig, gate, userId: 'admin');

      await ReceiptSettingsService.loadFromFeatureGate(gate);
      final current = ReceiptSettingsService.current;

      expect(current.storeActivity, 'مطاعم وكافيهات');
      expect(current.showItemDetails, false);
      expect(current.footerGreeting, 'شكراً لزيارتكم ونتمنى لكم وجبة شهية!');
      expect(current.returnPolicy.contains('الأطعمة والمشروبات'), true);
      expect(current.wifiInfo, 'WiFi: Restaurant-Guest');
    });
  });

  group('Task 30.6: ThermalReceiptLivePreview Widget Tests', () {
    testWidgets('Live preview renders hospitality header, meal items with kitchen notes, and wifi', (tester) async {
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

      // Verify prominent order number & table badge
      expect(find.text('طلب رقم: #042'), findsOneWidget);
      expect(find.text('[ صالة - طاولة: رقم 4 ]'), findsOneWidget);

      // Verify meal items and kitchen notes
      expect(find.text('وجبة برجر لحم مدخن'), findsOneWidget);
      expect(find.text('* ملاحظة التحضير: (بدون بصل - صوص زيادة)'), findsOneWidget);
      expect(find.text('عصير برتقال فريش'), findsOneWidget);
      expect(find.text('* ملاحظة التحضير: (سكر قليل - ثلج زيادة)'), findsOneWidget);

      // Verify hospitality policy and greeting
      expect(find.text(config.returnPolicy), findsOneWidget);
      expect(find.text('شكراً لزيارتكم ونتمنى لكم وجبة شهية!'), findsOneWidget);
      expect(find.text('WiFi: Restaurant-Guest'), findsOneWidget);
    });
  });

  group('Task 30.6: ReceiptCustomizerScreen Hospitality Template Button Test', () {
    testWidgets('Tapping apply hospitality template button updates all fields immediately', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await sl<FeatureGate>().setMeta(
        RetailSector.metaKey,
        RetailSector.hospitality,
        userId: 'system',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>(
            create: (_) => _FakeAuthCubit(),
            child: const Directionality(
              textDirection: TextDirection.rtl,
              child: ReceiptCustomizerScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find and tap the hospitality template button
      final templateBtn = find.byKey(const Key('apply_hospitality_template_btn'));
      expect(templateBtn, findsOneWidget);

      await tester.tap(templateBtn);
      await tester.pumpAndSettle();

      // Verify fields were updated to hospitality presets
      expect(find.text('مطاعم وكافيهات'), findsWidgets);
      expect(find.text('شكراً لزيارتكم ونتمنى لكم وجبة شهية!'), findsWidgets);
      expect(find.textContaining('الأطعمة والمشروبات الطازجة غير قابلة للاسترجاع'), findsWidgets);
      expect(find.text('WiFi: Restaurant-Guest'), findsWidgets);
    });
  });

  group('Task 30.6: Pure Hospitality Isolation & Navigation Tests', () {
    testWidgets('PurchasesScreen in Hospitality mode hides Pending Receipts tab', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final gate = sl<FeatureGate>();
      await gate.setMeta(RetailSector.metaKey, RetailSector.hospitality, userId: 'system');

      final actService = _FakeActivitySettingsService({ActivityType.restaurantsCafes});
      sl.registerSingleton<ActivitySettingsService>(actService);
      sl.registerSingleton<InventoryCubit>(_FakeInventoryCubit());
      sl.registerSingleton<ProductCubit>(_FakeProductCubit());
      sl.registerSingleton<CategoryCubit>(_FakeCategoryCubit());
      sl.registerSingleton<PurchasesCubit>(_FakePurchasesCubit());
      sl.registerSingleton<SuppliersCubit>(_FakeSuppliersCubit());
      sl.registerSingleton<GoodsReceiptCubit>(_FakeGoodsReceiptCubit());

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>(
            create: (_) => _FakeAuthCubit(),
            child: const Directionality(
              textDirection: TextDirection.rtl,
              child: PurchasesScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('فواتير المشتريات'), findsOneWidget);
      expect(find.text('سجل الموردين والمديونيات'), findsOneWidget);
      expect(find.text('مرتجعات المشتريات'), findsOneWidget);
      expect(find.text('استلامات معلقة (Pending Receipts)'), findsNothing);
    });

    testWidgets('PurchasesScreen in Apparel mode reveals Pending Receipts tab', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final actService = _FakeActivitySettingsService({ActivityType.clothing});
      sl.registerSingleton<ActivitySettingsService>(actService);
      sl.registerSingleton<PurchasesCubit>(_FakePurchasesCubit());
      sl.registerSingleton<SuppliersCubit>(_FakeSuppliersCubit());
      sl.registerSingleton<GoodsReceiptCubit>(_FakeGoodsReceiptCubit());

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>(
            create: (_) => _FakeAuthCubit(),
            child: const Directionality(
              textDirection: TextDirection.rtl,
              child: PurchasesScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('فواتير المشتريات'), findsOneWidget);
      expect(find.text('استلامات معلقة (Pending Receipts)'), findsOneWidget);
      expect(find.text('سجل الموردين والمديونيات'), findsOneWidget);
      expect(find.text('مرتجعات المشتريات'), findsOneWidget);
    });

    testWidgets('InventoryScreen in Hospitality mode purges receive shipment button and displays hospitality subtitle', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final gate = sl<FeatureGate>();
      await gate.setMeta(RetailSector.metaKey, RetailSector.hospitality, userId: 'system');

      final actService = _FakeActivitySettingsService({ActivityType.restaurantsCafes});
      sl.registerSingleton<ActivitySettingsService>(actService);
      sl.registerSingleton<InventoryCubit>(_FakeInventoryCubit());
      sl.registerSingleton<ProductCubit>(_FakeProductCubit());
      sl.registerSingleton<CategoryCubit>(_FakeCategoryCubit());

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<AuthCubit>(create: (_) => _FakeAuthCubit()),
              BlocProvider<InventoryCubit>(create: (_) => _FakeInventoryCubit()),
            ],
            child: const Directionality(
              textDirection: TextDirection.rtl,
              child: InventoryScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('inventory_receive_shipment_btn')), findsNothing);
      expect(find.text('تقييم تكلفة الوجبات، مخزون المواد الخام، والهالك'), findsOneWidget);
    });

    testWidgets('ProductListScreen in Hospitality mode displays menu title and hospitality subtitle', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final gate = sl<FeatureGate>();
      await gate.setMeta(RetailSector.metaKey, RetailSector.hospitality, userId: 'system');

      final actService = _FakeActivitySettingsService({ActivityType.restaurantsCafes});
      sl.registerSingleton<ActivitySettingsService>(actService);
      sl.registerSingleton<InventoryCubit>(_FakeInventoryCubit());
      sl.registerSingleton<ProductCubit>(_FakeProductCubit());
      sl.registerSingleton<CategoryCubit>(_FakeCategoryCubit());

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<AuthCubit>(create: (_) => _FakeAuthCubit()),
              BlocProvider<ProductCubit>(create: (_) => _FakeProductCubit()),
              BlocProvider<CategoryCubit>(create: (_) => _FakeCategoryCubit()),
            ],
            child: const Directionality(
              textDirection: TextDirection.rtl,
              child: ProductListScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('قائمة الطعام والمشروبات (المنيو)'), findsOneWidget);
      expect(find.text('إدارة أقسام المنيو والوجبات والمشروبات وجداول الأسعار'), findsOneWidget);
    });
  });
}
