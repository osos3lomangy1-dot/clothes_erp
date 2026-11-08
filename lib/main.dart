import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/di/injection.dart';
import 'core/firebase/firebase_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/cubits/auth_cubit.dart';
import 'features/auth/presentation/cubits/auth_state.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/dashboard/presentation/screens/admin_dashboard_screen.dart';
import 'features/dashboard/presentation/screens/cashier_dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
