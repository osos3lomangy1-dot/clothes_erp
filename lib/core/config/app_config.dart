/// Application Configuration
///
/// Compile-time flags to configure features and safe-mode options.
class AppConfig {
  /// Whether Firebase is enabled.
  /// Intentionally false for Windows desktop.
  static const bool enableFirebase = false;
}

/// Global shortcut for convenience
const bool kEnableFirebase = false;
