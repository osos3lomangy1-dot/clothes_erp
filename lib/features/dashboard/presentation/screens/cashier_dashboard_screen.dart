import 'package:flutter/material.dart';
import '../../../../core/layout/main_layout.dart';
import '../../../../core/services/app_update_service.dart';
import '../../../pos/presentation/screens/pos_screen.dart';

/// Cashier Home Screen.
/// Directly displays the POS (Cashier) screen embedded inside [MainLayout] with the sidebar,
/// eliminating duplicate intermediate navigation cards.
class CashierDashboardScreen extends StatefulWidget {
  const CashierDashboardScreen({super.key});

  @override
  State<CashierDashboardScreen> createState() => _CashierDashboardScreenState();
}

class _CashierDashboardScreenState extends State<CashierDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppUpdateService.checkForUpdate(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const MainLayout(
      currentRoute: '/pos',
      child: PosScreen(),
    );
  }
}
