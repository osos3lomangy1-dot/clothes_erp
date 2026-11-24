import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:printing/printing.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../data/services/receipt_settings_service.dart';
import '../../domain/entities/invoice_details_entity.dart';
import '../../domain/entities/invoice_item_details_entity.dart';
import '../../domain/entities/receipt_config.dart';
import '../services/receipt_pdf_service.dart';
import '../widgets/thermal_receipt_live_preview.dart';

class ReceiptCustomizerScreen extends StatefulWidget {
  const ReceiptCustomizerScreen({super.key});

  @override
  State<ReceiptCustomizerScreen> createState() =>
      _ReceiptCustomizerScreenState();
}

class _ReceiptCustomizerScreenState extends State<ReceiptCustomizerScreen> {
  late TextEditingController _storeNameCtrl;
  late TextEditingController _storeActivityCtrl;
  late TextEditingController _storePhoneCtrl;
  late TextEditingController _storePhoneSecCtrl;
  late TextEditingController _storeAddressCtrl;
  late TextEditingController _taxNumberCtrl;
  late TextEditingController _returnPolicyCtrl;
  late TextEditingController _footerGreetingCtrl;
  late TextEditingController _wifiInfoCtrl;
  late TextEditingController _taxRateCtrl;
  late TextEditingController _dineInServiceChargeRateCtrl;

  late int _paperWidthMm;
  late bool _showCashierName;
  late bool _showCustomerInfo;
  late bool _showPaymentMethod;
  late bool _showBarcode;
  late bool _showItemDetails;
  late bool _groupVariantsOnReceipt;
  late bool _taxEnabled;
  late bool _taxInclusive;
  late bool _dineInServiceChargeEnabled;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final cfg = ReceiptSettingsService.current;
    _storeNameCtrl = TextEditingController(text: cfg.storeName);
    _storeActivityCtrl = TextEditingController(text: cfg.storeActivity);
    _storePhoneCtrl = TextEditingController(text: cfg.storePhone);
    _storePhoneSecCtrl = TextEditingController(text: cfg.storePhoneSecondary);
    _storeAddressCtrl = TextEditingController(text: cfg.storeAddress);
    _taxNumberCtrl = TextEditingController(text: cfg.taxNumber);
    _returnPolicyCtrl = TextEditingController(text: cfg.returnPolicy);
    _footerGreetingCtrl = TextEditingController(text: cfg.footerGreeting);
    _wifiInfoCtrl = TextEditingController(text: cfg.wifiInfo);
    _taxRateCtrl = TextEditingController(text: cfg.taxRate.toString());
    _dineInServiceChargeRateCtrl = TextEditingController(text: cfg.dineInServiceChargeRate.toString());

