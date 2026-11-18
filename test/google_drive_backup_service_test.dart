import 'dart:convert';
import 'dart:io';

import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/services/google_drive_backup_service.dart';
import 'package:clothes_erp/core/services/local_backup_service.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

class _FakeAuth implements AuthLocalDataSource {
  @override
  Future<void> cacheUser(UserModel user) async {}

  @override
  Future<void> clearCache() async {}

  @override
  Future<UserModel?> getCachedUser() async => UserModel(
        id: 'admin-1',
        name: 'Admin',
        email: 'admin@test.local',
        role: 'admin',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakeBranch implements BranchProvider {
  @override
  Future<String> getBranchId() async => 'branch-1';
}

class _MemoryTokenStore implements DriveTokenStore {
  final Map<String, String> data = {};

  @override
  Future<void> delete(String key) async => data.remove(key);

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

void main() {
  late Directory tempRoot;
  late Directory backupDir;
  late File liveDbFile;
  late AppDatabase db;
  late FeatureGate featureGate;
  late LocalBackupService localService;
  late _MemoryTokenStore store;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('clothes_erp_gdrive_test_');
    backupDir = Directory('${tempRoot.path}${Platform.pathSeparator}backups');
    await backupDir.create(recursive: true);
    liveDbFile = File('${tempRoot.path}${Platform.pathSeparator}clothes_erp.sqlite');

    db = AppDatabase(NativeDatabase(liveDbFile));
    featureGate = FeatureGate(db, _FakeAuth(), TxWriter(db), _FakeBranch());
    localService = LocalBackupService(
      db,
      featureGate,
      defaultBackupDirProvider: () async => backupDir,
      liveDbFileProvider: () async => liveDbFile,
    );
    store = _MemoryTokenStore();
    await db.select(db.appMeta).get();
  });

  tearDown(() async {
    try {
      await db.close();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    } catch (_) {}
  });

  test('1. connectAccount completes loopback OAuth PKCE flow and stores tokens & email', () async {
    final mockHttp = MockClient((req) async {
      if (req.url.toString() == 'https://oauth2.googleapis.com/token') {
        expect(req.bodyFields['code'], 'auth-code-123');
        expect(req.bodyFields['code_verifier'], isNotEmpty);
        return http.Response(
          jsonEncode({
            'access_token': 'access-xyz',
            'refresh_token': 'refresh-xyz',
            'expires_in': 3600,
          }),
          200,
        );
      }
      if (req.url.toString() == 'https://www.googleapis.com/oauth2/v2/userinfo') {
        return http.Response(jsonEncode({'email': 'owner@gmail.com'}), 200);
      }
      return http.Response('not found', 404);
    });

    final drive = GoogleDriveBackupService(
      localService,
      featureGate,
      store: store,
      httpClient: mockHttp,
    );
    await drive.saveOAuthCredentials(
      clientId: 'test-client-id.apps.googleusercontent.com',
      clientSecret: 'test-secret',
    );

    final email = await drive.connectAccount(
      launcher: (authUri) async {
        // Simulate Google redirecting browser back to our loopback callback URL
        final redirect = Uri.parse(authUri.queryParameters['redirect_uri']!);
        final state = authUri.queryParameters['state']!;
        final callbackUri = redirect.replace(queryParameters: {
          'code': 'auth-code-123',
          'state': state,
        });
        final client = HttpClient();
        final req = await client.getUrl(callbackUri);
        final res = await req.close();
        await res.drain<void>();
        client.close();
        return true;
      },
    );

    expect(email, 'owner@gmail.com');
    final status = await drive.getStatus();
    expect(status.isConnected, isTrue);
    expect(status.email, 'owner@gmail.com');
  });

  test('2. uploadBackupNow refreshes expired token, creates Drive folder, and uploads SQLite backup', () async {
    var refreshCalls = 0;
    var folderCreateCalls = 0;
    var uploadCalls = 0;
    List<int>? capturedUploadBody;

    final mockHttp = MockClient((req) async {
      if (req.url.toString() == 'https://oauth2.googleapis.com/token') {
        refreshCalls++;
        return http.Response(
          jsonEncode({'access_token': 'fresh-token', 'expires_in': 3600}),
          200,
        );
      }
      if (req.method == 'GET' && req.url.path == '/drive/v3/files') {
        // Folder not found yet
        return http.Response(jsonEncode({'files': []}), 200);
      }
      if (req.method == 'POST' && req.url.path == '/drive/v3/files') {
        folderCreateCalls++;
        return http.Response(jsonEncode({'id': 'folder-999'}), 200);
      }
      if (req.method == 'POST' && req.url.path == '/upload/drive/v3/files') {
        uploadCalls++;
        capturedUploadBody = req.bodyBytes;
        expect(req.headers['Authorization'], 'Bearer fresh-token');
        return http.Response(
          jsonEncode({
            'id': 'file-777',
            'name': 'sales_erp_backup.sqlite',
            'size': '${req.bodyBytes.length}',
            'modifiedTime': DateTime.now().toUtc().toIso8601String(),
          }),
          200,
        );
      }
      return http.Response('unexpected ${req.method} ${req.url}', 400);
    });

    final drive = GoogleDriveBackupService(
      localService,
      featureGate,
      store: store,
      httpClient: mockHttp,
    );
    await drive.saveOAuthCredentials(clientId: 'cid', clientSecret: 'csec');
    await store.write('gdrive_oauth_refresh_token', 'ref-1');
    await store.write(
      'gdrive_oauth_expiry_iso',
      DateTime.now().subtract(const Duration(minutes: 10)).toIso8601String(),
    );

    final uploaded = await drive.uploadBackupNow(userId: 'admin-1');
    expect(refreshCalls, 1);
    expect(folderCreateCalls, 1);
    expect(uploadCalls, 1);
    expect(uploaded.id, 'file-777');
    expect(capturedUploadBody, isNotNull);
    expect(capturedUploadBody!.length, greaterThan(1000));

    final status = await drive.getStatus();
    expect(status.lastUploadAt, isNotNull);
  });

  test('3. listRemoteBackups & downloadAndRestoreBackup restore valid SQLite snapshot from Drive', () async {
    final now = DateTime.now();
    await db.into(db.categories).insert(CategoriesCompanion.insert(
          id: 'cat-drive',
          branchId: 'branch-1',
          name: 'محفوظ على درايف',
          createdAt: now,
          updatedAt: now,
        ));
    final goodBackup = await localService.createBackup(
      targetFilePath: '${tempRoot.path}${Platform.pathSeparator}remote_copy.sqlite',
      userId: 'admin-1',
    );
    final goodBytes = await File(goodBackup.filePath).readAsBytes();

    // Mutate DB after backup
    await db.into(db.categories).insert(CategoriesCompanion.insert(
          id: 'cat-local-only',
          branchId: 'branch-1',
          name: 'غير موجود في درايف',
          createdAt: now,
          updatedAt: now,
        ));

    final mockHttp = MockClient((req) async {
      if (req.method == 'GET' && req.url.path == '/drive/v3/files') {
        return http.Response(
          jsonEncode({
            'files': [
              {
                'id': 'drive-file-1',
                'name': 'auto_drive_backup_2026-11-18.sqlite',
                'size': '${goodBytes.length}',
                'modifiedTime': '2026-11-18T02:00:00Z',
              },
            ],
          }),
          200,
        );
      }
      if (req.method == 'GET' && req.url.path == '/drive/v3/files/drive-file-1') {
        return http.Response.bytes(goodBytes, 200);
      }
      return http.Response('unexpected', 400);
    });

    final drive = GoogleDriveBackupService(
      localService,
      featureGate,
      store: store,
      httpClient: mockHttp,
    );
    await store.write('gdrive_oauth_access_token', 'valid-token');
    await store.write(
      'gdrive_oauth_expiry_iso',
      DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
    );
    await store.write('gdrive_backup_folder_id', 'folder-999');

    final files = await drive.listRemoteBackups();
    expect(files.length, 1);
    expect(files.first.name, 'auto_drive_backup_2026-11-18.sqlite');

    final restored = await drive.downloadAndRestoreBackup(
      file: files.first,
      userId: 'admin-1',
    );
    expect(File(restored.safetyBackupPath).existsSync(), isTrue);

    final checkDb = sqlite.sqlite3.open(liveDbFile.path, mode: sqlite.OpenMode.readOnly);
    try {
      expect(checkDb.select("SELECT id FROM categories WHERE id = 'cat-drive'").length, 1);
      expect(checkDb.select("SELECT id FROM categories WHERE id = 'cat-local-only'").isEmpty, isTrue);
    } finally {
      checkDb.dispose();
    }
  });

  test('4. runAutoDriveBackupIfDue uploads once per day and skips duplicate runs on same day', () async {
    var uploads = 0;
    final mockHttp = MockClient((req) async {
      if (req.method == 'POST' && req.url.path == '/upload/drive/v3/files') {
        uploads++;
        return http.Response(
          jsonEncode({
            'id': 'f-$uploads',
            'name': 'auto_drive_backup_2026-05-01.sqlite',
            'size': '2048',
            'modifiedTime': '2026-05-01T10:00:00Z',
          }),
          200,
        );
      }
      return http.Response('{}', 200);
    });

    final drive = GoogleDriveBackupService(
      localService,
      featureGate,
      store: store,
      httpClient: mockHttp,
    );
    await store.write('gdrive_oauth_access_token', 'valid-token');
    await store.write(
      'gdrive_oauth_expiry_iso',
      DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
    );
    await store.write('gdrive_backup_folder_id', 'folder-999');

    final first = await drive.runAutoDriveBackupIfDue(now: DateTime(2026, 5, 1, 9, 0));
    expect(first, isNotNull);
    expect(uploads, 1);

    final second = await drive.runAutoDriveBackupIfDue(now: DateTime(2026, 5, 1, 20, 0));
    expect(second, isNull);
    expect(uploads, 1);

    // Switch to weekly frequency: 3 days later should NOT upload, 7 days later SHOULD upload
    await drive.setBackupFrequency(DriveBackupFrequency.weekly, userId: 'admin-1');
    final day4 = await drive.runAutoDriveBackupIfDue(now: DateTime(2026, 5, 4, 10, 0));
    expect(day4, isNull);
    expect(uploads, 1);

    final day8 = await drive.runAutoDriveBackupIfDue(now: DateTime(2026, 5, 8, 10, 0));
    expect(day8, isNotNull);
    expect(uploads, 2);
  });
}

