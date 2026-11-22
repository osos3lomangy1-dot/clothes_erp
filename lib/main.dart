import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'core/constants/app_colors.dart';
import 'core/database/emergency_recovery_service.dart';
import 'core/database/migration_marker_service.dart';
import 'core/di/injection.dart';
import 'core/features/feature_gate.dart';
import 'core/presentation/screens/emergency_recovery_screen.dart';
import 'core/services/crash_logger_service.dart';
import 'core/services/google_drive_backup_service.dart';
import 'core/services/local_backup_service.dart';
import 'core/theme/app_branding.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/logging.dart';
import 'features/auth/presentation/cubits/auth_cubit.dart';
import 'features/auth/presentation/cubits/auth_state.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/dashboard/presentation/screens/admin_dashboard_screen.dart';
import 'features/dashboard/presentation/screens/cashier_dashboard_screen.dart';
import 'features/onboarding/presentation/screens/first_launch_setup_screen.dart';
import 'features/invoices/data/services/receipt_settings_service.dart';
import 'features/barcode_printing/services/barcode_settings_service.dart';
import 'features/auth/services/cashier_permissions_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 0. Initialize local crash logger
  await CrashLoggerService.init();

  // 1. Global Flutter framework error handling
  FlutterError.onError = (FlutterErrorDetails details) {
    CrashLoggerService.logCrash(
      details.exception,
      details.stack,
      context: 'Flutter Framework: ${details.context?.toDescription() ?? "General"}',
    );
    Logging.error('FlutterError: ${details.exceptionAsString()}\n${details.stack}');
  };

  // 2. Global asynchronous unhandled error handling
  PlatformDispatcher.instance.onError = (error, stack) {
    CrashLoggerService.logCrash(
      error,
      stack,
      context: 'PlatformDispatcher Unhandled Async',
    );
    Logging.error('PlatformDispatcher unhandled error: $error\n$stack');
    return true; // Prevent app termination
  };

  // 3. User-friendly custom ErrorWidget replacing the red screen
  ErrorWidget.builder = (FlutterErrorDetails details) {
    CrashLoggerService.logCrash(
      details.exception,
      details.stack,
      context: 'ErrorWidget (UI Render Failure)',
    );
    Logging.error('ErrorWidget built for: ${details.exceptionAsString()}');
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: AppColors.surface,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.error_outline_rounded,
                          color: AppColors.error,
                          size: 48,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'حدث خطأ غير متوقع',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'نعتذر عن هذا الخطأ المؤقت. بياناتك في أمان تام.\nيرجى إعادة المحاولة أو إعادة فتح الشاشة.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () {
                          // Allow the user to re-initialize or rebuild the app
                          runApp(
                            MultiBlocProvider(
                              providers: [BlocProvider(create: (context) => getIt<AuthCubit>())],
                              child: const MyApp(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text(
                          'إعادة المحاولة',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  };

  // Firebase intentionally disabled on Windows.
  // See Phase 0 decision + TD for full removal.
  Logging.info('[Safe Mode] Running without Firebase');

  // Emergency Recovery Pre-Flight Check
  try {
    final supportDir = await getApplicationSupportDirectory();
    if (!supportDir.existsSync()) {
      await supportDir.create(recursive: true);
    }
    final activeDbFile = File('${supportDir.path}/clothes_erp.sqlite');
    final markerService = MigrationMarkerService(supportDir);
    final recoveryService = EmergencyRecoveryService(
      activeDbFile: activeDbFile,
      markerService: markerService,
    );

    final emergencyStatus = await recoveryService.checkRecoveryNeeded();
    if (emergencyStatus.isEmergency) {
      Logging.error('[Emergency State Detected] Reason: ${emergencyStatus.reason}');
      runApp(
        Directionality(
          textDirection: TextDirection.rtl,
          child: MaterialApp(
            title: 'طوارئ النظام - Bay3ah ERP',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              fontFamily: 'Cairo',
              colorSchemeSeed: AppColors.primary,
              useMaterial3: true,
            ),
            home: EmergencyRecoveryScreen(
              recoveryService: recoveryService,
              status: emergencyStatus,
              onRestored: () async {
                await _startNormalApp();
              },
            ),
          ),
        ),
      );
      return;
    }
  } catch (e, stack) {
    Logging.error('Failed to run emergency recovery check: $e\n$stack');
  }

  await _startNormalApp();
}

Future<void> _startNormalApp() async {
  await configureDependencies();
  final gate = getIt<FeatureGate>();
  await AppBranding.loadFromFeatureGate(gate);
  await ReceiptSettingsService.loadFromFeatureGate(gate);
  await BarcodeSettingsService.loadFromFeatureGate(gate);
  await CashierPermissionsService.loadFromFeatureGate(gate);
  // Silent daily local SQLite auto-backup + Google Drive auto-upload (non-blocking)
  unawaited(getIt<LocalBackupService>().runAutoBackupIfDue());
  unawaited(getIt<GoogleDriveBackupService>().runAutoDriveBackupIfDue());

  // Check if first-time store onboarding setup is completed
  final setupMeta = await gate.getMeta('setup.completed');
  final isSetupCompleted = setupMeta == '1';

  runApp(
    MultiBlocProvider(
      providers: [BlocProvider(create: (context) => getIt<AuthCubit>())],
      child: MyApp(isSetupCompleted: isSetupCompleted),
    ),
  );
}

class MyApp extends StatefulWidget {
  final bool isSetupCompleted;

  const MyApp({super.key, this.isSetupCompleted = true});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late bool _setupCompleted;

  @override
  void initState() {
    super.initState();
    _setupCompleted = widget.isSetupCompleted;
  }

  void _onSetupCompleted() {
    setState(() {
      _setupCompleted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppBrandingConfig>(
      valueListenable: AppBranding.notifier,
      builder: (context, branding, _) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: MaterialApp(
            title: branding.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(
              primary: branding.primaryColor,
              secondary: branding.secondaryColor,
            ),
            navigatorObservers: [CrashRouteObserver()],
            builder: (context, child) {
              return Directionality(
                textDirection: TextDirection.rtl,
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: !_setupCompleted
                ? FirstLaunchSetupScreen(onSetupCompleted: _onSetupCompleted)
                : BlocBuilder<AuthCubit, AuthState>(
                    buildWhen: (previous, current) =>
                        previous.runtimeType != current.runtimeType ||
                        (current is AuthAuthenticated &&
                            previous is AuthAuthenticated &&
                            previous.user.role != current.user.role),
                    builder: (context, state) {
                      if (state is AuthAuthenticated) {
                        return state.user.role == 'admin'
                            ? const AdminDashboardScreen()
                            : const CashierDashboardScreen();
                      }
                      return const LoginScreen();
                    },
                  ),
          ),
        );
      },
    );
  }
}
