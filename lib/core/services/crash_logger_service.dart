import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/logging.dart';

class CrashLogEntry {
  final String id;
  final DateTime timestamp;
  final String error;
  final String stackTrace;
  final String context;
  final String platform;
  final List<String> breadcrumbs;
  final String raw;

  CrashLogEntry({
    required this.id,
    required this.timestamp,
    required this.error,
    required this.stackTrace,
    required this.context,
    required this.platform,
    this.breadcrumbs = const [],
    required this.raw,
  });

  String get formattedDate {
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp);
  }
}

class CrashLoggerService {
  static Directory? _logsDir;
  static File? _masterFile;
  static String _lastKnownContext = 'بدء تشغيل التطبيق';
  static final List<String> _breadcrumbs = [];
  static const int _maxBreadcrumbs = 25;
  static bool _initialized = false;

  static const String _delimiter =
      '================================================================================';

  /// Initialize local storage directory for crash logs
  static Future<void> init() async {
    if (_initialized) return;
    try {
      Directory baseDir;
      try {
        baseDir = await getApplicationSupportDirectory();
      } catch (_) {
        try {
          baseDir = await getApplicationDocumentsDirectory();
        } catch (_) {
          baseDir = Directory.current;
        }
      }

      _logsDir = Directory('${baseDir.path}/crash_logs');
      if (!_logsDir!.existsSync()) {
        _logsDir!.createSync(recursive: true);
      }

      _masterFile = File('${_logsDir!.path}/crash_logs.txt');
      if (!_masterFile!.existsSync()) {
        _masterFile!.createSync(recursive: true);
      }
      _initialized = true;
      addBreadcrumb('نظام تسجيل الأعطال المحلي جاهز');
    } catch (e) {
      Logging.error('فشل تهيئة CrashLoggerService: $e');
    }
  }

  /// Update the current screen or user action context
  static void setContext(String context) {
    _lastKnownContext = context;
  }

  /// Add a user action or lifecycle breadcrumb
  static void addBreadcrumb(String action) {
    try {
      final timeStr = DateFormat('HH:mm:ss').format(DateTime.now());
      _breadcrumbs.add('[$timeStr] $action');
      if (_breadcrumbs.length > _maxBreadcrumbs) {
        _breadcrumbs.removeAt(0);
      }
    } catch (_) {}
  }

  /// Log an unexpected crash or error to local disk immediately
  static void logCrash(
    dynamic error,
    StackTrace? stack, {
    String? context,
  }) {
    try {
      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
      final effectiveContext = context ?? _lastKnownContext;
      final platformInfo =
          '${Platform.operatingSystem} (${Platform.operatingSystemVersion})';
      final breadcrumbsSummary = _breadcrumbs.isEmpty
          ? '  (لا توجد سجلات تنقل سابقة)'
          : _breadcrumbs.map((b) => '  $b').join('\n');

      final logContent = StringBuffer()
        ..writeln(_delimiter)
        ..writeln('تقرير عطل (CRASH REPORT) - $dateStr')
        ..writeln('التوقيت الزمني (ISO): ${now.toIso8601String()}')
        ..writeln('السياق / الشاشة الأخيرة: $effectiveContext')
        ..writeln('نظام التشغيل: $platformInfo')
        ..writeln('المسار وسجل التنقلات الأخيرة (Breadcrumbs):')
        ..writeln(breadcrumbsSummary)
        ..writeln('تفاصيل الخطأ:')
        ..writeln(error?.toString() ?? 'خطأ غير معروف')
        ..writeln('تتبع الكومة (Stack Trace):')
        ..writeln(stack?.toString() ?? 'لا يوجد Stack Trace متاح')
        ..writeln(_delimiter)
        ..writeln();

      final logText = logContent.toString();

      // Ensure directory exists or fallback to current directory
      if (_masterFile == null || !_masterFile!.existsSync()) {
        try {
          final fallbackDir = Directory('${Directory.current.path}/crash_logs');
          if (!fallbackDir.existsSync()) fallbackDir.createSync(recursive: true);
          _masterFile = File('${fallbackDir.path}/crash_logs.txt');
        } catch (_) {}
      }

      if (_masterFile != null) {
        _masterFile!.writeAsStringSync(logText, mode: FileMode.append, flush: true);
      }

      // Also write an individual dated file
      if (_logsDir != null && _logsDir!.existsSync()) {
        final singleFile = File(
          '${_logsDir!.path}/crash_${now.millisecondsSinceEpoch}.log',
        );
        singleFile.writeAsStringSync(logText, flush: true);
      }

      Logging.error('تم تسجيل العطل بنجاح في ملفات النظام المحلية: $effectiveContext');
    } catch (e) {
      Logging.error('فشل كتابة تقرير العطل محلياً: $e');
    }
  }

