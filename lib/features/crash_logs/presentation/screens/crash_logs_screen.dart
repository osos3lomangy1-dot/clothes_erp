import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/crash_logger_service.dart';
import '../../../../features/auth/presentation/cubits/auth_cubit.dart';
import '../../../../features/auth/presentation/cubits/auth_state.dart';

class CrashLogsScreen extends StatefulWidget {
  const CrashLogsScreen({super.key});

  @override
  State<CrashLogsScreen> createState() => _CrashLogsScreenState();
}

class _CrashLogsScreenState extends State<CrashLogsScreen> {
  List<CrashLogEntry> _logs = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    final logs = await CrashLoggerService.getCrashLogs();
    if (mounted) {
      setState(() {
        _logs = logs;
        _isLoading = false;
      });
    }
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: AppColors.error),
            SizedBox(width: 8),
            Text('تأكيد مسح السجلات', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text('هل أنت متأكد من رغبتك في حذف كافة سجلات الأعطال المحفوظة محلياً؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('مسح الكل', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await CrashLoggerService.clearLogs();
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم مسح كافة سجلات الأعطال بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
          _loadLogs();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تعذر مسح بعض ملفات السجلات'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  void _copyAllLogs() {
    if (_logs.isEmpty) return;
    final all = _logs.map((e) => e.raw).join('\n\n');
    Clipboard.setData(ClipboardData(text: all));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ جميع تقارير الأعطال إلى الحافظة'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _copySingleLog(CrashLogEntry entry) {
    Clipboard.setData(ClipboardData(text: entry.raw));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم نسخ تقرير عطل ${entry.formattedDate}'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. Verify Admin Access
    final authState = context.watch<AuthCubit>().state;
    final isAdmin = authState is AuthAuthenticated && authState.user.role == 'admin';

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('سجلات الأعطال')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_person_rounded, size: 64, color: AppColors.error),
              const SizedBox(height: 16),
              const Text(
                'هذه الصفحة مخصصة لمدير النظام فقط',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'ليس لديك الصلاحيات الكافية للوصول لسجلات أعطال النظام.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    final filteredLogs = _searchQuery.trim().isEmpty
        ? _logs
        : _logs.where((l) {
            final q = _searchQuery.toLowerCase();
            return l.error.toLowerCase().contains(q) ||
                l.context.toLowerCase().contains(q) ||
                l.platform.toLowerCase().contains(q) ||
                l.formattedDate.contains(q);
          }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.bug_report_rounded, color: Colors.white),
            SizedBox(width: 10),
            Text('سجلات الأعطال (Crash Logs)', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'تحديث السجلات',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadLogs,
          ),
          if (_logs.isNotEmpty) ...[
            IconButton(
              tooltip: 'نسخ جميع السجلات',
              icon: const Icon(Icons.copy_all_rounded),
              onPressed: _copyAllLogs,
            ),
            IconButton(
              tooltip: 'مسح السجلات',
              icon: const Icon(Icons.delete_sweep_rounded),
              onPressed: _clearLogs,
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Info & File path bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _logs.isEmpty ? Colors.green.shade50 : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _logs.isEmpty ? Colors.green.shade300 : Colors.red.shade300,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _logs.isEmpty ? Icons.check_circle_rounded : Icons.warning_rounded,
                                  size: 16,
                                  color: _logs.isEmpty ? Colors.green.shade700 : AppColors.error,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'عدد الأعطال المسجلة: ${_logs.length}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: _logs.isEmpty ? Colors.green.shade700 : AppColors.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              'مسار الملف: ${CrashLoggerService.getLogFilePath()}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Search bar
          if (_logs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'البحث في سجلات الأعطال (الرسالة، الشاشة، التوقيت)...',
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
            ),

          // Logs List or Empty State
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _logs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.check_circle_outline_rounded,
                                size: 72,
                                color: Colors.green.shade700,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'لا توجد أي سجلات أعطال مسجلة',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'التطبيق يعمل بكفاءة واستقرار تام دون أي انهيارات غير معالجة.',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )
                    : filteredLogs.isEmpty
                        ? Center(
                            child: Text(
                              'لا توجد نتائج مطابقة لـ "$_searchQuery"',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: filteredLogs.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final entry = filteredLogs[index];
                              return _buildLogCard(entry);
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogCard(CrashLogEntry entry) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.red.shade100, width: 1),
      ),
      color: Colors.white,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 24),
          ),
          title: Text(
            entry.error.split('\n').first,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: AppColors.error,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _chip(Icons.access_time_rounded, entry.formattedDate, Colors.blue.shade700, Colors.blue.shade50),
                _chip(Icons.layers_rounded, entry.context, Colors.purple.shade700, Colors.purple.shade50),
                _chip(Icons.devices_rounded, entry.platform, Colors.grey.shade700, Colors.grey.shade100),
              ],
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  const SizedBox(height: 8),

                  // Actions row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'تفاصيل التقرير الكامل:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _copySingleLog(entry),
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('نسخ التقرير', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Breadcrumbs section if available
                  if (entry.breadcrumbs.isNotEmpty) ...[
                    const Text(
                      'سجل التنقلات والإجراءات الأخيرة (Breadcrumbs):',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: entry.breadcrumbs
                            .map((b) => Text(b, style: TextStyle(fontSize: 11, color: Colors.amber.shade900)))
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Full Stack Trace / Raw Log
                  const Text(
                    'تتبع الأخطاء (Stack Trace):',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 260),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        entry.stackTrace.isNotEmpty ? entry.stackTrace : entry.raw,
                        style: const TextStyle(
                          color: Color(0xFFD4D4D4),
                          fontFamily: 'monospace',
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color textCol, Color bgCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgCol,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textCol),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: textCol, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
