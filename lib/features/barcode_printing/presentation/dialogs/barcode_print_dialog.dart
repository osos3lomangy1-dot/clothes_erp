import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../domain/models/barcode_label_item.dart';
import '../../services/barcode_label_service.dart';

class BarcodePrintDialog extends StatefulWidget {
  final List<BarcodeLabelItem> initialItems;
  final String title;

  const BarcodePrintDialog({
    super.key,
    required this.initialItems,
    this.title = 'طباعة ملصقات الباركود والأسعار',
  });

  @override
  State<BarcodePrintDialog> createState() => _BarcodePrintDialogState();
}

class _BarcodePrintDialogState extends State<BarcodePrintDialog> {
  late List<BarcodeLabelItem> _items;
  BarcodeLabelSize _selectedSize = BarcodeLabelSize.roll50x30;
  final TextEditingController _storeNameCtrl = TextEditingController(text: 'أوركيد للملابس');
  bool _showStoreName = true;
  bool _showPrice = true;
  bool _showColorAndSize = true;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.initialItems);
  }

  @override
  void dispose() {
    _storeNameCtrl.dispose();
    super.dispose();
  }

  int get _totalCopies => _items.fold<int>(0, (sum, item) => sum + item.copies);

  void _updateCopies(int index, int newCopies) {
    if (newCopies < 1) return;
    setState(() {
      _items[index] = _items[index].copyWith(copies: newCopies);
    });
  }

  void _setAllCopies(int copies) {
    if (copies < 1) return;
    setState(() {
      _items = _items.map((it) => it.copyWith(copies: copies)).toList();
    });
  }

  Future<void> _handlePrint() async {
    if (_items.isEmpty || _totalCopies == 0) return;

    setState(() => _isGenerating = true);
    try {
      await BarcodeLabelService.printLabels(
        items: _items,
        size: _selectedSize,
        storeName: _storeNameCtrl.text.trim(),
        showStoreName: _showStoreName,
        showPrice: _showPrice,
        showColorAndSize: _showColorAndSize,
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء إرسال أمر الطباعة: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(22.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.qr_code_2_rounded, color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        Text(
                          'تخصيص مقاس الاستيكر، عدد النسخ، والطباعة على طابعات الباركود الحرارية أو الورق العادي',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 24),

              // Options Row
              Row(
                children: [
                  // Size Selector
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<BarcodeLabelSize>(
                      initialValue: _selectedSize,
                      decoration: InputDecoration(
                        labelText: 'مقاس الملصق / نوع الورق',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: BarcodeLabelSize.values.map((s) {
                        return DropdownMenuItem(
                          value: s,
                          child: Text(s.name, style: const TextStyle(fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedSize = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Store Name
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _storeNameCtrl,
                      decoration: InputDecoration(
                        labelText: 'اسم المتجر / البراند',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Toggle Options
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: _showStoreName,
                        activeColor: AppColors.primary,
                        onChanged: (val) => setState(() => _showStoreName = val ?? true),
                      ),
                      const Text('اسم المحل', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: _showColorAndSize,
                        activeColor: AppColors.primary,
                        onChanged: (val) => setState(() => _showColorAndSize = val ?? true),
                      ),
                      const Text('اللون والمقاس', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: _showPrice,
                        activeColor: AppColors.primary,
                        onChanged: (val) => setState(() => _showPrice = val ?? true),
                      ),
                      const Text('سعر البيع', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                  // Quick Set Copies Button
                  PopupMenuButton<int>(
                    tooltip: 'تطبيق كمية موحدة على كل الأصناف',
                    onSelected: _setAllCopies,
                    itemBuilder: (ctx) => [1, 2, 5, 10, 20, 50].map((c) {
                      return PopupMenuItem(
                        value: c,
                        child: Text('$c ملصقات لكل صنف'),
                      );
                    }).toList(),
                    child: Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.format_list_numbered_rounded, size: 16, color: AppColors.primary),
                          SizedBox(width: 6),
                          Text('تحديد كمية موحدة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Items List Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Expanded(flex: 3, child: Text('الصنف / المقاس / اللون', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    Expanded(flex: 2, child: Text('الباركود / SKU', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    Expanded(flex: 2, child: Text('السعر', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    SizedBox(width: 120, child: Text('عدد النسخ', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // Items List
              Expanded(
                child: ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                Text('${item.color} - مقاس ${item.size}', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(item.sku, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text('${Money(item.salePricePiasters).toDisplay()} ج.م', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 13)),
                          ),
                          // Copies Counter
                          SizedBox(
                            width: 120,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.grey),
                                  onPressed: () => _updateCopies(index, item.copies - 1),
                                ),
                                Text(
                                  '${item.copies}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline, size: 20, color: AppColors.primary),
                                  onPressed: () => _updateCopies(index, item.copies + 1),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              const Divider(height: 16),

              // Footer Bar
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'إجمالي الملصقات: $_totalCopies ملصق',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 14),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('إلغاء'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    icon: _isGenerating
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.print_rounded, color: Colors.white, size: 20),
                    label: Text(
                      _isGenerating ? 'جاري التجهيز...' : 'طباعة الملصقات 🖨️',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    onPressed: _isGenerating ? null : _handlePrint,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