    _paperWidthMm = cfg.paperWidthMm;
    _showCashierName = cfg.showCashierName;
    _showCustomerInfo = cfg.showCustomerInfo;
    _showPaymentMethod = cfg.showPaymentMethod;
    _showBarcode = cfg.showBarcode;
    _showItemDetails = cfg.showItemDetails;
    _groupVariantsOnReceipt = cfg.groupVariantsOnReceipt;
    _taxEnabled = cfg.taxEnabled;
    _taxInclusive = cfg.taxInclusive;
    _dineInServiceChargeEnabled = cfg.dineInServiceChargeEnabled;
  }

  @override
  void dispose() {
    _storeNameCtrl.dispose();
    _storeActivityCtrl.dispose();
    _storePhoneCtrl.dispose();
    _storePhoneSecCtrl.dispose();
    _storeAddressCtrl.dispose();
    _taxNumberCtrl.dispose();
    _returnPolicyCtrl.dispose();
    _footerGreetingCtrl.dispose();
    _wifiInfoCtrl.dispose();
    _taxRateCtrl.dispose();
    _dineInServiceChargeRateCtrl.dispose();
    super.dispose();
  }

  ReceiptConfig get _currentConfig => ReceiptConfig(
        storeName: _storeNameCtrl.text.trim(),
        storeActivity: _storeActivityCtrl.text.trim(),
        storePhone: _storePhoneCtrl.text.trim(),
        storePhoneSecondary: _storePhoneSecCtrl.text.trim(),
        storeAddress: _storeAddressCtrl.text.trim(),
        taxNumber: _taxNumberCtrl.text.trim(),
        paperWidthMm: _paperWidthMm,
        showCashierName: _showCashierName,
        showCustomerInfo: _showCustomerInfo,
        showPaymentMethod: _showPaymentMethod,
        showBarcode: _showBarcode,
        showItemDetails: _showItemDetails,
        groupVariantsOnReceipt: _groupVariantsOnReceipt,
        returnPolicy: _returnPolicyCtrl.text.trim(),
        footerGreeting: _footerGreetingCtrl.text.trim(),
        wifiInfo: _wifiInfoCtrl.text.trim(),
        taxEnabled: _taxEnabled,
        taxRate: double.tryParse(_taxRateCtrl.text.trim()) ?? 14.0,
        taxInclusive: _taxInclusive,
        dineInServiceChargeEnabled: _dineInServiceChargeEnabled,
        dineInServiceChargeRate: double.tryParse(_dineInServiceChargeRateCtrl.text.trim()) ?? 12.0,
      );

  String _getUserId(BuildContext context) {
    final auth = context.read<AuthCubit>().state;
    if (auth is AuthAuthenticated) return auth.user.id;
    return 'admin';
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final gate = getIt<FeatureGate>();
      await ReceiptSettingsService.save(
        _currentConfig,
        gate,
        userId: _getUserId(context),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ وتحديث إعدادات الفاتورة بنجاح'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل الحفظ: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _resetToDefaults() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استعادة الإعدادات الافتراضية'),
        content: const Text(
          'هل أنت متأكد من رغبتك في استعادة النصوص والخيارات الافتراضية للفاتورة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              Navigator.pop(ctx);
              final def = ReceiptConfig.defaults;
              setState(() {
                _storeActivityCtrl.text = def.storeActivity;
                _storePhoneCtrl.text = def.storePhone;
                _storePhoneSecCtrl.text = def.storePhoneSecondary;
                _storeAddressCtrl.text = def.storeAddress;
                _taxNumberCtrl.text = def.taxNumber;
                _returnPolicyCtrl.text = def.returnPolicy;
                _footerGreetingCtrl.text = def.footerGreeting;
                _paperWidthMm = def.paperWidthMm;
                _showCashierName = def.showCashierName;
                _showCustomerInfo = def.showCustomerInfo;
                _showPaymentMethod = def.showPaymentMethod;
                _showBarcode = def.showBarcode;
                _showItemDetails = def.showItemDetails;
                _groupVariantsOnReceipt = def.groupVariantsOnReceipt;
                _taxEnabled = def.taxEnabled;
                _taxRateCtrl.text = def.taxRate.toString();
                _taxInclusive = def.taxInclusive;
                _dineInServiceChargeEnabled = def.dineInServiceChargeEnabled;
                _dineInServiceChargeRateCtrl.text = def.dineInServiceChargeRate.toString();
              });
            },
            child: const Text('استعادة'),
          ),
        ],
      ),
    );
  }

  void _applyHospitalityTemplate() {
    final hosp = ReceiptConfig.hospitalityDefaults;
    setState(() {
      _storeActivityCtrl.text = hosp.storeActivity;
      _returnPolicyCtrl.text = hosp.returnPolicy;
      _footerGreetingCtrl.text = hosp.footerGreeting;
      _showItemDetails = hosp.showItemDetails; // false
      _wifiInfoCtrl.text = hosp.wifiInfo;
      _taxEnabled = hosp.taxEnabled;
      _taxRateCtrl.text = hosp.taxRate.toString();
      _taxInclusive = hosp.taxInclusive;
      _dineInServiceChargeEnabled = hosp.dineInServiceChargeEnabled;
      _dineInServiceChargeRateCtrl.text = hosp.dineInServiceChargeRate.toString();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم تطبيق قالب المطاعم والكافيهات بنجاح'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _testPrint() async {
    final sampleInvoice = InvoiceDetailsEntity(
      id: 'sample-inv',
      shortRef: 'INV-9824',
      date: DateTime.now(),
      cashierId: 'cashier-1',
      cashierName: 'أحمد مصطفى',
      customerName: 'كريم السيد',
      customerPhone: '01012345678',
      subtotal: 63000,
      discountAmount: 3000,
      total: 60000,
      paymentMethod: 'نقدي (كاش)',
      items: const [
        InvoiceItemDetailsEntity(
          id: 'item-1',
          variantId: 'var-1',
          productName: 'قميص كاجوال رجالي',
          color: 'كحلي',
          size: 'L',
          qty: 1,
          price: 28000,
          lineTotal: 28000,
        ),
        InvoiceItemDetailsEntity(
          id: 'item-2',
          variantId: 'var-2',
          productName: 'بنطلون جينز كلاسيك',
          color: 'أزرق غامق',
          size: '34',
          qty: 1,
          price: 35000,
          lineTotal: 35000,
        ),
      ],
    );

    try {
      final pdfBytes = await ReceiptPdfService.generateReceiptPdf(
        sampleInvoice,
        config: _currentConfig,
      );
      await Printing.layoutPdf(
        name: 'معاينة_فاتورة_${sampleInvoice.shortRef}',
        onLayout: (format) async => pdfBytes,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر إجراء طباعة تجريبية: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 860;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: AppColors.onSurface,
                ),
                tooltip: 'رجوع',
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'تخصيص الفاتورة الحرارية (Receipt Customizer)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: AppColors.onSurface,
              ),
            ),
            Text(
              'تعديل الترويسة، سياسة الاستبدال، مقاس الورق، ومعاينة حية فورية',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          OutlinedButton.icon(
            key: const Key('apply_hospitality_template_btn'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.outlineVariant),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: _applyHospitalityTemplate,
            icon: const Icon(Icons.restaurant_rounded, size: 18),
            label: const Text('قالب المطاعم والكافيهات'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.outlineVariant),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: _resetToDefaults,
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('الافتراضي'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.outlineVariant),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: _testPrint,
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('طباعة تجريبية'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: _isSaving ? null : _saveSettings,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: const Text('حفظ التعديلات'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: isDesktop ? _buildSplitView() : _buildTabbedView(),
    );
  }

  Widget _buildSplitView() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Settings Form (Left/Center)
        Expanded(
          flex: 6,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildStoreHeaderCard(),
              const SizedBox(height: 14),
              _buildLayoutOptionsCard(),
              const SizedBox(height: 14),
              _buildTaxAndServiceCard(),
              const SizedBox(height: 14),
              _buildFooterPoliciesCard(),
            ],
          ),
        ),

        // Live Preview (Right Side)
        Expanded(
          flex: 4,
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(Icons.remove_red_eye_outlined, color: AppColors.primary, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'معاينة مباشرة للفاتورة الحرارية',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Center(
                      child: ThermalReceiptLivePreview(
                        config: _currentConfig,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabbedView() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            labelColor: AppColors.primary,
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(icon: Icon(Icons.tune_rounded), text: 'خيارات وبيانات الفاتورة'),
              Tab(icon: Icon(Icons.receipt_rounded), text: 'المعاينة الحية'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildStoreHeaderCard(),
                    const SizedBox(height: 14),
                    _buildLayoutOptionsCard(),
                    const SizedBox(height: 14),
                    _buildTaxAndServiceCard(),
                    const SizedBox(height: 14),
                    _buildFooterPoliciesCard(),
                  ],
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: ThermalReceiptLivePreview(
                      config: _currentConfig,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreHeaderCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storefront_rounded, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'ترويسة الفاتورة وبيانات المحل',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _storeNameCtrl,
              decoration: InputDecoration(
                labelText: 'اسم المتجر / المحل التجاري *',
                prefixIcon: const Icon(Icons.business_outlined, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _storeActivityCtrl,
              decoration: InputDecoration(
                labelText: 'نشاط المحل أو السلوجان (مثال: أحدث صيحات الملابس الجاهزة)',
                prefixIcon: const Icon(Icons.loyalty_outlined, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _storeAddressCtrl,
              decoration: InputDecoration(
                labelText: 'العنوان بالتفصيل المطبوع على الفاتورة',
                prefixIcon: const Icon(Icons.location_on_outlined, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _storePhoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'رقم الهاتف الأساسي *',
                      prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _storePhoneSecCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'رقم هاتف إضافي (اختياري)',
                      prefixIcon: const Icon(Icons.phone_android_outlined, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _taxNumberCtrl,
              decoration: InputDecoration(
                labelText: 'الرقم الضريبي أو السجل التجاري (اختياري)',
                prefixIcon: const Icon(Icons.receipt_outlined, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayoutOptionsCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune_rounded, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'أبعاد الورق وخيارات العرض',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Paper Roll Width Selector
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'عرض بكرة الورق الحراري:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                ChoiceChip(
                  label: const Text('80 مم (القياسي العريض)'),
                  selected: _paperWidthMm == 80,
                  onSelected: (val) {
                    if (val) setState(() => _paperWidthMm = 80);
                  },
                ),
                ChoiceChip(
                  label: const Text('58 مم (الصغير المدمج)'),
                  selected: _paperWidthMm == 58,
                  onSelected: (val) {
                    if (val) setState(() => _paperWidthMm = 58);
                  },
                ),
              ],
            ),
            const Divider(height: 24),

            // Toggles
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('إظهار اسم الكاشير في بيانات الفاتورة'),
              value: _showCashierName,
              onChanged: (v) => setState(() => _showCashierName = v),
            ),
            const Divider(height: 1),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('إظهار بيانات العميل (الاسم ورقم الهاتف)'),
              value: _showCustomerInfo,
              onChanged: (v) => setState(() => _showCustomerInfo = v),
            ),
            const Divider(height: 1),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('إظهار طريقة الدفع (نقدي / فيزا / آجل)'),
              value: _showPaymentMethod,
              onChanged: (v) => setState(() => _showPaymentMethod = v),
            ),
            const Divider(height: 1),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('إظهار باركود رقم الفاتورة (Code 128) لتسهيل المسح في المرتجعات'),
              value: _showBarcode,
              onChanged: (v) => setState(() => _showBarcode = v),
            ),
            const Divider(height: 1),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('إظهار تفاصيل الصنف (المقاس واللون بجانب اسم الصنف)'),
              value: _showItemDetails,
              onChanged: (v) => setState(() => _showItemDetails = v),
            ),
            const Divider(height: 1),
            SwitchListTile(
              key: const Key('receipt_group_variants_switch'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('تجميع مقاسات نفس الموديل في سطر واحد (توفير الورق الحراري)'),
              value: _groupVariantsOnReceipt,
              onChanged: (v) => setState(() => _groupVariantsOnReceipt = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaxAndServiceCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.percent_rounded, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'التحكم في الضريبة وخدمة الصالة للمطاعم والكافيهات',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 1. Tax Switch
            SwitchListTile(
              key: const Key('receipt_tax_enabled_switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('تفعيل ضريبة القيمة المضافة (VAT)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: const Text('إظهار سطر الضريبة في الفاتورة واحتسابه ضمن الإجمالي', style: TextStyle(fontSize: 11, color: Colors.grey)),
              value: _taxEnabled,
              onChanged: (v) => setState(() => _taxEnabled = v),
            ),
            if (_taxEnabled) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('receipt_tax_rate_field'),
                      controller: _taxRateCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'نسبة الضريبة % (افتراضي: 14%)',
                        prefixIcon: const Icon(Icons.calculate_outlined, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const Key('receipt_tax_inclusive_switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('الأسعار شاملة الضريبة (قيمة الضريبة ضمن السعر)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                subtitle: const Text('عند التفعيل لا تضاف الضريبة على إجمالي الفاتورة بل يطبع إشعار بالشمول', style: TextStyle(fontSize: 11, color: Colors.grey)),
                value: _taxInclusive,
                onChanged: (v) => setState(() => _taxInclusive = v),
              ),
            ],

            const Divider(height: 24),

            // 2. Dine-In Service Charge Switch
            SwitchListTile(
              key: const Key('receipt_service_charge_enabled_switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('تفعيل خدمة الصالة لطلبات الأكل بالمكان (Dine-In Service Charge)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: const Text('تطبق حصرياً وتلقائياً على فواتير الصالة فقط، وتستثني التيك أواي والدليفري بنسبة 0%', style: TextStyle(fontSize: 11, color: Colors.grey)),
              value: _dineInServiceChargeEnabled,
              onChanged: (v) => setState(() => _dineInServiceChargeEnabled = v),
            ),
            if (_dineInServiceChargeEnabled) ...[
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('receipt_service_charge_rate_field'),
                controller: _dineInServiceChargeRateCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'نسبة خدمة الصالة % (افتراضي: 12%)',
                  prefixIcon: const Icon(Icons.room_service_outlined, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFooterPoliciesCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.policy_outlined, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'سياسة الاستبدال ورسائل الذيل (Footer)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _returnPolicyCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'شروط وسياسة الاستبدال والاسترجاع المطبوعة أسفل الفاتورة',
                prefixIcon: const Icon(Icons.assignment_return_outlined, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _footerGreetingCtrl,
              decoration: InputDecoration(
                labelText: 'رسالة الشكر والترحيب في نهاية الإيصال',
                prefixIcon: const Icon(Icons.favorite_outline_rounded, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _wifiInfoCtrl,
              decoration: InputDecoration(
                labelText: 'بيانات واي فاي المطعم أو المتجر (اختياري)',
                prefixIcon: const Icon(Icons.wifi_rounded, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('apply_hospitality_template_body_btn'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _applyHospitalityTemplate,
                icon: const Icon(Icons.restaurant_menu_rounded, size: 18),
                label: const Text('تطبيق قالب المطاعم والكافيهات'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
