import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/navigation/app_navigator.dart';
import '../../../../core/navigation/app_routes.dart';
import '../cubits/category_cubit.dart';
import '../cubits/category_state.dart';

class CategoryListScreen extends StatelessWidget {
  const CategoryListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<CategoryCubit>()..getCategories(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Categories'),
        ),
        body: BlocBuilder<CategoryCubit, CategoryState>(
          builder: (context, state) {
            if (state is CategoryLoading) {
              return const Center(child: CircularProgressIndicator());
            } else if (state is CategoryLoaded) {
              return ListView.builder(
                itemCount: state.categories.length,
                itemBuilder: (context, index) {
                  final category = state.categories[index];
                  return ListTile(
                    title: Text(category.name),
                    subtitle: Text(category.description),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => AppNavigator.push(
                            context,
                            AppRoutes.categoryForm,
                            extra: category,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => context.read<CategoryCubit>().deleteCategory(category.id),
                        ),
                      ],
                    ),
                  );
                },
              );
            } else if (state is CategoryEmpty) {
              return const Center(child: Text('No categories found'));
            } else if (state is CategoryError) {
              return Center(child: Text(state.message));
            }
            return const SizedBox.shrink();
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => AppNavigator.push(context, AppRoutes.categoryForm),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
