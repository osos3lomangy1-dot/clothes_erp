import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/settings/presentation/cubits/settings_cubit.dart';
import 'package:clothes_erp/features/settings/presentation/screens/system_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

class _MockSettingsCubit extends Cubit<SettingsState> implements SettingsCubit {
  final Map<String, bool> _features;

  _MockSettingsCubit({Map<String, bool>? initialFeatures})
      : _features = initialFeatures ??
            {
              FeatureKeys.wholesalePricing: true,
              FeatureKeys.splitPayment: true,
              FeatureKeys.creditSales: true,
              FeatureKeys.holdBills: true,
              FeatureKeys.delivery: true,
              FeatureKeys.lowStockAlerts: true,
              FeatureKeys.productTimestamps: true,
              FeatureKeys.shifts: true,
              FeatureKeys.expenses: true,
              FeatureKeys.reports: true,
              FeatureKeys.managerPinProtection: true,
              FeatureKeys.installments: false,
              FeatureKeys.preOrders: false,
              FeatureKeys.consolidatedBatches: false,
              FeatureKeys.telegramBot: false,
              FeatureKeys.purchases: true,
              FeatureKeys.suppliers: true,
              FeatureKeys.employees: true,
              FeatureKeys.payroll: true,
            },
        super(SettingsState(
          features: initialFeatures ??
              {
                FeatureKeys.wholesalePricing: true,
                FeatureKeys.splitPayment: true,
                FeatureKeys.creditSales: true,
                FeatureKeys.holdBills: true,
                FeatureKeys.delivery: true,
                FeatureKeys.lowStockAlerts: true,
                FeatureKeys.productTimestamps: true,
                FeatureKeys.shifts: true,
                FeatureKeys.expenses: true,
                FeatureKeys.reports: true,
                FeatureKeys.managerPinProtection: true,
                FeatureKeys.installments: false,
                FeatureKeys.preOrders: false,
                FeatureKeys.consolidatedBatches: false,
                FeatureKeys.telegramBot: false,
                FeatureKeys.purchases: true,
                FeatureKeys.suppliers: true,
                FeatureKeys.employees: true,
                FeatureKeys.payroll: true,
              },
          isLoading: false,
        ));

  @override
  void start() {}

  @override
  Future<String?> toggleFeature(String key, bool enabled, String userId) async {
    _features[key] = enabled;
    emit(state.copyWith(features: Map.of(_features)));
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _FakeAuthCubit(UserModel user) : super(AuthAuthenticated(user));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Task 26: Master Modular Feature Hub, Presets Strip & Accordion Architecture', () {
    late UserModel adminUser;
    late _FakeAuthCubit authCubit;
    late _MockSettingsCubit settingsCubit;
    final getIt = GetIt.instance;

    setUp(() {
      adminUser = UserModel(
        id: 'u1',
        name: 'مدير النظام',
        email: 'admin@bay3ah.com',
        role: 'admin',
        isActive: true,
        createdAt: DateTime(2025, 1, 1),
      );
      authCubit = _FakeAuthCubit(adminUser);
      settingsCubit = _MockSettingsCubit();

      getIt.registerSingleton<SettingsCubit>(settingsCubit);
      getIt.registerSingleton<AuthCubit>(authCubit);
    });

    tearDown(() async {
      await getIt.reset();
    });

    Widget buildTestScreen() {
      return MaterialApp(
        theme: ThemeData(fontFamily: 'Cairo'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: MultiBlocProvider(
            providers: [
              BlocProvider<AuthCubit>.value(value: authCubit),
              BlocProvider<SettingsCubit>.value(value: settingsCubit),
            ],
            child: const SystemSettingsScreen(),
          ),
        ),
      );
    }

    testWidgets('1. Quick Industry Presets strip renders 4 cards and highlights matching preset', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      // Verify all 4 preset cards exist
      expect(find.byKey(const Key('preset_card_boutique')), findsOneWidget);
      expect(find.byKey(const Key('preset_card_wholesale')), findsOneWidget);
      expect(find.byKey(const Key('preset_card_home_appliances')), findsOneWidget);
      expect(find.byKey(const Key('preset_card_minimal_pos')), findsOneWidget);

      // In our setup, boutique preset is active
      expect(find.text('متجر ملابس وأزياء'), findsOneWidget);
      expect(find.text('تجارة جملة وتوزيع'), findsOneWidget);
      expect(find.text('مفروشات وأجهزة منزلية'), findsOneWidget);
      expect(find.text('كاشير سريع ومبسط'), findsOneWidget);
      expect(find.text('مطبق حالياً'), findsOneWidget);
    });

