import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class StoreProfile {
  final String id;
  final String name;
  final String activityLabel;
  final DateTime createdAt;

  const StoreProfile({
    required this.id,
    required this.name,
    this.activityLabel = '',
    required this.createdAt,
  });

  bool get isDefault => id == StoreProfileService.defaultProfileId;

  String get dbBaseName => isDefault ? 'clothes_erp' : 'store';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'activityLabel': activityLabel,
        'createdAt': createdAt.toIso8601String(),
      };

  factory StoreProfile.fromJson(Map<String, dynamic> json) {
    return StoreProfile(
      id: (json['id'] as String?) ?? StoreProfileService.defaultProfileId,
      name: (json['name'] as String?) ?? 'المتجر الرئيسي',
      activityLabel: (json['activityLabel'] as String?) ?? '',
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime(2026, 1, 1),
    );
  }
}

class StoreProfileService {
  static const String defaultProfileId = 'default';
  static const String registryFileName = 'store_profiles.json';

  /// Global hook wired in `main.dart` to close DB, reset GetIt, switch profile, and restart UI root.
  static Future<void> Function(String profileId)? onSwitchProfileRequested;

  static final StoreProfileService instance = StoreProfileService._();

  final Future<Directory> Function() _supportDirProvider;
  final Future<Directory> Function()? _docsDirProvider;

  StoreProfileService._()
      : _supportDirProvider = getApplicationSupportDirectory,
        _docsDirProvider = getApplicationDocumentsDirectory;

  StoreProfileService.withProviders({
    required Future<Directory> Function() supportDirProvider,
    Future<Directory> Function()? docsDirProvider,
  })  : _supportDirProvider = supportDirProvider,
        _docsDirProvider = docsDirProvider;

  String _activeProfileId = defaultProfileId;
  List<StoreProfile> _profiles = [
    StoreProfile(
      id: defaultProfileId,
      name: 'المتجر الرئيسي',
      createdAt: DateTime(2026, 1, 1),
    ),
  ];

  String get activeProfileId => _activeProfileId;

  List<StoreProfile> get profiles => List.unmodifiable(_profiles);

  StoreProfile get activeProfile => _profiles.firstWhere(
        (p) => p.id == _activeProfileId,
        orElse: () => _profiles.first,
      );

  String get activeDbBaseName => activeProfile.dbBaseName;

  Future<File> _registryFile() async {
    final supportDir = await _supportDirProvider();
    if (!supportDir.existsSync()) {
      await supportDir.create(recursive: true);
    }
    return File('${supportDir.path}${Platform.pathSeparator}$registryFileName');
  }

  Future<void> init() async {
    try {
      final regFile = await _registryFile();
      if (!regFile.existsSync()) {
        await _saveRegistry();
        return;
      }
      final raw = await regFile.readAsString();
      if (raw.trim().isEmpty) {
        await _saveRegistry();
        return;
      }
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final list = (decoded['profiles'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(StoreProfile.fromJson)
          .toList();

      if (!list.any((p) => p.id == defaultProfileId)) {
        list.insert(
          0,
          StoreProfile(
            id: defaultProfileId,
            name: 'المتجر الرئيسي',
            createdAt: DateTime(2026, 1, 1),
          ),
        );
      }

      _profiles = list;
      final savedActive = decoded['activeProfileId'] as String?;
      if (savedActive != null && _profiles.any((p) => p.id == savedActive)) {
        _activeProfileId = savedActive;
      } else {
        _activeProfileId = defaultProfileId;
      }
    } catch (_) {
      _activeProfileId = defaultProfileId;
      _profiles = [
        StoreProfile(
          id: defaultProfileId,
          name: 'المتجر الرئيسي',
          createdAt: DateTime(2026, 1, 1),
        ),
      ];
    }
  }

  Future<void> _saveRegistry() async {
    final regFile = await _registryFile();
    final payload = {
      'activeProfileId': _activeProfileId,
      'profiles': _profiles.map((p) => p.toJson()).toList(),
    };
    await regFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  Future<File> activeDbFile() => dbFileFor(_activeProfileId);

  Future<File> dbFileFor(String profileId) async {
    final supportDir = await _supportDirProvider();
    if (profileId == defaultProfileId) {
      return File('${supportDir.path}${Platform.pathSeparator}clothes_erp.sqlite');
    }
    final profileDir = Directory(
      '${supportDir.path}${Platform.pathSeparator}profiles${Platform.pathSeparator}$profileId',
    );
    if (!profileDir.existsSync()) {
      await profileDir.create(recursive: true);
    }
    return File('${profileDir.path}${Platform.pathSeparator}store.sqlite');
  }

  Future<Directory> activeBackupDirectory() =>
      backupDirectoryFor(_activeProfileId);

  Future<Directory> backupDirectoryFor(String profileId) async {
    Directory baseBackupDir;
    try {
      final docs = _docsDirProvider != null
          ? await _docsDirProvider()
          : await getApplicationDocumentsDirectory();
      baseBackupDir =
          Directory('${docs.path}${Platform.pathSeparator}SalesSystemBackups');
    } catch (_) {
      final support = await _supportDirProvider();
      baseBackupDir = Directory('${support.path}${Platform.pathSeparator}backups');
    }

    if (profileId == defaultProfileId) {
      return baseBackupDir;
    }
    return Directory(
      '${baseBackupDir.path}${Platform.pathSeparator}profiles${Platform.pathSeparator}$profileId',
    );
  }

  Future<StoreProfile> createProfile({
    required String name,
    String activityLabel = '',
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw ArgumentError('اسم المتجر مطلوب');
    }
    final id = 'store_${DateTime.now().millisecondsSinceEpoch}';
    final profile = StoreProfile(
      id: id,
      name: cleanName,
      activityLabel: activityLabel.trim(),
      createdAt: DateTime.now(),
    );

    // Ensure isolated profile directory exists
    await dbFileFor(id);

    _profiles = [..._profiles, profile];
    await _saveRegistry();
    return profile;
  }

  Future<void> setActiveProfile(String profileId) async {
    if (!_profiles.any((p) => p.id == profileId)) {
      throw StateError('البروفايل غير موجود: $profileId');
    }
    _activeProfileId = profileId;
    await _saveRegistry();
  }
}

