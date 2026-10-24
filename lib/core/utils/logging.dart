import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

class Logging {
  /// General log (Green)
  static void g(String message, {String tag = 'MyApp-Log'}) {
    if (kDebugMode) {
      developer.log(
        message,
        name: tag,
        time: DateTime.now(),
        level: 0, 
      );
    }
  }

  /// Error log (Red)
  static void error(String message, {String tag = 'MyApp-Error'}) {
    if (kDebugMode) {
      developer.log(
        message,
        name: tag,
        time: DateTime.now(),
        level: 1000, // Severe error
      );
    }
  }

  /// Warning log (Yellow)
  static void warn(String message, {String tag = 'MyApp-Warning'}) {
    if (kDebugMode) {
      developer.log(
        message,
        name: tag,
        time: DateTime.now(),
        level: 900, // Warning
      );
    }
  }

  /// Info log (Blue)
  static void info(String message, {String tag = 'MyApp-Info'}) {
    if (kDebugMode) {
      developer.log(
        message,
        name: tag,
        time: DateTime.now(),
        level: 800, // Info
      );
    }
  }
}
