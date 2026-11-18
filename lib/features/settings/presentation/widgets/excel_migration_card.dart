import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/excel_workbook_service.dart';
import '../screens/excel_migration_screen.dart';

class ExcelMigrationCard extends StatefulWidget {
  final String userId;
  final ExcelWorkbookService? serviceOverride;

  const ExcelMigrationCard({
    super.key,
    required this.userId,
    this.serviceOverride,
  });

  @override
  State<ExcelMigrationCard> createState() => _ExcelMigrationCardState();
}

class _ExcelMigrationCardState extends State<ExcelMigrationCard> {
  bool _busy = false;
  String? _busyMessage;

  ExcelWorkbookService? get _service {
    if (widget.serviceOverride != null) return widget.serviceOverride;
    return getIt.isRegistered<ExcelWorkbookService>()
        ? getIt<ExcelWorkbookService>()
        : null;
  }

  Future<void> _exportFullWorkbook() async {
    final svc = _service;
    if (svc == null) return;
    setState(() {
      _busy = true;
      _busyMessage = 'جارٍ تصدير النظام بالكامل (12 شيت مربوطة بالمعادلات)...';
    });
    try {
      final result = await svc.exportFullWorkbook();
      if (!mounted) return;
      if (result == null) return; // User cancelled

      final sizeKb = (result.sizeBytes / 1024).toStringAsFixed(1);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.teal),
              SizedBox(width: 8),
              Expanded(child: Text('تم التصدير الشامل بنجاح')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('عدد الأوراق (الشيتات المربوطة): ${result.sheetCount} شيت'),
              Text('الأصناف: ${result.productsCount} | العملاء: ${result.customersCount} | الموردون: ${result.suppliersCount}'),
              Text('الفواتير: ${result.salesCount} | عقود التقسيط: ${result.installmentsCount} | المصروفات: ${result.expensesCount}'),
              const SizedBox(height: 8),
              Text(
                'الحجم: $sizeKb كيلوبايت',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
              const SizedBox(height: 8),
              SelectableText(
                result.filePath,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          actions: [
            if (Platform.isWindows)
              TextButton.icon(
                onPressed: () {
                  final dir = File(result.filePath).parent.path;
                  Process.start('explorer.exe', [dir]);
                },
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('فتح المجلد'),
              ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          content: Text('فشل التصدير الشامل: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyMessage = null;
        });
      }
    }
  }

  Future<void> _downloadTemplate() async {
    final svc = _service;
    if (svc == null) return;
    setState(() {
      _busy = true;
      _busyMessage = 'جارٍ تجهيز قالب النقل الجاهز...';
    });
    try {
      final path = await svc.exportMigrationTemplate();
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade800,
          content: Text('تم حفظ قالب النقل الجاهز في:\n$path'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          content: Text('فشل تحميل القالب: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyMessage = null;
        });
      }
    }
  }

  void _openImportWizard() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExcelMigrationScreen(
          userId: widget.userId,
          serviceOverride: widget.serviceOverride,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.table_chart_rounded,
                    color: Colors.teal.shade800,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مركز الإكسيل ونقل بيانات المحلات',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'صدّر النظام بالكامل في ملف إكسيل واحد (12 شيت مربوطة بالمعادلات) أو انقل بيانات محلك من إكسيل بسهولة.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _busyMessage ?? 'جارٍ التنفيذ...',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  key: const Key('export_full_excel_btn'),
                  onPressed: _busy ? null : _exportFullWorkbook,
                  icon: const Icon(Icons.file_download_rounded, size: 18),
                  label: const Text('تصدير النظام بالكامل (إكسيل مربوط)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
                OutlinedButton.icon(
                  key: const Key('open_excel_wizard_btn'),
                  onPressed: _busy ? null : _openImportWizard,
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: const Text('استيراد ونقل بيانات من إكسيل'),
                ),
                TextButton.icon(
                  key: const Key('download_excel_template_btn'),
                  onPressed: _busy ? null : _downloadTemplate,
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text('تحميل قالب النقل الجاهز'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

