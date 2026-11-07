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
          return Scaffold(
            backgroundColor: AppColors.surface,
            appBar: AppBar(
              backgroundColor: Colors.white,
              title: Text(
                state.isEdit ? 'تعديل التصنيف' : 'إضافة تصنيف جديد',
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                          const SizedBox(height: 28),
                          SizedBox(
                            width: double.infinity,
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
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
