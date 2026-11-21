import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../config/google_drive_config.dart';
import '../features/feature_gate.dart';
import '../utils/logging.dart';
import 'local_backup_service.dart';

/// Storage abstraction so [GoogleDriveBackupService] uses [FlutterSecureStorage]
/// in production and an in-memory map in unit tests.
abstract class DriveTokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureDriveTokenStore implements DriveTokenStore {
  final FlutterSecureStorage _storage;

  const SecureDriveTokenStore([
    this._storage = const FlutterSecureStorage(),
  ]);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

enum DriveBackupFrequency {
  manual('manual', 'يدوي فقط (عند الضغط على نسخ احتياطي)'),
  daily('daily', 'يومياً'),
  weekly('weekly', 'أسبوعياً'),
  monthly('monthly', 'شهرياً');

  final String key;
  final String label;

  const DriveBackupFrequency(this.key, this.label);

  static DriveBackupFrequency fromKey(String? raw) {
    for (final v in values) {
      if (v.key == raw) return v;
    }
    return DriveBackupFrequency.daily;
  }
}

class DriveBackupMetaKeys {
  static const String autoEnabled = 'backup.gdrive.auto_enabled';
  static const String frequency = 'backup.gdrive.frequency';
  static const String lastUploadAt = 'backup.gdrive.last_upload_at';
  static const String lastUploadName = 'backup.gdrive.last_upload_name';
  static const String lastUploadSize = 'backup.gdrive.last_upload_size';
  static const String lastAutoDate = 'backup.gdrive.last_auto_date';
}

class _DriveSecretKeys {
  static const String clientId = 'gdrive_oauth_client_id';
  static const String clientSecret = 'gdrive_oauth_client_secret';
  static const String accessToken = 'gdrive_oauth_access_token';
  static const String refreshToken = 'gdrive_oauth_refresh_token';
  static const String expiryIso = 'gdrive_oauth_expiry_iso';
  static const String userEmail = 'gdrive_oauth_user_email';
  static const String folderId = 'gdrive_backup_folder_id';
}

class DriveAccountStatus {
  final bool hasOAuthConfig;
  final bool isConnected;
  final String? email;
  final bool autoUploadEnabled;
  final DriveBackupFrequency frequency;
  final DateTime? lastUploadAt;
  final String? lastUploadName;
  final int? lastUploadSizeBytes;
  final String? clientIdPreview;

  const DriveAccountStatus({
    required this.hasOAuthConfig,
    required this.isConnected,
    this.email,
    required this.autoUploadEnabled,
    required this.frequency,
    this.lastUploadAt,
    this.lastUploadName,
    this.lastUploadSizeBytes,
    this.clientIdPreview,
  });
}

class DriveBackupFile {
  final String id;
  final String name;
  final int sizeBytes;
  final DateTime modifiedAt;

  const DriveBackupFile({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.modifiedAt,
  });
}

/// Direct Google Drive Account backup & restore using Google OAuth 2.0
/// (Desktop Loopback + PKCE S256) and Google Drive REST API v3.
///
/// Uses the minimal `drive.file` scope: the app can ONLY access backups it creates,
/// never the user's private Drive files.
class GoogleDriveBackupService {
  static const String _backupFolderName = 'SalesSystemBackups';
  static const String _scope =
      'https://www.googleapis.com/auth/drive.file https://www.googleapis.com/auth/userinfo.email';

  final LocalBackupService _localBackup;
  final FeatureGate _featureGate;
  final DriveTokenStore _store;
  final http.Client _httpClient;

  GoogleDriveBackupService(
    this._localBackup,
    this._featureGate, {
    DriveTokenStore? store,
    http.Client? httpClient,
  })  : _store = store ?? const SecureDriveTokenStore(),
        _httpClient = httpClient ?? http.Client();

  Future<({String clientId, String clientSecret})> getOAuthCredentials() async {
    final storedId = (await _store.read(_DriveSecretKeys.clientId))?.trim() ?? '';
    final storedSecret =
        (await _store.read(_DriveSecretKeys.clientSecret))?.trim() ?? '';
    return (
      clientId: storedId.isNotEmpty ? storedId : GoogleDriveConfig.clientId,
      clientSecret: storedSecret.isNotEmpty
          ? storedSecret
          : GoogleDriveConfig.clientSecret,
    );
  }

