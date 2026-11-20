import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/app_colors.dart';
import '../../database/emergency_recovery_service.dart';

class EmergencyRecoveryScreen extends StatefulWidget {
  final EmergencyRecoveryService recoveryService;
  final EmergencyStatus status;
  final VoidCallback onRestored;

  const EmergencyRecoveryScreen({
    super.key,
    required this.recoveryService,
    required this.status,
    required this.onRestored,
  });

  @override
  State<EmergencyRecoveryScreen> createState() =>
      _EmergencyRecoveryScreenState();
}

class _EmergencyRecoveryScreenState extends State<EmergencyRecoveryScreen> {
  final _pinController = TextEditingController();
  bool _isRestoring = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _handleRestore() async {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال رمز الأمان (PIN) للمتابعة');
      return;
    }

    if (widget.status.backupFile == null ||
        !widget.status.backupFile!.existsSync()) {
      setState(() => _errorMessage = 'ملف النسخة الاحتياطية غير متوفر');
      return;
    }

    setState(() {
      _isRestoring = true;
      _errorMessage = null;
    });

    try {
      final success = await widget.recoveryService.restoreFromVerifiedBackup(
        widget.status.backupFile!,
      );

      if (success) {
        setState(() {
          _isRestoring = false;
          _successMessage = 'تمت استعادة قاعدة البيانات بنجاح وبأمان تام.';
        });
        await Future.delayed(const Duration(seconds: 1));
        widget.onRestored();
      }
    } catch (e) {
      setState(() {
        _isRestoring = false;
        _errorMessage = 'فشلت عملية الاستعادة: $e';
      });
    }
  }

  Future<void> _handleExportDiagnostics() async {
    final report = await widget.recoveryService.exportDiagnosticReport(
      widget.status,
    );
    await Clipboard.setData(ClipboardData(text: report));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'تم نسخ تقرير التشخيص للحافظة بنجاح، يمكنك إرساله للدعم الفني.',
          ),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final backup = widget.status.backupFile;
    final marker = widget.status.marker;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: AppColors.error.withValues(alpha: 0.2),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header Icon & Title
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.shield_outlined,
                            color: AppColors.error,
                            size: 48,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'شاشة الاسترجاع المحمي ونظام الطوارئ',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.status.reason ==
                                EmergencyReason.incompleteMigration
                            ? 'تم رصد محاولة ترقية سابقة لم تكتمل (انقطاع كهرباء أو إغلاق قسري).\nبياناتك محمية داخل نسخة احتياطية معتمدة ومفحوصة.'
                            : 'تم رصد تعثر في فتح ملف قاعدة البيانات الحالي.\nيمكنك استعادة النسخة الاحتياطية المعتمدة فوراً.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Backup Details Card
                      if (backup != null)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: AppColors.success,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'النسخة الاحتياطية المعتمدة (Verified)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 16),
                              Text(
                                'الملف: ${backup.path.split(Platform.pathSeparator).last}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              if (marker != null)
                                Text(
                                  'الإصدار: ترقية من V${marker.versionFrom} إلى V${marker.versionTo}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              Text(
                                'الحجم: ${(backup.lengthSync() / 1024).toStringAsFixed(1)} KB',
                                style: const TextStyle(fontSize: 12),
                              ),
                              Text(
                                'التاريخ: ${backup.lastModifiedSync().toLocal()}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 20),

                      // PIN Input
                      TextField(
                        controller: _pinController,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'رمز أمان الإدارة (Manager PIN)',
                          hintText: 'أدخل الرمز لتأكيد الاستعادة',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          errorText: _errorMessage,
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (_successMessage != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _successMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),

                      // Restore Action Button
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _isRestoring ? null : _handleRestore,
                        icon: _isRestoring
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.restore_rounded),
                        label: Text(
                          _isRestoring
                              ? 'جاري الاستعادة...'
                              : 'استعادة النسخة الاحتياطية المعتمدة',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Export Diagnostics Button
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.onSurface,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _handleExportDiagnostics,
                        icon: const Icon(Icons.bug_report_outlined, size: 18),
                        label: const Text(
                          'نسخ تقرير التشخيص الفني (بدون بيانات عملاء)',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
