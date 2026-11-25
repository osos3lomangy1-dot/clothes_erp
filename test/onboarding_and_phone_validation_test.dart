import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/di/injection.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/utils/phone_validator.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/dashboard/domain/entities/dashboard_stats_entity.dart';
import 'package:clothes_erp/features/dashboard/presentation/cubits/dashboard_cubit.dart';
import 'package:clothes_erp/features/dashboard/presentation/cubits/dashboard_state.dart';
import 'package:clothes_erp/features/dashboard/presentation/screens/admin_dashboard_screen.dart';
import 'package:clothes_erp/features/onboarding/presentation/screens/first_launch_setup_screen.dart';

class _FakeFeatureGate implements FeatureGate {
  @override
  Stream<Map<String, bool>> watchFeatures() => Stream.value(const {
        FeatureKeys.installments: false,
        FeatureKeys.suppliers: true,
      });

  @override
  Stream<String?> watchMeta(String key) => Stream.value(null);

  @override
  Future<bool> isEnabled(String key) async => false;

  @override
  Future<Map<String, bool>> getFeatures() async => const {};

  @override
  Future<String?> getMeta(String key) async => null;

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubDashboardCubit extends Cubit<DashboardState> implements DashboardCubit {
  _StubDashboardCubit()
      : super(
          const DashboardState(
            status: DashboardStatus.success,
            stats: DashboardStatsEntity(),
          ),
        );

  @override
  Future<void> loadStats({bool silent = false}) async {}
}

class _StubAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _StubAuthCubit()
      : super(
          AuthAuthenticated(
            UserModel(
              id: 'admin',
              name: 'المدير العام',
              email: 'admin@store.local',
              role: 'admin',
              isActive: true,
              createdAt: DateTime(2026),
            ),
          ),
        );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PhoneValidator Unit Tests', () {
    test('normalizes Arabic-Indic digits and strips separators', () {
      expect(PhoneValidator.normalize('٠١٠ ١٢٣٤-٥٦٧٨'), '01012345678');
    });

    test('validates Egyptian mobile numbers (010/011/012/015, 11 digits)', () {
      expect(PhoneValidator.validate('01012345678'), isNull);
      expect(PhoneValidator.validate('01112345678'), isNull);
      expect(PhoneValidator.validate('01212345678'), isNull);
      expect(PhoneValidator.validate('01512345678'), isNull);
      expect(PhoneValidator.validate('٠١٠١٢٣٤٥٦٧٨'), isNull);

      expect(PhoneValidator.validate('01312345678'), isNotNull);
      expect(PhoneValidator.validate('0101234'), isNotNull);
    });

    test('validates landline/international (8-15 digits) and rejects letters', () {
      expect(PhoneValidator.validate('0223456789'), isNull);
      expect(PhoneValidator.validate('+201012345678'), isNull);
      expect(PhoneValidator.validate('010abc45678'), isNotNull);
      expect(PhoneValidator.validate('12345'), isNotNull);
      expect(PhoneValidator.validate('', required: false), isNull);
      expect(PhoneValidator.validate('', required: true), isNotNull);
    });
  });

  group('FirstLaunchSetupScreen Preset Cards & Phone Validation', () {
    testWidgets('validates store phone and renders upgraded preset cards with chips', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: FirstLaunchSetupScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'متجر التجربة');
      await tester.enterText(find.byKey(const Key('setup_store_phone_field')), '013');
      await tester.tap(find.text('التالي'));
      await tester.pumpAndSettle();

      // Must remain on Step 0 due to invalid phone
      expect(find.byKey(const Key('setup_store_phone_field')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('setup_store_phone_field')),
        '01012345678',
      );
      await tester.tap(find.text('التالي'));
      await tester.pumpAndSettle();

      // Now on Step 1 with upgraded preset cards & feature chips
      expect(find.byKey(const Key('preset_card_electronics')), findsOneWidget);
      expect(find.text('IMEI'), findsOneWidget);
      expect(find.text('ضمان'), findsWidgets);
      expect(find.text('طاولات'), findsOneWidget);
      expect(find.text('أمتار'), findsOneWidget);
    });
  });

  group('AdminDashboardScreen Quick Setup Card', () {
    late AppDatabase db;
    late _FakeFeatureGate gate;
    late _StubDashboardCubit dashCubit;
    late _StubAuthCubit authCubit;

    setUp(() async {
      await getIt.reset();
      db = AppDatabase(NativeDatabase.memory());
      await db.customSelect('SELECT 1').get();
      gate = _FakeFeatureGate();
      dashCubit = _StubDashboardCubit();
      authCubit = _StubAuthCubit();

      getIt.registerSingleton<AppDatabase>(db);
      getIt.registerSingleton<FeatureGate>(gate);
      getIt.registerFactory<DashboardCubit>(() => dashCubit);
    });

    tearDown(() async {
      await dashCubit.close();
      await authCubit.close();
      gate.dispose();
      await db.close();
      await getIt.reset();
    });

    testWidgets('QuickSetupGuideCard renders 4 links, collapses/hides and persists in AppMeta', (tester) async {
      tester.view.physicalSize = const Size(1400, 950);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: QuickSetupGuideCard(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('quick_setup_guide_card')), findsOneWidget);
      expect(find.byKey(const Key('quick_setup_partners_btn')), findsOneWidget);
      expect(find.byKey(const Key('quick_setup_excel_btn')), findsOneWidget);
      expect(find.byKey(const Key('quick_setup_receive_btn')), findsOneWidget);
      expect(find.byKey(const Key('quick_setup_employees_btn')), findsOneWidget);

      // Collapse
      await tester.tap(find.byKey(const Key('quick_setup_toggle_btn')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('quick_setup_partners_btn')), findsNothing);

      final collapsedRow = await tester.runAsync(
        () => (db.select(db.appMeta)
              ..where((t) => t.key.equals('dashboard.quick_setup_state')))
            .getSingleOrNull(),
      );
      expect(collapsedRow?.value, 'collapsed');

      // Hide
      await tester.tap(find.byKey(const Key('quick_setup_hide_btn')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('quick_setup_guide_card')), findsNothing);

      final hiddenRow = await tester.runAsync(
        () => (db.select(db.appMeta)
              ..where((t) => t.key.equals('dashboard.quick_setup_state')))
            .getSingleOrNull(),
      );
      expect(hiddenRow?.value, 'hidden');
    });
  });
}