  Future<void> saveOAuthCredentials({
    required String clientId,
    required String clientSecret,
  }) async {
    final cleanId = clientId.trim();
    final cleanSecret = clientSecret.trim();
    if (cleanId.isEmpty) {
      throw ArgumentError('يرجى إدخال Client ID الصالح من Google Cloud Console');
    }
    await _store.write(_DriveSecretKeys.clientId, cleanId);
    await _store.write(_DriveSecretKeys.clientSecret, cleanSecret);
  }

  Future<DriveAccountStatus> getStatus() async {
    final creds = await getOAuthCredentials();
    final refresh = await _store.read(_DriveSecretKeys.refreshToken);
    final access = await _store.read(_DriveSecretKeys.accessToken);
    final email = await _store.read(_DriveSecretKeys.userEmail);
    final autoRaw = await _featureGate.getMeta(DriveBackupMetaKeys.autoEnabled);
    final freqRaw = await _featureGate.getMeta(DriveBackupMetaKeys.frequency);
    final lastAtRaw = await _featureGate.getMeta(DriveBackupMetaKeys.lastUploadAt);
    final lastName = await _featureGate.getMeta(DriveBackupMetaKeys.lastUploadName);
    final lastSizeRaw = await _featureGate.getMeta(DriveBackupMetaKeys.lastUploadSize);

    final isConnected = (refresh != null && refresh.isNotEmpty) ||
        (access != null && access.isNotEmpty);

    DriveBackupFrequency frequency;
    if (freqRaw != null && freqRaw.isNotEmpty) {
      frequency = DriveBackupFrequency.fromKey(freqRaw);
    } else {
      frequency = autoRaw == '0'
          ? DriveBackupFrequency.manual
          : DriveBackupFrequency.daily;
    }

    String? preview;
    if (creds.clientId.isNotEmpty) {
      preview = creds.clientId.length > 22
          ? '${creds.clientId.substring(0, 12)}...${creds.clientId.substring(creds.clientId.length - 8)}'
          : creds.clientId;
    }

    return DriveAccountStatus(
      hasOAuthConfig: creds.clientId.isNotEmpty,
      isConnected: isConnected,
      email: email,
      autoUploadEnabled: frequency != DriveBackupFrequency.manual,
      frequency: frequency,
      lastUploadAt: lastAtRaw != null ? DateTime.tryParse(lastAtRaw) : null,
      lastUploadName: lastName,
      lastUploadSizeBytes: lastSizeRaw != null ? int.tryParse(lastSizeRaw) : null,
      clientIdPreview: preview,
    );
  }

  Future<void> setBackupFrequency(
    DriveBackupFrequency frequency, {
    required String userId,
  }) async {
    await _featureGate.setMeta(
      DriveBackupMetaKeys.frequency,
      frequency.key,
      userId: userId,
    );
    await _featureGate.setMeta(
      DriveBackupMetaKeys.autoEnabled,
      frequency == DriveBackupFrequency.manual ? '0' : '1',
      userId: userId,
    );
  }

  Future<void> setAutoUploadEnabled(bool enabled, {required String userId}) async {
    await setBackupFrequency(
      enabled ? DriveBackupFrequency.daily : DriveBackupFrequency.manual,
      userId: userId,
    );
  }

  /// Launches Google's official OAuth 2.0 browser sign-in flow using a local
  /// loopback redirect (`http://127.0.0.1:<port>/callback`) with PKCE S256.
  Future<String> connectAccount({
    Duration timeout = const Duration(minutes: 3),
    Future<bool> Function(Uri uri)? launcher,
  }) async {
    final creds = await getOAuthCredentials();
    if (creds.clientId.isEmpty) {
      throw Exception(
        'يرجى إدخال بيانات ربط Google Cloud (Client ID) أولاً قبل ربط الحساب.',
      );
    }

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${server.port}/callback';
    final codeVerifier = _randomBase64Url(48);
    final codeChallenge = base64UrlEncode(
      sha256.convert(utf8.encode(codeVerifier)).bytes,
    ).replaceAll('=', '');
    final state = _randomBase64Url(24);

    final authUri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': creds.clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': _scope,
      'access_type': 'offline',
      'prompt': 'select_account consent',
      'state': state,
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
    });

