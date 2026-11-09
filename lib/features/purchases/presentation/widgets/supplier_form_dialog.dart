import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../domain/entities/supplier_entity.dart';

class SupplierFormDialog extends StatefulWidget {
  final SupplierEntity? supplier;
  final Function({
    required String name,
    String? phone,
    String? companyName,
    String? address,
  }) onSave;

  const SupplierFormDialog({
    super.key,
    this.supplier,
    required this.onSave,
  });

  @override
  State<SupplierFormDialog> createState() => _SupplierFormDialogState();
}

class _SupplierFormDialogState extends State<SupplierFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _companyController;
  late final TextEditingController _addressController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.supplier?.name ?? '');
    _phoneController = TextEditingController(text: widget.supplier?.phone ?? '');
    _companyController = TextEditingController(text: widget.supplier?.companyName ?? '');
    _addressController = TextEditingController(text: widget.supplier?.address ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _companyController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      widget.onSave(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        companyName: _companyController.text.trim().isEmpty ? null : _companyController.text.trim(),
        address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.supplier != null;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            isEdit ? Icons.edit_rounded : Icons.person_add_rounded,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          Text(
            isEdit ? 'تعديل بيانات المورد' : 'إضافة مورد جديد',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'اسم المورد أو المسؤول *',
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'يرجى كتابة اسم المورد' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _companyController,
                  decoration: InputDecoration(
                    labelText: 'اسم المصنع أو الشركة',
                    prefixIcon: const Icon(Icons.business_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'رقم الهاتف',
                    prefixIcon: const Icon(Icons.phone_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _addressController,
                  decoration: InputDecoration(
                    labelText: 'العنوان أو المحافظة',
                    prefixIcon: const Icon(Icons.location_on_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _submit,
          child: Text(
            isEdit ? 'حفظ التعديل' : 'إضافة المورد',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

