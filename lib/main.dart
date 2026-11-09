import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/constants/app_colors.dart';
import 'core/di/injection.dart';
import 'core/firebase/firebase_service.dart';
import 'core/services/crash_logger_service.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/logging.dart';
import 'features/auth/presentation/cubits/auth_cubit.dart';
import 'features/auth/presentation/cubits/auth_state.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/dashboard/presentation/screens/admin_dashboard_screen.dart';
import 'features/dashboard/presentation/screens/cashier_dashboard_screen.dart';

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

  await FirebaseService.init();
  await configureDependencies();

  runApp(
    MultiBlocProvider(
      providers: [BlocProvider(create: (context) => getIt<AuthCubit>())],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: MaterialApp(
        title: 'أوركييييد',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        navigatorObservers: [CrashRouteObserver()],
        builder: (context, child) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: BlocBuilder<AuthCubit, AuthState>(
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
  }
}