    final codeCompleter = Completer<String>();
    final sub = server.listen((HttpRequest req) async {
      try {
        if (req.uri.path != '/callback') {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
          return;
        }
        final params = req.uri.queryParameters;
        final err = params['error'];
        final returnedState = params['state'];
        final code = params['code'];

        req.response.headers.contentType = ContentType.html;
        if (err != null) {
          req.response.write(_htmlPage(
            title: 'تم إلغاء الربط',
            body: 'لم يكتمل تسجيل الدخول بحساب Google ($err). يمكنك إغلاق هذه الصفحة.',
            isError: true,
          ));
          await req.response.close();
          if (!codeCompleter.isCompleted) {
            codeCompleter.completeError(Exception('تم إلغاء تسجيل الدخول من Google: $err'));
          }
          return;
        }
        if (returnedState != state || code == null || code.isEmpty) {
          req.response.write(_htmlPage(
            title: 'خطأ في التحقق',
            body: 'تعذر التحقق من جلسة الربط. يرجى المحاولة مرة أخرى.',
            isError: true,
          ));
          await req.response.close();
          if (!codeCompleter.isCompleted) {
            codeCompleter.completeError(Exception('فشل التحقق من استجابة Google OAuth'));
          }
          return;
        }

        req.response.write(_htmlPage(
          title: 'تم ربط حساب Google Drive بنجاح',
          body: 'يمكنك إغلاق هذه الصفحة الآن والعودة إلى برنامج سيستم المبيعات.',
          isError: false,
        ));
        await req.response.close();
        if (!codeCompleter.isCompleted) {
          codeCompleter.complete(code);
        }
      } catch (e) {
        if (!codeCompleter.isCompleted) {
          codeCompleter.completeError(e);
        }
      }
    });

