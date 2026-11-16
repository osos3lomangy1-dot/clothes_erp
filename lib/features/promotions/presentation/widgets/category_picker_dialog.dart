import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../categories/domain/entities/category_entity.dart';
import '../../../categories/domain/repositories/category_repository.dart';

class CategoryPickerDialog extends StatefulWidget {
  final List<String> initialSelectedIds;
  final CategoryRepository? repository;

  const CategoryPickerDialog({
    super.key,
    this.initialSelectedIds = const [],
    this.repository,
  });

  @override
  State<CategoryPickerDialog> createState() => _CategoryPickerDialogState();
}

class _CategoryPickerDialogState extends State<CategoryPickerDialog> {
  final _searchController = TextEditingController();
  List<CategoryEntity> _all = const [];
  List<CategoryEntity> _filtered = const [];
  late Set<String> _selected;
  bool _loading = true;
  String? _error;

  CategoryRepository get _repo =>
      widget.repository ?? getIt<CategoryRepository>();

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initialSelectedIds);
    _load();
  }

  Future<void> _load() async {
    final result = await _repo.getCategories();
    if (!mounted) return;
    result.fold(
      (f) => setState(() {
        _loading = false;
        _error = f.message;
      }),
      (list) => setState(() {
        _loading = false;
        _all = list;
        _filtered = list;
      }),
    );
  }

  void _onSearch(String q) {
    final lower = q.trim().toLowerCase();
    setState(() {
      _filtered = lower.isEmpty
          ? _all
          : _all.where((c) => c.name.toLowerCase().contains(lower)).toList();
    });
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('اختيار الأقسام',
              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          if (_selected.isNotEmpty)
            Chip(
              label: Text('${_selected.length} محدد',
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            ),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 450,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: _onSearch,
              decoration: const InputDecoration(
                hintText: 'ابحث باسم القسم...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Text('خطأ: $_error',
                              style: const TextStyle(fontFamily: 'Cairo')))
                      : _filtered.isEmpty
                          ? const Center(
                              child: Text('لا توجد نتائج',
                                  style: TextStyle(fontFamily: 'Cairo')))
                          : ListView.builder(
                              itemCount: _filtered.length,
                              itemBuilder: (_, i) {
                                final c = _filtered[i];
                                return CheckboxListTile(
                                  value: _selected.contains(c.id),
                                  onChanged: (_) => _toggle(c.id),
                                  title: Text(c.name,
                                      style:
                                          const TextStyle(fontFamily: 'Cairo')),
                                  subtitle: c.description.isNotEmpty
                                      ? Text(c.description,
                                          style: const TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 12))
                                      : null,
                                  activeColor: AppColors.primary,
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: _selected.isEmpty
              ? null
              : () {
                  final selected =
                      _all.where((c) => _selected.contains(c.id)).toList();
                  Navigator.pop(context, selected);
                },
          child: Text('تأكيد (${_selected.length})',
              style: const TextStyle(
                  fontFamily: 'Cairo',
                  color: Colors.white,
                  fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
