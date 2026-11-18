import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/google_drive_backup_service.dart';
import '../../../../core/services/local_backup_service.dart';

/// WhatsApp-style Google Drive backup card:
/// - Pick your Google email account with 1 click
/// - Choose backup schedule: Daily / Weekly / Monthly / Manual only
/// - 1-click "نسخ احتياطي الآن" & "استعادة من Google Drive"
class GoogleDriveBackupCard extends StatefulWidget {
  final String userId;

  const GoogleDriveBackupCard({super.key, required this.userId});

  @override
  State<GoogleDriveBackupCard> createState() => _GoogleDriveBackupCardState();
}

class _GoogleDriveBackupCardState extends State<GoogleDriveBackupCard> {
  DriveAccountStatus? _status;
  bool _loading = true;
  bool _busy = false;
  String? _busyMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  GoogleDriveBackupService? get _service =>
      getIt.isRegistered<GoogleDriveBackupService>()
      ? getIt<GoogleDriveBackupService>()
      : null;

  Future<void> _load() async {
    final svc = _service;
    if (svc == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final s = await svc.getStatus();
      if (!mounted) return;
      setState(() {
        _status = s;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chooseGoogleAccount() async {
    final svc = _service;
    if (svc == null) return;

    if (!(_status?.hasOAuthConfig ?? false)) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.info_outline_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'تفعيل تسجيل الدخول بحساب Google',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: const Text(
            'لتفعيل اختيار حساب Google مباشرة (مثل واتساب)، يجب إضافة مفتاح التطبيق (OAuth Desktop Client ID) مرة واحدة فقط من قِبل المطور في الملف:\n'
            'lib/core/config/google_drive_config.dart\n\n'
            'بعد إضافته، سيعمل هذا الزر مباشرةً لاختيار إيميل Gmail بدون أي خطوات إضافية للمستخدم.',
            style: TextStyle(height: 1.5, fontSize: 13),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() {
      _busy = true;
      _busyMessage = 'تم فتح المتصفح — اختر إيميلك على Google واضغط سماح...';
    });

    try {
      final email = await svc.connectAccount();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade800,
          content: Text('تم ربط حساب Google بنجاح ($email)'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          content: Text(e.toString().replaceFirst('Exception: ', '')),
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

  Future<void> _uploadNow() async {
    final svc = _service;
    if (svc == null) return;

    setState(() {
      _busy = true;
      _busyMessage = 'جارٍ رفع النسخة الاحتياطية إلى Google Drive...';
    });

    try {
      final file = await svc.uploadBackupNow(userId: widget.userId);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade800,
          content: Text(
            'تم النسخ الاحتياطي إلى Google Drive بنجاح (${LocalBackupService.formatBytes(file.sizeBytes)})',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          content: Text(e.toString().replaceFirst('Exception: ', '')),
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

  Future<void> _openFrequencyPicker(DriveAccountStatus status) async {
    final picked = await showDialog<DriveBackupFrequency>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'النسخ الاحتياطي في Google Drive',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: DriveBackupFrequency.values.map((freq) {
            final selected = freq == status.frequency;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? Colors.teal.shade700 : Colors.grey,
              ),
              title: Text(
                freq.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              onTap: () => Navigator.of(ctx).pop(freq),
            );
          }).toList(),
        ),
      ),
    );

    if (picked != null && _service != null) {
      await _service!.setBackupFrequency(picked, userId: widget.userId);
      await _load();
    }
  }

  Future<void> _openRemoteBackupsDialog() async {
    final svc = _service;
    if (svc == null) return;

    setState(() {
      _busy = true;
      _busyMessage = 'جارٍ تحميل قائمة النسخ من Google Drive...';
    });

    List<DriveBackupFile> files;
    try {
      files = await svc.listRemoteBackups();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyMessage = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            content: Text(e.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _busyMessage = null;
    });

    final dateFmt = DateFormat('yyyy/MM/dd - hh:mm a');
    final selectedFile = await showDialog<DriveBackupFile>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.cloud_download_rounded, color: Colors.teal.shade700),
            const SizedBox(width: 8),
            const Text(
              'النسخ المحفوظة على Google Drive',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          height: 340,
          child: files.isEmpty
              ? const Center(
                  child: Text(
                    'لا توجد نسخ احتياطية على حسابك في Google Drive بعد.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.separated(
                  itemCount: files.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, idx) {
                    final f = files[idx];
                    return ListTile(
                      leading: Icon(
                        Icons.storage_rounded,
                        color: Colors.teal.shade700,
                      ),
                      title: Text(
                        f.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${dateFmt.format(f.modifiedAt)}  •  ${LocalBackupService.formatBytes(f.sizeBytes)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onPressed: () => Navigator.of(ctx).pop(f),
                        child: const Text(
                          'استعادة',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );

    if (selectedFile == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error),
            SizedBox(width: 8),
            Text(
              'تأكيد الاستعادة من Google Drive',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'سيتم تحميل النسخة "${selectedFile.name}" من Google Drive واستبدال البيانات الحالية (بعد حفظ نسخة أمان محلية تلقائياً).\n\nهل تريد المتابعة؟',
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
            child: const Text('استعادة الآن'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _busyMessage = 'جارٍ تحميل النسخة من Google Drive واستعادتها...';
    });

    try {
      final result = await svc.downloadAndRestoreBackup(
        file: selectedFile,
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.green.shade700),
              const SizedBox(width: 8),
              const Text(
                'تمت الاستعادة بنجاح',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text(
            'تم تحميل واستعادة النسخة الاحتياطية من Google Drive بنجاح.\n'
            'تم حفظ نسخة أمان من البيانات السابقة في:\n${result.safetyBackupPath}\n\n'
            'سيتم إعادة تشغيل البرنامج الآن لتحميل البيانات المستعادة.',
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
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _disconnect() async {
    final svc = _service;
    if (svc == null) return;
    await svc.disconnect();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تسجيل الخروج من حساب Google Drive')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_service == null) return const SizedBox.shrink();
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final status = _status!;
    final dateFmt = DateFormat('yyyy/MM/dd - hh:mm a');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Last Backup Summary (WhatsApp style)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.backup_rounded,
                    color: Colors.teal.shade700,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'آخر نسخة احتياطية على Google Drive',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        status.lastUploadAt != null
                            ? 'التاريخ: ${dateFmt.format(status.lastUploadAt!)}'
                                  '${status.lastUploadSizeBytes != null ? '  •  الحجم: ${LocalBackupService.formatBytes(status.lastUploadSizeBytes!)}' : ''}'
                            : 'لم يتم إجراء نسخ احتياطي سحابي بعد',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'احفظ نسخة من بيانات محلك على حسابك في Google Drive لتتمكن من استعادتها في أي وقت أو عند تغيير الجهاز.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (_busy) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.teal.shade700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _busyMessage ?? 'جارٍ التنفيذ...',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),

            // Primary WhatsApp-style green "Backup Now" button (or Sign In)
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  key: Key(
                    status.isConnected
                        ? 'gdrive_upload_btn'
                        : 'gdrive_connect_btn',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00A884),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  onPressed: _busy
                      ? null
                      : (status.isConnected
                            ? _uploadNow
                            : _chooseGoogleAccount),
                  icon: Icon(
                    status.isConnected
                        ? Icons.cloud_upload_rounded
                        : Icons.mail_outline_rounded,
                    size: 18,
                  ),
                  label: Text(
                    status.isConnected
                        ? 'نسخ احتياطي الآن'
                        : 'اختيار حساب Google (الإيميل)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (status.isConnected)
                  OutlinedButton.icon(
                    key: const Key('gdrive_restore_btn'),
                    onPressed: _busy ? null : _openRemoteBackupsDialog,
                    icon: const Icon(Icons.cloud_download_rounded, size: 18),
                    label: const Text('استعادة من Google Drive'),
                  ),
              ],
            ),

            const Divider(height: 24),

            // WhatsApp-style Settings Rows: Google Account & Frequency
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.alternate_email_rounded,
                color: status.isConnected ? Colors.teal.shade700 : Colors.grey,
              ),
              title: const Text(
                'حساب Google',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              subtitle: Text(
                status.isConnected
                    ? (status.email ?? 'حساب Google متصل')
                    : 'لم يتم تحديد حساب',
                style: TextStyle(
                  fontSize: 12,
                  color: status.isConnected
                      ? Colors.teal.shade800
                      : Colors.grey,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: _busy ? null : _chooseGoogleAccount,
                    child: Text(
                      status.isConnected ? 'تغيير الحساب' : 'اختيار إيميل',
                    ),
                  ),
                  if (status.isConnected)
                    TextButton(
                      onPressed: _busy ? null : _disconnect,
                      child: const Text(
                        'فصل',
                        style: TextStyle(color: AppColors.error),
                      ),
                    ),
                ],
              ),
            ),

            ListTile(
              key: const Key('gdrive_frequency_tile'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.event_repeat_rounded,
                color: status.isConnected ? Colors.teal.shade700 : Colors.grey,
              ),
              title: const Text(
                'إجراء النسخ الاحتياطي في Google Drive',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              subtitle: Text(
                status.frequency.label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              trailing: const Icon(
                Icons.chevron_left_rounded,
                color: Colors.grey,
              ),
              onTap: _busy ? null : () => _openFrequencyPicker(status),
            ),
          ],
        ),
      ),
    );
  }
}