    try {
      final launched = launcher != null
          ? await launcher(authUri)
          : await launchUrl(authUri, mode: LaunchMode.externalApplication);
      if (!launched) {
        throw Exception('تعذر فتح المتصفح لتسجيل الدخول إلى Google');
      }

      final code = await codeCompleter.future.timeout(
        timeout,
        onTimeout: () => throw Exception('انتهت مهلة انتظار تسجيل الدخول في المتصفح'),
      );

      // Exchange authorization code for access + refresh tokens
      final tokenRes = await _httpClient.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': creds.clientId,
          if (creds.clientSecret.isNotEmpty) 'client_secret': creds.clientSecret,
          'code': code,
          'code_verifier': codeVerifier,
          'grant_type': 'authorization_code',
          'redirect_uri': redirectUri,
        },
      );

      if (tokenRes.statusCode != 200) {
        throw Exception('فشل إتمام المصادقة مع Google (${tokenRes.statusCode})');
      }

      final data = jsonDecode(tokenRes.body) as Map<String, dynamic>;
      final accessToken = data['access_token'] as String? ?? '';
      final refreshToken = data['refresh_token'] as String? ?? '';
      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3500;
      if (accessToken.isEmpty) {
        throw Exception('لم يتم استلام رمز الوصول من Google');
      }

      await _store.write(_DriveSecretKeys.accessToken, accessToken);
      if (refreshToken.isNotEmpty) {
        await _store.write(_DriveSecretKeys.refreshToken, refreshToken);
      }
      await _store.write(
        _DriveSecretKeys.expiryIso,
        DateTime.now().add(Duration(seconds: expiresIn - 60)).toIso8601String(),
      );

      // Fetch connected Google account email
      String email = 'حساب Google متصل';
      try {
        final infoRes = await _httpClient.get(
          Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
          headers: {'Authorization': 'Bearer $accessToken'},
        );
        if (infoRes.statusCode == 200) {
          final info = jsonDecode(infoRes.body) as Map<String, dynamic>;
          final e = (info['email'] as String?)?.trim();
          if (e != null && e.isNotEmpty) email = e;
        }
      } catch (_) {}

      await _store.write(_DriveSecretKeys.userEmail, email);
      await _store.delete(_DriveSecretKeys.folderId);
      return email;
    } finally {
      await sub.cancel();
      await server.close(force: true);
    }
  }

  Future<void> disconnect() async {
    await _store.delete(_DriveSecretKeys.accessToken);
    await _store.delete(_DriveSecretKeys.refreshToken);
    await _store.delete(_DriveSecretKeys.expiryIso);
    await _store.delete(_DriveSecretKeys.userEmail);
    await _store.delete(_DriveSecretKeys.folderId);
  }

  /// Returns a valid OAuth access token, refreshing it transparently if expired.
  Future<String> getValidAccessToken() async {
    final access = await _store.read(_DriveSecretKeys.accessToken);
    final expiryRaw = await _store.read(_DriveSecretKeys.expiryIso);
    final expiry = expiryRaw != null ? DateTime.tryParse(expiryRaw) : null;

    if (access != null &&
        access.isNotEmpty &&
        expiry != null &&
        DateTime.now().isBefore(expiry)) {
      return access;
    }

    final refresh = await _store.read(_DriveSecretKeys.refreshToken);
    if (refresh == null || refresh.isEmpty) {
      throw Exception('انتهت جلسة Google Drive. يرجى إعادة ربط الحساب.');
    }

    final creds = await getOAuthCredentials();
    if (creds.clientId.isEmpty) {
      throw Exception('بيانات Google OAuth غير مضبوطة.');
    }

    final res = await _httpClient.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': creds.clientId,
        if (creds.clientSecret.isNotEmpty) 'client_secret': creds.clientSecret,
        'refresh_token': refresh,
        'grant_type': 'refresh_token',
      },
    );

    if (res.statusCode != 200) {
      throw Exception('تعذر تجديد جلسة Google Drive. يرجى إعادة ربط الحساب.');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final newAccess = data['access_token'] as String? ?? '';
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3500;
    if (newAccess.isEmpty) {
      throw Exception('استجابة غير صالحة من Google أثناء تجديد الجلسة');
    }

    await _store.write(_DriveSecretKeys.accessToken, newAccess);
    await _store.write(
      _DriveSecretKeys.expiryIso,
      DateTime.now().add(Duration(seconds: expiresIn - 60)).toIso8601String(),
    );
    return newAccess;
  }

  Future<String> _ensureBackupFolder(String token) async {
    final cached = await _store.read(_DriveSecretKeys.folderId);
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    // Search for existing folder created by this app
    final q =
        "name = '$_backupFolderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
    final searchUri = Uri.https('www.googleapis.com', '/drive/v3/files', {
      'q': q,
      'fields': 'files(id,name)',
      'spaces': 'drive',
    });
    final searchRes = await _httpClient.get(
      searchUri,
      headers: {'Authorization': 'Bearer $token'},
    );
    if (searchRes.statusCode == 200) {
      final body = jsonDecode(searchRes.body) as Map<String, dynamic>;
      final files = (body['files'] as List<dynamic>?) ?? const [];
      if (files.isNotEmpty) {
        final id = (files.first as Map<String, dynamic>)['id'] as String;
        await _store.write(_DriveSecretKeys.folderId, id);
        return id;
      }
    }

    // Create the folder
    final createRes = await _httpClient.post(
      Uri.parse('https://www.googleapis.com/drive/v3/files?fields=id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode({
        'name': _backupFolderName,
        'mimeType': 'application/vnd.google-apps.folder',
      }),
    );
    if (createRes.statusCode != 200 && createRes.statusCode != 201) {
      throw Exception('فشل إنشاء مجلد النسخ الاحتياطي على Google Drive');
    }
    final created = jsonDecode(createRes.body) as Map<String, dynamic>;
    final folderId = created['id'] as String;
    await _store.write(_DriveSecretKeys.folderId, folderId);
    return folderId;
  }

  /// Creates a WAL-safe `VACUUM INTO` snapshot and uploads it to the user's
  /// Google Drive `SalesSystemBackups` folder.
  Future<DriveBackupFile> uploadBackupNow({
    String userId = 'admin',
    bool isAuto = false,
  }) async {
    final token = await getValidAccessToken();
    final folderId = await _ensureBackupFolder(token);

    final tempDir = await Directory.systemTemp.createTemp('sales_erp_gdrive_');
    final now = DateTime.now();
    final stamp = _formatTimestamp(now);
    final fileName = isAuto
        ? 'auto_drive_backup_${_formatDateOnly(now)}.sqlite'
        : 'sales_erp_backup_$stamp.sqlite';
    final tempFile = File('${tempDir.path}${Platform.pathSeparator}$fileName');

    try {
      await _localBackup.createBackup(
        targetFilePath: tempFile.path,
        userId: userId,
        updateMetadata: false,
      );
      final bytes = await tempFile.readAsBytes();

      final boundary = 'sales_erp_boundary_${now.millisecondsSinceEpoch}';
      final metadataJson = jsonEncode({
        'name': fileName,
        'parents': [folderId],
      });

      final bodyBuilder = BytesBuilder(copy: false)
        ..add(utf8.encode('--$boundary\r\n'))
        ..add(utf8.encode('Content-Type: application/json; charset=UTF-8\r\n\r\n'))
        ..add(utf8.encode(metadataJson))
        ..add(utf8.encode('\r\n--$boundary\r\n'))
        ..add(utf8.encode('Content-Type: application/x-sqlite3\r\n\r\n'))
        ..add(bytes)
        ..add(utf8.encode('\r\n--$boundary--\r\n'));

      final uploadRes = await _httpClient.post(
        Uri.parse(
          'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name,size,modifiedTime',
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'multipart/related; boundary=$boundary',
        },
        body: bodyBuilder.toBytes(),
      );

      if (uploadRes.statusCode != 200 && uploadRes.statusCode != 201) {
        throw Exception('فشل رفع النسخة إلى Google Drive (${uploadRes.statusCode})');
      }

      final respData = jsonDecode(uploadRes.body) as Map<String, dynamic>;
      final uploaded = DriveBackupFile(
        id: respData['id'] as String? ?? '',
        name: respData['name'] as String? ?? fileName,
        sizeBytes: int.tryParse('${respData['size'] ?? ''}') ?? bytes.length,
        modifiedAt: DateTime.tryParse('${respData['modifiedTime'] ?? ''}') ?? now,
      );

      await _featureGate.setMeta(
        DriveBackupMetaKeys.lastUploadAt,
        now.toIso8601String(),
        userId: userId,
      );
      await _featureGate.setMeta(
        DriveBackupMetaKeys.lastUploadName,
        uploaded.name,
        userId: userId,
      );
      await _featureGate.setMeta(
        DriveBackupMetaKeys.lastUploadSize,
        '${uploaded.sizeBytes}',
        userId: userId,
      );

      return uploaded;
    } finally {
      try {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  /// Lists backups saved in the user's Google Drive `SalesSystemBackups` folder.
  Future<List<DriveBackupFile>> listRemoteBackups() async {
    final token = await getValidAccessToken();
    final folderId = await _ensureBackupFolder(token);

    final q = "'$folderId' in parents and trashed = false";
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
      'q': q,
      'orderBy': 'modifiedTime desc',
      'pageSize': '30',
      'fields': 'files(id,name,size,modifiedTime)',
    });

    final res = await _httpClient.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200) {
      throw Exception('تعذر جلب قائمة النسخ من Google Drive (${res.statusCode})');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final rawFiles = (data['files'] as List<dynamic>?) ?? const [];
    return rawFiles
        .whereType<Map<String, dynamic>>()
        .map((m) => DriveBackupFile(
              id: m['id'] as String? ?? '',
              name: m['name'] as String? ?? '',
              sizeBytes: int.tryParse('${m['size'] ?? 0}') ?? 0,
              modifiedAt:
                  DateTime.tryParse('${m['modifiedTime'] ?? ''}')?.toLocal() ??
                      DateTime.now(),
            ))
        .where((f) =>
            f.name.toLowerCase().endsWith('.sqlite') ||
            f.name.toLowerCase().endsWith('.db'))
        .toList();
  }

  /// Downloads a remote backup from Google Drive and restores it safely via
  /// [LocalBackupService.restoreFromBackup] (integrity check + pre-restore safety copy).
  Future<RestoreResult> downloadAndRestoreBackup({
    required DriveBackupFile file,
    String userId = 'admin',
  }) async {
    final token = await getValidAccessToken();
    final downloadRes = await _httpClient.get(
      Uri.parse('https://www.googleapis.com/drive/v3/files/${file.id}?alt=media'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (downloadRes.statusCode != 200) {
      throw Exception('فشل تحميل النسخة من Google Drive (${downloadRes.statusCode})');
    }

    final tempDir = await Directory.systemTemp.createTemp('sales_erp_gdrive_dl_');
    final tempFile = File('${tempDir.path}${Platform.pathSeparator}${file.name}');
    try {
      await tempFile.writeAsBytes(downloadRes.bodyBytes);
      return await _localBackup.restoreFromBackup(
        sourceBackupPath: tempFile.path,
        userId: userId,
      );
    } finally {
      try {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  /// Silently uploads a scheduled backup to Google Drive according to the
  /// user's WhatsApp-style frequency (daily / weekly / monthly / manual).
  Future<DriveBackupFile?> runAutoDriveBackupIfDue({DateTime? now}) async {
    try {
      final status = await getStatus();
      if (!status.isConnected || status.frequency == DriveBackupFrequency.manual) {
        return null;
      }

      final current = now ?? DateTime.now();
      final todayKey = _formatDateOnly(current);
      final lastAutoRaw = await _featureGate.getMeta(DriveBackupMetaKeys.lastAutoDate);
      if (lastAutoRaw != null && lastAutoRaw.isNotEmpty) {
        if (lastAutoRaw == todayKey) return null;
        final lastDate = DateTime.tryParse(lastAutoRaw);
        if (lastDate != null) {
          final daysSince = DateTime(current.year, current.month, current.day)
              .difference(DateTime(lastDate.year, lastDate.month, lastDate.day))
              .inDays;
          final requiredDays = switch (status.frequency) {
            DriveBackupFrequency.daily => 1,
            DriveBackupFrequency.weekly => 7,
            DriveBackupFrequency.monthly => 30,
            DriveBackupFrequency.manual => 999999,
          };
          if (daysSince < requiredDays) return null;
        }
      }

      final uploaded = await uploadBackupNow(
        userId: 'system_auto_drive_backup',
        isAuto: true,
      );
      await _featureGate.setMeta(
        DriveBackupMetaKeys.lastAutoDate,
        todayKey,
        userId: 'system_auto_drive_backup',
      );
      Logging.info('[DriveBackup] Uploaded scheduled backup: ${uploaded.name}');
      return uploaded;
    } catch (e) {
      Logging.error('[DriveBackup] Auto upload skipped/failed: $e');
      return null;
    }
  }

  static String _randomBase64Url(int byteLength) {
    final rng = Random.secure();
    final bytes = List<int>.generate(byteLength, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String _formatDateOnly(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _formatTimestamp(DateTime dt) {
    final date = _formatDateOnly(dt);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '${date}_$hh-$mm-$ss';
  }

  static String _htmlPage({
    required String title,
    required String body,
    required bool isError,
  }) {
    final color = isError ? '#b91c1c' : '#0f766e';
    return '''
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8" />
  <title>$title</title>
  <style>
    body { font-family: 'Segoe UI', Tahoma, sans-serif; background: #f8fafc; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
    .card { background: #fff; padding: 32px 40px; border-radius: 16px; box-shadow: 0 10px 30px rgba(0,0,0,0.08); text-align: center; max-width: 460px; }
    h2 { color: $color; margin-top: 0; }
    p { color: #475569; line-height: 1.6; }
  </style>
</head>
<body>
  <div class="card">
    <h2>$title</h2>
    <p>$body</p>
  </div>
</body>
</html>
''';
  }
}
