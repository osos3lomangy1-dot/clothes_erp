import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/services/hotkey_strip_service.dart';
import 'package:clothes_erp/core/services/shortcut_settings_service.dart';
import 'package:clothes_erp/core/theme/app_branding.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/domain/models/cashier_permissions_config.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/auth/services/cashier_permissions_service.dart';
import 'package:clothes_erp/features/categories/domain/entities/category_entity.dart';
import 'package:clothes_erp/features/categories/domain/repositories/category_repository.dart';
import 'package:clothes_erp/features/pos/domain/entities/sale_item_entity.dart';
import 'package:clothes_erp/features/pos/domain/repositories/pos_repository.dart';
import 'package:clothes_erp/features/pos/domain/services/kitchen_order_ticket_service.dart';
import 'package:clothes_erp/features/pos/domain/usecases/create_sale_usecase.dart';
import 'package:clothes_erp/features/pos/presentation/cubits/pos_cubit.dart';
import 'package:clothes_erp/features/pos/presentation/screens/pos_screen.dart';
import 'package:clothes_erp/features/product_variants/domain/entities/variant_entity.dart';
import 'package:clothes_erp/features/product_variants/domain/repositories/variant_repository.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/products/domain/repositories/product_repository.dart';
import 'package:clothes_erp/features/settings/data/services/activity_settings_service.dart';
import 'package:clothes_erp/features/shifts/presentation/cubits/shift_cubit.dart';
import 'package:clothes_erp/features/shifts/presentation/cubits/shift_state.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

