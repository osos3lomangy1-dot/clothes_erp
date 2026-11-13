import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection.dart';
import '../cubits/cashier_payroll_cubit.dart';
import 'cashier_payroll_card.dart';

class CashierProfileDialog extends StatelessWidget {
  final String employeeId;

  const CashierProfileDialog({super.key, required this.employeeId});

  static Future<void> show(BuildContext context, {required String employeeId}) {
    return showDialog(
      context: context,
      builder: (_) => CashierProfileDialog(employeeId: employeeId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<CashierPayrollCubit>()..loadSummary(employeeId),
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CashierPayrollCard(employeeId: employeeId, showActions: true),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إغلاق'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

