import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/app_colors.dart';
import '../app_update_service.dart';

class AppUpdateDialog extends StatefulWidget {
  final AppUpdateInfo updateInfo;
  final String currentVersion;
  final bool isForce;

  const AppUpdateDialog({
    super.key,
    required this.updateInfo,
    required this.currentVersion,
    required this.isForce,
  });

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  bool _downloading = false;
  double _progress = 0.0;
  String? _downloadedPath;
  String? _errorMessage;
  final CancelToken _cancelToken = CancelToken();

  Future<void> _handleUpdate() async {
    final urlStr = widget.updateInfo.downloadUrl.trim();
    if (urlStr.isEmpty) {
      setState(() => _errorMessage = 'رابط التحديث غير متوفر حالياً');
      return;
    }

    setState(() {
      _downloading = true;
      _progress = 0.0;
      _errorMessage = null;
      _downloadedPath = null;
    });

    try {
      final path = await AppUpdateService.downloadUpdate(
        urlStr,
        cancelToken: _cancelToken,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadedPath = path;
        _progress = 1.0;
      });
    } catch (e) {
      if (!mounted) return;
      if (e is DioException && e.type == DioExceptionType.cancel) {
        setState(() {
          _downloading = false;
          _progress = 0.0;
        });
        return;
      }
      setState(() {
        _downloading = false;
        _errorMessage = 'فشل تحميل التحديث: $e';
      });
    }
  }

  void _cancelDownload() {
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel('cancelled');
    }
    setState(() {
      _downloading = false;
      _progress = 0.0;
    });
  }

  Future<void> _openFile() async {
    final path = _downloadedPath;
    if (path == null) return;
    try {
      final uri = Uri.file(path);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        await launchUrl(Uri.file(File(path).parent.path), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر فتح الملف: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _openFolder() async {
    final path = _downloadedPath;
    if (path == null) return;
    try {
      await launchUrl(Uri.file(File(path).parent.path), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر فتح المجلد: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _installUpdate() async {
    final path = _downloadedPath;
    if (path == null) return;
    final lower = path.toLowerCase();
    try {
      if (Platform.isWindows && (lower.endsWith('.exe') || lower.endsWith('.msix'))) {
        final uri = Uri.file(path);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
      if (Platform.isWindows && lower.endsWith('.zip')) {
        await launchUrl(Uri.file(File(path).parent.path), mode: LaunchMode.externalApplication);
        return;
      }
      await _openFile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر بدء التثبيت: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _applyPortableUpdate() async {
    final path = _downloadedPath;
    if (path == null) return;
    final lower = path.toLowerCase();
    if (!Platform.isWindows || !lower.endsWith('.exe')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('التحديث الذاتي متاح فقط لملفات .exe على ويندوز'), backgroundColor: AppColors.warning),
        );
      }
      return;
    }
    try {
      await AppUpdateService.applyUpdateAndRestart(path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تطبيق التحديث: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final updateInfo = widget.updateInfo;
    final currentVersion = widget.currentVersion;
    final isForce = widget.isForce;
    final canClose = !isForce && !_downloading;

    return PopScope(
      canPop: canClose,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 8,
        backgroundColor: Colors.white,
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryContainer],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(
                  _downloadedPath != null ? Icons.check_circle_rounded : Icons.system_update_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _downloadedPath != null ? 'اكتمل تحميل التحديث' : 'تحديث جديد متوفر!',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.onSurface),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _downloadedPath != null
                    ? 'تم تحميل ملف التحديث بنجاح. يمكنك تثبيته الآن أو فتح المجلد.'
                    : 'يتوفر إصدار أحدث من التطبيق يتضمن تحسينات ومزايا جديدة.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _versionBadge('الإصدار الحالي', 'v$currentVersion', Colors.grey.shade200, Colors.grey.shade800),
                    const Icon(Icons.arrow_forward_rounded, color: AppColors.primary, size: 20),
                    _versionBadge('الإصدار الجديد', 'v${updateInfo.latestVersion}', AppColors.successContainer, AppColors.success),
                  ],
                ),
              ),
              if (isForce && _downloadedPath == null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.warningContainer,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'هذا التحديث إجباري لمتابعة استخدام النظام ومزامنة البيانات.',
                          style: TextStyle(fontSize: 12, color: AppColors.warning, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (updateInfo.releaseNotes.isNotEmpty && !_downloading && _downloadedPath == null) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('ما الجديد في هذا التحديث:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 120),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.outlineVariant),
                  ),
                  child: SingleChildScrollView(
                    child: Text(updateInfo.releaseNotes, style: const TextStyle(fontSize: 12, height: 1.5, color: AppColors.onSurface)),
                  ),
                ),
              ],
              if (_downloading) ...[
                const SizedBox(height: 20),
                LinearProgressIndicator(
                  value: _progress,
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(8),
                  backgroundColor: AppColors.surfaceContainer,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 8),
                Text('جارٍ التحميل: ${(_progress * 100).toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
              if (_downloadedPath != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.successContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _downloadedPath!,
                    style: const TextStyle(fontSize: 11),
                    textDirection: TextDirection.ltr,
                  ),
                ),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(_errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
                ),
              ],
              const SizedBox(height: 24),
              _buildActions(canClose),
            ],
          ),
        ),
      ),
    );
  }

  Widget _versionBadge(String label, String version, Color bg, Color fg) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          child: Text(version, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: fg)),
        ),
      ],
    );
  }

  Widget _buildActions(bool canClose) {
    if (_downloading) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _cancelDownload,
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('إلغاء التحميل'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: const BorderSide(color: AppColors.error),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    if (_downloadedPath != null) {
      final isPortableExe = Platform.isWindows && _downloadedPath!.toLowerCase().endsWith('.exe');
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openFolder,
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text('فتح المجلد'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _installUpdate,
                  icon: const Icon(Icons.install_desktop_rounded, color: Colors.white),
                  label: const Text('تثبيت الآن', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          if (isPortableExe) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: _applyPortableUpdate,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('تطبيق التحديث وإعادة التشغيل (نسخة محمولة)'),
              ),
            ),
          ],
        ],
      );
    }

    return Row(
      children: [
        if (canClose) ...[
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('لاحقاً', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: _handleUpdate,
            icon: const Icon(Icons.download_rounded, color: Colors.white, size: 20),
            label: const Text('حدث الآن', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }
}