  /// Read and parse all crash logs
  static Future<List<CrashLogEntry>> getCrashLogs() async {
    try {
      if (!_initialized) {
        await init();
      }

      if (_masterFile == null || !_masterFile!.existsSync()) {
        return [];
      }

      final content = await _masterFile!.readAsString();
      if (content.trim().isEmpty) return [];

      final chunks = content.split(_delimiter);
      final entries = <CrashLogEntry>[];

      for (int i = 0; i < chunks.length; i++) {
        final chunk = chunks[i].trim();
        if (chunk.isEmpty) continue;

        DateTime timestamp = DateTime.now();
        String context = 'غير محدد';
        String platform = 'غير محدد';
        String error = '';
        String stackTrace = '';
        final breadcrumbs = <String>[];

        final lines = chunk.split('\n');
        bool inStack = false;
        bool inError = false;
        bool inBreadcrumbs = false;
        final stackBuffer = StringBuffer();
        final errorBuffer = StringBuffer();

        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('التوقيت الزمني (ISO):')) {
            final isoStr = trimmed.replaceFirst('التوقيت الزمني (ISO):', '').trim();
            timestamp = DateTime.tryParse(isoStr) ?? timestamp;
          } else if (trimmed.startsWith('السياق / الشاشة الأخيرة:')) {
            context = trimmed.replaceFirst('السياق / الشاشة الأخيرة:', '').trim();
          } else if (trimmed.startsWith('نظام التشغيل:')) {
            platform = trimmed.replaceFirst('نظام التشغيل:', '').trim();
          } else if (trimmed.startsWith('المسار وسجل التنقلات الأخيرة (Breadcrumbs):')) {
            inBreadcrumbs = true;
            inError = false;
            inStack = false;
          } else if (trimmed.startsWith('تفاصيل الخطأ:')) {
            inError = true;
            inBreadcrumbs = false;
            inStack = false;
          } else if (trimmed.startsWith('تتبع الكومة (Stack Trace):')) {
            inStack = true;
            inError = false;
            inBreadcrumbs = false;
          } else if (inStack) {
            stackBuffer.writeln(line);
          } else if (inError) {
            errorBuffer.writeln(line);
          } else if (inBreadcrumbs) {
            if (trimmed.isNotEmpty && !trimmed.startsWith('(')) {
              breadcrumbs.add(trimmed);
            }
          }
        }

        error = errorBuffer.toString().trim();
        stackTrace = stackBuffer.toString().trim();

        if (error.isEmpty) {
          error = chunk;
        }

        entries.add(
          CrashLogEntry(
            id: 'crash_${entries.length + 1}',
            timestamp: timestamp,
            error: error,
            stackTrace: stackTrace,
            context: context,
            platform: platform,
            breadcrumbs: breadcrumbs,
            raw: chunk,
          ),
        );
      }

      // Return descending order (newest first)
      entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return entries;
    } catch (e) {
      Logging.error('فشل قراءة سجلات الأعطال: $e');
      return [];
    }
  }

  /// Clear all crash logs
  static Future<bool> clearLogs() async {
    try {
      if (_masterFile != null && _masterFile!.existsSync()) {
        await _masterFile!.writeAsString('', flush: true);
      }

      if (_logsDir != null && _logsDir!.existsSync()) {
        final files = _logsDir!.listSync();
        for (final file in files) {
          if (file is File && file.path.endsWith('.log')) {
            try {
              file.deleteSync();
            } catch (_) {}
          }
        }
      }
      return true;
    } catch (e) {
      Logging.error('فشل مسح سجلات الأعطال: $e');
      return false;
    }
  }

  /// Get master log file path
  static String getLogFilePath() {
    return _masterFile?.path ?? (_logsDir != null ? '${_logsDir!.path}/crash_logs.txt' : '');
  }
}

/// NavigatorObserver to automatically track screen transitions as breadcrumbs
class CrashRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    final name = _getRouteName(route);
    CrashLoggerService.setContext('شاشة: $name');
    CrashLoggerService.addBreadcrumb('انتقال إلى $name');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute != null) {
      final name = _getRouteName(previousRoute);
      CrashLoggerService.setContext('شاشة: $name');
      CrashLoggerService.addBreadcrumb('رجوع إلى $name');
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) {
      final name = _getRouteName(newRoute);
      CrashLoggerService.setContext('شاشة: $name');
      CrashLoggerService.addBreadcrumb('استبدال الشاشة بـ $name');
    }
  }

  String _getRouteName(Route<dynamic> route) {
    return route.settings.name ?? route.runtimeType.toString();
  }
}
