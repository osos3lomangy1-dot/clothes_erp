import 'package:clothes_erp/core/services/app_update_service.dart';
import 'package:clothes_erp/core/services/widgets/app_update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppUpdateService - Version Comparison Tests', () {
    test('compareSemanticVersions returns correct order', () {
      expect(AppUpdateService.compareSemanticVersions('1.0.1', '1.0.0'), 1);
      expect(AppUpdateService.compareSemanticVersions('1.0.0', '1.0.1'), -1);
      expect(AppUpdateService.compareSemanticVersions('1.0.0', '1.0.0'), 0);
      expect(AppUpdateService.compareSemanticVersions('1.2.0', '1.1.9'), 1);
      expect(AppUpdateService.compareSemanticVersions('2.0.0', '1.9.9'), 1);
      expect(AppUpdateService.compareSemanticVersions('1.0.0.1', '1.0.0'), 1);
      expect(AppUpdateService.compareSemanticVersions('1.0.0-beta', '1.0.0'), 0);
    });

    test('isUpdateAvailable returns true when remote build is higher', () {
      final available = AppUpdateService.isUpdateAvailable(
        currentVersion: '1.0.0',
        currentBuildNumber: 1,
        remoteVersion: '1.0.0',
        remoteBuildNumber: 2,
      );
      expect(available, isTrue);
    });

    test('isUpdateAvailable returns true when remote version is higher even if build is same', () {
      final available = AppUpdateService.isUpdateAvailable(
        currentVersion: '1.0.0',
        currentBuildNumber: 1,
        remoteVersion: '1.0.1',
        remoteBuildNumber: 1,
      );
      expect(available, isTrue);
    });

    test('isUpdateAvailable returns false when current version is equal or higher', () {
      expect(
        AppUpdateService.isUpdateAvailable(
          currentVersion: '1.0.1',
          currentBuildNumber: 2,
          remoteVersion: '1.0.1',
          remoteBuildNumber: 2,
        ),
        isFalse,
      );

      expect(
        AppUpdateService.isUpdateAvailable(
          currentVersion: '1.1.0',
          currentBuildNumber: 3,
          remoteVersion: '1.0.9',
          remoteBuildNumber: 2,
        ),
        isFalse,
      );
    });

    test('isForceUpdateRequired detects force update triggers', () {
      // 1. Explicit force update flag
      final info1 = AppUpdateInfo(
        latestVersion: '1.1.0',
        latestBuildNumber: 2,
        downloadUrl: 'https://example.com/app.apk',
        isForceUpdate: true,
      );
      expect(
        AppUpdateService.isForceUpdateRequired(
          currentVersion: '1.0.0',
          currentBuildNumber: 1,
          updateInfo: info1,
        ),
        isTrue,
      );

      // 2. Minimum required build number higher than current
      final info2 = AppUpdateInfo(
        latestVersion: '1.1.0',
        latestBuildNumber: 3,
        minRequiredBuildNumber: 2,
        downloadUrl: 'https://example.com/app.apk',
        isForceUpdate: false,
      );
      expect(
        AppUpdateService.isForceUpdateRequired(
          currentVersion: '1.0.0',
          currentBuildNumber: 1,
          updateInfo: info2,
        ),
        isTrue,
      );

      // 3. Minimum required semantic version higher than current
      final info3 = AppUpdateInfo(
        latestVersion: '1.2.0',
        latestBuildNumber: 4,
        minRequiredVersion: '1.1.0',
        downloadUrl: 'https://example.com/app.apk',
        isForceUpdate: false,
      );
      expect(
        AppUpdateService.isForceUpdateRequired(
          currentVersion: '1.0.5',
          currentBuildNumber: 1,
          updateInfo: info3,
        ),
        isTrue,
      );

      // 4. Optional update (not forced)
      final info4 = AppUpdateInfo(
        latestVersion: '1.1.0',
        latestBuildNumber: 2,
        minRequiredVersion: '1.0.0',
        minRequiredBuildNumber: 1,
        downloadUrl: 'https://example.com/app.apk',
        isForceUpdate: false,
      );
      expect(
        AppUpdateService.isForceUpdateRequired(
          currentVersion: '1.0.0',
          currentBuildNumber: 1,
          updateInfo: info4,
        ),
        isFalse,
      );
    });

    test('AppUpdateInfo serialization and parsing', () {
      final map = {
        'latest_version': '2.0.0',
        'latest_build_number': 10,
        'min_required_version': '1.5.0',
        'min_required_build_number': 5,
        'download_url': 'https://firebasestorage.googleapis.com/...',
        'release_notes': '• تحسينات استثنائية\n• دعم التحديث التلقائي',
        'is_force_update': true,
        'enabled': true,
      };

      final info = AppUpdateInfo.fromMap(map);
      expect(info.latestVersion, '2.0.0');
      expect(info.latestBuildNumber, 10);
      expect(info.minRequiredVersion, '1.5.0');
      expect(info.minRequiredBuildNumber, 5);
      expect(info.downloadUrl, 'https://firebasestorage.googleapis.com/...');
      expect(info.releaseNotes, contains('دعم التحديث التلقائي'));
      expect(info.isForceUpdate, isTrue);
      expect(info.enabled, isTrue);

      final serialized = info.toMap();
      expect(serialized['latest_version'], '2.0.0');
      expect(serialized['latest_build_number'], 10);
      expect(serialized['is_force_update'], isTrue);
    });
  });

  group('AppUpdateDialog UI Tests', () {
    testWidgets('renders update dialog with optional update details', (tester) async {
      final info = AppUpdateInfo(
        latestVersion: '1.1.0',
        latestBuildNumber: 2,
        downloadUrl: 'https://example.com/download.apk',
        releaseNotes: 'إصلاح بعض الأخطاء وميزات جديدة',
        isForceUpdate: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppUpdateDialog(
              updateInfo: info,
              currentVersion: '1.0.0',
              isForce: false,
            ),
          ),
        ),
      );

      // Assertions
      expect(find.text('تحديث جديد متوفر!'), findsOneWidget);
      expect(find.text('v1.0.0'), findsOneWidget);
      expect(find.text('v1.1.0'), findsOneWidget);
      expect(find.text('إصلاح بعض الأخطاء وميزات جديدة'), findsOneWidget);
      expect(find.text('حدث الآن'), findsOneWidget);
      expect(find.text('لاحقاً'), findsOneWidget); // optional update shows "لاحقاً"
    });

    testWidgets('renders mandatory update dialog without cancel button and with warning', (tester) async {
      final info = AppUpdateInfo(
        latestVersion: '2.0.0',
        latestBuildNumber: 5,
        downloadUrl: 'https://example.com/download.apk',
        releaseNotes: 'تحديث أمني إجباري',
        isForceUpdate: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppUpdateDialog(
              updateInfo: info,
              currentVersion: '1.0.0',
              isForce: true,
            ),
          ),
        ),
      );

      expect(find.text('تحديث جديد متوفر!'), findsOneWidget);
      expect(find.text('حدث الآن'), findsOneWidget);
      expect(find.text('لاحقاً'), findsNothing); // Force update must NOT allow skipping
      expect(
        find.text('هذا التحديث إجباري لمتابعة استخدام النظام ومزامنة البيانات.'),
        findsOneWidget,
      );
    });
  });
}

