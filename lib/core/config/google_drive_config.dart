import 'dart:convert';
import 'dart:io';

/// Developer-level Google OAuth 2.0 Desktop credentials for WhatsApp-style
/// 1-click Google Drive backup ("Sign in with Google Email").
///
/// End users (shop owners) NEVER see or enter these values — they only pick
/// their Gmail account in the browser, just like WhatsApp.
///
/// Security:
/// - Keep real credentials ONLY in the gitignored `env/google_drive.local.json`
///   file (copy `env/google_drive.example.json`).
/// - For release builds, bake them in at compile time with:
///   `flutter build windows --dart-define-from-file=env/google_drive.local.json`
/// - During local development (`flutter run`), if `--dart-define` wasn't passed,
///   this class automatically reads `env/google_drive.local.json` from disk.
class GoogleDriveConfig {
  static const String _compiledClientId = String.fromEnvironment(
    'GDRIVE_CLIENT_ID',
    defaultValue: '',
  );
  static const String _compiledClientSecret = String.fromEnvironment(
    'GDRIVE_CLIENT_SECRET',
    defaultValue: '',
  );

  static Map<String, String>? _localFileCache;

  static Map<String, String> _readLocalFile() {
    if (_localFileCache != null) return _localFileCache!;
    final result = <String, String>{};
    try {
      final file = File(
        '${Directory.current.path}${Platform.pathSeparator}env${Platform.pathSeparator}google_drive.local.json',
      );
      if (file.existsSync()) {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is Map<String, dynamic>) {
          for (final entry in decoded.entries) {
            if (entry.value != null) {
              result[entry.key] = entry.value.toString().trim();
            }
          }
        }
      }
    } catch (_) {}
    _localFileCache = result;
    return result;
  }

  static String get clientId {
    if (_compiledClientId.isNotEmpty) return _compiledClientId;
    return _readLocalFile()['GDRIVE_CLIENT_ID'] ?? '';
  }

  static String get clientSecret {
    if (_compiledClientSecret.isNotEmpty) return _compiledClientSecret;
    return _readLocalFile()['GDRIVE_CLIENT_SECRET'] ?? '';
  }

  static bool get isConfigured => clientId.trim().isNotEmpty;
}
