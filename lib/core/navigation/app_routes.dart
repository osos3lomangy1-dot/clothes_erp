import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../di/injection.dart';
import '../../features/auth/presentation/cubits/auth_cubit.dart';
import '../../features/auth/presentation/cubits/auth_state.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/dashboard/presentation/screens/admin_dashboard_screen.dart';
import '../../features/dashboard/presentation/screens/cashier_dashboard_screen.dart';
import '../../features/categories/presentation/screens/category_list_screen.dart';
import '../../features/categories/presentation/screens/category_form_screen.dart';
import '../../features/categories/domain/entities/category_entity.dart';
import '../../features/products/presentation/screens/product_list_screen.dart';
import '../../features/products/presentation/screens/product_form_screen.dart';
import '../../features/products/domain/entities/product_entity.dart';
import '../../features/product_variants/presentation/screens/variant_list_screen.dart';
import '../../features/product_variants/presentation/screens/variant_form_screen.dart';
import '../../features/product_variants/domain/entities/variant_entity.dart';
import '../../features/inventory/presentation/screens/inventory_screen.dart';
import '../../features/pos/presentation/screens/pos_screen.dart';

class AppRoutes {
  static const String login = '/login';
  static const String adminDashboard = '/admin';
  static const String cashierDashboard = '/cashier';
  static const String categories = '/categories';
  static const String categoryForm = '/categories-form';
  static const String products = '/products';
  static const String productForm = '/products-form';
  static const String variants = '/variants';
  static const String variantForm = '/variants-form';
  static const String inventory = '/inventory';
  static const String pos = '/pos';

  static final GoRouter router = GoRouter(
    initialLocation: login,
    redirect: (context, state) {
      final authState = getIt<AuthCubit>().state;
      final isLoggingIn = state.matchedLocation == login;

      if (authState is AuthUnauthenticated || authState is AuthInitial) {
        return isLoggingIn ? null : login;
      }

      if (authState is AuthAuthenticated) {
        if (isLoggingIn) {
          return authState.user.role == 'admin' ? adminDashboard : cashierDashboard;
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: adminDashboard,
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: cashierDashboard,
        builder: (context, state) => const CashierDashboardScreen(),
      ),
      GoRoute(
        path: categories,
        builder: (context, state) => const CategoryListScreen(),
      ),
      GoRoute(
        path: categoryForm,
        builder: (context, state) {
          final category = state.extra as CategoryEntity?;
          return CategoryFormScreen(category: category);
        },
      ),
      GoRoute(
        path: products,
        builder: (context, state) => const ProductListScreen(),
      ),
      GoRoute(
        path: productForm,
        builder: (context, state) {
          final product = state.extra as ProductEntity?;
          return ProductFormScreen(product: product);
        },
      ),
      GoRoute(
        path: variants,
        builder: (context, state) {
          final product = state.extra;
          if (product == null || product is! ProductEntity) {
            return const LoginScreen();
          }
          return VariantListScreen(product: product);
        },
      ),
      GoRoute(
        path: variantForm,
        builder: (context, state) {
          final extra = state.extra;
          if (extra == null || extra is! Map<String, dynamic>) {
            return const LoginScreen();
          }
          final product = extra['product'];
          if (product == null || product is! ProductEntity) {
            return const LoginScreen();
          }
          final variant = extra['variant'];
          if (variant != null && variant is! VariantEntity) {
            return const LoginScreen();
          }
          return VariantFormScreen(product: product, variant: variant);
        },
      ),
      GoRoute(
        path: inventory,
        builder: (context, state) => const InventoryScreen(),
      ),
      GoRoute(
        path: pos,
        builder: (context, state) => const PosScreen(),
      ),
    ],
  );
}