    testWidgets('2. Tapping an inactive preset opens confirmation dialog and applies features on confirm', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      // Tap Minimalist POS preset card
      await tester.tap(find.byKey(const Key('preset_card_minimal_pos')));
      await tester.pumpAndSettle();

      // Verify confirmation dialog opened
      expect(find.text('تطبيق نمط "كاشير سريع ومبسط"'), findsOneWidget);
      expect(find.byKey(const Key('confirm_apply_preset_btn')), findsOneWidget);

      // Confirm
      await tester.tap(find.byKey(const Key('confirm_apply_preset_btn')));
      await tester.pumpAndSettle();

      // Verify features updated in cubit (minimal pos sets wholesalePricing to false)
      expect(settingsCubit.state.features[FeatureKeys.wholesalePricing], isFalse);
      expect(settingsCubit.state.features[FeatureKeys.delivery], isFalse);

      // Verify floating toast / SnackBar appears
      expect(find.text('تم تطبيق نمط "كاشير سريع ومبسط" بنجاح'), findsOneWidget);
    });

    testWidgets('3. 5 Collapsible Master Modules are present with dynamic enabled count badges', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      // Verify 5 module headers exist
      expect(find.byKey(const Key('module_header_0')), findsOneWidget);
      expect(find.byKey(const Key('module_header_1')), findsOneWidget);
      expect(find.byKey(const Key('module_header_2')), findsOneWidget);
      expect(find.byKey(const Key('module_header_3')), findsOneWidget);
      expect(find.byKey(const Key('module_header_4')), findsOneWidget);

      // Module titles
      expect(find.text('المبيعات ونقطة البيع والعملاء'), findsOneWidget);
      expect(find.text('المخازن والتوريد والتسعير'), findsOneWidget);
      expect(find.text('التوصيل والدليفري والتجارة الحديثة'), findsOneWidget);
      expect(find.text('الخزينة والمالية والورديات'), findsOneWidget);
      expect(find.text('فريق العمل والأمان والرقابة'), findsOneWidget);

      // Module 0 is open by default: should find items inside module 0
      expect(find.byKey(const Key('feature_wholesale_pricing_toggle')), findsOneWidget);
      expect(find.byKey(const Key('feature_split_payment_toggle')), findsOneWidget);
      expect(find.byKey(const Key('feature_credit_sales_toggle')), findsOneWidget);
      expect(find.byKey(const Key('feature_hold_bills_toggle')), findsOneWidget);

      // Module 2 is collapsed by default: delivery toggle is not in the tree
      expect(find.byKey(const Key('feature_delivery_toggle')), findsNothing);
    });

    testWidgets('4. Accordion collapse and expand works interactively', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      // Module 0 is open. Tap header to collapse it.
      await tester.tap(find.byKey(const Key('module_header_0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('feature_wholesale_pricing_toggle')), findsNothing);

      // Tap Module 0 again to re-expand it.
      await tester.tap(find.byKey(const Key('module_header_0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('feature_wholesale_pricing_toggle')), findsOneWidget);

      // Collapse Module 0 so Module 1 moves into view
      await tester.tap(find.byKey(const Key('module_header_0')));
      await tester.pumpAndSettle();

      // Tap Module 1 header to expand inventory
      await tester.tap(find.byKey(const Key('module_header_1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('feature_purchases_toggle')), findsOneWidget);
      expect(find.byKey(const Key('feature_suppliers_toggle')), findsOneWidget);
    });

    testWidgets('5. Direct status anchors (مفعّل / معطل / أساسي مفعّل) render next to switches', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      // Inside open Module 0:
      // Status badges should be rendered
      expect(find.text('مفعّل'), findsWidgets);
      expect(find.text('معطل'), findsWidgets);
      expect(find.text('أساسي مفعّل'), findsWidgets);
    });

    testWidgets('6. Live feature search filters features and shows module breadcrumb path', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      // Enter search query
      final searchField = find.byKey(const Key('settings_search_field'));
      expect(searchField, findsOneWidget);

      await tester.enterText(searchField, 'الدفع المجزأ');
      await tester.pumpAndSettle();

      // Presets strip and accordion headers are hidden in search results
      expect(find.byKey(const Key('preset_card_boutique')), findsNothing);
      expect(find.byKey(const Key('module_header_0')), findsNothing);

      // Live search results are visible with breadcrumb
      expect(find.byKey(const Key('settings_search_results_list')), findsOneWidget);
      expect(find.text('المبيعات ونقطة البيع والعملاء > الدفع المجزأ'), findsOneWidget);

      // Clear search button restores main modular view
      await tester.tap(find.byKey(const Key('settings_clear_search_btn')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('preset_card_boutique')), findsOneWidget);
      expect(find.byKey(const Key('module_header_0')), findsOneWidget);
    });

    testWidgets('7. Non-matching search query displays elegant empty state with clear button', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      final searchField = find.byKey(const Key('settings_search_field'));
      await tester.enterText(searchField, 'كلمة غير موجودة بتاتاً');
      await tester.pumpAndSettle();

      expect(find.text('لا توجد إعدادات أو ميزات مطابقة لـ "كلمة غير موجودة بتاتاً"'), findsOneWidget);
      expect(find.byIcon(Icons.search_off_rounded), findsOneWidget);
    });
  });
}
