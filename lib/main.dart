import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/di/injection.dart';
import 'core/firebase/firebase_service.dart';
import 'core/navigation/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/firebase_setup.dart';
import 'features/auth/presentation/cubits/auth_cubit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await FirebaseService.init();
  
  // Initialize Dependency Injection (Injectable)
  await configureDependencies();
  await FirebaseSetup.setupAdmin('admin', 'osamaabdelnabi242@gmail.com', 'Admin');
  runApp(
    BlocProvider(
      create: (context) => getIt<AuthCubit>(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Clothes ERP',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: AppRoutes.router,
    );
  }
}
