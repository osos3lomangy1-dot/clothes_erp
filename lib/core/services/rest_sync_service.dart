import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import '../../firebase_options.dart';
import '../database/app_database.dart';
import '../utils/logging.dart';

class SyncResult {
  final int total;
  final int synced;
  final int failed;
  final String? error;

  const SyncResult({
    required this.total,
    required this.synced,
    required this.failed,
    this.error,
  });

  bool get isSuccess => failed == 0;
}

@lazySingleton
class RestSyncService {
  final AppDatabase _db;
  final http.Client _client;
  final String _projectId;
  final String _apiKey;

  String? _idToken;
  Timer? _autoSyncTimer;
  bool _isSyncing = false;

  final _syncStatusController = StreamController<bool>.broadcast();

  RestSyncService(
    this._db,
    this._client, {
    String? projectId,
    String? apiKey,
  })  : _projectId = projectId ?? DefaultFirebaseOptions.windows.projectId,
        _apiKey = apiKey ?? DefaultFirebaseOptions.windows.apiKey;

  String? get idToken => _idToken;
  bool get isSyncing => _isSyncing;
  Stream<bool> get isSyncingStream => _syncStatusController.stream;

  /// Starts automatic background synchronization (every [interval]).
  /// Also triggers an immediate synchronization in the background.
  void startAutoSync({Duration interval = const Duration(minutes: 5)}) {
    _autoSyncTimer?.cancel();
    Logging.info('🔄 [Auto-Sync] Started auto-sync timer (every ${interval.inMinutes} mins)');

    // Trigger immediate background sync
    unawaited(syncPendingData());

    _autoSyncTimer = Timer.periodic(interval, (_) async {
      final pendingCount = await getPendingCount();
      if (pendingCount > 0 && !_isSyncing) {
        Logging.info('🔄 [Auto-Sync] Auto-syncing $pendingCount pending items...');
        await syncPendingData();
      }
    });
  }

