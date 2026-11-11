import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../domain/entities/shift_entity.dart';
import '../cubits/shift_cubit.dart';
import '../cubits/shift_state.dart';
import '../widgets/close_shift_dialog.dart';
import '../widgets/open_shift_dialog.dart';

class ShiftScreen extends StatelessWidget {
  const ShiftScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<ShiftCubit>()..loadShiftData(),
      child: const _ShiftView(),
    );
  }
}

class _ShiftView extends StatelessWidget {
  const _ShiftView();

  void _openShiftDialog(BuildContext context) {
    final authState = context.read<AuthCubit>().state;
    String cashierId = 'admin';
    String cashierName = 'المدير';
    if (authState is AuthAuthenticated) {
      cashierId = authState.user.id;
      cashierName = authState.user.name;
    }

    showDialog(
      context: context,
      builder: (_) => OpenShiftDialog(
        cashierName: cashierName,
        onOpen: (openingPiasters) async {
          final cubit = context.read<ShiftCubit>();
          final ok = await cubit.openShift(
            openingBalance: openingPiasters,
            cashierId: cashierId,
            cashierName: cashierName,
          );
          if (!ok) {
            return cubit.state.errorMessage ?? 'تعذر بدء الوردية. يرجى المحاولة مجدداً.';
          }
          return null;
        },
      ),
    );
  }

