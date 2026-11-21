import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../../core/theme/app_branding.dart';
import '../../domain/models/barcode_config.dart';
import '../../domain/models/barcode_label_item.dart';
import '../../services/barcode_label_service.dart';
import '../../services/barcode_settings_service.dart';
import '../widgets/barcode_sticker_live_preview.dart';

class BarcodeCustomizerScreen extends StatefulWidget {
  const BarcodeCustomizerScreen({super.key});

  @override
  State<BarcodeCustomizerScreen> createState() =>
      _BarcodeCustomizerScreenState();
}

class _BarcodeCustomizerScreenState extends State<BarcodeCustomizerScreen> {
  late BarcodeConfig _config;
  late TextEditingController _storeNameCtrl;
  bool _isSaving = false;
  bool _isPrintingTest = false;

  final List<BarcodeLabelItem> _samplePresets = const [
    BarcodeLabelItem(
      variantId: 'sample-1',
      productName: 'تيشرت بولو قطن فاخر',
      sku: '622100010001',
      color: 'كحلي',
      size: 'XL',
      salePricePiasters: 35000,
      copies: 1,
    ),
    BarcodeLabelItem(
      variantId: 'sample-2',
      productName: 'بنطلون جينز سليم فيت',
      sku: '622100020002',
      color: 'أزرق غامق',
      size: '34',
      salePricePiasters: 55000,
      copies: 1,
    ),
    BarcodeLabelItem(
      variantId: 'sample-3',
      productName: 'فستان صيفي مشجر',
      sku: '622100030003',
      color: 'وردي',
      size: 'M',
      salePricePiasters: 48000,
      copies: 1,
    ),
  ];
  int _activeSamplePresetIndex = 0;

  @override
  void initState() {
    super.initState();
    _config = BarcodeSettingsService.current;
    _storeNameCtrl = TextEditingController(text: _config.storeName);
  }

  @override
  void dispose() {
    _storeNameCtrl.dispose();
    super.dispose();
  }

