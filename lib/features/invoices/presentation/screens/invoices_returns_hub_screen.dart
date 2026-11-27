import 'package:flutter/material.dart';

import '../../../returns/presentation/screens/return_screen.dart';
import 'invoices_screen.dart';

/// Unified entry point for Invoices & Returns:
/// - Users with invoice history permission see [InvoicesScreen] directly
///   (which already includes the Returns status filter + direct quick-return).
/// - Cashiers without invoice history permission see [ReturnScreen].
class InvoicesReturnsHubScreen extends StatelessWidget {
  final int initialTabIndex;
  final bool canViewInvoices;

  const InvoicesReturnsHubScreen({
    super.key,
    this.initialTabIndex = 0,
    this.canViewInvoices = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!canViewInvoices) {
      return const ReturnScreen();
    }
    if (initialTabIndex == 1) {
      return const ReturnScreen(forcedTabIndex: 1);
    }
    return const InvoicesScreen();
  }
}
