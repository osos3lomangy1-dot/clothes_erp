import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/local_backup_service.dart';

class LocalBackupCard extends StatefulWidget {
  final String userId;

  const LocalBackupCard({super.key, required this.userId});

  @override
  State<LocalBackupCard> createState() => _LocalBackupCardState();
}

class _LocalBackupCardState extends State<LocalBackupCard> {
  LocalBackupConfig? _config;
  List<BackupFileInfo> _recentBackups = const [];
  bool _loading = true;
  bool _busy = false;
  String? _busyMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  LocalBackupService? get _service =>
      getIt.isRegistered<LocalBackupService>() ? getIt<LocalBackupService>() : null;

  Future<void> _load() async {
    final svc = _service;
    if (svc == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final cfg = await svc.loadConfig();
      final files = await svc.listBackups(directoryPath: cfg.directoryPath);
      if (!mounted) return;
      setState(() {
        _config = cfg;
        _recentBackups = files.take(5).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createQuickBackup() async {
    final svc = _service;
    if (svc == null) return;
    setState(() {
      _busy = true;
      _busyMessage = 'جارٍ إنشاء نسخة احتياطية آمنة...';
    });
    try {
      final res = await svc.createBackup(userId: widget.userId);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade800,
          content: Text(
            'تم إنشاء النسخة الاحتياطية بنجاح (${LocalBackupService.formatBytes(res.sizeBytes)})\n${res.filePath}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          content: Text('فشل إنشاء النسخة الاحتياطية: $e'),
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

  Future<void> _createBackupToCustomLocation() async {
    final svc = _service;
    if (svc == null) return;

    final stamp = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
    final selectedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'اختر مكان حفظ النسخة الاحتياطية (فلاشة USB / D: / Google Drive)',
      fileName: 'sales_erp_backup_$stamp.sqlite',
      type: FileType.custom,
      allowedExtensions: ['sqlite'],
    );
    if (selectedPath == null || selectedPath.trim().isEmpty) return;

    setState(() {
      _busy = true;
      _busyMessage = 'جارٍ حفظ النسخة الاحتياطية...';
    });
    try {
      final res = await svc.createBackup(
        targetFilePath: selectedPath,
        userId: widget.userId,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade800,
          content: Text(
            'تم حفظ النسخة الاحتياطية بنجاح (${LocalBackupService.formatBytes(res.sizeBytes)})\n${res.filePath}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          content: Text('فشل حفظ النسخة الاحتياطية: $e'),
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

  Future<void> _pickBackupDirectory() async {
    final svc = _service;
    if (svc == null) return;

    final chosen = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'اختر مجلد النسخ الاحتياطي التلقائي (مثلاً D:\\Backups أو Google Drive)',
      initialDirectory: _config?.directoryPath,
    );
    if (chosen == null || chosen.trim().isEmpty) return;

    try {
      await svc.setBackupDirectory(chosen, userId: widget.userId);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade800,
          content: Text('تم تحديث مجلد النسخ الاحتياطي إلى:\n$chosen'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          content: Text('تعذر تغيير المجلد: $e'),
        ),
      );
    }
  }

  Future<void> _openBackupFolder() async {
    final dirPath = _config?.directoryPath;
    if (dirPath == null || dirPath.isEmpty) return;
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      if (Platform.isWindows) {
        await Process.run('explorer', [dir.path]);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر فتح المجلد: $e')),
      );
    }
  }

  Future<void> _pickAndRestoreBackup({String? preselectedPath}) async {
    final svc = _service;
    if (svc == null) return;

    String? sourcePath = preselectedPath;
    if (sourcePath == null) {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: 'اختر ملف النسخة الاحتياطية (.sqlite) للاستعادة',
        type: FileType.custom,
        allowedExtensions: ['sqlite', 'db'],
      );
      if (picked == null || picked.files.isEmpty) return;
      sourcePath = picked.files.first.path;
    }
    if (sourcePath == null || sourcePath.trim().isEmpty) return;

    // Step 1: Validate integrity BEFORE asking confirmation
    setState(() {
      _busy = true;
      _busyMessage = 'جارٍ فحص سلامة ملف النسخة الاحتياطية...';
    });
    final validationError = await svc.validateBackupFile(sourcePath);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _busyMessage = null;
    });

    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          content: Text(validationError),
        ),
      );
      return;
    }

    // Step 2: Explicit Admin Confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 26),
            SizedBox(width: 8),
            Text('تأكيد استعادة النسخة الاحتياطية', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'سيتم استبدال قاعدة البيانات الحالية بالكامل بالنسخة المحددة:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  sourcePath!,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, color: Colors.green.shade800, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'للأمان: سيأخذ النظام تلقائياً نسخة أمان من بياناتك الحالية قبل الاستبدال.',
                        style: TextStyle(fontSize: 12, color: Colors.green.shade900),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'بعد الاستعادة سيُطلب إغلاق البرنامج وإعادة فتحه لتفعيل البيانات المستعادة.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('تأكيد الاستعادة الآن'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _busyMessage = 'جارٍ أخذ نسخة أمان واستعادة البيانات...';
    });

    try {
      final result = await svc.restoreFromBackup(
        sourceBackupPath: sourcePath,
        userId: widget.userId,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _busyMessage = null;
      });

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.green.shade700, size: 26),
              const SizedBox(width: 8),
              const Text('تمت الاستعادة بنجاح', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            'تمت استعادة قاعدة البيانات بنجاح.\n'
            'تم حفظ نسخة أمان من البيانات السابقة في:\n${result.safetyBackupPath}\n\n'
            'سيتم إعادة تشغيل البرنامج الآن لتحميل البيانات المستعادة وتحديث جميع الشاشات.',
          ),
          actions: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('إعادة تشغيل البرنامج الآن'),
              onPressed: () async {
                if (Platform.isWindows) {
                  try {
                    await Process.start(
                      Platform.resolvedExecutable,
                      const [],
                      mode: ProcessStartMode.detached,
                    );
                  } catch (_) {}
                }
                exit(0);
              },
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _busyMessage = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          content: Text('فشلت الاستعادة: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_service == null) {
      return const SizedBox.shrink();
    }
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final cfg = _config!;
    final dateFmt = DateFormat('yyyy/MM/dd - hh:mm a');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Last Backup Status Banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cfg.lastBackupAt != null
                    ? Colors.green.shade50
                    : Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: cfg.lastBackupAt != null
                      ? Colors.green.shade200
                      : Colors.amber.shade300,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    cfg.lastBackupAt != null
                        ? Icons.verified_user_rounded
                        : Icons.info_outline_rounded,
                    color: cfg.lastBackupAt != null
                        ? Colors.green.shade800
                        : Colors.amber.shade900,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cfg.lastBackupAt != null
                              ? 'آخر نسخة احتياطية: ${dateFmt.format(cfg.lastBackupAt!)}'
                              : 'لم يتم إنشاء نسخة احتياطية يدوية أو تلقائية بعد',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: cfg.lastBackupAt != null
                                ? Colors.green.shade900
                                : Colors.amber.shade900,
                          ),
                        ),
                        if (cfg.lastBackupPath != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            cfg.lastBackupPath!,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Busy Indicator
            if (_busy) ...[
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _busyMessage ?? 'جارٍ التنفيذ...',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],

            // Primary Action Buttons
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  key: const Key('backup_quick_btn'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _busy ? null : _createQuickBackup,
                  icon: const Icon(Icons.backup_rounded, size: 18),
                  label: const Text('نسخة احتياطية الآن'),
                ),
                OutlinedButton.icon(
                  key: const Key('backup_save_as_btn'),
                  onPressed: _busy ? null : _createBackupToCustomLocation,
                  icon: const Icon(Icons.usb_rounded, size: 18),
                  label: const Text('حفظ على فلاشة / مسار مخصص'),
                ),
                OutlinedButton.icon(
                  key: const Key('backup_restore_btn'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
                  ),
                  onPressed: _busy ? null : () => _pickAndRestoreBackup(),
                  icon: const Icon(Icons.settings_backup_restore_rounded, size: 18),
                  label: const Text('استعادة نسخة احتياطية'),
                ),
              ],
            ),

            const Divider(height: 24),

            // Auto Daily Backup Toggle
            SwitchListTile(
              key: const Key('backup_auto_toggle'),
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'النسخ الاحتياطي التلقائي اليومي',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              subtitle: const Text(
                'ينشئ النظام تلقائياً نسخة احتياطية نظيفة مرة واحدة يومياً عند الفتح، ويحذف النسخ الأقدم تلقائياً.',
                style: TextStyle(fontSize: 12),
              ),
              secondary: Icon(
                cfg.autoEnabled ? Icons.schedule_rounded : Icons.pause_circle_outline_rounded,
                color: cfg.autoEnabled ? AppColors.primary : Colors.grey,
              ),
              value: cfg.autoEnabled,
              onChanged: _busy
                  ? null
                  : (v) async {
                      await _service!.setAutoEnabled(v, userId: widget.userId);
                      await _load();
                    },
            ),

            // Backup Directory & Retention Row
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.folder_rounded, size: 18, color: Colors.amber),
                      const SizedBox(width: 8),
                      const Text(
                        'مجلد النسخ الاحتياطي:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _busy ? null : _openBackupFolder,
                        icon: const Icon(Icons.open_in_new_rounded, size: 15),
                        label: const Text('فتح المجلد', style: TextStyle(fontSize: 12)),
                      ),
                      TextButton.icon(
                        onPressed: _busy ? null : _pickBackupDirectory,
                        icon: const Icon(Icons.edit_location_alt_outlined, size: 15),
                        label: const Text('تغيير المجلد', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  Text(
                    cfg.directoryPath,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade800, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'الاحتفاظ بآخر:',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                      const SizedBox(width: 10),
                      DropdownButton<int>(
                        value: [7, 14, 30, 60].contains(cfg.retentionCount)
                            ? cfg.retentionCount
                            : 30,
                        isDense: true,
                        items: const [
                          DropdownMenuItem(value: 7, child: Text('7 نسخ يومية')),
                          DropdownMenuItem(value: 14, child: Text('14 نسخة يومية')),
                          DropdownMenuItem(value: 30, child: Text('30 نسخة يومية')),
                          DropdownMenuItem(value: 60, child: Text('60 نسخة يومية')),
                        ],
                        onChanged: _busy
                            ? null
                            : (val) async {
                                if (val != null) {
                                  await _service!.setRetentionCount(val, userId: widget.userId);
                                  await _load();
                                }
                              },
                      ),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          'نصيحة: اختر مجلد Google Drive أو بارتشن D: لحماية بياناتك لو تلف الويندوز',
                          style: TextStyle(fontSize: 11, color: Colors.teal.shade800),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Recent Backups in Folder
            if (_recentBackups.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'أحدث النسخ المحفوظة في المجلد (${_recentBackups.length}):',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 6),
              ..._recentBackups.map((file) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.storage_rounded, size: 18, color: AppColors.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              file.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${dateFmt.format(file.modifiedAt)}  •  ${LocalBackupService.formatBytes(file.sizeBytes)}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _pickAndRestoreBackup(preselectedPath: file.path),
                        child: const Text('استعادة', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

