import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:drift/drift.dart' as drift;
import '../../../../core/constants/app_colors.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../../../shifts/presentation/cubits/shift_cubit.dart';

class PettyCashDialog extends StatefulWidget {
  const PettyCashDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PettyCashDialog(),
    );
  }

  static const List<String> defaultReasons = [
    'شراء ثلج',
    'مخبوزات وعيش طازج',
    'خامات طارئة',
    'نظافة ومستلزمات',
    'مصروف عام',
  ];

  static const List<int> quickPresets = [20, 50, 100, 200];

  @override
  State<PettyCashDialog> createState() => _PettyCashDialogState();
}

class _PettyCashDialogState extends State<PettyCashDialog> {
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _selectedReason = PettyCashDialog.defaultReasons.first;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _selectPreset(int pounds) {
    setState(() {
      _amountCtrl.text = pounds.toString();
      _errorMessage = null;
    });
  }

  Future<void> _submitPettyCash() async {
    final amountText = _amountCtrl.text.trim();
    final pounds = double.tryParse(amountText);
    if (pounds == null || pounds <= 0) {
      setState(() => _errorMessage = 'يرجى إدخال مبلغ صحيح أكبر من صفر');
      return;
    }

    final amountPiasters = (pounds * 100).round();
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final shiftCubit = context.read<ShiftCubit>();
      final activeShift = shiftCubit.state.activeShift;
      final activeShiftId = activeShift?.id;

      final branchId = getIt.isRegistered<BranchProvider>()
          ? await getIt<BranchProvider>().getBranchId()
          : 'branch_main';

      final db = getIt<AppDatabase>();
      final now = DateTime.now();
      final nowSec = now.millisecondsSinceEpoch ~/ 1000;
      final notesText = _notesCtrl.text.trim();
      final noteCombined = notesText.isNotEmpty
          ? 'نثريات كاشير: $_selectedReason ($notesText)'
          : 'نثريات كاشير: $_selectedReason';

      await db.into(db.cashMovements).insert(
        CashMovementsCompanion.insert(
          id: 'cm_pc_${DateTime.now().microsecondsSinceEpoch}',
          branchId: branchId,
          shiftId: drift.Value(activeShiftId),
          type: 'withdrawal',
          method: 'cash',
          direction: 'out',
          amountPiasters: amountPiasters,
          notes: drift.Value(noteCombined),
          createdAt: nowSec,
          updatedAt: nowSec,
        ),
      );

      // Refresh shift summary if shift is open
      if (mounted) {
        shiftCubit.loadShiftData();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم صرف ${Money(amountPiasters).toDisplay()} ج.م نثريات وتوثيق السحب بالدرج بنجاح',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppColors.primary,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'تعذر تسجيل حركة السحب: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(22),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.money_off_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'سحب نقدية ونثريات الدرج (Paid Out)',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                        ),
                        Text(
                          'صرف مصروفات طارئة تخصم لحظياً من عهدة الكاشير',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Amount Input
              Text(
                'المبلغ المصروف (بالجنيه) *',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                key: const Key('petty_cash_amount_input'),
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
                decoration: InputDecoration(
                  hintText: '0.00',
                  prefixIcon: const Icon(Icons.attach_money_rounded),
                  suffixText: 'ج.م',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                onChanged: (_) {
                  if (_errorMessage != null) {
                    setState(() => _errorMessage = null);
                  }
                },
              ),
              const SizedBox(height: 10),

              // Quick Presets
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: PettyCashDialog.quickPresets.map((preset) {
                  return ActionChip(
                    key: Key('petty_cash_preset_$preset'),
                    label: Text(
                      '$preset ج',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
                      ),
                    ),
                    backgroundColor: Colors.grey.shade100,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    onPressed: () => _selectPreset(preset),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Quick Reason Chips
              Text(
                'سبب الصرف السريع *',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: PettyCashDialog.defaultReasons.map((reason) {
                  final isSelected = _selectedReason == reason;
                  return ChoiceChip(
                    key: Key('petty_cash_reason_$reason'),
                    label: Text(
                      reason,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11.5,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.white : AppColors.onSurface,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: AppColors.primary,
                    backgroundColor: Colors.grey.shade100,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: isSelected ? AppColors.primary : Colors.grey.shade300,
                      ),
                    ),
                    onSelected: (val) {
                      if (val) setState(() => _selectedReason = reason);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Additional Notes
              Text(
                'ملاحظات وبيان إضافي (اختياري)',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                key: const Key('petty_cash_notes_input'),
                controller: _notesCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'مثال: فاتورة بقالة، شراء مستلزمات نظافة...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Confirm Button
              ElevatedButton.icon(
                key: const Key('confirm_petty_cash_btn'),
                onPressed: _isSubmitting ? null : _submitPettyCash,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 1,
                ),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline_rounded, size: 20),
                label: Text(
                  _isSubmitting ? 'جارِ التسجيل...' : 'تأكيد صرف النقدية',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
