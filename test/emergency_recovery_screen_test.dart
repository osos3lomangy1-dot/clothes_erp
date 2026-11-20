import 'dart:io';
import 'package:clothes_erp/core/database/emergency_recovery_service.dart';
import 'package:clothes_erp/core/database/migration_marker_service.dart';
import 'package:clothes_erp/core/presentation/screens/emergency_recovery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late File dbFile;
  late File backupFile;
  late MigrationMarkerService markerService;
  late EmergencyRecoveryService recoveryService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('recovery_screen_test_');
    dbFile = File('${tempDir.path}/app.sqlite');
    await dbFile.writeAsString('test db content');

    backupFile = File('${tempDir.path}/backup.sqlite');
    await backupFile.writeAsString('backup db content');

    markerService = MigrationMarkerService(tempDir);
    recoveryService = EmergencyRecoveryService(
      activeDbFile: dbFile,
      markerService: markerService,
    );
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('renders EmergencyRecoveryScreen with emergency details and PIN input', (tester) async {
    final status = EmergencyStatus(
      isEmergency: true,
      reason: EmergencyReason.incompleteMigration,
      backupFile: backupFile,
      marker: MigrationMarker(
        versionFrom: 1,
        versionTo: 11,
        backupPath: backupFile.path,
        backupState: BackupState.verified,
        appVersion: '1.0.0',
        timestamp: DateTime.now(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: EmergencyRecoveryScreen(
            recoveryService: recoveryService,
            status: status,
            onRestored: () {},
          ),
        ),
      ),
    );

    expect(find.text('شاشة الاسترجاع المحمي ونظام الطوارئ'), findsOneWidget);
    expect(find.textContaining('تم رصد محاولة ترقية سابقة لم تكتمل'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('استعادة النسخة الاحتياطية المعتمدة'), findsOneWidget);
  });

  testWidgets('shows validation error when attempting restore without entering PIN', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final status = EmergencyStatus(
      isEmergency: true,
      reason: EmergencyReason.incompleteMigration,
      backupFile: backupFile,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: EmergencyRecoveryScreen(
            recoveryService: recoveryService,
            status: status,
            onRestored: () {},
          ),
        ),
      ),
    );

    final buttonFinder = find.text('استعادة النسخة الاحتياطية المعتمدة');
    await tester.ensureVisible(buttonFinder);
    await tester.tap(buttonFinder);
    await tester.pump();

    expect(find.text('يرجى إدخال رمز الأمان (PIN) للمتابعة'), findsOneWidget);
  });
}
