import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../config/app_config.dart';
import '../constants/app_colors.dart';
import 'widgets/app_update_dialog.dart';

class AppUpdateInfo {
  final String latestVersion;
  final int latestBuildNumber;
  final String minRequiredVersion;
  final int minRequiredBuildNumber;
  final String downloadUrl;
  final String releaseNotes;
  final bool isForceUpdate;
  final bool enabled;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.latestBuildNumber,
    this.minRequiredVersion = '1.0.0',
    this.minRequiredBuildNumber = 0,
    required this.downloadUrl,
    this.releaseNotes = '',
    this.isForceUpdate = false,
    this.enabled = true,
  });

  factory AppUpdateInfo.fromMap(Map<String, dynamic> data) {
    return AppUpdateInfo(
      latestVersion: data['latest_version'] as String? ?? (data['version'] as String? ?? '1.0.0'),
      latestBuildNumber: (data['latest_build_number'] as num?)?.toInt() ??
          (data['build_number'] as num?)?.toInt() ??
          0,
      minRequiredVersion: data['min_required_version'] as String? ?? '1.0.0',
      minRequiredBuildNumber: (data['min_required_build_number'] as num?)?.toInt() ?? 0,
      downloadUrl: data['download_url'] as String? ?? (data['apk_url'] as String? ?? ''),
      releaseNotes: data['release_notes'] as String? ?? (data['notes'] as String? ?? ''),
      isForceUpdate: data['is_force_update'] as bool? ?? (data['force_update'] as bool? ?? false),
      enabled: data['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'latest_version': latestVersion,
      'latest_build_number': latestBuildNumber,
      'min_required_version': minRequiredVersion,
      'min_required_build_number': minRequiredBuildNumber,
      'download_url': downloadUrl,
      'release_notes': releaseNotes,
      'is_force_update': isForceUpdate,
      'enabled': enabled,
      'updated_at': FieldValue.serverTimestamp(),
    };
  }
}

class AppUpdateService {
  static const String configCollection = 'app_config';
  static const String updateDoc = 'update_info';

  static bool _hasAutoChecked = false;

  /// Reset check state (useful for tests or manual re-check)
  static void resetAutoCheckState() {
    _hasAutoChecked = false;
  }

  /// Compares two semantic version strings (e.g., '1.0.1' and '1.0.0').
  /// Returns 1 if v1 > v2, -1 if v1 < v2, and 0 if equal.
  static int compareSemanticVersions(String v1, String v2) {
    final cleanV1 = v1.split('-').first.trim();
    final cleanV2 = v2.split('-').first.trim();

    final parts1 = cleanV1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final parts2 = cleanV2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    final maxLen = parts1.length > parts2.length ? parts1.length : parts2.length;
    for (int i = 0; i < maxLen; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 > p2) return 1;
      if (p1 < p2) return -1;
    }
    return 0;
  }

  /// Determines if an update is available given current and remote versions.
  static bool isUpdateAvailable({
    required String currentVersion,
    required int currentBuildNumber,
    required String remoteVersion,
    required int remoteBuildNumber,
  }) {
    if (remoteBuildNumber > currentBuildNumber) {
      return true;
    }
    if (remoteBuildNumber == currentBuildNumber) {
      return compareSemanticVersions(remoteVersion, currentVersion) > 0;
    }
    return compareSemanticVersions(remoteVersion, currentVersion) > 0;
  }

  /// Determines if the update is mandatory.
  static bool isForceUpdateRequired({
    required String currentVersion,
    required int currentBuildNumber,
    required AppUpdateInfo updateInfo,
  }) {
    if (updateInfo.isForceUpdate) return true;
    if (updateInfo.minRequiredBuildNumber > currentBuildNumber) return true;
    if (compareSemanticVersions(updateInfo.minRequiredVersion, currentVersion) > 0) return true;
    return false;
  }

  /// Fetches update info from Firestore `app_config/update_info`.
  static Future<AppUpdateInfo?> fetchUpdateInfo({FirebaseFirestore? firestore}) async {
    if (!kEnableFirebase) return null;
    try {
      final db = firestore ?? FirebaseFirestore.instance;
      final doc = await db.collection(configCollection).doc(updateDoc).get();
      if (!doc.exists || doc.data() == null) {
        return null;
      }
      return AppUpdateInfo.fromMap(doc.data()!);
    } catch (e) {
      debugPrint('AppUpdateService: Error fetching update info: $e');
      return null;
    }
  }

  /// Publishes new update configuration to Firestore.
  static Future<void> publishUpdateInfo(
    AppUpdateInfo info, {
    FirebaseFirestore? firestore,
  }) async {
    final db = firestore ?? FirebaseFirestore.instance;
    await db.collection(configCollection).doc(updateDoc).set(info.toMap(), SetOptions(merge: true));
  }

  /// Checks for updates and displays the modern Arabic update dialog if a new version is found.
  static Future<void> checkForUpdate(
    BuildContext context, {
    bool forceCheck = false,
    bool showNoUpdateToast = false,
    FirebaseFirestore? firestore,
    PackageInfo? mockPackageInfo,
  }) async {
    if (!forceCheck && _hasAutoChecked) {
      return;
    }
    _hasAutoChecked = true;

    try {
      final packageInfo = mockPackageInfo ?? await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version.trim();
      final currentBuildNumber = int.tryParse(packageInfo.buildNumber.trim()) ?? 0;

      final updateInfo = await fetchUpdateInfo(firestore: firestore);

      if (!context.mounted) return;

      if (updateInfo == null || !updateInfo.enabled) {
        if (showNoUpdateToast) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('أنت تستخدم أحدث إصدار من التطبيق (v$currentVersion)'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final hasUpdate = isUpdateAvailable(
        currentVersion: currentVersion,
        currentBuildNumber: currentBuildNumber,
        remoteVersion: updateInfo.latestVersion,
        remoteBuildNumber: updateInfo.latestBuildNumber,
      );

      if (hasUpdate) {
        final isForce = isForceUpdateRequired(
          currentVersion: currentVersion,
          currentBuildNumber: currentBuildNumber,
          updateInfo: updateInfo,
        );

        await showDialog(
          context: context,
          barrierDismissible: !isForce,
          builder: (dialogCtx) => AppUpdateDialog(
            updateInfo: updateInfo,
            currentVersion: currentVersion,
            isForce: isForce,
          ),
        );
      } else {
        if (showNoUpdateToast) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('أنت تستخدم أحدث إصدار من التطبيق (v$currentVersion)'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('AppUpdateService: Error during update check: $e');
      if (showNoUpdateToast && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر التحقق من وجود تحديثات في الوقت الحالي'),
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

