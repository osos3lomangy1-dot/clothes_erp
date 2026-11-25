import 'dart:convert';

import 'package:drift/drift.dart' as drift show InsertMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../../../partners/domain/entities/partner_entity.dart';

class _PartnerDraftRow {
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController percentCtrl = TextEditingController();

  void dispose() {
    nameCtrl.dispose();
    percentCtrl.dispose();
  }
}

class StoreFinancialInterviewDialog extends StatefulWidget {
  const StoreFinancialInterviewDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const StoreFinancialInterviewDialog(),
    );
  }

  @override
  State<StoreFinancialInterviewDialog> createState() =>
      _StoreFinancialInterviewDialogState();
}

class _StoreFinancialInterviewDialogState
    extends State<StoreFinancialInterviewDialog> {
  final _capitalCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  final List<_PartnerDraftRow> _partners = [_PartnerDraftRow()];
  bool _hasPartners = false;
  bool _isSaving = false;
  static const String _budgetMetaKey = 'finance.monthly_expense_budget';
  static const String _partnersMetaKey = 'partners_registry';

  @override
  void dispose() {
    _capitalCtrl.dispose();
    _budgetCtrl.dispose();
    for (final p in _partners) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final db = getIt<AppDatabase>();
      final now = DateTime.now();
      const uuid = Uuid();

      final totalCapitalPiasters =
          Money.fromString(_capitalCtrl.text.trim()).piasters;
      final monthlyBudgetPiasters =
          Money.fromString(_budgetCtrl.text.trim()).piasters;

      if (monthlyBudgetPiasters > 0) {
        await db.into(db.appMeta).insert(
              AppMetaCompanion.insert(
                key: _budgetMetaKey,
                value: monthlyBudgetPiasters.toString(),
                updatedAt: now,
              ),
              mode: drift.InsertMode.insertOrReplace,
            );
      }

      final List<PartnerEntity> partnersToSave = [];
      if (_hasPartners) {
        for (final row in _partners) {
          final name = row.nameCtrl.text.trim();
          final pct =
              double.tryParse(Money.normalizeDigits(row.percentCtrl.text)) ??
                  0.0;
          if (name.isEmpty) continue;
          final partnerCapital =
              ((totalCapitalPiasters * pct) / 100.0).round();
          partnersToSave.add(
            PartnerEntity(
              id: uuid.v4(),
              name: name,
              percentage: pct,
              capital: partnerCapital,
              createdAt: now,
            ),
          );
        }
      } else if (totalCapitalPiasters > 0) {
        partnersToSave.add(
          PartnerEntity(
            id: uuid.v4(),
            name: 'المالك الرئيسي',
            percentage: 100.0,
            capital: totalCapitalPiasters,
            createdAt: now,
          ),
        );
      }

      if (partnersToSave.isNotEmpty) {
        await db.into(db.appMeta).insert(
              AppMetaCompanion.insert(
                key: _partnersMetaKey,
                value: jsonEncode(partnersToSave.map((e) => e.toJson()).toList()),
                updatedAt: now,
              ),
              mode: drift.InsertMode.insertOrReplace,
            );
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر حفظ البيانات المالية: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(false),
        const SingleActivator(LogicalKeyboardKey.f12): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
      },
      child: AlertDialog(
        title: Row(
          children: [
            Icon(Icons.account_balance_wallet_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'استبيان الوضع المالي (اختياري)',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'تساعدنا هذه المعلومات الاختيارية في قياس العائد على رأس المال وتنبيهك إذا تجاوزت مصاريف الشهر الميزانية المتوقعة.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const Key('interview_capital_field'),
                  controller: _capitalCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'رأس مال المحل (أصل المحل بالجنيه)',
                    hintText: 'مثال: 250000',
                    prefixIcon: Icon(Icons.savings_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('interview_budget_field'),
                  controller: _budgetCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'متوسط المصاريف الشهرية المتوقعة (ج.م)',
                    hintText: 'مثال: 15000 (إيجار، كهرباء، رواتب)',
                    prefixIcon: Icon(Icons.request_quote_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  key: const Key('interview_has_partners_switch'),
                  contentPadding: EdgeInsets.zero,
                  value: _hasPartners,
                  onChanged: (v) => setState(() => _hasPartners = v),
                  title: const Text(
                    'هل يوجد شركاء في المحل؟',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                  subtitle: Text(
                    _hasPartners
                        ? 'أضف أسماء الشركاء ونسبة كل شريك'
                        : 'مالك منفرد بنسبة 100%',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (_hasPartners) ...[
                  const SizedBox(height: 6),
                  for (var i = 0; i < _partners.length; i++) ...[
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            key: Key('interview_partner_name_$i'),
                            controller: _partners[i].nameCtrl,
                            decoration: InputDecoration(
                              labelText: 'اسم الشريك ${i + 1}',
                              isDense: true,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            key: Key('interview_partner_percent_$i'),
                            controller: _partners[i].percentCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'النسبة %',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _partners.add(_PartnerDraftRow())),
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: const Text('إضافة شريك آخر'),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('interview_skip_btn'),
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
            child: const Text('تخطي / لا أعرف الآن'),
          ),
          ElevatedButton(
            key: const Key('interview_save_btn'),
            onPressed: _isSaving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('حفظ [F12]'),
          ),
        ],
      ),
    );
  }
}