  /// Stops automatic background synchronization.
  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    Logging.info('🛑 [Auto-Sync] Stopped auto-sync timer');
  }

  /// Authenticate with Firebase Auth REST API (optional, for secured Firestore rules)
  Future<bool> signInWithRest(String email, String password) async {
    final url = Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$_apiKey',
    );

    try {
      final response = await _client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'returnSecureToken': true,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _idToken = data['idToken'] as String?;
        Logging.info('🛡️ [REST Auth] Authenticated successfully with Firebase REST');
        return true;
      } else {
        Logging.warn('⚠️ [REST Auth] Failed to authenticate: ${response.body}');
        return false;
      }
    } catch (e) {
      Logging.error('⚠️ [REST Auth] Error during REST login: $e');
      return false;
    }
  }

  /// Returns the number of items currently pending synchronization.
  Future<int> getPendingCount() async {
    final query = _db.select(_db.syncQueue)
      ..where((q) => q.status.equals('pending'));
    final rows = await query.get();
    return rows.length;
  }

  /// Watch the count of pending items for UI real-time badges.
  Stream<int> watchPendingCount() {
    final query = _db.select(_db.syncQueue)
      ..where((q) => q.status.equals('pending'));
    return query.watch().map((rows) => rows.length);
  }

  /// Synchronize all pending items in `sync_queue` to Firebase via REST.
  Future<SyncResult> syncPendingData() async {
    if (_isSyncing) {
      return const SyncResult(total: 0, synced: 0, failed: 0);
    }

    _isSyncing = true;
    _syncStatusController.add(true);

    try {
      final pendingItems = await (_db.select(_db.syncQueue)
            ..where((q) => q.status.equals('pending'))
            ..orderBy([(q) => OrderingTerm.asc(q.createdAt)]))
          .get();

      if (pendingItems.isEmpty) {
        return const SyncResult(total: 0, synced: 0, failed: 0);
      }

      int syncedCount = 0;
      int failedCount = 0;

      for (final item in pendingItems) {
        try {
          final success = await _syncSingleItem(item);
          if (success) {
            syncedCount++;
            await (_db.update(_db.syncQueue)..where((q) => q.id.equals(item.id)))
                .write(
              SyncQueueCompanion(
                status: const Value('synced'),
                syncedAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
              ),
            );
          } else {
            failedCount++;
          }
        } catch (e) {
          failedCount++;
          Logging.error('Sync item ${item.id} error: $e');
          await (_db.update(_db.syncQueue)..where((q) => q.id.equals(item.id)))
              .write(
            SyncQueueCompanion(
              attempts: Value(item.attempts + 1),
              lastError: Value(e.toString()),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
      }

      return SyncResult(
        total: pendingItems.length,
        synced: syncedCount,
        failed: failedCount,
      );
    } finally {
      _isSyncing = false;
      _syncStatusController.add(false);
    }
  }

  Future<bool> _syncSingleItem(SyncQueueData item) async {
    final collection = _resolveCollectionName(item.entity);
    final docId = item.entityId;

    final url = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/$collection/$docId?key=$_apiKey',
    );

    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (_idToken != null) {
      headers['Authorization'] = 'Bearer $_idToken';
    }

    if (item.operation == 'delete') {
      final response = await _client.delete(url, headers: headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }
      _recordFailure(item, response);
      return false;
    }

    // Resolve payload
    Map<String, dynamic> data = {};
    if (item.payload.isNotEmpty && item.payload != '{}') {
      try {
        data = jsonDecode(item.payload) as Map<String, dynamic>;
      } catch (_) {}
    }

    if (data.isEmpty) {
      data = await _fetchEntityFromDrift(item.entity, item.entityId);
    }

    // Include metadata
    data['id'] = docId;
    data['branchId'] = item.branchId;
    data['updatedAt'] = DateTime.now().toUtc().toIso8601String();

    final firestorePayload = {
      'fields': encodeFirestoreFields(data),
    };

    final response = await _client.patch(
      url,
      headers: headers,
      body: jsonEncode(firestorePayload),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return true;
    } else {
      _recordFailure(item, response);
      return false;
    }
  }

  Future<void> _recordFailure(
      SyncQueueData item, http.Response response) async {
    Logging.warn(
      '⚠️ [REST Sync] Failed item ${item.id} (${item.entity}/${item.entityId}): '
      'HTTP ${response.statusCode} - ${response.body}',
    );
    await (_db.update(_db.syncQueue)..where((q) => q.id.equals(item.id))).write(
          SyncQueueCompanion(
            attempts: Value(item.attempts + 1),
            lastError: Value('HTTP ${response.statusCode}: ${response.body}'),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<Map<String, dynamic>> _fetchEntityFromDrift(
    String entity,
    String entityId,
  ) async {
    switch (entity.toLowerCase()) {
      case 'category':
      case 'categories':
        final row = await (_db.select(_db.categories)
              ..where((c) => c.id.equals(entityId)))
            .getSingleOrNull();
        if (row != null) return row.toJson();
        break;

      case 'product':
      case 'products':
        final row = await (_db.select(_db.products)
              ..where((p) => p.id.equals(entityId)))
            .getSingleOrNull();
        if (row != null) return row.toJson();
        break;

      case 'variant':
      case 'product_variant':
      case 'product_variants':
        final row = await (_db.select(_db.productVariants)
              ..where((v) => v.id.equals(entityId)))
            .getSingleOrNull();
        if (row != null) return row.toJson();
        break;

      case 'customer':
      case 'customers':
        final row = await (_db.select(_db.customers)
              ..where((c) => c.id.equals(entityId)))
            .getSingleOrNull();
        if (row != null) return row.toJson();
        break;

      case 'sale':
      case 'sales':
        final row = await (_db.select(_db.sales)
              ..where((s) => s.id.equals(entityId)))
            .getSingleOrNull();
        if (row != null) return row.toJson();
        break;

      case 'expense':
      case 'expenses':
        final row = await (_db.select(_db.expenses)
              ..where((e) => e.id.equals(entityId)))
            .getSingleOrNull();
        if (row != null) return row.toJson();
        break;

      case 'return':
      case 'returns':
        final row = await (_db.select(_db.returns)
              ..where((r) => r.id.equals(entityId)))
            .getSingleOrNull();
        if (row != null) return row.toJson();
        break;
    }
    return {};
  }

  String _resolveCollectionName(String entity) {
    switch (entity.toLowerCase()) {
      case 'category':
        return 'categories';
      case 'product':
        return 'products';
      case 'variant':
      case 'product_variant':
        return 'product_variants';
      case 'customer':
        return 'customers';
      case 'sale':
        return 'sales';
      case 'expense':
        return 'expenses';
      case 'return':
        return 'returns';
      default:
        return entity.endsWith('s') ? entity : '${entity}s';
    }
  }

  /// Converts standard Dart Map into Firestore REST format
  static Map<String, dynamic> encodeFirestoreFields(Map<String, dynamic> data) {
    final fields = <String, dynamic>{};
    data.forEach((key, value) {
      final encoded = _encodeValue(value);
      if (encoded != null) {
        fields[key] = encoded;
      }
    });
    return fields;
  }

  static Map<String, dynamic>? _encodeValue(dynamic value) {
    if (value == null) {
      return {'nullValue': null};
    }
    if (value is String) {
      return {'stringValue': value};
    }
    if (value is bool) {
      return {'booleanValue': value};
    }
    if (value is int) {
      return {'integerValue': value.toString()};
    }
    if (value is double) {
      return {'doubleValue': value};
    }
    if (value is DateTime) {
      return {'timestampValue': value.toUtc().toIso8601String()};
    }
    if (value is List) {
      return {
        'arrayValue': {
          'values': value
              .map(_encodeValue)
              .whereType<Map<String, dynamic>>()
              .toList(),
        }
      };
    }
    if (value is Map<String, dynamic>) {
      return {
        'mapValue': {
          'fields': encodeFirestoreFields(value),
        }
      };
    }
    return {'stringValue': value.toString()};
  }
}

