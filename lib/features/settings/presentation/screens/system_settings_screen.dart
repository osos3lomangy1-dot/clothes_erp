import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/retail_sector.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../../core/theme/app_branding.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../../installments/data/services/manager_pin_service.dart';
import '../../../invoices/data/services/receipt_settings_service.dart';
import '../../../invoices/domain/entities/receipt_config.dart';
import '../../../invoices/presentation/screens/receipt_customizer_screen.dart';
import '../../../barcode_printing/domain/models/barcode_config.dart';
import '../../../barcode_printing/presentation/screens/barcode_customizer_screen.dart';
import '../../../barcode_printing/services/barcode_settings_service.dart';
import '../cubits/settings_cubit.dart';
import '../widgets/excel_migration_card.dart';
import '../widgets/google_drive_backup_card.dart';
import '../widgets/local_backup_card.dart';

class SystemSettingsScreen extends StatelessWidget {
  const SystemSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<SettingsCubit>()..start(),
      child: const _SystemSettingsView(),
    );
  }
}

class _SystemSettingsView extends StatelessWidget {
  const _SystemSettingsView();

  bool _isAdmin(BuildContext context) {
    final auth = context.read<AuthCubit>().state;
    if (auth is! AuthAuthenticated) return true;
    return auth.user.role != 'cashier';
  }