  void _closeShiftDialog(BuildContext context, ShiftState state) {
    final authState = context.read<AuthCubit>().state;
    String currentUserId = 'admin';
    if (authState is AuthAuthenticated) {
      currentUserId = authState.user.id;
    }

    if (state.activeSummary == null) return;

    showDialog(
      context: context,
      builder: (_) => CloseShiftDialog(
        summary: state.activeSummary!,
        onClose: (countedPiasters) async {
          final cubit = context.read<ShiftCubit>();
          final ok = await cubit.closeShift(
            countedBalance: countedPiasters,
            userId: currentUserId,
          );
          if (!ok) {
            return cubit.state.errorMessage ?? 'تعذر إغلاق الوردية. يرجى المحاولة مجدداً.';
          }
          return null;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');
    final authState = context.watch<AuthCubit>().state;
    final isAdmin = authState is! AuthAuthenticated || authState.user.role == 'admin';
    final currentUserId = authState is AuthAuthenticated ? authState.user.id : 'admin';

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface),
          tooltip: 'رجوع',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'إدارة الورديات وتصفية الدرج',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.onSurface),
            ),
            Text(
              'متابعة عهدة الدرج، مبيعات الشفت، وتصفية العجز والزيادة',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          if (isAdmin)
            BlocBuilder<ShiftCubit, ShiftState>(
              builder: (context, state) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Row(
                    children: [
                      const Text(
                        'إلزامية الورديات:',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Switch(
                        value: state.shiftsEnabled,
                        activeThumbColor: AppColors.primary,
                        onChanged: (val) {
                          context.read<ShiftCubit>().toggleShiftsEnabled(val);
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: BlocConsumer<ShiftCubit, ShiftState>(
        listener: (context, state) {
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage!),
                backgroundColor: AppColors.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        builder: (context, state) {
          if (state.status == ShiftStatus.loading && state.activeShift == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final displayedHistory = isAdmin
              ? state.history
              : state.history.where((s) => s.cashierId == currentUserId).toList();

          return RefreshIndicator(
            onRefresh: () => context.read<ShiftCubit>().loadShiftData(),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (!state.shiftsEnabled && isAdmin)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, color: Colors.orange.shade800),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'نظام الورديات معطل حالياً من الإعدادات: البيع في الكاشير متاح مباشرة دون الحاجة لفتح وردية.',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.orange.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Active Shift Card
                if (state.hasActiveShift) ...[
                  _buildActiveShiftCard(
                    context,
                    state,
                    dateFormat,
                    isAdmin: isAdmin,
                    currentUserId: currentUserId,
                  ),
                ] else ...[
                  _buildNoActiveShiftCard(context),
                ],

                const SizedBox(height: 28),

                // History Section
                Row(
                  children: [
                    const Icon(Icons.history_rounded, color: AppColors.primary, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      isAdmin ? 'سجل الورديات السابقة' : 'سجل وردياتي السابقة',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.onSurface),
                    ),
                    const Spacer(),
                    Text(
                      'آخر ${displayedHistory.length} وردية',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildHistoryTable(displayedHistory, dateFormat),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildActiveShiftCard(
    BuildContext context,
    ShiftState state,
    DateFormat dateFormat, {
    required bool isAdmin,
    required String currentUserId,
  }) {
    final shift = state.activeShift!;
    final summary = state.activeSummary;
    final canClose = isAdmin || shift.cashierId == currentUserId;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.check_circle_outline_rounded, color: Colors.green.shade700, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Text(
                            'الوردية الحالية مفتوحة (نشطة)',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(width: 8),
                          _PulseBadge(),
                        ],
                      ),
                      Text(
                        'فُتحت بواسطة: ${shift.cashierName.isNotEmpty ? shift.cashierName : shift.cashierId} في ${dateFormat.format(shift.openedAt)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                if (canClose)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onPressed: () => _closeShiftDialog(context, state),
                    icon: const Icon(Icons.lock_rounded, color: Colors.white, size: 18),
                    label: const Text(
                      'إغلاق الوردية وتصفية الدرج',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline_rounded, size: 16, color: Colors.grey.shade600),
                        const SizedBox(width: 6),
                        Text(
                          'مفتوحة بواسطة كاشير آخر',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _metricBox(
                    'الرصيد الافتتاحي (الفكة)',
                    '${Money(shift.openingBalance).toDisplay()} ج.م',
                    Icons.account_balance_wallet_rounded,
                    Colors.blue.shade700,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _metricBox(
                    'مبيعات نقدية (كاش)',
                    '${Money(summary?.cashSales ?? 0).toDisplay()} ج.م',
                    Icons.monetization_on_rounded,
                    Colors.green.shade700,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _metricBox(
                    'مبيعات فيزا وإلكتروني',
                    '${Money(summary?.cardSales ?? 0).toDisplay()} ج.م',
                    Icons.credit_card_rounded,
                    Colors.purple.shade700,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _metricBox(
                    'مصروفات / مرتجعات',
                    '${Money((summary?.cashExpenses ?? 0) + (summary?.cashReturns ?? 0)).toDisplay()} ج.م',
                    Icons.outbox_rounded,
                    AppColors.error,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _metricBox(
                    'المتوقع حالياً بالدرج',
                    '${Money(summary?.expectedCashInDrawer ?? shift.openingBalance).toDisplay()} ج.م',
                    Icons.point_of_sale_rounded,
                    AppColors.primary,
                    isHighlight: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoActiveShiftCard(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lock_rounded, size: 40, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 14),
            const Text(
              'لا توجد وردية مفتوحة حالياً',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'لبدء تسجيل المبيعات وحركات الدرج، يرجى فتح وردية جديدة وتحديد رصيد الفكة الافتتاحي',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () => _openShiftDialog(context),
              icon: const Icon(Icons.lock_open_rounded, color: Colors.white, size: 20),
              label: const Text(
                'فتح وردية جديدة',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricBox(String title, String value, IconData icon, Color color, {bool isHighlight = false}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isHighlight ? color.withValues(alpha: 0.08) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isHighlight ? color.withValues(alpha: 0.3) : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isHighlight ? color : AppColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTable(List<ShiftEntity> shifts, DateFormat dateFormat) {
    if (shifts.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Padding(
          padding: EdgeInsets.all(24.0),
          child: Center(
            child: Text('لا توجد ورديات سابقة مسجلة بالنظام', style: TextStyle(color: Colors.grey)),
          ),
        ),
      );
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  columnSpacing: 20,
                  horizontalMargin: 16,
                  headingRowColor: WidgetStateProperty.all(Colors.grey.shade50),
                  columns: const [
                    DataColumn(label: Text('الكاشير', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('وقت الفتح', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('وقت الإغلاق', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('الرصيد الافتتاحي', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('المتوقع', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('الفعلي (المعدود)', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('الفارق (العجز/الزيادة)', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('الحالة', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: shifts.map((s) {
                    final diff = s.difference ?? 0;
                    Color diffColor;
                    String diffText;
                    if (s.isOpen) {
                      diffColor = Colors.grey;
                      diffText = '-';
                    } else if (diff == 0) {
                      diffColor = Colors.green.shade700;
                      diffText = 'مطابق (0 ج.م)';
                    } else if (diff > 0) {
                      diffColor = Colors.blue.shade700;
                      diffText = '+${Money(diff).toDisplay()} ج.م (زيادة)';
                    } else {
                      diffColor = AppColors.error;
                      diffText = '${Money(diff).toDisplay()} ج.م (عجز)';
                    }

                    return DataRow(
                      cells: [
                        DataCell(Text(s.cashierName.isNotEmpty ? s.cashierName : s.cashierId, style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Text(dateFormat.format(s.openedAt), style: const TextStyle(fontSize: 12))),
                        DataCell(Text(s.closedAt != null ? dateFormat.format(s.closedAt!) : 'قيد العمل', style: const TextStyle(fontSize: 12))),
                        DataCell(Text('${Money(s.openingBalance).toDisplay()} ج.م')),
                        DataCell(Text(s.expectedBalance != null ? '${Money(s.expectedBalance!).toDisplay()} ج.م' : '-')),
                        DataCell(Text(s.countedBalance != null ? '${Money(s.countedBalance!).toDisplay()} ج.م' : '-')),
                        DataCell(Text(diffText, style: TextStyle(color: diffColor, fontWeight: FontWeight.bold))),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: s.isOpen ? Colors.green.shade50 : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: s.isOpen ? Colors.green.shade200 : Colors.grey.shade300),
                            ),
                            child: Text(
                              s.isOpen ? 'مفتوحة' : 'مغلقة',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: s.isOpen ? Colors.green.shade800 : Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PulseBadge extends StatelessWidget {
  const _PulseBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: Colors.green,
        shape: BoxShape.circle,
      ),
    );
  }
}
