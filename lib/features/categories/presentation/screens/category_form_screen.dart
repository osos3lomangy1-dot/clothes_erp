import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
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
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface),
          tooltip: 'رجوع للتصنيفات',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          category != null ? 'تعديل التصنيف' : 'إضافة تصنيف جديد',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 550),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: CategoryFormView(category: category, isDialog: false),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CategoryFormDialog extends StatelessWidget {
  final CategoryEntity? category;

  const CategoryFormDialog({super.key, this.category});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: CategoryFormView(category: category, isDialog: true),
        ),
      ),
    );
  }
}

class CategoryFormView extends StatelessWidget {
  final CategoryEntity? category;
  final bool isDialog;

  const CategoryFormView({super.key, this.category, this.isDialog = false});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<CategoryFormCubit>()..init(category),
      child: BlocConsumer<CategoryFormCubit, CategoryFormState>(
        listener: (context, state) {
          if (state.status == CategoryFormStatus.success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: Colors.green,
                content: Text('تم حفظ بيانات التصنيف بنجاح'),
              ),
            );
            AppNavigator.pop(context);
          } else if (state.status == CategoryFormStatus.error && state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppColors.error,
                content: Text(state.errorMessage!),
              ),
            );
          }
        },
        builder: (context, state) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isDialog) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      state.isEdit ? 'تعديل التصنيف' : 'إضافة تصنيف جديد',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.onSurface),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const Divider(height: 20),
              ],
              TextFormField(
                initialValue: state.name,
                decoration: InputDecoration(
                  labelText: 'اسم التصنيف *',
                  hintText: 'مثال: ملابس رجالي، بناطيل، فساتين',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onChanged: (value) => context.read<CategoryFormCubit>().onNameChanged(value),
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: state.description,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'وصف إضافي (اختياري)',
                  hintText: 'اكتب وصفاً مختصراً للتصنيف...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onChanged: (value) => context.read<CategoryFormCubit>().onDescriptionChanged(value),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: state.status == CategoryFormStatus.loading
                      ? null
                      : () => context.read<CategoryFormCubit>().submit(category?.id),
                  child: state.status == CategoryFormStatus.loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          state.isEdit ? 'تحديث التصنيف' : 'حفظ التصنيف',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