  String _userId(BuildContext context) {
    final auth = context.read<AuthCubit>().state;
    if (auth is AuthAuthenticated) return auth.user.id;
    return 'admin';
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = _isAdmin(context);
    if (!isAdmin) {
      return const Scaffold(
        body: Center(child: Text('إعدادات النظام متاحة للمدير فقط')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'إعدادات النظام',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
      ),
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          if (state.isLoading && state.features.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          final togglable = FeatureKeys.definitions
              .where((d) => !d.coreAlwaysEnabled)
              .toList();
          final installmentsEnabled =
              state.features[FeatureKeys.installments] ?? false;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
              _sectionTitle('نمط النشاط ونوع المتجر'),
              _SectorModeSettingsCard(userId: _userId(context)),
              const SizedBox(height: 20),
              _sectionTitle('هوية النظام والألوان (الاسم والمظهر)'),
              _BrandingSettingsCard(userId: _userId(context)),
              const SizedBox(height: 20),
              _sectionTitle('إعدادات الطباعة (الفواتير وملصقات الباركود)'),
              _ReceiptCustomizerSettingsCard(userId: _userId(context)),
              const SizedBox(height: 12),
              _BarcodeCustomizerSettingsCard(userId: _userId(context)),
              const SizedBox(height: 20),
              _sectionTitle('الميزات'),
              Card(
                child: Column(
                  children: [
                    for (final def in togglable) ...[
                      _featureTile(context, state, def),
                      if (def != togglable.last) const Divider(height: 1),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'الميزات الأساسية (المصادقة، نقطة البيع، المخزون، حركات المخزن، العملاء) مفعّلة دائمًا.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
              const SizedBox(height: 20),
              _sectionTitle('طرق الدفع'),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('نقدي'),
                      value: state.cashEnabled,
                      onChanged: (v) async {
                        final err = await context
                            .read<SettingsCubit>()
                            .setPaymentMethod(
                              'payment.cash',
                              v,
                              _userId(context),
                            );
                        if (err != null && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(err),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('بطاقة / فيزا'),
                      value: state.cardEnabled,
                      onChanged: (v) async {
                        final err = await context
                            .read<SettingsCubit>()
                            .setPaymentMethod(
                              'payment.card',
                              v,
                              _userId(context),
                            );
                        if (err != null && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(err),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      },
                    ),
                    if (installmentsEnabled) ...[
                      const Divider(height: 1),
                      SwitchListTile(
                        key: const Key('payment_installment_toggle'),
                        title: const Text('تقسيط'),
                        value: state.installmentPaymentEnabled,
                        onChanged: (v) async {
                          final err = await context
                              .read<SettingsCubit>()
                              .setPaymentMethod(
                                'payment.installment',
                                v,
                                _userId(context),
                              );
                          if (err != null && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(err),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        },
                      ),
                    ],
                    const Divider(height: 1),
                    SwitchListTile(
                      key: const Key('payment_credit_toggle'),
                      title: const Text('آجل (الدفع على الحساب)'),
                      value: state.creditPaymentEnabled,
                      onChanged: (v) async {
                        final err = await context
                            .read<SettingsCubit>()
                            .setPaymentMethod(
                              'payment.credit',
                              v,
                              _userId(context),
                            );
                        if (err != null && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(err),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _sectionTitle('إعدادات الدفع الآجل (البيع على الحساب)'),
              _CreditSalesSettingsSection(userId: _userId(context)),
              if (installmentsEnabled) ...[
                const SizedBox(height: 20),
                _sectionTitle('إعدادات التقسيط'),
                const _InstallmentSettingsSection(),
              ],
              const SizedBox(height: 20),
              _sectionTitle('النسخ الاحتياطي والاستعادة (حماية البيانات المحلية)'),
              LocalBackupCard(userId: _userId(context)),
              const SizedBox(height: 16),
              _sectionTitle('النسخ الاحتياطي على حساب Google Drive'),
              GoogleDriveBackupCard(userId: _userId(context)),
              const SizedBox(height: 16),
              _sectionTitle('التصدير والاستيراد الشامل (Excel)'),
              ExcelMigrationCard(userId: _userId(context)),
              const SizedBox(height: 20),
              _sectionTitle('المزامنة السحابية عبر الإنترنت'),
              Card(
                child: SwitchListTile(
                  key: const Key('cloud_sync_toggle'),
                  title: const Text('تفعيل المزامنة السحابية (اختياري)'),
                  subtitle: const Text(
                    'عند التعطيل يعمل النظام محلياً بالكامل بدون أي اتصال بالإنترنت، ويختفي زر المزامنة من القائمة الجانبية.',
                    style: TextStyle(fontSize: 12),
                  ),
                  secondary: Icon(
                    state.cloudSyncEnabled
                        ? Icons.cloud_done_rounded
                        : Icons.cloud_off_rounded,
                    color: state.cloudSyncEnabled
                        ? AppColors.primary
                        : Colors.grey,
                  ),
                  value: state.cloudSyncEnabled,
                  onChanged: (v) async {
                    final err = await context
                        .read<SettingsCubit>()
                        .setCloudSyncEnabled(v, _userId(context));
                    if (err != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(err),
                          backgroundColor: AppColors.error,
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 20),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'كل تغيير يُسجَّل في سجل التدقيق.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
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

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, right: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.onSurface,
        ),
      ),
    );
  }

  Widget _featureTile(
    BuildContext context,
    SettingsState state,
    FeatureDefinition def,
  ) {
    final enabled = state.features[def.key] ?? def.defaultEnabled;
    String? subtitle;
    if (def.dependencies.isNotEmpty) {
      final deps = def.dependencies
          .map((d) => FeatureKeys.byKey[d]?.label ?? d)
          .join('، ');
      subtitle = 'يعتمد على: $deps';
    }
    return SwitchListTile(
      title: Text(def.label),
      subtitle: subtitle != null ? Text(subtitle) : null,
      value: enabled,
      onChanged: (v) async {
        final err = await context.read<SettingsCubit>().toggleFeature(
          def.key,
          v,
          _userId(context),
        );
        if (err != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err), backgroundColor: AppColors.error),
          );
        }
      },
    );
  }
}

class _InstallmentSettingsSection extends StatefulWidget {
  const _InstallmentSettingsSection();

  @override
  State<_InstallmentSettingsSection> createState() =>
      _InstallmentSettingsSectionState();
}

class _InstallmentSettingsSectionState
    extends State<_InstallmentSettingsSection> {
  bool _pinRequired = true;
  bool _pinSet = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPinStatus();
  }

  Future<void> _loadPinStatus() async {
    final pinSvc = getIt<ManagerPinService>();
    final required = await pinSvc.isPinRequired();
    final set = await pinSvc.isPinSet();
    if (mounted) {
      setState(() {
        _pinRequired = required;
        _pinSet = set;
        _loading = false;
      });
    }
  }

  String _userId(BuildContext context) {
    final auth = context.read<AuthCubit>().state;
    if (auth is AuthAuthenticated) return auth.user.id;
    return 'admin';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        key: Key('installment_settings_section'),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final pinSvc = getIt<ManagerPinService>();
    return Card(
      key: const Key('installment_settings_section'),
      child: Column(
        children: [
          SwitchListTile(
            key: const Key('installment_pin_required_toggle'),
            title: const Text('طلب الرقم السري للمدير (Manager PIN) في التقسيط'),
            subtitle: const Text(
              'تأكيد المدير عند إنشاء عقد تقسيط، تسجيل دفعة، التسوية المبكرة، أو الإلغاء',
            ),
            value: _pinRequired,
            onChanged: (v) async {
              final uid = _userId(context);
              await pinSvc.setPinRequired(required: v, userId: uid);
              if (mounted) {
                setState(() => _pinRequired = v);
              }
            },
          ),
          const Divider(height: 1),
          ListTile(
            enabled: _pinRequired,
            title: const Text('الرقم السري للمدير'),
            subtitle: Text(
              !_pinRequired
                  ? 'معطّل حالياً في التقسيط'
                  : (_pinSet ? 'الرقم السري مُعيَّن' : 'لم يتم تعيين الرقم السري بعد'),
            ),
            trailing: OutlinedButton(
              onPressed: _pinRequired ? () => _showSetPinDialog(context) : null,
              child: Text(_pinSet ? 'تغيير' : 'تعيين'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSetPinDialog(BuildContext context) async {
    final controller = TextEditingController();
    final uid = _userId(context);
    final pinSvc = getIt<ManagerPinService>();
    await showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(_pinSet ? 'تغيير الرقم السري' : 'تعيين الرقم السري'),
        content: TextField(
          controller: controller,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'الرقم السري الجديد'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final res = await pinSvc.setPin(
                  pin: controller.text,
                  userId: uid,
                );
                res.fold(
                  (f) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(f.message),
                          backgroundColor: AppColors.error,
                        ),
                      );
                    }
                  },
                  (_) {
                    if (mounted) {
                      setState(() => _pinSet = true);
                    }
                  },
                );
              }
              if (dialogCtx.mounted) {
                Navigator.of(dialogCtx).pop();
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

class _CreditSalesSettingsSection extends StatefulWidget {
  final String userId;

  const _CreditSalesSettingsSection({required this.userId});

  @override
  State<_CreditSalesSettingsSection> createState() =>
      _CreditSalesSettingsSectionState();
}

class _CreditSalesSettingsSectionState
    extends State<_CreditSalesSettingsSection> {
  bool _loading = true;
  bool _creditPinRequired = false;
  bool _pinSet = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pinSvc = getIt<ManagerPinService>();
    final creditPin = await pinSvc.isCreditPinRequired();
    final pinSet = await pinSvc.isPinSet();
    if (mounted) {
      setState(() {
        _creditPinRequired = creditPin;
        _pinSet = pinSet;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        key: Key('credit_settings_section'),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final pinSvc = getIt<ManagerPinService>();
    final state = context.watch<SettingsCubit>().state;
    final creditEnabled = state.creditPaymentEnabled;

    return Card(
      key: const Key('credit_settings_section'),
      child: Column(
        children: [
          SwitchListTile(
            key: const Key('credit_sales_enabled_toggle'),
            title: const Text('تفعيل الدفع الآجل في الكاشير (نقطة البيع)'),
            subtitle: const Text(
              'إظهار طريقة الدفع "آجل" في شاشة البيع، مع تسجيل الفواتير في ذمة العميل',
            ),
            value: creditEnabled,
            onChanged: (v) async {
              final err = await context
                  .read<SettingsCubit>()
                  .setPaymentMethod('payment.credit', v, widget.userId);
              if (err != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(err), backgroundColor: AppColors.error),
                );
              }
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            key: const Key('credit_sales_pin_required_toggle'),
            title: const Text('طلب الرقم السري للمدير عند البيع الآجل'),
            subtitle: const Text(
              'طلب موافقة وتأكيد المدير برقم الـ PIN عند إتمام أي عملية بيع بالآجل',
            ),
            value: _creditPinRequired,
            onChanged: (v) async {
              await pinSvc.setCreditPinRequired(required: v, userId: widget.userId);
              if (mounted) {
                setState(() => _creditPinRequired = v);
              }
            },
          ),
          const Divider(height: 1),
          ListTile(
            enabled: _creditPinRequired,
            title: const Text('الرقم السري للمدير (Manager PIN) للآجل'),
            subtitle: Text(
              !_creditPinRequired
                  ? 'معطّل حالياً في البيع الآجل — لن يُطلب الرقم السري'
                  : (_pinSet ? 'الرقم السري مُعيَّن' : 'لم يتم تعيين الرقم السري بعد'),
            ),
            trailing: OutlinedButton(
              onPressed: _creditPinRequired ? () => _showSetPinDialog(context) : null,
              child: Text(_pinSet ? 'تغيير' : 'تعيين'),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 20, color: AppColors.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'ملاحظة: يمكن للمدير تحديد "الحد الأقصى للآجل (الائتماني)" لكل عميل من شاشة سجل العملاء. في حال تجاوز العميل للحد الائتماني، يلزم النظام إدخال الرقم السري للمدير للموافقة على الاستثناء.',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSetPinDialog(BuildContext context) async {
    final controller = TextEditingController();
    final uid = widget.userId;
    final pinSvc = getIt<ManagerPinService>();
    await showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(_pinSet ? 'تغيير الرقم السري' : 'تعيين الرقم السري'),
        content: TextField(
          controller: controller,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'الرقم السري الجديد'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final res = await pinSvc.setPin(
                  pin: controller.text,
                  userId: uid,
                );
                res.fold(
                  (f) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(f.message),
                          backgroundColor: AppColors.error,
                        ),
                      );
                    }
                  },
                  (_) {
                    if (mounted) {
                      setState(() => _pinSet = true);
                    }
                  },
                );
              }
              if (dialogCtx.mounted) {
                Navigator.of(dialogCtx).pop();
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

class _BrandingSettingsCard extends StatefulWidget {
  final String userId;

  const _BrandingSettingsCard({required this.userId});

  @override
  State<_BrandingSettingsCard> createState() => _BrandingSettingsCardState();
}

class _BrandingSettingsCardState extends State<_BrandingSettingsCard> {
  late TextEditingController _nameCtrl;
  late TextEditingController _primaryHexCtrl;
  late TextEditingController _secondaryHexCtrl;
  late Color _selectedPrimary;
  late Color _selectedSecondary;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final cur = AppBranding.current;
    _nameCtrl = TextEditingController(text: cur.appName);
    _selectedPrimary = cur.primaryColor;
    _selectedSecondary = cur.secondaryColor;
    _primaryHexCtrl = TextEditingController(
      text: '#${AppBranding.colorToHex(cur.primaryColor).substring(2)}',
    );
    _secondaryHexCtrl = TextEditingController(
      text: '#${AppBranding.colorToHex(cur.secondaryColor).substring(2)}',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _primaryHexCtrl.dispose();
    _secondaryHexCtrl.dispose();
    super.dispose();
  }

  void _selectPreset(AppColorPreset preset) {
    setState(() {
      _selectedPrimary = preset.primary;
      _selectedSecondary = preset.secondary;
      _primaryHexCtrl.text =
          '#${AppBranding.colorToHex(preset.primary).substring(2)}';
      _secondaryHexCtrl.text =
          '#${AppBranding.colorToHex(preset.secondary).substring(2)}';
    });
  }

  Future<void> _saveBranding() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال اسم النظام / المحل'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await AppBranding.save(
        getIt<FeatureGate>(),
        appName: name,
        primaryColor: _selectedPrimary,
        secondaryColor: _selectedSecondary,
        userId: widget.userId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade800,
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                'تم حفظ وتطبيق هوية وألوان "$name" بنجاح',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء الحفظ: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetDefaults() async {
    setState(() => _saving = true);
    try {
      await AppBranding.resetToDefaults(
        getIt<FeatureGate>(),
        userId: widget.userId,
      );
      if (!mounted) return;
      final def = AppBrandingConfig.defaults;
      setState(() {
        _nameCtrl.text = def.appName;
        _selectedPrimary = def.primaryColor;
        _selectedSecondary = def.secondaryColor;
        _primaryHexCtrl.text =
            '#${AppBranding.colorToHex(def.primaryColor).substring(2)}';
        _secondaryHexCtrl.text =
            '#${AppBranding.colorToHex(def.secondaryColor).substring(2)}';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم استعادة الاسم والألوان الافتراضية للنظام'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. System / Store Name
            TextField(
              key: const Key('branding_app_name_field'),
              controller: _nameCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'اسم النظام / المحل',
                hintText: 'مثال: بيعة',
                prefixIcon: Icon(Icons.storefront_rounded, color: _selectedPrimary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 16),

            // 2. Curated Theme Color Presets
            const Text(
              'اختر قالب ألوان النظام:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: AppBranding.presets.map((preset) {
                final isSelected =
                    _selectedPrimary.toARGB32() == preset.primary.toARGB32() &&
                        _selectedSecondary.toARGB32() == preset.secondary.toARGB32();
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _selectPreset(preset),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? preset.primary.withValues(alpha: 0.1)
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? preset.primary : Colors.grey.shade300,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: preset.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, color: Colors.white, size: 14)
                              : null,
                        ),
                        const SizedBox(width: 4),
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: preset.secondary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          preset.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // 3. Custom Hex Color Inputs
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('branding_primary_hex_field'),
                    controller: _primaryHexCtrl,
                    decoration: InputDecoration(
                      labelText: 'كود اللون الأساسي',
                      hintText: '#340588',
                      prefixIcon: Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircleAvatar(
                          radius: 10,
                          backgroundColor: _selectedPrimary,
                        ),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (val) {
                      final parsed = AppBranding.parseHexColor(val);
                      if (parsed != null) {
                        setState(() => _selectedPrimary = parsed);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const Key('branding_secondary_hex_field'),
                    controller: _secondaryHexCtrl,
                    decoration: InputDecoration(
                      labelText: 'كود اللون الثانوي',
                      hintText: '#4B2A9E',
                      prefixIcon: Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircleAvatar(
                          radius: 10,
                          backgroundColor: _selectedSecondary,
                        ),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (val) {
                      final parsed = AppBranding.parseHexColor(val);
                      if (parsed != null) {
                        setState(() => _selectedSecondary = parsed);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 4. Live Preview Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _selectedPrimary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.storefront_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _nameCtrl.text.trim().isEmpty
                          ? AppBrandingConfig.defaults.appName
                          : _nameCtrl.text.trim(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _selectedSecondary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'معاينة المظهر',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 5. Action Buttons
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _saving ? null : _resetDefaults,
                  icon: const Icon(Icons.restore_rounded, size: 18),
                  label: const Text('استعادة الافتراضي'),
                ),
                ElevatedButton.icon(
                  key: const Key('branding_save_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedPrimary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _saving ? null : _saveBranding,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.palette_rounded, size: 18),
                  label: const Text('حفظ وتطبيق الهوية والألوان'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptCustomizerSettingsCard extends StatelessWidget {
  final String userId;

  const _ReceiptCustomizerSettingsCard({required this.userId});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReceiptConfig>(
      valueListenable: ReceiptSettingsService.notifier,
      builder: (context, cfg, _) {
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.black12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.receipt_long_rounded,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الفاتورة الحرارية: ${cfg.storeName}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'مقاس: ${cfg.paperWidthMm} مم | هاتف: ${cfg.storePhone} | عنوان: ${cfg.storeAddress}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ReceiptCustomizerScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: const Text('تخصيص وبرمجة الفاتورة'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BarcodeCustomizerSettingsCard extends StatelessWidget {
  final String userId;

  const _BarcodeCustomizerSettingsCard({required this.userId});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BarcodeConfig>(
      valueListenable: BarcodeSettingsService.notifier,
      builder: (context, cfg, _) {
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.black12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.qr_code_2_rounded,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ملصقات الباركود والأسعار: ${cfg.storeName}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'المقاس: ${cfg.selectedSize.name} | السعر: ${cfg.showPrice ? "مفعل" : "معطل"} | المقاس واللون: ${cfg.showColorAndSize ? "مفعل" : "معطل"}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BarcodeCustomizerScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: const Text('تخصيص ملصق الباركود'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SectorModeSettingsCard extends StatelessWidget {
  final String userId;

  const _SectorModeSettingsCard({required this.userId});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final currentMode = state.sectorMode;

        final options = [
          (
            key: RetailSector.apparel,
            title: RetailSector.getLabel(RetailSector.apparel),
            desc: RetailSector.getDescription(RetailSector.apparel),
            icon: Icons.checkroom_rounded,
            color: const Color(0xFF6A1B9A),
          ),
          (
            key: RetailSector.supermarket,
            title: RetailSector.getLabel(RetailSector.supermarket),
            desc: RetailSector.getDescription(RetailSector.supermarket),
            icon: Icons.shopping_cart_rounded,
            color: const Color(0xFF2E7D32),
          ),
          (
            key: RetailSector.houseware,
            title: RetailSector.getLabel(RetailSector.houseware),
            desc: RetailSector.getDescription(RetailSector.houseware),
            icon: Icons.kitchen_rounded,
            color: const Color(0xFFE65100),
          ),
        ];

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.storefront_rounded, color: AppColors.primary),
                    const SizedBox(width: 8),
                    const Text(
                      'تخصيص نمط النظام لنشاط المحل',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'اختر نوع نشاط متجرك لتكييف شاشات إضافة المنتجات والكاشير وسلوك الماسح الضوئي تلقائياً.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 14),
                for (final opt in options) ...[
                  InkWell(
                    key: Key('sector_tile_${opt.key}'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      if (currentMode == opt.key) return;
                      final err = await context
                          .read<SettingsCubit>()
                          .setSectorMode(opt.key, userId);
                      if (context.mounted) {
                        if (err != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(err),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('تم تفعيل نمط: ${opt.title} بنجاح'),
                              backgroundColor: Colors.green.shade800,
                            ),
                          );
                        }
                      }
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: currentMode == opt.key
                            ? opt.color.withValues(alpha: 0.08)
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: currentMode == opt.key
                              ? opt.color
                              : Colors.grey.shade200,
                          width: currentMode == opt.key ? 1.8 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: currentMode == opt.key
                                  ? opt.color
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              opt.icon,
                              color: currentMode == opt.key
                                  ? Colors.white
                                  : Colors.grey.shade700,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      opt.title,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: currentMode == opt.key
                                            ? opt.color
                                            : AppColors.onSurface,
                                      ),
                                    ),
                                    if (currentMode == opt.key) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: opt.color,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'النشط حالياً',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  opt.desc,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // ignore: deprecated_member_use
                          Radio<String>(
                            value: opt.key,
                            // ignore: deprecated_member_use
                            groupValue: currentMode,
                            activeColor: opt.color,
                            // ignore: deprecated_member_use
                            onChanged: (_) async {
                              final err = await context
                                  .read<SettingsCubit>()
                                  .setSectorMode(opt.key, userId);
                              if (context.mounted && err != null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(err),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
