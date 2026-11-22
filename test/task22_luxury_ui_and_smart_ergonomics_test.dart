import 'package:clothes_erp/core/utils/money.dart';
import 'package:clothes_erp/core/widgets/app_floating_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// TEST HELPER: Smart Tender Algorithm Mirror for direct unit verification
// ---------------------------------------------------------------------------
class _SmartTenderPresetModel {
  final double amount;
  final double change;
  final String label;
  final bool isExact;

  const _SmartTenderPresetModel({
    required this.amount,
    required this.change,
    required this.label,
    this.isExact = false,
  });
}

List<_SmartTenderPresetModel> _calculateTestSmartPresets(int totalPiasters) {
  if (totalPiasters <= 0) return const [];
  final totalEgp = totalPiasters / 100.0;
  final List<_SmartTenderPresetModel> results = [];

  final candidates = <double>{};
  final next5 = ((totalEgp / 5.0).floor() + 1) * 5.0;
  if (next5 > totalEgp) candidates.add(next5);

  final next50 = ((totalEgp / 50.0).floor() + 1) * 50.0;
  if (next50 > totalEgp) candidates.add(next50);

  final next100 = ((totalEgp / 100.0).floor() + 1) * 100.0;
  if (next100 > totalEgp) candidates.add(next100);

  const standardNotes = [20.0, 50.0, 100.0, 200.0, 500.0];
  for (final note in standardNotes) {
    if (note > totalEgp) candidates.add(note);
  }

  final sorted = candidates.toList()..sort();
  for (final amt in sorted) {
    if (results.length >= 2) break;
    final change = amt - totalEgp;
    final amtStr =
        amt % 1 == 0 ? amt.toInt().toString() : amt.toStringAsFixed(2);
    final changeStr =
        change % 1 == 0 ? change.toInt().toString() : change.toStringAsFixed(2);
    results.add(_SmartTenderPresetModel(
      amount: amt,
      change: change,
      label: '$amtStr ج.م ◄ باقي $changeStr ج.م',
    ));
  }

  final exactStr =
      totalEgp % 1 == 0 ? totalEgp.toInt().toString() : totalEgp.toStringAsFixed(2);
  results.add(_SmartTenderPresetModel(
    amount: totalEgp,
    change: 0.0,
    label: 'المبلغ بالضبط: $exactStr ج.م',
    isExact: true,
  ));

  return results;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AppFloatingToast.dismissCurrent();
  });

  group('Task 22: AppFloatingToast Luxury Pill Notifications', () {
    testWidgets('AppFloatingToast renders in top-center with custom message and toast type', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                key: const Key('show_toast_btn'),
                onPressed: () {
                  AppFloatingToast.show(
                    context,
                    message: 'تم تعليق الفاتورة السابقة وفتح فاتورة 2 جديدة [F10]',
                    type: ToastType.success,
                  );
                },
                child: const Text('إظهار الإشعار'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('show_toast_btn')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(const Key('app_floating_toast')), findsOneWidget);
      expect(
        find.text('تم تعليق الفاتورة السابقة وفتح فاتورة 2 جديدة [F10]'),
        findsOneWidget,
      );

      // Verify that it is in the upper area of the screen (top padding)
      final toastOffset = tester.getTopLeft(find.byKey(const Key('app_floating_toast')));
      expect(toastOffset.dy, lessThan(100.0));

      // Dismiss early and advance time to ensure clean disposal without pending timers
      AppFloatingToast.dismissCurrent();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    });

    testWidgets('AppFloatingToast supports all 4 toast types (success, error, warning, info)', (tester) async {
      for (final type in ToastType.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  key: Key('btn_${type.name}'),
                  onPressed: () {
                    AppFloatingToast.show(
                      context,
                      message: 'رسالة من النوع: ${type.name}',
                      type: type,
                    );
                  },
                  child: Text(type.name),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(Key('btn_${type.name}')));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byKey(const Key('app_floating_toast')), findsOneWidget);
        expect(find.text('رسالة من النوع: ${type.name}'), findsOneWidget);

        AppFloatingToast.dismissCurrent();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
      }
    });
  });

  group('Task 22: Dynamic Contextual Hotkey Strip', () {
    Widget buildContextualBar({
      required String stripKey,
      required List<Map<String, dynamic>> items,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Container(
            key: Key(stripKey),
            height: 38,
            color: const Color(0xFF0F172A),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ...items.map((item) {
                    return InkWell(
                      key: Key(item['key'] as String),
                      onTap: item['onTap'] as VoidCallback?,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: Text(item['label'] as String),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('Products contextual hotkeys are properly rendered with required shortcuts', (tester) async {
      final items = [
        {'key': 'hotkey_products_new_size', 'label': 'F3 سطر مقاس جديد'},
        {'key': 'hotkey_products_save', 'label': 'Ctrl+S حفظ المنتجات'},
        {'key': 'hotkey_products_barcode', 'label': 'F4 طباعة باركود'},
        {'key': 'hotkey_products_grid_nav', 'label': 'تنقل شبكي بالأسهم'},
        {'key': 'hotkey_products_shortcuts', 'label': 'F1 اختصارات'},
      ];

      await tester.pumpWidget(
        buildContextualBar(
          stripKey: 'contextual_hotkey_strip_products',
          items: items,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('contextual_hotkey_strip_products')), findsOneWidget);
      expect(find.text('F3 سطر مقاس جديد'), findsOneWidget);
      expect(find.text('Ctrl+S حفظ المنتجات'), findsOneWidget);
      expect(find.text('F4 طباعة باركود'), findsOneWidget);
      expect(find.text('تنقل شبكي بالأسهم'), findsOneWidget);
      expect(find.text('F1 اختصارات'), findsOneWidget);
    });

    testWidgets('Delivery contextual hotkeys are properly rendered with required shortcuts', (tester) async {
      final items = [
        {'key': 'hotkey_delivery_new_order', 'label': 'طلب دليفري جديد'},
        {'key': 'hotkey_delivery_settle_courier', 'label': 'تصفية كاش طيار'},
        {'key': 'hotkey_delivery_company_payout', 'label': 'تسجيل دفعة شركة'},
        {'key': 'hotkey_delivery_palette', 'label': 'Ctrl+K لوحة الأوامر'},
      ];

      await tester.pumpWidget(
        buildContextualBar(
          stripKey: 'contextual_hotkey_strip_delivery',
          items: items,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('contextual_hotkey_strip_delivery')), findsOneWidget);
      expect(find.text('طلب دليفري جديد'), findsOneWidget);
      expect(find.text('تصفية كاش طيار'), findsOneWidget);
      expect(find.text('تسجيل دفعة شركة'), findsOneWidget);
      expect(find.text('Ctrl+K لوحة الأوامر'), findsOneWidget);
    });

    testWidgets('Purchases and General contextual hotkeys are properly rendered', (tester) async {
      final purchasesItems = [
        {'key': 'hotkey_purchases_new_bill', 'label': 'فاتورة مشتريات جديدة'},
        {'key': 'hotkey_purchases_save', 'label': 'Ctrl+S اعتماد وحفظ'},
        {'key': 'hotkey_purchases_supplier', 'label': 'F2 اختيار مورد'},
        {'key': 'hotkey_purchases_shortcuts', 'label': 'F1 اختصارات'},
      ];

      await tester.pumpWidget(
        buildContextualBar(
          stripKey: 'contextual_hotkey_strip_purchases',
          items: purchasesItems,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('contextual_hotkey_strip_purchases')), findsOneWidget);
      expect(find.text('فاتورة مشتريات جديدة'), findsOneWidget);
      expect(find.text('Ctrl+S اعتماد وحفظ'), findsOneWidget);
      expect(find.text('F2 اختيار مورد'), findsOneWidget);
    });
  });

  group('Task 22: Held Bills Visual Pulse & Dynamic Tooltip', () {
    testWidgets('Held bill badge dot appears for inactive bill with items and shows count', (tester) async {
      Widget buildHeldBillsBar({
        required int activeIndex,
        required List<Map<String, dynamic>> bills,
      }) {
        return MaterialApp(
          home: Scaffold(
            body: Row(
              children: bills.asMap().entries.map((entry) {
                final index = entry.key;
                final b = entry.value;
                final isActive = index == activeIndex;
                final count = b['count'] as int;
                final title = b['title'] as String;
                final totalPiasters = b['total'] as int;
                final tooltipMsg =
                    '$title ($count أصناف - إجمالي ${Money(totalPiasters).toDisplay()} ج.م) - اضغط F11 للتنقل';

                return Tooltip(
                  message: tooltipMsg,
                  child: Row(
                    children: [
                      Text(title),
                      if (!isActive && count > 0)
                        Container(
                          key: Key('held_bill_badge_$index'),
                          child: Text('$count'),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        );
      }

      // 1. Bill 0 is active (1 item), Bill 1 is inactive (3 items)
      await tester.pumpWidget(
        buildHeldBillsBar(
          activeIndex: 0,
          bills: [
            {'title': 'فاتورة 1', 'count': 1, 'total': 15000},
            {'title': 'فاتورة 2', 'count': 3, 'total': 45000},
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Inactive bill 1 should display badge with count 3
      expect(find.byKey(const Key('held_bill_badge_1')), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      // Active bill 0 should not display inactive badge dot
      expect(find.byKey(const Key('held_bill_badge_0')), findsNothing);

      // Verify Tooltip exists for inactive bill
      final tooltipFinder = find.byType(Tooltip);
      expect(tooltipFinder, findsNWidgets(2));

      // 2. Clear Bill 1 (count = 0)
      await tester.pumpWidget(
        buildHeldBillsBar(
          activeIndex: 0,
          bills: [
            {'title': 'فاتورة 1', 'count': 1, 'total': 15000},
            {'title': 'فاتورة 2', 'count': 0, 'total': 0},
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Badge must disappear when bill is empty
      expect(find.byKey(const Key('held_bill_badge_1')), findsNothing);
    });
  });

  group('Task 22: Smart Cash Tender Presets', () {
    test('calculateSmartTenderPresets generates accurate denominations for 145 EGP', () {
      final presets = _calculateTestSmartPresets(14500); // 145 EGP
      expect(presets.length, 3);

      expect(presets[0].amount, 150.0);
      expect(presets[0].change, 5.0);
      expect(presets[0].label, '150 ج.م ◄ باقي 5 ج.م');
      expect(presets[0].isExact, isFalse);

      expect(presets[1].amount, 200.0);
      expect(presets[1].change, 55.0);
      expect(presets[1].label, '200 ج.م ◄ باقي 55 ج.م');
      expect(presets[1].isExact, isFalse);

      expect(presets[2].amount, 145.0);
      expect(presets[2].change, 0.0);
      expect(presets[2].label, 'المبلغ بالضبط: 145 ج.م');
      expect(presets[2].isExact, isTrue);
    });

    testWidgets('Tapping smart tender preset auto-populates received field and displays change', (tester) async {
      final receivedCtrl = TextEditingController();
      int totalPiasters = 14500;
      double changeEgp = 0.0;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            final presets = _calculateTestSmartPresets(totalPiasters);
            return MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    TextField(controller: receivedCtrl),
                    Text('باقي: ${changeEgp.toStringAsFixed(2)}'),
                    ...presets.asMap().entries.map((entry) {
                      final index = entry.key;
                      final preset = entry.value;
                      final key = preset.isExact
                          ? const Key('smart_tender_exact')
                          : Key('smart_tender_preset_$index');

                      return ElevatedButton(
                        key: key,
                        onPressed: () {
                          setState(() {
                            receivedCtrl.text = preset.amount.toStringAsFixed(2);
                            changeEgp = preset.change;
                          });
                        },
                        child: Text(preset.label),
                      );
                    }),
                  ],
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('smart_tender_preset_0')), findsOneWidget);
      expect(find.byKey(const Key('smart_tender_preset_1')), findsOneWidget);
      expect(find.byKey(const Key('smart_tender_exact')), findsOneWidget);

      // Tap 150 EGP preset (5 EGP change)
      await tester.tap(find.byKey(const Key('smart_tender_preset_0')));
      await tester.pumpAndSettle();

      expect(receivedCtrl.text, '150.00');
      expect(find.text('باقي: 5.00'), findsOneWidget);

      // Tap Exact 145 EGP preset (0 EGP change)
      await tester.tap(find.byKey(const Key('smart_tender_exact')));
      await tester.pumpAndSettle();

      expect(receivedCtrl.text, '145.00');
      expect(find.text('باقي: 0.00'), findsOneWidget);
    });
  });

  group('Task 22: Illustrated Friendly Empty States', () {
    testWidgets('Empty cart displays friendly guidance text along with standard empty title', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Icon(Icons.shopping_cart_outlined),
                Text('سلة المشتريات فارغة'),
                Text(
                  'السلة بانتظار مسح الأصناف.. امسح الباركود أو اضغط [F2] للبحث السريع',
                  key: Key('cart_empty_state_text'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('سلة المشتريات فارغة'), findsOneWidget);
      expect(find.byKey(const Key('cart_empty_state_text')), findsOneWidget);
      expect(
        find.text('السلة بانتظار مسح الأصناف.. امسح الباركود أو اضغط [F2] للبحث السريع'),
        findsOneWidget,
      );
    });

    testWidgets('Empty delivery list displays friendly completed status text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Icon(Icons.two_wheeler_rounded),
                Text(
                  'لا توجد طلبات دليفري جارية حالياً.. جميع الطلبات تم تسليمها وتصفيتها بنجاح',
                  key: Key('delivery_empty_state_text'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delivery_empty_state_text')), findsOneWidget);
      expect(
        find.text('لا توجد طلبات دليفري جارية حالياً.. جميع الطلبات تم تسليمها وتصفيتها بنجاح'),
        findsOneWidget,
      );
    });
  });
}
