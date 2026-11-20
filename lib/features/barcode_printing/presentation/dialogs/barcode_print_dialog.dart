import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_branding.dart';
import '../../../../core/utils/money.dart';
import '../../domain/models/barcode_config.dart';
import '../../domain/models/barcode_label_item.dart';
import '../../services/barcode_label_service.dart';
import '../../services/barcode_settings_service.dart';
import '../widgets/barcode_sticker_live_preview.dart';

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
  int _activePreviewIndex = 0;

  late BarcodeLabelSize _selectedSize;
  late TextEditingController _storeNameCtrl;
  late bool _showStoreName;
  late bool _showProductName;
  late bool _showPrice;
  late bool _showColorAndSize;
  late bool _showBarcodeText;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.initialItems);

    final savedConfig = BarcodeSettingsService.current;
    _selectedSize = savedConfig.selectedSize;
    _storeNameCtrl = TextEditingController(
      text: savedConfig.storeName.isNotEmpty
          ? savedConfig.storeName
          : AppBranding.current.appName,
    );
    _showStoreName = savedConfig.showStoreName;
    _showProductName = savedConfig.showProductName;
    _showPrice = savedConfig.showPrice;
    _showColorAndSize = savedConfig.showColorAndSize;
    _showBarcodeText = savedConfig.showBarcodeText;
  }

  @override
  void dispose() {
    _storeNameCtrl.dispose();
    super.dispose();
  }

  BarcodeConfig get _currentConfig => BarcodeConfig(
        selectedSize: _selectedSize,
        storeName: _storeNameCtrl.text.trim(),
        showStoreName: _showStoreName,
        showProductName: _showProductName,
        showColorAndSize: _showColorAndSize,
        showPrice: _showPrice,
        showBarcodeText: _showBarcodeText,
      );

  BarcodeLabelItem get _activeSampleItem {
    if (_items.isEmpty) {
      return const BarcodeLabelItem(
        variantId: 'sample-0',
        productName: 'تيشرت بولو صيفي',
        sku: '100020003000',
        color: 'كحلي',
        size: 'XL',
        salePricePiasters: 25000,
        copies: 1,
      );
    }
    final safeIndex = _activePreviewIndex.clamp(0, _items.length - 1);
    return _items[safeIndex];
  }

  int get _totalCopies => _items.fold<int>(0, (sum, item) => sum + item.copies);

  void _updateCopies(int index, int newCopies) {
    if (newCopies < 0) return;
    setState(() {
      _items[index] = _items[index].copyWith(copies: newCopies);
      _activePreviewIndex = index;
    });
  }

  void _setAllCopies(int copies) {
    if (copies < 1) return;
    setState(() {
      _items = _items.map((it) => it.copyWith(copies: copies)).toList();
    });
  }

  Future<void> _handleTestPrint() async {
    final sample = _activeSampleItem.copyWith(copies: 1);
    setState(() => _isGenerating = true);
    try {
      await BarcodeLabelService.printLabels(
        items: [sample],
        size: _selectedSize,
        storeName: _storeNameCtrl.text.trim(),
        showStoreName: _showStoreName,
        showPrice: _showPrice,
        showColorAndSize: _showColorAndSize,
        showProductName: _showProductName,
        showBarcodeText: _showBarcodeText,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء الطباعة التجريبية: $e'),
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

  Future<void> _handlePrint() async {
    final printable = _items.where((it) => it.copies > 0).toList();
    if (printable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تحديد كمية نسخة واحدة على الأقل لصنف واحد.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _isGenerating = true);
    try {
      await BarcodeLabelService.printLabels(
        items: printable,
        size: _selectedSize,
        storeName: _storeNameCtrl.text.trim(),
        showStoreName: _showStoreName,
        showPrice: _showPrice,
        showColorAndSize: _showColorAndSize,
        showProductName: _showProductName,
        showBarcodeText: _showBarcodeText,
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
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
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
                    child: Icon(Icons.qr_code_2_rounded, color: AppColors.primary, size: 24),
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
                          'تخصيص ملصقات الباركود والأسعار مع المعاينة الواقعية الفورية للطباعة الحرارية',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 20),

              // Two-pane Body: Left = Live Preview, Right = Controls & Items
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Preview Pane (Left)
                    SizedBox(
                      width: 320,
                      child: Column(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              child: BarcodeStickerLivePreview(
                                config: _currentConfig,
                                sampleItem: _activeSampleItem,
                              ),
                            ),
                          ),
                          if (_items.length > 1) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.chevron_right_rounded, size: 20),
                                    tooltip: 'الصنف السابق',
                                    onPressed: _activePreviewIndex > 0
                                        ? () => setState(() => _activePreviewIndex--)
                                        : null,
                                  ),
                                  Text(
                                    'معاينة صنف ${_activePreviewIndex + 1} من ${_items.length}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.chevron_left_rounded, size: 20),
                                    tooltip: 'الصنف التالي',
                                    onPressed: _activePreviewIndex < _items.length - 1
                                        ? () => setState(() => _activePreviewIndex++)
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),

                    // Controls Pane (Right)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Size Selector & Store Name
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: DropdownButtonFormField<BarcodeLabelSize>(
                                  isExpanded: true,
                                  initialValue: _selectedSize,
                                  decoration: InputDecoration(
                                    labelText: 'مقاس الملصق / نوع الورق',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                  items: BarcodeLabelSize.values.map((s) {
                                    return DropdownMenuItem(
                                      value: s,
                                      child: Text(
                                        s.name,
                                        style: const TextStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) setState(() => _selectedSize = val);
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: _storeNameCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'اسم المتجر / البراند',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                  style: const TextStyle(fontSize: 12),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Toggle Chips
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              FilterChip(
                                label: const Text('اسم المحل', style: TextStyle(fontSize: 12)),
                                selected: _showStoreName,
                                onSelected: (v) => setState(() => _showStoreName = v),
                                selectedColor: AppColors.primary.withValues(alpha: 0.15),
                                checkmarkColor: AppColors.primary,
                              ),
                              FilterChip(
                                label: const Text('اسم الصنف', style: TextStyle(fontSize: 12)),
                                selected: _showProductName,
                                onSelected: (v) => setState(() => _showProductName = v),
                                selectedColor: AppColors.primary.withValues(alpha: 0.15),
                                checkmarkColor: AppColors.primary,
                              ),
                              FilterChip(
                                label: const Text('اللون والمقاس', style: TextStyle(fontSize: 12)),
                                selected: _showColorAndSize,
                                onSelected: (v) => setState(() => _showColorAndSize = v),
                                selectedColor: AppColors.primary.withValues(alpha: 0.15),
                                checkmarkColor: AppColors.primary,
                              ),
                              FilterChip(
                                label: const Text('سعر البيع', style: TextStyle(fontSize: 12)),
                                selected: _showPrice,
                                onSelected: (v) => setState(() => _showPrice = v),
                                selectedColor: AppColors.primary.withValues(alpha: 0.15),
                                checkmarkColor: AppColors.primary,
                              ),
                              FilterChip(
                                label: const Text('كود الباركود', style: TextStyle(fontSize: 12)),
                                selected: _showBarcodeText,
                                onSelected: (v) => setState(() => _showBarcodeText = v),
                                selectedColor: AppColors.primary.withValues(alpha: 0.15),
                                checkmarkColor: AppColors.primary,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Table Header with Quick Uniform Setter
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'الأصناف المراد طباعتها (${_items.length})',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
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
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.format_list_numbered_rounded, size: 15, color: AppColors.primary),
                                      const SizedBox(width: 4),
                                      const Text(
                                        'تحديد كمية موحدة',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),

                          // Items List
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade200),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: _items.isEmpty
                                  ? Center(
                                      child: Text(
                                        'لا توجد أصناف محددة للطباعة',
                                        style: TextStyle(color: Colors.grey.shade500),
                                      ),
                                    )
                                  : ListView.separated(
                                      itemCount: _items.length,
                                      separatorBuilder: (_, index) => const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        final item = _items[index];
                                        final isSelected = index == _activePreviewIndex;

                                        return InkWell(
                                          onTap: () => setState(() => _activePreviewIndex = index),
                                          child: Container(
                                            color: isSelected
                                                ? AppColors.primary.withValues(alpha: 0.05)
                                                : Colors.transparent,
                                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  flex: 3,
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        item.productName,
                                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                      Text(
                                                        '${item.color} - مقاس ${item.size} • SKU: ${item.sku}',
                                                        style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 2,
                                                  child: Text(
                                                    '${Money(item.salePricePiasters).toDisplay()} ج.م',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      color: AppColors.primary,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                                // Copies Control
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(Icons.remove_circle_outline, size: 18, color: Colors.grey),
                                                      onPressed: () => _updateCopies(index, item.copies - 1),
                                                    ),
                                                    SizedBox(
                                                      width: 28,
                                                      child: Text(
                                                        '${item.copies}',
                                                        textAlign: TextAlign.center,
                                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                      ),
                                                    ),
                                                    IconButton(
                                                      icon: Icon(Icons.add_circle_outline, size: 18, color: AppColors.primary),
                                                      onPressed: () => _updateCopies(index, item.copies + 1),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 20),

              // Bottom Actions
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 10,
                spacing: 12,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.confirmation_number_outlined, size: 16, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          'إجمالي الملصقات: $_totalCopies ملصق',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                        icon: const Icon(Icons.print_outlined, size: 16),
                        label: const Text('طباعة تجريبية'),
                        onPressed: _isGenerating ? null : _handleTestPrint,
                      ),
                      const SizedBox(width: 8),
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
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.print_rounded, color: Colors.white, size: 18),
                        label: Text(
                          _isGenerating ? 'جاري التجهيز...' : 'طباعة الملصقات',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        onPressed: _isGenerating ? null : _handlePrint,
                      ),
                    ],
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
