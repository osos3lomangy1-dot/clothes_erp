import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
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
  static const String _githubToken = String.fromEnvironment('GITHUB_TOKEN');
  static const String _githubRepo = String.fromEnvironment(
    'GITHUB_REPO',
    defaultValue: 'osos3lomangy1-dot/clothes_erp',
  );

  static const String configCollection = 'app_config';
  static const String updateDoc = 'update_info';

  static bool _hasAutoChecked = false;

  static void resetAutoCheckState() {
    _hasAutoChecked = false;
  }

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

  static Future<AppUpdateInfo?> fetchFromGitHubReleases({
    http.Client? client,
    String? repo,
    String? token,
  }) async {
    final effectiveRepo = repo ?? _githubRepo;
    final effectiveToken = token ?? _githubToken;

    if (effectiveRepo.isEmpty) return null;

    final url = Uri.parse('https://api.github.com/repos/$effectiveRepo/releases/latest');
    final headers = <String, String>{
      'Accept': 'application/vnd.github.v3+json',
      'User-Agent': 'clothes_erp-updater',
    };
    if (effectiveToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $effectiveToken';
    }

    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient.get(url, headers: headers).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode != 200) {
        debugPrint('AppUpdateService: GitHub returned status ${response.statusCode}');
        return null;
      }

      final rawBody = utf8.decode(response.bodyBytes);
      final data = jsonDecode(rawBody) as Map<String, dynamic>;
      final tagName = (data['tag_name'] as String? ?? '').trim();
      if (tagName.isEmpty) return null;

      final cleanTag = tagName.startsWith('v') || tagName.startsWith('V')
          ? tagName.substring(1).trim()
          : tagName;

      String versionStr = cleanTag;
      int buildNum = 0;

      if (cleanTag.contains('+')) {
        final parts = cleanTag.split('+');
        versionStr = parts[0].trim();
        buildNum = int.tryParse(parts[1].trim()) ?? 0;
      }

      final assets = (data['assets'] as List?) ?? [];
      String downloadUrl = data['html_url'] as String? ?? '';

      String? exeUrl;
      String? msixUrl;
      String? zipUrl;

      for (final asset in assets) {
        if (asset is Map<String, dynamic>) {
          final name = (asset['name'] as String? ?? '').toLowerCase();
          final browserUrl = asset['browser_download_url'] as String? ?? '';
          if (name.endsWith('.exe')) {
            exeUrl = browserUrl;
          } else if (name.endsWith('.msix')) {
            msixUrl = browserUrl;
          } else if (name.endsWith('.zip')) {
            zipUrl = browserUrl;
          }
        }
      }

      downloadUrl = exeUrl ?? msixUrl ?? zipUrl ?? downloadUrl;
      final releaseNotes = data['body'] as String? ?? '';

      return AppUpdateInfo(
        latestVersion: versionStr,
        latestBuildNumber: buildNum,
        downloadUrl: downloadUrl,
        releaseNotes: releaseNotes,
        isForceUpdate: releaseNotes.contains('[FORCE_UPDATE]') ||
            releaseNotes.contains('إجباري'),
        enabled: true,
      );
    } catch (e) {
      debugPrint('AppUpdateService: Error fetching from GitHub Releases: $e');
      return null;
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  static Future<AppUpdateInfo?> fetchFromFirestore({FirebaseFirestore? firestore}) async {
    if (!kEnableFirebase) return null;
    try {
      final db = firestore ?? FirebaseFirestore.instance;
      final doc = await db.collection(configCollection).doc(updateDoc).get();
      if (!doc.exists || doc.data() == null) {
        return null;
      }
      return AppUpdateInfo.fromMap(doc.data()!);
    } catch (e) {
      if (e.toString().contains('permission-denied')) {
        return null;
      }
      debugPrint('AppUpdateService: Error fetching from Firestore: $e');
      return null;
    }
  }

  static Future<AppUpdateInfo?> fetchUpdateInfo({
    FirebaseFirestore? firestore,
    http.Client? httpClient,
  }) async {
    final githubInfo = await fetchFromGitHubReleases(client: httpClient);
    if (githubInfo != null) {
      return githubInfo;
    }
    return await fetchFromFirestore(firestore: firestore);
  }

  static Future<void> publishUpdateInfo(
    AppUpdateInfo info, {
    FirebaseFirestore? firestore,
  }) async {
    final db = firestore ?? FirebaseFirestore.instance;
    await db.collection(configCollection).doc(updateDoc).set(info.toMap(), SetOptions(merge: true));
  }

  static Future<String> downloadUpdate(
    String url, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
    Dio? dio,
  }) async {
    final dir = await getApplicationSupportDirectory();
    final uri = Uri.parse(url);
    var fileName = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    fileName = fileName.split('?').first;
    if (fileName.isEmpty) {
      fileName = 'update_${DateTime.now().millisecondsSinceEpoch}.exe';
    }
    final safeName = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final filePath = '${dir.path}${Platform.pathSeparator}update_${DateTime.now().millisecondsSinceEpoch}_$safeName';

    final client = dio ?? Dio();
    try {
      await client.download(
        url,
        filePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress?.call((received / total).clamp(0.0, 1.0));
          }
        },
      );
      return filePath;
    } finally {
      if (dio == null) {
        client.close();
      }
    }
  }

  static Future<void> checkForUpdate(
    BuildContext context, {
    bool forceCheck = false,
    bool showNoUpdateToast = false,
    FirebaseFirestore? firestore,
    PackageInfo? mockPackageInfo,
    http.Client? mockHttpClient,
  }) async {
    if (!forceCheck && _hasAutoChecked) {
      return;
    }
    _hasAutoChecked = true;

    try {
      final packageInfo = mockPackageInfo ?? await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version.trim();
      final currentBuildNumber = int.tryParse(packageInfo.buildNumber.trim()) ?? 0;

      final updateInfo = await fetchUpdateInfo(
        firestore: firestore,
        httpClient: mockHttpClient,
      );

      if (!context.mounted) return;

      if (updateInfo == null) {
        if (showNoUpdateToast) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تعذر التحقق من التحديثات، يرجى التأكد من اتصال الإنترنت'),
              backgroundColor: AppColors.warning,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      if (!updateInfo.enabled) {
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