  BarcodeLabelItem get _currentSample =>
      _samplePresets[_activeSamplePresetIndex];

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);
    try {
      final updated = _config.copyWith(
        storeName: _storeNameCtrl.text.trim().isEmpty
            ? AppBranding.current.appName
            : _storeNameCtrl.text.trim(),
      );

      final gate = getIt<FeatureGate>();
      await BarcodeSettingsService.save(updated, gate, userId: 'admin');

      setState(() => _config = updated);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تم حفظ إعدادات ملصقات الباركود بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء الحفظ: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _handleReset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استعادة الإعدادات الافتراضية'),
        content: const Text(
          'هل أنت متأكد من استعادة النموذج القياسي لملصقات الباركود؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'تأكيد الاستعادة',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final gate = getIt<FeatureGate>();
    await BarcodeSettingsService.resetToDefaults(gate, userId: 'admin');
    setState(() {
      _config = BarcodeSettingsService.current;
      _storeNameCtrl.text = _config.storeName;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('تمت استعادة الإعدادات الافتراضية بنجاح'),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  Future<void> _handlePrintTest() async {
    setState(() => _isPrintingTest = true);
    try {
      await BarcodeLabelService.printLabels(
        items: [_currentSample],
        size: _config.selectedSize,
        storeName: _storeNameCtrl.text.trim(),
        showStoreName: _config.showStoreName,
        showPrice: _config.showPrice,
        showColorAndSize: _config.showColorAndSize,
        showProductName: _config.showProductName,
        showBarcodeText: _config.showBarcodeText,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء طباعة الملصق التجريبي: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrintingTest = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'تخصيص ملصقات الباركود والأسعار',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey.shade700,
              side: BorderSide(color: Colors.grey.shade300),
            ),
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('استعادة الافتراضي'),
            onPressed: _handleReset,
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary),
            ),
            icon: _isPrintingTest
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print_outlined, size: 18),
            label: const Text('طباعة ملصق تجريبي'),
            onPressed: _isPrintingTest ? null : _handlePrintTest,
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            icon: _isSaving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.save_rounded, size: 18),
            label: const Text(
              'حفظ الإعدادات',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: _isSaving ? null : _handleSave,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Settings Controls Pane
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: _buildControlsPane(),
                  ),
                ),
                // Live Sticker Preview Pane
                Expanded(
                  flex: 2,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 24, 24, 24),
                    child: _buildPreviewPane(),
                  ),
                ),
              ],
            );
          } else {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildPreviewPane(),
                  const SizedBox(height: 20),
                  _buildControlsPane(),
                ],
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildPreviewPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Preset sample switcher
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.category_outlined, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text(
                'نموذج المعاينة:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<int>(
                  value: _activeSamplePresetIndex,
                  isExpanded: true,
                  underline: const SizedBox(),
                  items: List.generate(_samplePresets.length, (i) {
                    final p = _samplePresets[i];
                    return DropdownMenuItem(
                      value: i,
                      child: Text(
                        '${p.productName} (${p.color})',
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  }),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _activeSamplePresetIndex = val);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Live Sticker Preview Card
        BarcodeStickerLivePreview(
          config: _config.copyWith(storeName: _storeNameCtrl.text),
          sampleItem: _currentSample,
        ),
      ],
    );
  }

  Widget _buildControlsPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Card 1: Sticker Dimensions
        _sectionCard(
          title: 'مقاس الملصق ونوع الورق',
          icon: Icons.aspect_ratio_rounded,
          child: Column(
            children: BarcodeLabelSize.values.map((size) {
              final isSelected = _config.selectedSize == size;
              return InkWell(
                onTap: () => setState(
                  () => _config = _config.copyWith(selectedSize: size),
                ),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.05)
                        : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : Colors.grey.shade200,
                      width: isSelected ? 1.5 : 1,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: isSelected ? AppColors.primary : Colors.grey,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              size.name,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              size == BarcodeLabelSize.sheetA4
                                  ? '210 × 297 مم - شبكة 24 ملصق بالورقة'
                                  : '${size.widthMm.toInt()} مم عرض × ${size.heightMm.toInt()} مم طول',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),

        // Card 2: Store/Brand Branding
        _sectionCard(
          title: 'بيانات المتجر والبراند',
          icon: Icons.storefront_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _storeNameCtrl,
                decoration: InputDecoration(
                  labelText: 'اسم المتجر / البراند المطبوع بأعلى الملصق',
                  hintText: AppBranding.current.appName,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
                onChanged: (v) {
                  setState(() => _config = _config.copyWith(storeName: v));
                },
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                title: const Text(
                  'إظهار اسم المتجر على الاستيكر',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: const Text(
                  'طباعة اسم المحل في أعلى كل ملصق باركود',
                  style: TextStyle(fontSize: 11),
                ),
                value: _config.showStoreName,
                activeThumbColor: AppColors.primary,
                onChanged: (v) => setState(
                  () => _config = _config.copyWith(showStoreName: v),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Card 3: Elements on Sticker
        _sectionCard(
          title: 'حقول وبيانات الصنف على الاستيكر',
          icon: Icons.tune_rounded,
          child: Column(
            children: [
              SwitchListTile(
                title: const Text(
                  'إظهار اسم الصنف',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: const Text(
                  'طباعة اسم المنتج بوضوح في المنتصف',
                  style: TextStyle(fontSize: 11),
                ),
                value: _config.showProductName,
                activeThumbColor: AppColors.primary,
                onChanged: (v) => setState(
                  () => _config = _config.copyWith(showProductName: v),
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text(
                  'إظهار المقاس واللون',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: const Text(
                  'تمييز المتغيرات مثل مقاس L ولون أزرق',
                  style: TextStyle(fontSize: 11),
                ),
                value: _config.showColorAndSize,
                activeThumbColor: AppColors.primary,
                onChanged: (v) => setState(
                  () => _config = _config.copyWith(showColorAndSize: v),
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text(
                  'إظهار سعر البيع',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: const Text(
                  'طباعة السعر بخط عريض وواضح بالجنيه المصري (ج.م)',
                  style: TextStyle(fontSize: 11),
                ),
                value: _config.showPrice,
                activeThumbColor: AppColors.primary,
                onChanged: (v) =>
                    setState(() => _config = _config.copyWith(showPrice: v)),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text(
                  'إظهار الرمز الرقمي للباركود (SKU)',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: const Text(
                  'كتابة الأرقام أسفل خطوط الباركود للقراءة اليدوية عند الحاجة',
                  style: TextStyle(fontSize: 11),
                ),
                value: _config.showBarcodeText,
                activeThumbColor: AppColors.primary,
                onChanged: (v) => setState(
                  () => _config = _config.copyWith(showBarcodeText: v),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
