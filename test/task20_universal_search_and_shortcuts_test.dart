import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/layout/command_palette_dialog.dart';
import 'package:clothes_erp/core/services/shortcut_settings_service.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_cubit.dart';
import 'package:clothes_erp/features/auth/presentation/cubits/auth_state.dart';
import 'package:clothes_erp/features/settings/presentation/cubits/settings_cubit.dart';
import 'package:clothes_erp/features/settings/presentation/screens/system_settings_screen.dart';
import 'package:clothes_erp/features/settings/presentation/widgets/shortcuts_config_dialog.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

class _FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _FakeAuthCubit()
      : super(
          AuthAuthenticated(
            UserModel(
              id: 'admin-1',
              name: 'المشرف العام',
              email: 'admin@test.com',
              role: 'admin',
              isActive: true,
              createdAt: DateTime(2025, 1, 1),
            ),
          ),
        );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsCubit extends Cubit<SettingsState> implements SettingsCubit {
  _FakeSettingsCubit() : super(const SettingsState(features: {}));

  String? toggledKey;
  bool? toggledVal;

  @override
  Future<void> start() async {
    emit(state.copyWith(
      features: {
        FeatureKeys.installments: true,
        FeatureKeys.delivery: false,
        FeatureKeys.preOrders: true,
      },
      isLoading: false,
    ));
  }

  @override
  Future<String?> toggleFeature(String key, bool val, String userId) async {
    toggledKey = key;
    toggledVal = val;
    final updated = Map<String, bool>.from(state.features);
    updated[key] = val;
    emit(state.copyWith(features: updated));
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ShortcutSettingsService shortcutService;

  setUp(() async {
    await GetIt.I.reset();
    db = AppDatabase(NativeDatabase.memory());
    shortcutService = ShortcutSettingsService(db);
    GetIt.I.registerSingleton<AppDatabase>(db);
    GetIt.I.registerSingleton<ShortcutSettingsService>(shortcutService);
  });

  tearDown(() async {
    await db.close();
    await GetIt.I.reset();
  });

  group('Task 20: ShortcutSettingsService Engine', () {
    test('loads default shortcuts and parses combos into SingleActivator', () async {
      final all = shortcutService.getAllShortcuts();
      expect(all['openCommandPalette'], equals('Ctrl+K'));
      expect(all['completeSale'], equals('F12'));
      expect(all['holdBill'], equals('F10'));
      expect(all['recallBill'], equals('F11'));
      expect(all['quickPayCash'], equals('Alt+1'));
      expect(all['quickPayCard'], equals('Alt+2'));
      expect(all['focusDiscount'], equals('Ctrl+D'));

      final act = shortcutService.getActivator('completeSale');
      expect(act.trigger, equals(LogicalKeyboardKey.f12));
      expect(act.control, isFalse);
      expect(act.alt, isFalse);

      final ctrlK = shortcutService.getActivator('openCommandPalette');
      expect(ctrlK.trigger, equals(LogicalKeyboardKey.keyK));
      expect(ctrlK.control, isTrue);

      final alt1 = shortcutService.getActivator('quickPayCash');
      expect(alt1.trigger, equals(LogicalKeyboardKey.digit1));
      expect(alt1.alt, isTrue);
    });

    test('detects conflicting shortcuts accurately', () async {
      expect(shortcutService.hasConflict('holdBill', 'F12'), isTrue);
      expect(shortcutService.getConflictingAction('holdBill', 'F12'), equals('completeSale'));

      expect(shortcutService.hasConflict('holdBill', 'F10'), isFalse);
      expect(shortcutService.hasConflict('holdBill', 'Ctrl+Shift+Z'), isFalse);
    });

    test('saves customized shortcuts and restores system defaults', () async {
      await shortcutService.setShortcut('holdBill', 'Ctrl+H');
      expect(shortcutService.getShortcut('holdBill'), equals('Ctrl+H'));

      await shortcutService.restoreDefaults();
      expect(shortcutService.getShortcut('holdBill'), equals('F10'));
    });
  });

  group('Task 20: CommandPaletteDialog Spotlight', () {
    testWidgets('renders search field, filters command items, and executes selection', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      String? selectedId;

      final items = [
        CommandPaletteItem(
          id: 'nav_pos',
          title: 'شاشة نقطة البيع (الكاشير)',
          category: 'screens',
          icon: Icons.point_of_sale_rounded,
          onSelect: () => selectedId = 'nav_pos',
        ),
        CommandPaletteItem(
          id: 'nav_inventory',
          title: 'إدارة المخزون والأصناف',
          category: 'screens',
          icon: Icons.inventory_2_rounded,
          onSelect: () => selectedId = 'nav_inventory',
        ),
        CommandPaletteItem(
          id: 'act_hold',
          title: 'تعليق الفاتورة الحالية',
          category: 'actions',
          icon: Icons.pause_circle_outline_rounded,
          subtitle: 'F10',
          onSelect: () => selectedId = 'act_hold',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommandPaletteDialog(
              items: items,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('command_palette_dialog')), findsOneWidget);
      expect(find.byKey(const Key('command_palette_search_field')), findsOneWidget);
      expect(find.text('شاشة نقطة البيع (الكاشير)'), findsOneWidget);
      expect(find.text('تعليق الفاتورة الحالية'), findsOneWidget);

      // Filter by 'تعليق'
      await tester.enterText(find.byKey(const Key('command_palette_search_field')), 'تعليق');
      await tester.pumpAndSettle();

      expect(find.text('تعليق الفاتورة الحالية'), findsOneWidget);
      expect(find.text('شاشة نقطة البيع (الكاشير)'), findsNothing);

      // Tap on item
      await tester.tap(find.byKey(const Key('command_palette_item_act_hold')));
      await tester.pumpAndSettle();

      expect(selectedId, equals('act_hold'));
    });
  });

  group('Task 20: SystemSettingsScreen Live Search & Hotkeys', () {
    testWidgets('searches features, displays direct switch, and toggles feature', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      final fakeSettingsCubit = _FakeSettingsCubit();
      final fakeAuthCubit = _FakeAuthCubit();
      GetIt.I.registerSingleton<SettingsCubit>(fakeSettingsCubit);
      GetIt.I.registerSingleton<AuthCubit>(fakeAuthCubit);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<SettingsCubit>.value(value: fakeSettingsCubit),
              BlocProvider<AuthCubit>.value(value: fakeAuthCubit),
            ],
            child: const SystemSettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings_search_field')), findsOneWidget);

      // Type 'دليفري' into search
      await tester.enterText(find.byKey(const Key('settings_search_field')), 'دليفري');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings_search_results_list')), findsOneWidget);
      expect(find.byKey(Key('feature_switch_${FeatureKeys.delivery}')), findsOneWidget);

      // Toggle delivery feature switch
      await tester.tap(find.byKey(Key('feature_switch_${FeatureKeys.delivery}')));
      await tester.pumpAndSettle();

      expect(fakeSettingsCubit.toggledKey, equals(FeatureKeys.delivery));
      expect(fakeSettingsCubit.toggledVal, isTrue);

      // Clear search
      await tester.enterText(find.byKey(const Key('settings_search_field')), '');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings_search_results_list')), findsNothing);
    });
  });

  group('Task 20: ShortcutsConfigDialog UI', () {
    testWidgets('renders categories and restore defaults button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ShortcutsConfigDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shortcuts_config_dialog')), findsOneWidget);
      expect(find.byKey(const Key('restore_default_shortcuts_btn')), findsOneWidget);
      expect(find.text('إتمام ودفع الفاتورة'), findsOneWidget);
      expect(find.text('تعليق الفاتورة (Hold Bill)'), findsOneWidget);
    });
  });

  group('Task 20: Excel-like Arrow Grid Navigation in Tables', () {
    testWidgets('handles arrow navigation and adds row on down arrow at last row', (tester) async {
      final rows = <List<FocusNode>>[];
      for (int i = 0; i < 2; i++) {
        rows.add([FocusNode(), FocusNode(), FocusNode()]);
      }

      int targetRow = 0;
      int targetCol = 0;
      int addRowCalls = 0;

      KeyEventResult handleGridKey(KeyEvent event, int rowIdx, int colIdx) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          if (rowIdx < rows.length - 1) {
            targetRow = rowIdx + 1;
            targetCol = colIdx;
          } else {
            addRowCalls++;
            rows.add([FocusNode(), FocusNode(), FocusNode()]);
            targetRow = rowIdx + 1;
            targetCol = colIdx;
          }
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          if (rowIdx > 0) {
            targetRow = rowIdx - 1;
            targetCol = colIdx;
          }
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          if (colIdx < rows[rowIdx].length - 1) {
            targetRow = rowIdx;
            targetCol = colIdx + 1;
            return KeyEventResult.handled;
          }
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          if (colIdx > 0) {
            targetRow = rowIdx;
            targetCol = colIdx - 1;
            return KeyEventResult.handled;
          }
        }

        return KeyEventResult.ignored;
      }

      // Down arrow -> moves to row 1, col 0
      final r1 = handleGridKey(const KeyDownEvent(physicalKey: PhysicalKeyboardKey.arrowDown, logicalKey: LogicalKeyboardKey.arrowDown, timeStamp: Duration.zero), 0, 0);
      expect(r1, equals(KeyEventResult.handled));
      expect(targetRow, equals(1));
      expect(targetCol, equals(0));

      // Left arrow -> moves to col 1 in row 1
      final r2 = handleGridKey(const KeyDownEvent(physicalKey: PhysicalKeyboardKey.arrowLeft, logicalKey: LogicalKeyboardKey.arrowLeft, timeStamp: Duration.zero), 1, 0);
      expect(r2, equals(KeyEventResult.handled));
      expect(targetRow, equals(1));
      expect(targetCol, equals(1));

      // Down arrow on last row (row 1) -> adds row 2 and moves target to row 2, col 1
      final r3 = handleGridKey(const KeyDownEvent(physicalKey: PhysicalKeyboardKey.arrowDown, logicalKey: LogicalKeyboardKey.arrowDown, timeStamp: Duration.zero), 1, 1);
      expect(r3, equals(KeyEventResult.handled));
      expect(addRowCalls, equals(1));
      expect(rows.length, equals(3));
      expect(targetRow, equals(2));
      expect(targetCol, equals(1));

      // Up arrow from row 2 -> row 1, col 1
      final r4 = handleGridKey(const KeyDownEvent(physicalKey: PhysicalKeyboardKey.arrowUp, logicalKey: LogicalKeyboardKey.arrowUp, timeStamp: Duration.zero), 2, 1);
      expect(r4, equals(KeyEventResult.handled));
      expect(targetRow, equals(1));
      expect(targetCol, equals(1));
    });
  });

  group('Task 20: POS Hotkey Footer Strip UI', () {
    testWidgets('renders all cashier hotkey chips and responds to taps', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      final tappedKeys = <String>[];

      Widget buildChip(String keyId, String label, IconData icon) {
        return InkWell(
          key: Key(keyId),
          onTap: () => tappedKeys.add(keyId),
          child: Row(
            children: [
              Icon(icon, size: 14),
              Text(label),
            ],
          ),
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: Container(
              key: const Key('pos_hotkey_footer_strip'),
              child: Row(
                children: [
                  buildChip('pos_footer_hotkey_search', 'F2 بحث', Icons.search),
                  buildChip('pos_footer_hotkey_cash', 'F5 كاش', Icons.payments),
                  buildChip('pos_footer_hotkey_card', 'F6 فيزا', Icons.credit_card),
                  buildChip('pos_footer_hotkey_hold', 'F10 تعليق', Icons.pause),
                  buildChip('pos_footer_hotkey_recall', 'F11 استرجاع', Icons.play_arrow),
                  buildChip('pos_footer_hotkey_discount', 'Ctrl+D خصم', Icons.percent),
                  buildChip('pos_footer_hotkey_checkout', 'F12 دفع', Icons.check),
                  buildChip('pos_footer_hotkey_shortcuts', 'F1 دليل ومفاتيح', Icons.keyboard),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pos_hotkey_footer_strip')), findsOneWidget);
      expect(find.byKey(const Key('pos_footer_hotkey_search')), findsOneWidget);
      expect(find.byKey(const Key('pos_footer_hotkey_cash')), findsOneWidget);
      expect(find.byKey(const Key('pos_footer_hotkey_card')), findsOneWidget);
      expect(find.byKey(const Key('pos_footer_hotkey_hold')), findsOneWidget);
      expect(find.byKey(const Key('pos_footer_hotkey_recall')), findsOneWidget);
      expect(find.byKey(const Key('pos_footer_hotkey_discount')), findsOneWidget);
      expect(find.byKey(const Key('pos_footer_hotkey_checkout')), findsOneWidget);
      expect(find.byKey(const Key('pos_footer_hotkey_shortcuts')), findsOneWidget);

      await tester.tap(find.byKey(const Key('pos_footer_hotkey_hold')));
      await tester.tap(find.byKey(const Key('pos_footer_hotkey_checkout')));
      await tester.pumpAndSettle();

      expect(tappedKeys, contains('pos_footer_hotkey_hold'));
      expect(tappedKeys, contains('pos_footer_hotkey_checkout'));
    });
  });
}
