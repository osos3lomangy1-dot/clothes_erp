import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/navigation/app_navigator.dart';
import '../../domain/entities/category_entity.dart';
import '../cubits/category_form_cubit.dart';
import '../cubits/category_form_state.dart';

class CategoryFormScreen extends StatelessWidget {
  final CategoryEntity? category;

  const CategoryFormScreen({super.key, this.category});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<CategoryFormCubit>()..init(category),
      child: BlocConsumer<CategoryFormCubit, CategoryFormState>(
        listener: (context, state) {
          if (state.status == CategoryFormStatus.success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Category saved successfully')),
            );
            AppNavigator.pop(context);
          } else if (state.status == CategoryFormStatus.error && state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.errorMessage!)),
            );
          }
        },
        builder: (context, state) {
          return Scaffold(
            appBar: AppBar(
              title: Text(state.isEdit ? 'Edit Category' : 'Add Category'),
            ),
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  TextFormField(
                    initialValue: state.name,
                    decoration: const InputDecoration(labelText: 'Category Name'),
                    onChanged: (value) => context.read<CategoryFormCubit>().onNameChanged(value),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: state.description,
                    decoration: const InputDecoration(labelText: 'Description'),
                    onChanged: (value) => context.read<CategoryFormCubit>().onDescriptionChanged(value),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: state.status == CategoryFormStatus.loading
                          ? null
                          : () => context.read<CategoryFormCubit>().submit(category?.id),
                      child: state.status == CategoryFormStatus.loading
                          ? const CircularProgressIndicator()
                          : Text(state.isEdit ? 'Update' : 'Save'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
