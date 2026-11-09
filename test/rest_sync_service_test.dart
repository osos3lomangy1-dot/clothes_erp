import 'dart:convert';
import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/services/rest_sync_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Firestore REST Field Encoding Tests', () {
    test(
      'encodeFirestoreFields correctly encodes primitive and complex types',
      () {
        final input = {
          'name': 'Summer T-Shirt',
          'price': 150,
          'rating': 4.5,
          'isAvailable': true,
          'nullValue': null,
          'tags': ['cotton', 'casual'],
          'meta': {'brand': 'Orchid', 'year': 2026},
        };

        final encoded = RestSyncService.encodeFirestoreFields(input);

        expect(encoded['name'], {'stringValue': 'Summer T-Shirt'});
        expect(encoded['price'], {'integerValue': '150'});
        expect(encoded['rating'], {'doubleValue': 4.5});
        expect(encoded['isAvailable'], {'booleanValue': true});
        expect(encoded['nullValue'], {'nullValue': null});
        expect(encoded['tags']?['arrayValue']?['values'], [
          {'stringValue': 'cotton'},
          {'stringValue': 'casual'},
        ]);
        expect(encoded['meta']?['mapValue']?['fields']?['brand'], {
          'stringValue': 'Orchid',
        });
        expect(encoded['meta']?['mapValue']?['fields']?['year'], {
          'integerValue': '2026',
        });
      },
    );
  });

  group('RestSyncService Queue Synchronization Tests', () {
    test(
      'syncPendingData returns empty result when no items are pending',
      () async {
        final mockClient = MockClient((request) async {
          return http.Response('{}', 200);
        });

        final service = RestSyncService(
          db,
          mockClient,
          projectId: 'test-project',
          apiKey: 'test-key',
        );

        final result = await service.syncPendingData();

        expect(result.total, 0);
        expect(result.synced, 0);
        expect(result.failed, 0);
        expect(result.isSuccess, isTrue);
      },
    );

    test(
      'syncPendingData successfully sends PATCH request and updates sync_queue row',
      () async {
        final now = DateTime.now();

        // Seed a pending item
        await db
            .into(db.syncQueue)
            .insert(
              SyncQueueCompanion.insert(
                id: 'q-101',
                branchId: 'branch-1',
                entity: 'categories',
                entityId: 'cat-202',
                operation: 'insert',
                payload: jsonEncode({'name': 'Winter Wear', 'sortOrder': 1}),
                createdAt: now,
                updatedAt: now,
              ),
            );

        http.Request? capturedRequest;
        final mockClient = MockClient((request) async {
          capturedRequest = request;
          return http.Response(
            jsonEncode({
              'name':
                  'projects/test-project/databases/(default)/documents/categories/cat-202',
              'fields': {},
            }),
            200,
          );
        });

        final service = RestSyncService(
          db,
          mockClient,
          projectId: 'test-project',
          apiKey: 'test-key',
        );

        final result = await service.syncPendingData();

        expect(result.total, 1);
        expect(result.synced, 1);
        expect(result.failed, 0);

        // Verify HTTP request details
        expect(capturedRequest, isNotNull);
        expect(capturedRequest!.method, 'PATCH');
        expect(
          capturedRequest!.url.toString(),
          contains(
            'firestore.googleapis.com/v1/projects/test-project/databases/(default)/documents/categories/cat-202?key=test-key',
          ),
        );

        final decodedBody =
            jsonDecode(capturedRequest!.body) as Map<String, dynamic>;
        expect(decodedBody['fields']?['name']?['stringValue'], 'Winter Wear');

        // Verify sync_queue status in DB
        final row = await (db.select(
          db.syncQueue,
        )..where((q) => q.id.equals('q-101'))).getSingle();
        expect(row.status, 'synced');
        expect(row.syncedAt, isNotNull);
      },
    );

    test(
      'syncPendingData handles HTTP error gracefully and increments attempts',
      () async {
        final now = DateTime.now();

        await db
            .into(db.syncQueue)
            .insert(
              SyncQueueCompanion.insert(
                id: 'q-102',
                branchId: 'branch-1',
                entity: 'products',
                entityId: 'prod-303',
                operation: 'insert',
                payload: jsonEncode({'name': 'Silk Shirt'}),
                createdAt: now,
                updatedAt: now,
              ),
            );

        final mockClient = MockClient((request) async {
          return http.Response('Server Error', 500);
        });

        final service = RestSyncService(
          db,
          mockClient,
          projectId: 'test-project',
          apiKey: 'test-key',
        );

        final result = await service.syncPendingData();

        expect(result.total, 1);
        expect(result.synced, 0);
        expect(result.failed, 1);
        expect(result.isSuccess, isFalse);

        final row = await (db.select(
          db.syncQueue,
        )..where((q) => q.id.equals('q-102'))).getSingle();
        expect(row.status, 'pending');
        expect(row.attempts, 1);
        expect(row.lastError, contains('HTTP 500'));
      },
    );

    test(
      'syncPendingData handles delete operation using HTTP DELETE',
      () async {
        final now = DateTime.now();

        await db
            .into(db.syncQueue)
            .insert(
              SyncQueueCompanion.insert(
                id: 'q-103',
                branchId: 'branch-1',
                entity: 'customer',
                entityId: 'cust-404',
                operation: 'delete',
                payload: '{}',
                createdAt: now,
                updatedAt: now,
              ),
            );

        http.Request? capturedRequest;
        final mockClient = MockClient((request) async {
          capturedRequest = request;
          return http.Response('{}', 200);
        });

        final service = RestSyncService(
          db,
          mockClient,
          projectId: 'test-project',
          apiKey: 'test-key',
        );

        final result = await service.syncPendingData();

        expect(result.total, 1);
        expect(result.synced, 1);
        expect(capturedRequest!.method, 'DELETE');
        expect(
          capturedRequest!.url.toString(),
          contains('/customers/cust-404'),
        );
      },
    );

    test('startAutoSync triggers background sync and stopAutoSync cancels it', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{}', 200);
      });

      final service = RestSyncService(
        db,
        mockClient,
        projectId: 'test-project',
        apiKey: 'test-key',
      );

      service.startAutoSync(interval: const Duration(milliseconds: 50));
      await Future.delayed(const Duration(milliseconds: 20));
      service.stopAutoSync();
    });
  });
}
