import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../cubits/inventory_log_cubit.dart';

class InventoryLogsScreen extends StatelessWidget {
  const InventoryLogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<InventoryLogCubit>(),
      child: const _InventoryLogsView(),
    );
  }
}

class _InventoryLogsView extends StatelessWidget {
  const _InventoryLogsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'سجل حركات المخزن',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.onSurface),
            ),
            Text(
              'تتبع حركات الإدخال، الإخراج، التوريد، والخصم من الرصيد',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      body: BlocBuilder<InventoryLogCubit, InventoryLogState>(
        builder: (context, state) {
          if (state.status == InventoryLogStatus.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.status == InventoryLogStatus.error) {
            return Center(child: Text('خطأ: ${state.errorMessage ?? "حدث خطأ غير متوقع"}'));
          }
          if (state.logs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_toggle_off_rounded, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text(
                    'لا توجد حركات مخزن مسجلة حتى الآن',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: state.logs.length,
            separatorBuilder: (_, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final log = state.logs[index];
              final isIn = log.type == 'in' || log.type == 'receive' || log.type == 'return';

              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isIn ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isIn ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                      color: isIn ? Colors.green.shade800 : Colors.red.shade800,
                    ),
                  ),
                  title: Text(
                    'المنتج: ${log.productId}${log.variantId != null ? ' (المقاس: ${log.variantId})' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    'الكمية: ${log.quantity} قطعة • بواسطة: ${log.userId}',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                  trailing: Text(
                    '${log.date.hour}:${log.date.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
