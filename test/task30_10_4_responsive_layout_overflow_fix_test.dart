import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/di/injection.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/purchases_cubit.dart';
import 'package:clothes_erp/features/purchases/presentation/cubits/suppliers_cubit.dart';
import 'package:clothes_erp/features/purchases/presentation/screens/create_purchase_screen.dart';
import 'package:clothes_erp/features/reports/presentation/widgets/payment_method_pie_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    if (!getIt.isRegistered<AppDatabase>()) {
      await configureDependencies();
    }
  });

  group('Addendum 30.10.4: Responsive Layout & No RenderFlex Overflows Across All Resolutions', () {
    testWidgets('PaymentMethodPieChart has zero overflow across widths (300px to 1400px)', (tester) async {
      final breakdown = {'cash': 6000, 'card': 3000, 'instapay': 1000};
      for (double w = 300; w <= 1400; w += 50) {
        tester.view.physicalSize = Size(w, 800);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: SizedBox(
                  width: w,
                  child: PaymentMethodPieChart(breakdown: breakdown),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'Overflowed at width $w');
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('CreatePurchaseScreen has zero overflow across widths (320px to 1400px)', (tester) async {
      final widths = [320.0, 360.0, 400.0, 500.0, 600.0, 650.0, 750.0, 900.0, 1000.0, 1140.0, 1160.0, 1200.0, 1400.0];
      for (final w in widths) {
        tester.view.physicalSize = Size(w, 900);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<PurchasesCubit>.value(value: getIt<PurchasesCubit>()),
              BlocProvider<SuppliersCubit>.value(value: getIt<SuppliersCubit>()),
            ],
            child: MaterialApp(
              home: Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  body: SizedBox(
                    width: w,
                    child: const CreatePurchaseScreen(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'Overflowed at width $w');
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}