class _FakeBranchProvider implements BranchProvider {
  @override
  Future<String> getBranchId() async => 'branch-1';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthLocalDataSource implements AuthLocalDataSource {
  UserModel? _cached;
  @override
  Future<void> cacheUser(UserModel user) async => _cached = user;
  @override
  Future<UserModel?> getCachedUser() async => _cached;
  @override
  Future<void> clearCache() async => _cached = null;
}

class _FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _FakeAuthCubit(UserModel user) : super(AuthAuthenticated(user));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVariantRepo implements VariantRepository {
  @override
  Stream<Either<Failure, List<VariantEntity>>> watchAllVariants() =>
      Stream.value(const Right([]));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProductRepo implements ProductRepository {
  @override
  Stream<Either<Failure, List<ProductEntity>>> watchAllProducts() =>
      Stream.value(const Right([]));
  @override
  Future<Either<Failure, List<ProductEntity>>> getProducts() async =>
      const Right([]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCategoryRepo implements CategoryRepository {
  @override
  Future<Either<Failure, List<CategoryEntity>>> getCategories() async =>
      const Right([]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePosRepo implements PosRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCreateSaleUseCase implements CreateSaleUseCase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeShiftCubit extends Cubit<ShiftState> implements ShiftCubit {
  _FakeShiftCubit()
      : super(const ShiftState(shiftsEnabled: false, status: ShiftStatus.loaded));
  @override
  Future<void> loadShiftData() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FeatureGate featureGate;
  late ShortcutSettingsService shortcutService;
  late ActivitySettingsService activityService;
  late AuthLocalDataSource authLocalDs;
  late AuthCubit authCubit;

  setUp(() async {
    final sl = GetIt.instance;
    await sl.reset();

    db = AppDatabase(NativeDatabase.memory());
    authLocalDs = _FakeAuthLocalDataSource();
    final branchProvider = _FakeBranchProvider();
    final txWriter = TxWriter(db);

    featureGate = FeatureGate(db, authLocalDs, txWriter, branchProvider);
    shortcutService = ShortcutSettingsService(db);
    activityService = ActivitySettingsService(db, featureGate);

    final adminUser = UserModel(
      id: 'admin_1',
      name: 'مدير المطعم',
      email: 'admin@test.com',
      role: 'admin',
      isActive: true,
      createdAt: DateTime.now(),
    );
    await authLocalDs.cacheUser(adminUser);
    authCubit = _FakeAuthCubit(adminUser);

    sl.registerSingleton<AppDatabase>(db);
    sl.registerSingleton<FeatureGate>(featureGate);
    sl.registerSingleton<ShortcutSettingsService>(shortcutService);
    sl.registerSingleton<ActivitySettingsService>(activityService);
    sl.registerSingleton<AuthCubit>(authCubit);

    sl.registerFactory<PosCubit>(() => PosCubit(
          _FakeCreateSaleUseCase(),
          _FakeVariantRepo(),
          _FakeCategoryRepo(),
          _FakeProductRepo(),
          _FakePosRepo(),
        ));
    sl.registerFactory<ShiftCubit>(() => _FakeShiftCubit());

    AppBranding.apply(AppBrandingConfig.defaults);
    CashierPermissionsService.notifier.value = const CashierPermissionsConfig();
    HotkeyStripService.isVisible.value = true;
  });

  tearDown(() async {
    await authCubit.close();
    await db.close();
    await GetIt.instance.reset();
  });

  group('Task 30: Hospitality & Kitchen Notes Model & Financial Integrity', () {
    test('SaleItemEntity supports kitchenNotes and modifiers without altering total calculation', () {
      const item = SaleItemEntity(
        variantId: 'meal_1',
        productName: 'وجبة برجر دبل',
        size: 'L',
        color: '-',
        price: 8500, // 85.00
        quantity: 2,
        discount: 500, // 5.00
        promotionDiscount: 500, // 5.00
        kitchenNotes: 'بدون بصل - سبايسي',
        modifiers: ['بدون بصل', 'سبايسي'],
      );

      // (8500 * 2) - 500 - 500 = 16000
      expect(item.total, equals(16000));
      expect(item.kitchenNotes, equals('بدون بصل - سبايسي'));
      expect(item.modifiers, equals(['بدون بصل', 'سبايسي']));

      // Updating notes via copyWith must keep financial total unchanged
      final updated = item.copyWith(
        kitchenNotes: 'بدون مخلل - زيادة جبنة',
        modifiers: ['بدون مخلل', 'زيادة جبنة'],
      );
      expect(updated.total, equals(16000));
      expect(updated.kitchenNotes, equals('بدون مخلل - زيادة جبنة'));

      // Clearing notes
      final cleared = updated.copyWith(clearKitchenNotes: true, modifiers: const []);
      expect(cleared.kitchenNotes, isNull);
      expect(cleared.modifiers, isEmpty);
      expect(cleared.total, equals(16000));
    });

    test('KitchenOrderTicketService generates pure operational ticket with zero prices or currency symbols', () {
      final items = [
        const SaleItemEntity(
          variantId: 'v1',
          productName: 'برجر لحم مشوي',
          size: '-',
          color: '-',
          price: 9000,
          quantity: 2,
          kitchenNotes: 'بدون بصل - زيادة صوص',
        ),
        const SaleItemEntity(
          variantId: 'v2',
          productName: 'عصير برتقال فريش',
          size: '-',
          color: '-',
          price: 3500,
          quantity: 1,
          kitchenNotes: 'بدون ثلج - سكر خفيف',
        ),
      ];

      final ticket = KitchenOrderTicketService.generateKitchenOrderTicket(
        orderType: 'dineIn',
        tableNumber: '7',
        invoiceNumber: 'KOT-1042',
        date: DateTime(2026, 11, 23, 15, 30),
        items: items,
        cashierName: 'أحمد سعيد',
      );

      // Contains header and table info
      expect(ticket, contains('بون تحضير المطبخ (KOT)'));
      expect(ticket, contains('صالة (طاولة: 7)'));
      expect(ticket, contains('KOT-1042'));
      expect(ticket, contains('أحمد سعيد'));

      // Contains items and exceptions
      expect(ticket, contains('2 x ] برجر لحم مشوي'));
      expect(ticket, contains('استثناءات: بدون بصل - زيادة صوص'));
      expect(ticket, contains('1 x ] عصير برتقال فريش'));
      expect(ticket, contains('استثناءات: بدون ثلج - سكر خفيف'));

      // Strictly zero financial mentions
      expect(ticket.contains('ج.م'), isFalse);
      expect(ticket.contains('جنيه'), isFalse);
      expect(ticket.contains('سعر'), isFalse);
      expect(ticket.contains('إجمالي'), isFalse);
      expect(ticket.contains('خصم'), isFalse);
    });

    test('PosCubit.updateKitchenNotes updates notes and modifiers in cart state', () {
      final posCubit = GetIt.instance<PosCubit>();
      final variant = VariantEntity(
        id: 'var_food_1',
        productId: 'prod_food_1',
        productCode: 'MEAL-001',
        productName: 'بيتزا سوبريم',
        size: 'عائلي',
        color: '-',
        salePrice: 12000,
        costPrice: 6000,
        quantity: 50,
        minStock: 5,
        createdAt: DateTime.now(),
      );

      posCubit.addToCart(variant, 1);
      expect(posCubit.state.cart.first.kitchenNotes, isNull);

      // Add kitchen notes
      posCubit.updateKitchenNotes(
        variant.id,
        'بدون مشروم - زيادة جبنة',
        modifiers: ['بدون مشروم', 'زيادة جبنة'],
      );
      expect(posCubit.state.cart.first.kitchenNotes, equals('بدون مشروم - زيادة جبنة'));
      expect(posCubit.state.cart.first.modifiers, equals(['بدون مشروم', 'زيادة جبنة']));

      // Clear kitchen notes
      posCubit.updateKitchenNotes(variant.id, null);
      expect(posCubit.state.cart.first.kitchenNotes, isNull);
    });
  });

  group('Task 30: UI Kitchen Exceptions, Table Management & Strict Sector Encapsulation', () {
    testWidgets('When restaurantsCafes is enabled: shows table selector, kitchen notes button, and allows selecting modifier pills', (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Enable restaurantsCafes activity in database
      await db.into(db.appMeta).insertOnConflictUpdate(
        AppMetaCompanion.insert(
          key: 'activity.restaurantsCafes',
          value: '1',
          updatedAt: DateTime.now(),
        ),
      );
      await activityService.getEnabledActivities();

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<AuthCubit>.value(value: authCubit),
                BlocProvider<ShiftCubit>.value(value: _FakeShiftCubit()),
              ],
              child: const PosScreen(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Table selector and KOT print button are visible
      expect(find.byKey(const Key('hospitality_dine_in')), findsOneWidget);
      expect(find.byKey(const Key('hospitality_table_selector')), findsOneWidget);
      expect(find.byKey(const Key('print_kot_button')), findsOneWidget);

      final posCubit = tester.element(find.byType(Scaffold)).read<PosCubit>();
      final variant = VariantEntity(
        id: 'var_food_ui_1',
        productId: 'prod_food_ui_1',
        productCode: 'BURGER-DBL',
        productName: 'ساندوتش برجر دبل',
        size: 'L',
        color: '-',
        salePrice: 9500,
        costPrice: 5000,
        quantity: 30,
        minStock: 5,
        createdAt: DateTime.now(),
      );
      posCubit.addToCart(variant, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Kitchen notes button is present next to food item in cart
      final kitchenNotesBtn = find.byKey(const Key('kitchen_notes_btn_var_food_ui_1'));
      expect(kitchenNotesBtn, findsOneWidget);

      // Open kitchen notes dialog
      await tester.tap(kitchenNotesBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('kitchen_notes_dialog')), findsOneWidget);

      // Select modifier pills: [ بدون بيض ] and [ سبايسي ]
      final pillNoEgg = find.byKey(const Key('modifier_pill_بدون بيض'));
      final pillSpicy = find.byKey(const Key('modifier_pill_سبايسي'));
      expect(pillNoEgg, findsOneWidget);
      expect(pillSpicy, findsOneWidget);

      await tester.tap(pillNoEgg);
      await tester.pump();
      await tester.tap(pillSpicy);
      await tester.pump();

      // Confirm note
      await tester.tap(find.byKey(const Key('confirm_kitchen_notes_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Note text appears in cart below item
      final notesTextFinder = find.byKey(const Key('kitchen_notes_text_var_food_ui_1'));
      expect(notesTextFinder, findsOneWidget);
      expect(tester.widget<Text>(notesTextFinder).data, contains('بدون بيض'));

      // Clear note using the quick clear button
      final clearBtn = find.byKey(const Key('clear_kitchen_notes_var_food_ui_1'));
      expect(clearBtn, findsOneWidget);
      await tester.tap(clearBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const Key('kitchen_notes_text_var_food_ui_1')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('Table Selector allows changing table number and stores it in state', (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await db.into(db.appMeta).insertOnConflictUpdate(
        AppMetaCompanion.insert(
          key: 'activity.restaurantsCafes',
          value: '1',
          updatedAt: DateTime.now(),
        ),
      );
      await activityService.getEnabledActivities();

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<AuthCubit>.value(value: authCubit),
                BlocProvider<ShiftCubit>.value(value: _FakeShiftCubit()),
              ],
              child: const PosScreen(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Initial table is table 1
      expect(find.text('طاولة: رقم 1'), findsOneWidget);

      // Tap table selector to open dialog
      await tester.tap(find.byKey(const Key('hospitality_table_selector')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('table_selector_dialog')), findsOneWidget);

      // Select table 5
      await tester.tap(find.byKey(const Key('table_chip_5')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('confirm_table_number_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Table selector now shows table 5
      expect(find.text('طاولة: رقم 5'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('Strict Sector Encapsulation: Non-hospitality mode (clothing only) completely hides all hospitality tools', (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Set only clothing to true, disable restaurantsCafes
      await db.into(db.appMeta).insertOnConflictUpdate(
        AppMetaCompanion.insert(
          key: 'activity.restaurantsCafes',
          value: '0',
          updatedAt: DateTime.now(),
        ),
      );
      await db.into(db.appMeta).insertOnConflictUpdate(
        AppMetaCompanion.insert(
          key: 'activity.clothing',
          value: '1',
          updatedAt: DateTime.now(),
        ),
      );
      await activityService.getEnabledActivities();

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<AuthCubit>.value(value: authCubit),
                BlocProvider<ShiftCubit>.value(value: _FakeShiftCubit()),
              ],
              child: const PosScreen(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Hospitality order type bar, table selector, and KOT print button must NOT be present
      expect(find.byKey(const Key('hospitality_dine_in')), findsNothing);
      expect(find.byKey(const Key('hospitality_table_selector')), findsNothing);
      expect(find.byKey(const Key('print_kot_button')), findsNothing);

      // Add a clothing item to cart
      final posCubit = tester.element(find.byType(Scaffold)).read<PosCubit>();
      final shirtVariant = VariantEntity(
        id: 'var_clothing_1',
        productId: 'prod_clothing_1',
        productCode: 'SHIRT-BLU',
        productName: 'قميص أكسفورد أزرق',
        size: 'XL',
        color: 'أزرق',
        salePrice: 15000,
        costPrice: 8000,
        quantity: 20,
        minStock: 5,
        createdAt: DateTime.now(),
      );
      posCubit.addToCart(shirtVariant, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Kitchen notes button must NOT appear on fashion item
      expect(find.byKey(const Key('kitchen_notes_btn_var_clothing_1')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
