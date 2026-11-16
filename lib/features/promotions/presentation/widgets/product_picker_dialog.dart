import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../../products/domain/repositories/product_repository.dart';
import '../../../products/domain/services/product_search_filter.dart';

class ProductPickerDialog extends StatefulWidget {
  final List<String> initialSelectedIds;
  final ProductRepository? repository;

  const ProductPickerDialog({
    super.key,
    this.initialSelectedIds = const [],
    this.repository,
  });

  @override
  State<ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<ProductPickerDialog> {
  final _searchController = TextEditingController();
  List<ProductEntity> _all = const [];
  List<ProductEntity> _filtered = const [];
  late Set<String> _selected;
  bool _loading = true;
  String? _error;

  ProductRepository get _repo => widget.repository ?? getIt<ProductRepository>();

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initialSelectedIds);
    _load();
  }

  Future<void> _load() async {
    final result = await _repo.getProducts();
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
    setState(() {
      _filtered =
          _all.where((p) => ProductSearchFilter.matches(p, q)).toList();
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
          const Text('اختيار المنتجات',
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
        width: 600,
        height: 550,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: _onSearch,
              decoration: const InputDecoration(
                hintText: 'ابحث بالاسم أو الكود أو الباركود...',
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
                                final p = _filtered[i];
                                final isSel = _selected.contains(p.id);
                                final sku = p.variants.isNotEmpty
                                    ? p.variants.first.sku
                                    : 'بدون كود';
                                final cat = p.categoryName.isNotEmpty
                                    ? p.categoryName
                                    : 'بدون قسم';
                                return CheckboxListTile(
                                  value: isSel,
                                  onChanged: (_) => _toggle(p.id),
                                  title: Text(p.name,
                                      style:
                                          const TextStyle(fontFamily: 'Cairo')),
                                  subtitle: Text('$cat • $sku',
                                      style: const TextStyle(
                                          fontFamily: 'Cairo', fontSize: 12)),
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
                      _all.where((p) => _selected.contains(p.id)).toList();
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
