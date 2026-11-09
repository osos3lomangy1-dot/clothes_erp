/// Application Configuration
///
/// Compile-time flags to configure features and safe-mode options.
class AppConfig {
  /// Whether Firebase is enabled.
  ///
  /// Can be overridden at build time via:
  /// `--dart-define=ENABLE_FIREBASE=false`
  static const bool enableFirebase = bool.fromEnvironment(
    'ENABLE_FIREBASE',
    defaultValue: true,
  );
}

/// Global shortcut for convenience
const bool kEnableFirebase = AppConfig.enableFirebase;

