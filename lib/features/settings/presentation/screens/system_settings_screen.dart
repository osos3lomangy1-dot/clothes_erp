import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/retail_sector.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../../core/theme/app_branding.dart';
import '../../../auth/domain/models/cashier_permissions_config.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../../auth/services/cashier_permissions_service.dart';
import '../../../barcode_printing/domain/models/barcode_config.dart';
import '../../../barcode_printing/presentation/screens/barcode_customizer_screen.dart';
import '../../../barcode_printing/services/barcode_settings_service.dart';
import '../../../installments/data/services/manager_pin_service.dart';
import '../../../invoices/data/services/receipt_settings_service.dart';
import '../../../invoices/domain/entities/receipt_config.dart';
import '../../../invoices/presentation/screens/receipt_customizer_screen.dart';
import '../cubits/settings_cubit.dart';
import '../widgets/excel_migration_card.dart';
import '../widgets/google_drive_backup_card.dart';
import '../widgets/local_backup_card.dart';
import '../../../pre_orders/data/services/telegram_bot_service.dart';
import '../../../pre_orders/presentation/widgets/telegram_inbox_dialog.dart';
import '../../../products/domain/entities/activity_type.dart';
import '../../data/services/activity_settings_service.dart';

class SystemSettingsScreen extends StatelessWidget {
  final String? initialCategory;

  const SystemSettingsScreen({super.key, this.initialCategory});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<SettingsCubit>()..start(),
      child: _SystemSettingsView(initialCategory: initialCategory),
    );
  }
}

class _SettingsCategoryItem {
  final String key;
  final String label;
  final String subtitle;
  final IconData icon;

  const _SettingsCategoryItem({
    required this.key,
    required this.label,
    required this.subtitle,
    required this.icon,
  });
}

class _SystemSettingsView extends StatefulWidget {
  final String? initialCategory;

  const _SystemSettingsView({this.initialCategory});

  @override
  State<_SystemSettingsView> createState() => _SystemSettingsViewState();
}

class _SystemSettingsViewState extends State<_SystemSettingsView> {
  String? _selectedCategory;

  static const _categories = <_SettingsCategoryItem>[
    _SettingsCategoryItem(
      key: 'features',
      label: 'لوحة التحكم في المزايا',
      subtitle: 'التحكم الشامل في تفعيل المزايا وموديولات النظام والأنشطة',
      icon: Icons.tune_rounded,
    ),
    _SettingsCategoryItem(
      key: 'activities',
      label: 'الأنشطة وخطوط العمل',
      subtitle: 'تخصيص أقسام المتجر، الحجز المسبق، وتيليجرام',
      icon: Icons.dashboard_customize_rounded,
    ),
    _SettingsCategoryItem(
      key: 'pos',
      label: 'نقطة البيع',
      subtitle: 'طرق الدفع، الأقساط، الآجل، والعروض',
      icon: Icons.point_of_sale_rounded,
    ),
    _SettingsCategoryItem(
      key: 'inventory',
      label: 'المخزون',
      subtitle: 'الأصناف، حركات المخزن، والمشتريات',
      icon: Icons.inventory_2_rounded,
    ),
    _SettingsCategoryItem(
      key: 'staff',
      label: 'العملاء وفريق العمل',
      subtitle: 'العملاء، الموظفون، وصلاحيات الكاشير',
      icon: Icons.groups_rounded,
    ),
    _SettingsCategoryItem(
      key: 'treasury',
      label: 'الخزينة والشركاء',
      subtitle: 'المصروفات، الشركاء، والتقارير المالية',
      icon: Icons.account_balance_wallet_rounded,
    ),
    _SettingsCategoryItem(
      key: 'printing',
      label: 'الطباعة',
      subtitle: 'الفواتير الحرارية وملصقات الأسعار',
      icon: Icons.print_rounded,
    ),
    _SettingsCategoryItem(
      key: 'backup',
      label: 'النسخ السحابي والبيانات',
      subtitle: 'النسخ المحلي، Google Drive، و Excel',
      icon: Icons.cloud_sync_rounded,
    ),
    _SettingsCategoryItem(
      key: 'store',
      label: 'المظهر وهوية المتجر',
      subtitle: 'نمط النشاط التجاري واسم وألوان المحل',
      icon: Icons.palette_rounded,
    ),
  ];

  String _normalizeCategory(String cat) {
    if (cat == 'features' || cat == 'feature_matrix') return 'features';
    if (cat == 'activities' || cat == 'activity') return 'activities';
    if (cat == 'sales') return 'pos';
    if (cat == 'permissions') return 'staff';
    if (cat == 'data') return 'backup';
    if (cat == 'branding') return 'store';
    return cat;
  }

  String _currentCategory(SettingsState state) {
    if (_selectedCategory != null) {
      return _normalizeCategory(_selectedCategory!);
    }
    if (widget.initialCategory != null) {
      return _normalizeCategory(widget.initialCategory!);
    }
    return 'features';
  }

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
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(
          child: Text(
            'إعدادات النظام متاحة للمدير فقط',
            style: TextStyle(fontSize: 16, color: Color(0xFF64748B)),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'مركز الإعدادات الموحد',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Color(0xFF0F172A),
              ),
            ),
            Text(
              'تحكم شامل في ميزات النظام وصلاحيات العمل وهوية المتجر',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.outlineVariant),
        ),
      ),
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          if (state.isLoading && state.features.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final currentCat = _currentCategory(state);
          final activeCategoryItem = _categories.firstWhere(
            (c) => c.key == currentCat,
            orElse: () => _categories.first,
          );
          final installmentsEnabled =
              state.features[FeatureKeys.installments] ?? false;
          final userId = _userId(context);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Settings Sidebar (Right rail in RTL) ──
              Container(
                width: 220,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    left: BorderSide(color: AppColors.outlineVariant),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      alignment: Alignment.centerRight,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: AppColors.outlineVariant),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.tune_rounded,
                            size: 16,
                            color: Color(0xFF64748B),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'أقسام الإعدادات',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 8,
                        ),
                        children: [
                          for (final cat in _categories)
                            _SidebarNavItem(
                              item: cat,
                              selected: currentCat == cat.key,
                              onTap: () =>
                                  setState(() => _selectedCategory = cat.key),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Main Content Area (Left rail in RTL) ──
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 24,
                      ),
                      children: [
                        // Category Header
                        _CategoryHeader(
                          icon: activeCategoryItem.icon,
                          label: activeCategoryItem.label,
                          subtitle: activeCategoryItem.subtitle,
                        ),
                        const SizedBox(height: 24),

                        // ─── لوحة التحكم الشاملة في المزايا (Master Categorized Feature Control Matrix) ───
                        if (currentCat == 'features') ...[
                          _sectionTitle('1. مزايا الكاشير ونقطة البيع (POS)'),
                          _buildPosFeaturesCard(state, userId),
                          const SizedBox(height: 24),

                          _sectionTitle('2. مزايا المخزون والأنشطة التجارية'),
                          _buildInventoryFeaturesCard(state, userId),
                          const SizedBox(height: 24),

                          _sectionTitle('3. مزايا التجارة المتعددة والحجز المسبق'),
                          _buildOmnichannelFeaturesCard(state, userId),
                          const SizedBox(height: 24),

                          _sectionTitle('4. مزايا الحسابات والورديات والأمان'),
                          _buildFinancialAndSecurityFeaturesCard(state, userId),
                          const SizedBox(height: 32),
                        ],

                        // ─── 0. الأنشطة وخطوط العمل (Activities & Telegram) ───
                        if (currentCat == 'activities') ...[
                          _sectionTitle('أقسام المنتجات والأنشطة التجارية'),
                          _ActivitiesMasterSettingsCard(userId: userId),
                          const SizedBox(height: 24),
                          _sectionTitle('مجمع وبوت تيليجرام للحجوزات والطلبيات'),
                          _TelegramBotSettingsCard(userId: userId),
                        ],

                        // ─── 1. نقطة البيع والمبيعات (POS) ───
                        if (currentCat == 'pos') ...[
                          _sectionTitle('ميزات البيع والتسويق'),
                          _cardWrapper(
                            child: Column(
                              children: [
                                _cardHeader(
                                  icon: Icons.local_offer_rounded,
                                  title: 'ميزات البيع والعروض الترويجية',
                                  subtitle:
                                      'التحكم في الميزات الإضافية لشاشة البيع وخدمات العملاء',
                                ),
                                Divider(
                                  height: 24,
                                  color: AppColors.outlineVariant,
                                ),
                                _buildFeatureItem(
                                  title: 'شاشة الكاشير ونقطة البيع (POS)',
                                  description:
                                      'المحرك الأساسي لعمليات البيع، مسح الباركود، الفواتير الفورية، وتطبيق الخصومات',
                                  isCore: true,
                                  isEnabled: true,
                                ),
                                Divider(
                                  height: 16,
                                  color: AppColors.outlineVariant,
                                ),
                                _buildFeatureItem(
                                  key: const Key('feature_promotions_toggle'),
                                  title: 'العروض والخصومات الترويجية',
                                  description:
                                      'تفعيل إنشاء عروض الخصم المباشر، باقات الشراء، والخصومات المئوية المؤقتة',
                                  isCore: false,
                                  isEnabled:
                                      state.features[FeatureKeys.promotions] ??
                                      false,
                                  onChanged: (v) => _toggleFeature(
                                    context,
                                    FeatureKeys.promotions,
                                    v,
                                    userId,
                                  ),
                                ),
                                Divider(
                                  height: 16,
                                  color: AppColors.outlineVariant,
                                ),
                                _buildFeatureItem(
                                  key: const Key('feature_loyalty_toggle'),
                                  title: 'برنامج ولاء ونقاط العملاء',
                                  description:
                                      'احتساب نقاط مكافآت للمشتريات واستبدالها برصيد أو خصومات في الفواتير القادمة',
                                  dependencyInfo: 'يعتمد على: العملاء',
                                  isCore: false,
                                  isEnabled:
                                      state.features[FeatureKeys.loyalty] ??
                                      false,
                                  onChanged: (v) => _toggleFeature(
                                    context,
                                    FeatureKeys.loyalty,
                                    v,
                                    userId,
                                  ),
                                ),
                                Divider(
                                  height: 16,
                                  color: AppColors.outlineVariant,
                                ),
                                _buildFeatureItem(
                                  key: const Key(
                                    'feature_installments_master_toggle',
                                  ),
                                  title: 'نظام البيع بالتقسيط وإيصالات الأمانة',
                                  description:
                                      'تمكين البيع بنظام الأقساط الشهرية، احتساب المرابحة، جدولة السداد، وإيصالات الأمانة والتحصيل القضائي',
                                  dependencyInfo: 'يعتمد على: العملاء',
                                  isCore: false,
                                  isEnabled: installmentsEnabled,
                                  onChanged: (v) => _toggleFeature(
                                    context,
                                    FeatureKeys.installments,
                                    v,
                                    userId,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          _sectionTitle('طرق الدفع المعتمدة في الكاشير'),
                          _cardWrapper(
                            child: Column(
                              children: [
                                _cardHeader(
                                  icon: Icons.payments_rounded,
                                  title: 'طرق الدفع المقبولة',
                                  subtitle:
                                      'حدد طرق الدفع التي تظهر للكاشير أثناء تقفيل الفاتورة (يلزم طريقة واحدة على الأقل)',
                                ),
                                Divider(
                                  height: 24,
                                  color: AppColors.outlineVariant,
                                ),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                    'نقدي (Cash)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: const Text(
                                    'الدفع الفوري بالدرج والنقدية',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  activeThumbColor: AppColors.primary,
                                  value: state.cashEnabled,
                                  onChanged: (v) => _setPaymentMethod(
                                    context,
                                    'payment.cash',
                                    v,
                                    userId,
                                  ),
                                ),
                                Divider(
                                  height: 1,
                                  color: AppColors.outlineVariant,
                                ),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                    'بطاقة بنكية / فيزا (Card)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: const Text(
                                    'الدفع عبر ماكينات نقاط البيع والمحافظ الإلكترونية',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  activeThumbColor: AppColors.primary,
                                  value: state.cardEnabled,
                                  onChanged: (v) => _setPaymentMethod(
                                    context,
                                    'payment.card',
                                    v,
                                    userId,
                                  ),
                                ),
                                Divider(
                                  height: 1,
                                  color: AppColors.outlineVariant,
                                ),
                                SwitchListTile(
                                  key: const Key('payment_credit_toggle'),
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                    'آجل (البيع على الحساب)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: const Text(
                                    'تسجيل الفاتورة في ذمة العميل مع متابعة التحصيل لاحقاً',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  activeThumbColor: AppColors.primary,
                                  value: state.creditPaymentEnabled,
                                  onChanged: (v) => _setPaymentMethod(
                                    context,
                                    'payment.credit',
                                    v,
                                    userId,
                                  ),
                                ),
                                if (installmentsEnabled) ...[
                                  Divider(
                                    height: 1,
                                    color: AppColors.outlineVariant,
                                  ),
                                  SwitchListTile(
                                    key: const Key('payment_installment_toggle'),
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text(
                                      'تقسيط (عقود وجدولة أقساط)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    subtitle: const Text(
                                      'إتاحة زر التقسيط وإصدار عقد تقسيط ذكي ومطالبة الضامن',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                    activeThumbColor: AppColors.primary,
                                    value: state.installmentPaymentEnabled,
                                    onChanged: (v) => _setPaymentMethod(
                                      context,
                                      'payment.installment',
                                      v,
                                      userId,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          _sectionTitle('إعدادات الدفع الآجل (البيع على الحساب)'),
                          _CreditSalesSettingsSection(userId: userId),
                          if (installmentsEnabled) ...[
                            const SizedBox(height: 20),
                            _sectionTitle('إعدادات التقسيط والأمان'),
                            const _InstallmentSettingsSection(),
                          ],
                        ],

                        // ─── 2. المخزون والتوريد (Inventory) ───
                        if (currentCat == 'inventory') ...[
                          _sectionTitle('المخزون وحركات المستودع'),
                          _cardWrapper(
                            child: Column(
                              children: [
                                _cardHeader(
                                  icon: Icons.warehouse_rounded,
                                  title: 'إدارة المستودع والأصناف',
                                  subtitle:
                                      'ميزات تتبع المنتجات والأصناف والتدقيق المخزني',
                                ),
                                Divider(
                                  height: 24,
                                  color: AppColors.outlineVariant,
                                ),
                                _buildFeatureItem(
                                  title: 'إدارة المخزون ودليل المنتجات',
                                  description:
                                      'تتبع أرصدة المنتجات، المقاسات، الألوان، الباركودات، وأسعار التكلفة والبيع',
                                  isCore: true,
                                  isEnabled: true,
                                ),
                                Divider(
                                  height: 16,
                                  color: AppColors.outlineVariant,
                                ),
                                _buildFeatureItem(
                                  title: 'سجل حركات المخزن والتدقيق المخزني',
                                  description:
                                      'توثيق كل حركة إضافة، بيع، مرتجع، إهلاك، أو تسوية جردية مع هوية المستخدم والتوقيت',
                                  isCore: true,
                                  isEnabled: true,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          _sectionTitle('التوريد وإدارة الموردين'),
                          _cardWrapper(
                            child: Column(
                              children: [
                                _cardHeader(
                                  icon: Icons.local_shipping_rounded,
                                  title: 'المشتريات والموردون',
                                  subtitle:
                                      'إثبات بضاعة الموردين وتتبع المديونيات وجداول السداد',
                                ),
                                Divider(
                                  height: 24,
                                  color: AppColors.outlineVariant,
                                ),
                                _buildFeatureItem(
                                  key: const Key('feature_purchases_toggle'),
                                  title: 'فواتير المشتريات واستلام الشحنات',
                                  description:
                                      'إثبات بضاعة الموردين وتحديث التكلفة وكميات المستودع آلياً عند الاستلام',
                                  isCore: false,
                                  isEnabled:
                                      state.features[FeatureKeys.purchases] ??
                                      true,
                                  onChanged: (v) => _toggleFeature(
                                    context,
                                    FeatureKeys.purchases,
                                    v,
                                    userId,
                                  ),
                                ),
                                Divider(
                                  height: 16,
                                  color: AppColors.outlineVariant,
                                ),
                                _buildFeatureItem(
                                  key: const Key('feature_suppliers_toggle'),
                                  title: 'دليل وحسابات الموردين',
                                  description:
                                      'متابعة كشوفات حساب الموردين، الدفعات المسددة، والمبالغ المتبقية في الذمة',
                                  dependencyInfo: 'يعتمد على: المشتريات',
                                  isCore: false,
                                  isEnabled:
                                      state.features[FeatureKeys.suppliers] ??
                                      true,
                                  onChanged: (v) => _toggleFeature(
                                    context,
                                    FeatureKeys.suppliers,
                                    v,
                                    userId,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          _sectionTitle('الرقابة المخزنية الذكية'),
                          _cardWrapper(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.lightbulb_outline_rounded,
                                    color: Color(0xFFD97706),
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'تنبيهات حد الطلب والجرد الدوري',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'يقوم النظام بمراقبة حد إعادة الطلب تلقائياً، وإشعارك عند اقتراب نفاذ أي مقاس أو لون لتفادي توقف المبيعات.',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: Color(0xFF64748B),
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // ─── 3. العملاء وفريق العمل (Staff) ───
                        if (currentCat == 'staff') ...[
                          _sectionTitle('شؤون العملاء'),
                          _cardWrapper(
                            child: Column(
                              children: [
                                _cardHeader(
                                  icon: Icons.person_pin_rounded,
                                  title: 'قاعدة بيانات العملاء',
                                  subtitle:
                                      'دليل العملاء وحسابات الديون والائتمان',
                                ),
                                Divider(
                                  height: 24,
                                  color: AppColors.outlineVariant,
                                ),
                                _buildFeatureItem(
                                  title: 'دليل العملاء وحسابات الديون',
                                  description:
                                      'حفظ بيانات العملاء، أرقام الهواتف، كشف حساب المشتريات، والحدود الائتمانية للآجل والتقسيط',
                                  isCore: true,
                                  isEnabled: true,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          _sectionTitle('فريق العمل والرواتب والورديات'),
                          _cardWrapper(
                            child: Column(
                              children: [
                                _cardHeader(
                                  icon: Icons.badge_rounded,
                                  title: 'شؤون الموظفين والورديات',
                                  subtitle:
                                      'إدارة المستخدمين، كشوف الرواتب، وجداول الورديات',
                                ),
                                Divider(
                                  height: 24,
                                  color: AppColors.outlineVariant,
                                ),
                                _buildFeatureItem(
                                  key: const Key('feature_employees_toggle'),
                                  title: 'إدارة الموظفين ومستخدمي النظام',
                                  description:
                                      'إنشاء حسابات المستخدمين وتحديد الأدوار (مدير / كاشير) وكلمات المرور',
                                  isCore: false,
                                  isEnabled:
                                      state.features[FeatureKeys.employees] ??
                                      true,
                                  onChanged: (v) => _toggleFeature(
                                    context,
                                    FeatureKeys.employees,
                                    v,
                                    userId,
                                  ),
                                ),
                                Divider(
                                  height: 16,
                                  color: AppColors.outlineVariant,
                                ),
                                _buildFeatureItem(
                                  key: const Key('feature_payroll_toggle'),
                                  title:
                                      'مسير الرواتب والمستحقات والخصومات',
                                  description:
                                      'تسجيل السلف، المكافآت، الخصومات الشهرية، وصرف الرواتب من الخزينة',
                                  dependencyInfo: 'يعتمد على: الموظفون',
                                  isCore: false,
                                  isEnabled:
                                      state.features[FeatureKeys.payroll] ??
                                      true,
                                  onChanged: (v) => _toggleFeature(
                                    context,
                                    FeatureKeys.payroll,
                                    v,
                                    userId,
                                  ),
                                ),
                                Divider(
                                  height: 16,
                                  color: AppColors.outlineVariant,
                                ),
                                _buildFeatureItem(
                                  key: const Key('feature_shifts_toggle'),
                                  title: 'إدارة الورديات وتقفيل اليومية',
                                  description:
                                      'فتح وردية كاشير بعهدة أولية، ومطابقة الكاش الفعلي مع المسجل بالنظام عند الإغلاق',
                                  isCore: false,
                                  isEnabled:
                                      state.features[FeatureKeys.shifts] ??
                                      true,
                                  onChanged: (v) => _toggleFeature(
                                    context,
                                    FeatureKeys.shifts,
                                    v,
                                    userId,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          _sectionTitle('صلاحيات الكاشير الموثوق'),
                          _CashierPermissionsSettingsCard(userId: userId),
                        ],

                        // ─── 4. الخزينة والشركاء (Treasury) ───
                        if (currentCat == 'treasury') ...[
                          _sectionTitle('العمليات المالية والتقارير'),
                          _cardWrapper(
                            child: Column(
                              children: [
                                _cardHeader(
                                  icon: Icons.monetization_on_rounded,
                                  title: 'الخزينة والمصروفات النثرية',
                                  subtitle:
                                      'توثيق حركة النقدية والمصروفات التشغيلية والتقارير المالية',
                                ),
                                Divider(
                                  height: 24,
                                  color: AppColors.outlineVariant,
                                ),
                                _buildFeatureItem(
                                  key: const Key('feature_expenses_toggle'),
                                  title: 'إدارة المصروفات النثرية والتشغيلية',
                                  description:
                                      'تسجيل مصاريف المحل اليومية والشهرية (إيجار، كهرباء، بوفيه، نقل) وتأثيرها على صافي الأرباح',
                                  isCore: false,
                                  isEnabled:
                                      state.features[FeatureKeys.expenses] ??
                                      true,
                                  onChanged: (v) => _toggleFeature(
                                    context,
                                    FeatureKeys.expenses,
                                    v,
                                    userId,
                                  ),
                                ),
                                Divider(
                                  height: 16,
                                  color: AppColors.outlineVariant,
                                ),
                                _buildFeatureItem(
                                  key: const Key('feature_reports_toggle'),
                                  title: 'التقارير الإدارية والمالية الشاملة',
                                  description:
                                      'كشوف الأرباح والخسائر، حركة الخزينة، تقارير مبيعات الأصناف، وتقارير أداء الكاشير',
                                  isCore: false,
                                  isEnabled:
                                      state.features[FeatureKeys.reports] ??
                                      true,
                                  onChanged: (v) => _toggleFeature(
                                    context,
                                    FeatureKeys.reports,
                                    v,
                                    userId,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          _sectionTitle('الشركاء ورؤوس الأموال'),
                          _cardWrapper(
                            child: Column(
                              children: [
                                _cardHeader(
                                  icon: Icons.handshake_rounded,
                                  title: 'حسابات الشركاء وتوزيع الأرباح',
                                  subtitle:
                                      'إدارة مساهمات الشركاء والمسحوبات وتوزيع صافي الأرباح',
                                ),
                                Divider(
                                  height: 24,
                                  color: AppColors.outlineVariant,
                                ),
                                _buildFeatureItem(
                                  key: const Key('feature_partners_toggle'),
                                  title: 'نظام الشركاء ورؤوس الأموال',
                                  description:
                                      'إدارة حصص الشركاء في رأس مال المتجر، تسجيل المسحوبات الشخصية، والتوزيع الدوري للأرباح',
                                  isCore: false,
                                  isEnabled:
                                      state.features[FeatureKeys.partners] ??
                                      false,
                                  onChanged: (v) => _toggleFeature(
                                    context,
                                    FeatureKeys.partners,
                                    v,
                                    userId,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          _sectionTitle('الأمان والرقابة المالية'),
                          _cardWrapper(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFECFDF5),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.verified_user_rounded,
                                    color: Color(0xFF10B981),
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'سجل التدقيق المالي المحمي (Audit Trail)',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'جميع العمليات المالية وحركات الخزينة وسندات الصرف والقبض تُوثق في سجل تدقيق محمي لا يمكن حذفه للحفاظ على الشفافية والمساءلة.',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: Color(0xFF64748B),
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // ─── 5. الطباعة والباركود (Printing) ───
                        if (currentCat == 'printing') ...[
                          _sectionTitle('تخصيص الفاتورة والإيصال'),
                          _ReceiptCustomizerSettingsCard(userId: userId),
                          const SizedBox(height: 20),
                          _sectionTitle('تخصيص ملصقات واستيكرات الباركود'),
                          _BarcodeCustomizerSettingsCard(userId: userId),
                        ],

                        // ─── 6. النسخ السحابي والبيانات (Backup) ───
                        if (currentCat == 'backup') ...[
                          _sectionTitle('النسخ الاحتياطي المحلي'),
                          LocalBackupCard(userId: userId),
                          const SizedBox(height: 20),
                          _sectionTitle('النسخ الاحتياطي على Google Drive'),
                          GoogleDriveBackupCard(userId: userId),
                          const SizedBox(height: 20),
                          _sectionTitle('تصدير واستيراد البيانات (Excel)'),
                          ExcelMigrationCard(userId: userId),
                          const SizedBox(height: 20),
                          _sectionTitle('المزامنة السحابية'),
                          _cardWrapper(
                            child: SwitchListTile(
                              key: const Key('cloud_sync_toggle'),
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'تفعيل المزامنة السحابية (اختياري)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              subtitle: const Text(
                                'عند التعطيل يعمل النظام محلياً بالكامل (Offline-First) بدون أي اتصال بالإنترنت.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              secondary: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: state.cloudSyncEnabled
                                      ? AppColors.primary.withValues(alpha: 0.1)
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  state.cloudSyncEnabled
                                      ? Icons.cloud_done_rounded
                                      : Icons.cloud_off_rounded,
                                  color: state.cloudSyncEnabled
                                      ? AppColors.primary
                                      : const Color(0xFF94A3B8),
                                  size: 22,
                                ),
                              ),
                              activeThumbColor: AppColors.primary,
                              value: state.cloudSyncEnabled,
                              onChanged: (v) async {
                                final err = await context
                                    .read<SettingsCubit>()
                                    .setCloudSyncEnabled(v, userId);
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
                        ],

                        // ─── 7. المظهر وهوية المتجر (Store / Branding) ───
                        if (currentCat == 'store') ...[
                          _sectionTitle('نمط النشاط ونوع المتجر'),
                          _SectorModeSettingsCard(userId: userId),
                          const SizedBox(height: 20),
                          _sectionTitle('هوية النظام والألوان (الاسم والمظهر)'),
                          _BrandingSettingsCard(userId: userId),
                        ],

                        const SizedBox(height: 32),
                        const Center(
                          child: Text(
                            'كل تعديل في الإعدادات يُسجَّل فورياً في سجل تدقيق النظام.',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _toggleFeature(
    BuildContext context,
    String key,
    bool value,
    String userId,
  ) async {
    final err = await context.read<SettingsCubit>().toggleFeature(
          key,
          value,
          userId,
        );
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _setPaymentMethod(
    BuildContext context,
    String key,
    bool value,
    String userId,
  ) async {
    final err = await context.read<SettingsCubit>().setPaymentMethod(
          key,
          value,
          userId,
        );
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: AppColors.error),
      );
    }
  }

  // ─── 1. كارت مزايا الكاشير ونقطة البيع (POS) ───
  Widget _buildPosFeaturesCard(SettingsState state, String userId) {
    final installmentsEnabled = state.features[FeatureKeys.installments] ?? false;
    return _cardWrapper(
      child: Column(
        children: [
          _cardHeader(
            icon: Icons.point_of_sale_rounded,
            title: 'مزايا الكاشير ونقطة البيع (POS)',
            subtitle: 'التحكم في وظائف المبيعات، التسعير، طرق السداد، وإدارة الفواتير',
          ),
          Divider(height: 24, color: AppColors.outlineVariant),
          _buildFeatureItem(
            title: 'شاشة الكاشير ونقطة البيع (POS)',
            description: 'المحرك الأساسي لعمليات البيع، مسح الباركود، الفواتير الفورية، والطباعة',
            isCore: true,
            isEnabled: true,
          ),
          Divider(height: 16, color: AppColors.outlineVariant),
          _buildFeatureItem(
            key: const Key('feature_wholesale_pricing_toggle'),
            title: 'البيع بسعر القطاعي والجملة',
            description: 'تمكين زر التبديل السريع بين سعر القطاعي وسعر الجملة مباشرة على شاشة الكاشير',
            isCore: false,
            isEnabled: state.features[FeatureKeys.wholesalePricing] ?? true,
            onChanged: (v) => _toggleFeature(context, FeatureKeys.wholesalePricing, v, userId),
          ),
          Divider(height: 16, color: AppColors.outlineVariant),
          _buildFeatureItem(
            key: const Key('feature_split_payment_toggle'),
            title: 'الدفع المجزأ (Split Payment)',
            description: 'السماح بسداد الفاتورة الواحدة بجزء نقدي بالدرج وجزء بطاقة بنكية أو محفظة إلكترونية',
            isCore: false,
            isEnabled: state.features[FeatureKeys.splitPayment] ?? true,
            onChanged: (v) => _toggleFeature(context, FeatureKeys.splitPayment, v, userId),
          ),
          Divider(height: 16, color: AppColors.outlineVariant),
          _buildFeatureItem(
            key: const Key('feature_credit_sales_toggle'),
            title: 'البيع الآجل والشكك (Credit Sales)',
            description: 'تمكين خيار "أجل / متبقي" وترحيل المبالغ المتبقية كديون في كشف حساب العميل',
            dependencyInfo: 'يعتمد على: العملاء',
            isCore: false,
            isEnabled: state.features[FeatureKeys.creditSales] ?? true,
            onChanged: (v) => _toggleFeature(context, FeatureKeys.creditSales, v, userId),
          ),
          Divider(height: 16, color: AppColors.outlineVariant),
          _buildFeatureItem(
            key: const Key('feature_hold_bills_toggle'),
            title: 'فواتير متعددة وتعليق الفاتورة (Hold / Multi-Bills)',
            description: 'إتاحة شريط تبويبات الفواتير لتعليق فاتورة وخدمة عميل آخر في الطابور دون فقد البيانات',
            isCore: false,
            isEnabled: state.features[FeatureKeys.holdBills] ?? true,
            onChanged: (v) => _toggleFeature(context, FeatureKeys.holdBills, v, userId),
          ),
          Divider(height: 16, color: AppColors.outlineVariant),
          _buildFeatureItem(
            key: const Key('feature_promotions_toggle'),
            title: 'العروض والخصومات الترويجية',
            description: 'تفعيل إنشاء عروض الخصم المباشر، باقات الشراء، والخصومات المئوية المؤقتة',
            isCore: false,
            isEnabled: state.features[FeatureKeys.promotions] ?? false,
            onChanged: (v) => _toggleFeature(context, FeatureKeys.promotions, v, userId),
          ),
          Divider(height: 16, color: AppColors.outlineVariant),
          _buildFeatureItem(
            key: const Key('feature_loyalty_toggle'),
            title: 'برنامج ولاء ونقاط العملاء',
            description: 'احتساب نقاط مكافآت للمشتريات واستبدالها برصيد أو خصومات في الفواتير القادمة',
            dependencyInfo: 'يعتمد على: العملاء',
            isCore: false,
            isEnabled: state.features[FeatureKeys.loyalty] ?? false,
            onChanged: (v) => _toggleFeature(context, FeatureKeys.loyalty, v, userId),
          ),
          Divider(height: 16, color: AppColors.outlineVariant),
          _buildFeatureItem(
            key: const Key('feature_installments_master_toggle'),
            title: 'نظام البيع بالتقسيط وإيصالات الأمانة',
            description: 'تمكين البيع بنظام الأقساط الشهرية، احتساب المرابحة، جدولة السداد، وإيصالات الأمانة والتحصيل القضائي',
            dependencyInfo: 'يعتمد على: العملاء',
            isCore: false,
            isEnabled: installmentsEnabled,
            onChanged: (v) => _toggleFeature(context, FeatureKeys.installments, v, userId),
          ),
        ],
      ),
    );
  }

  // ─── 2. كارت مزايا المخزون والأنشطة التجارية ───
  Widget _buildInventoryFeaturesCard(SettingsState state, String userId) {
    return _cardWrapper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
            icon: Icons.inventory_2_rounded,
            title: 'مزايا المخزون والأنشطة التجارية',
            subtitle: 'التحكم في دليل المنتجات، المشتريات، الموردين، وتتبع الحركات',
          ),
          Divider(height: 24, color: AppColors.outlineVariant),
          _buildFeatureItem(
            title: 'إدارة المخزون ودليل المنتجات',
            description: 'المحرك الأساسي لبطاقات الأصناف، الأقسام، المقاسات والألوان، وأسعار التكلفة والبيع',
            isCore: true,
            isEnabled: true,
          ),
          Divider(height: 16, color: AppColors.outlineVariant),
          _buildFeatureItem(
            title: 'سجل حركات المخزن والتدقيق المخزني',
            description: 'تتبع حركات الإدخال، الصرف، التسوية، الجرد الدوري، وتاريخ كل حركة بالوقت والمسؤول',
            isCore: true,
            isEnabled: true,
          ),
          Divider(height: 16, color: AppColors.outlineVariant),
          _buildFeatureItem(
            key: const Key('feature_purchases_toggle'),
            title: 'إدارة المشتريات وفواتير الشراء',
            description: 'تسجيل فواتير الشراء الواردة، تكلفة الأصناف، وتحديث أرصدة المخازن آلياً',
            isCore: false,
            isEnabled: state.features[FeatureKeys.purchases] ?? true,
            onChanged: (v) => _toggleFeature(context, FeatureKeys.purchases, v, userId),
          ),
          Divider(height: 16, color: AppColors.outlineVariant),
          _buildFeatureItem(
            key: const Key('feature_suppliers_toggle'),
            title: 'دليل الموردين وحسابات التوريد',
            description: 'إدارة سجلات الموردين، متابعة الديون المستحقة، ودفعات فواتير التوريد',
            dependencyInfo: 'يعتمد على: المشتريات',
            isCore: false,
            isEnabled: state.features[FeatureKeys.suppliers] ?? true,
            onChanged: (v) => _toggleFeature(context, FeatureKeys.suppliers, v, userId),
          ),
          Divider(height: 16, color: AppColors.outlineVariant),
          _buildFeatureItem(
            key: const Key('feature_low_stock_alerts_toggle'),
            title: 'تنبيهات النواقص والحد الأدنى للمخزون',
            description: 'إبراز الأصناف التي أوشكت على النفاد وإظهار مؤشرات تنبيه في الكروت وشريط الإشعارات',
            isCore: false,
            isEnabled: state.features[FeatureKeys.lowStockAlerts] ?? true,
            onChanged: (v) => _toggleFeature(context, FeatureKeys.lowStockAlerts, v, userId),
          ),
          Divider(height: 16, color: AppColors.outlineVariant),
          _buildFeatureItem(
            key: const Key('feature_product_timestamps_toggle'),
            title: 'عرض تواريخ التعديل والإنشاء على كروت المنتجات',
            description: 'إظهار سطر التوثيق الرمادي الهادئ (أُضيف: ... • آخر تعديل: ...) أسفل بطاقات المنتجات',
            isCore: false,
            isEnabled: state.features[FeatureKeys.productTimestamps] ?? true,
            onChanged: (v) => _toggleFeature(context, FeatureKeys.productTimestamps, v, userId),
          ),
          Divider(height: 16, color: AppColors.outlineVariant),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(Icons.dashboard_customize_rounded, size: 18, color: AppColors.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تخصيص أقسام الأنشطة (ملابس، أحذية، إكسسوارات، أدوات منزلية)',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                      Text(
                        'التحكم في ظهور أو إخفاء حقول المقاسات والضمان والألوان في شاشة الإضافة ونقطة البيع',
                        style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedCategory = 'activities';
                    });
                  },
                  icon: const Icon(Icons.arrow_back_rounded, size: 15),
                  label: const Text('إدارة الأنشطة'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── 3. كارت مزايا التجارة المتعددة والحجز المسبق ───
  Widget _buildOmnichannelFeaturesCard(SettingsState state, String userId) {
    return _cardWrapper(
      child: Column(
        children: [
          _cardHeader(
            icon: Icons.local_shipping_rounded,
            title: 'مزايا التجارة المتعددة والحجز المسبق',
            subtitle: 'إدارة طلبات الحجز المسبق، الشحنات المجمعة، وتكامل تيليجرام وواتساب',
          ),
          Divider(height: 24, color: AppColors.outlineVariant),
          _buildFeatureItem(
            key: const Key('feature_pre_orders_toggle'),
            title: 'موديول الحجز المسبق والطلبات الخاصة (Pre-Orders)',
            description: 'إدارة طلبات الاستيراد والحجز المسبق، تسجيل العربونات، وتتبع حالة وصول الشحنات',
            isCore: false,
            isEnabled: state.features[FeatureKeys.preOrders] ?? true,
            onChanged: (v) => _toggleFeature(context, FeatureKeys.preOrders, v, userId),
          ),
          Divider(height: 16, color: AppColors.outlineVariant),
          _buildFeatureItem(
            key: const Key('feature_consolidated_batches_toggle'),
            title: 'الشحنات المجمعة وتوزيع الشحن (Consolidated Batches)',
            description: 'تمكين دورة شحن الكراتين المجمعة وتوزيع تكلفة الشحن على بنود العملاء بحسابات مرنة عادلة',
            dependencyInfo: 'يعتمد على: الحجز المسبق',
            isCore: false,
            isEnabled: state.features[FeatureKeys.consolidatedBatches] ?? true,
            onChanged: (v) => _toggleFeature(context, FeatureKeys.consolidatedBatches, v, userId),
          ),
          Divider(height: 16, color: AppColors.outlineVariant),
          _buildFeatureItem(
            key: const Key('feature_telegram_bot_toggle'),
            title: 'سحب رسائل تيليجرام التلقائي (Telegram Bot Polling)',
            description: 'الاستقبال الآلي للرسائل وحجوزات العملاء من جروبات وقنوات تيليجرام وتحويلها لأوردرات بضغطة زر',
            dependencyInfo: 'يعتمد على: الحجز المسبق',
            isCore: false,
            isEnabled: state.features[FeatureKeys.telegramBot] ?? true,
            onChanged: (v) => _toggleFeature(context, FeatureKeys.telegramBot, v, userId),
          ),
          Divider(height: 16, color: AppColors.outlineVariant),
          _buildFeatureItem(
            key: const Key('feature_whatsapp_direct_toggle'),
            title: 'تنبيهات وتحديثات العملاء عبر واتساب (WhatsApp Direct)',
            description: 'أزرار مراسلة فورية للعميل برقم التتبع وتنبيهه عند وصول الشحنة للمحل واستحقاق المتبقي',
            dependencyInfo: 'يعتمد على: الحجز المسبق',
            isCore: false,
            isEnabled: state.features[FeatureKeys.whatsappDirect] ?? true,
            onChanged: (v) => _toggleFeature(context, FeatureKeys.whatsappDirect, v, userId),
          ),
        ],
      ),
    );
  }

  // ─── 4. كارت مزايا الحسابات والورديات والأمان ───
  Widget _buildFinancialAndSecurityFeaturesCard(SettingsState state, String userId) {
    return _cardWrapper(
      child: Column(
        children: [
          _cardHeader(
            icon: Icons.admin_panel_settings_rounded,
            title: 'مزايا الحسابات والورديات والأمان',
            subtitle: 'إدارة دورة الكاش، إغلاق الوردية، التقارير المالية، وصلاحيات الحماية',
          ),
          Divider(height: 24, color: AppColors.outlineVariant),
          _buildFeatureItem(
            key: const Key('feature_shifts_toggle'),
            title: 'إدارة الورديات وتقفيل الكاشير (Shift Z-Report)',
            description: 'إلزام الكاشير بفتح وردية وتحديد العهدة الافتتاحية وجرد الدرج النقدي عند تقفيل الوردية',
            isCore: false,
            isEnabled: state.features[FeatureKeys.shifts] ?? true,
            onChanged: (v) => _toggleFeature(context, FeatureKeys.shifts, v, userId),
          ),
          Divider(height: 16, color: AppColors.outlineVariant),
          _buildFeatureItem(
            key: const Key('feature_blind_shift_closing_toggle'),
            title: 'الجرد الأعمى عند تقفيل الوردية (Blind Shift Closing)',
            description: 'إخفاء الرصيد المتوقع للدرج وإلزام الكاشير بعدّ النقدية يدوياً لمنع التلاعب وتوليد تقرير العجز/الزيادة للمدير فقط',
            dependencyInfo: 'يعتمد على: الورديات',
            isCore: false,
            isEnabled: state.features[FeatureKeys.blindShiftClosing] ?? false,
            onChanged: (v) => _toggleFeature(context, FeatureKeys.blindShiftClosing, v, userId),
          ),
          Divider(height: 16, color: AppColors.outlineVariant),
          _buildFeatureItem(
            key: const Key('feature_drawer_petty_cash_toggle'),
            title: 'حركات الدرج النقدية (مصروفات نثرية / إيداع)',
            description: 'تمكين أزرار السحب والإيداع السريع للنقدية من درج الكاشير أثناء الوردية مع تدوين السبب',
            dependencyInfo: 'يعتمد على: الورديات',
            isCore: false,
            isEnabled: state.features[FeatureKeys.drawerPettyCash] ?? true,
            onChanged: (v) => _toggleFeature(context, FeatureKeys.drawerPettyCash, v, userId),
          ),
          Divider(height: 16, color: AppColors.outlineVariant),
          _buildFeatureItem(
            key: const Key('feature_expenses_toggle'),
            title: 'المصروفات اليومية وسجل النثريات',
            description: 'تسجيل بنود المصروفات التشغيلية اليومية والإيجارات والفواتير وخصمها من الخزينة العامة',
            isCore: false,
            isEnabled: state.features[FeatureKeys.expenses] ?? true,
            onChanged: (v) => _toggleFeature(context, FeatureKeys.expenses, v, userId),
          ),
          Divider(height: 16, color: AppColors.outlineVariant),
          _buildFeatureItem(
            key: const Key('feature_reports_toggle'),
            title: 'التقارير المالية والتحليلية',
            description: 'لوحات مؤشرات الأداء، الأرباح، تقارير الضرائب، وحركة المبيعات والمنتجات الأكثر مبيعاً',
            isCore: false,
            isEnabled: state.features[FeatureKeys.reports] ?? true,
            onChanged: (v) => _toggleFeature(context, FeatureKeys.reports, v, userId),
          ),
          Divider(height: 16, color: AppColors.outlineVariant),
          _buildFeatureItem(
            key: const Key('feature_partners_toggle'),
            title: 'حسابات الشركاء وتوزيع الأرباح',
            description: 'إدارة حصص الشركاء ورؤوس الأموال، تسجيل المسحوبات، وتوزيع الأرباح الصافية',
            isCore: false,
            isEnabled: state.features[FeatureKeys.partners] ?? false,
            onChanged: (v) => _toggleFeature(context, FeatureKeys.partners, v, userId),
          ),
          Divider(height: 16, color: AppColors.outlineVariant),
          _buildFeatureItem(
            key: const Key('feature_employees_toggle'),
            title: 'شؤون الموظفين وفريق العمل',
            description: 'إدارة ملفات الموظفين، ساعات العمل، والصلاحيات الوظيفية',
            isCore: false,
            isEnabled: state.features[FeatureKeys.employees] ?? true,
            onChanged: (v) => _toggleFeature(context, FeatureKeys.employees, v, userId),
          ),
          Divider(height: 16, color: AppColors.outlineVariant),
          _buildFeatureItem(
            key: const Key('feature_payroll_toggle'),
            title: 'مسير الرواتب والمستحقات',
            description: 'احتساب الرواتب الشهرية، الخصومات، البدلات، والمكافآت وترحيلها للخزينة',
            dependencyInfo: 'يعتمد على: الموظفون',
            isCore: false,
            isEnabled: state.features[FeatureKeys.payroll] ?? true,
            onChanged: (v) => _toggleFeature(context, FeatureKeys.payroll, v, userId),
          ),
          Divider(height: 16, color: AppColors.outlineVariant),
          _buildFeatureItem(
            key: const Key('feature_manager_pin_protection_toggle'),
            title: 'طلب الرقم السري للمدير عند الخصم أو المرتجع',
            description: 'قفل عمليات الخصم العالي أو إلغاء واسترجاع الفواتير بطلب PIN المدير لمنع تلاعب الكاشير',
            isCore: false,
            isEnabled: state.features[FeatureKeys.managerPinProtection] ?? false,
            onChanged: (v) => _toggleFeature(context, FeatureKeys.managerPinProtection, v, userId),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Color(0xFF0F172A),
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _cardWrapper({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(18),
    Key? key,
  }) {
    return Card(
      key: key,
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.outlineVariant),
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }

  Widget _cardHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14.5,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureItem({
    required String title,
    required String description,
    required bool isEnabled,
    required bool isCore,
    String? dependencyInfo,
    ValueChanged<bool>? onChanged,
    Key? key,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    if (isCore) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 11,
                              color: Color(0xFF64748B),
                            ),
                            SizedBox(width: 3),
                            Text(
                              'أساسي مفعّل',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    height: 1.35,
                  ),
                ),
                if (dependencyInfo != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      dependencyInfo,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFD97706),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 14),
          if (isCore)
            const Switch(
              value: true,
              onChanged: null,
            )
          else
            Switch(
              key: key,
              value: isEnabled,
              onChanged: onChanged,
              activeThumbColor: AppColors.primary,
            ),
        ],
      ),
    );
  }
}

// ─── Sidebar Nav Item Widget ───
class _SidebarNavItem extends StatelessWidget {
  final _SettingsCategoryItem item;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarNavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: selected
                  ? Border.all(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      width: 1.2,
                    )
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primary
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    item.icon,
                    size: 18,
                    color: selected ? Colors.white : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.w600,
                          color: selected
                              ? AppColors.primary
                              : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        item.subtitle,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: selected
                              ? AppColors.primary.withValues(alpha: 0.8)
                              : const Color(0xFF94A3B8),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Category Header Widget ───
class _CategoryHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;

  const _CategoryHeader({
    required this.icon,
    required this.label,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Cashier Permissions Settings Card ───
class _CashierPermissionsSettingsCard extends StatefulWidget {
  final String userId;

  const _CashierPermissionsSettingsCard({required this.userId});

  @override
  State<_CashierPermissionsSettingsCard> createState() =>
      _CashierPermissionsSettingsCardState();
}

class _CashierPermissionsSettingsCardState
    extends State<_CashierPermissionsSettingsCard> {
  late CashierPermissionsConfig _config;

  @override
  void initState() {
    super.initState();
    _config = CashierPermissionsService.current;
  }

  Future<void> _update(CashierPermissionsConfig newConfig) async {
    setState(() => _config = newConfig);
    final gate = getIt<FeatureGate>();
    await CashierPermissionsService.save(
      gate,
      newConfig,
      userId: widget.userId,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تحديث صلاحيات الكاشير بنجاح'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.shield_rounded, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'صلاحيات الكاشير الموثوق (Trusted Cashier)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14.5,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'حدد الميزات المسموح بها للكاشير، وتظل باقي العمليات الحساسة محجوبة للمدير فقط.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Divider(height: 24, color: AppColors.outlineVariant),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('السماح بالبيع الآجل (على الحساب)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              subtitle: const Text('تمكين الكاشير من اختيار الدفع الآجل وربط الفاتورة بمديونية العميل', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              activeThumbColor: AppColors.primary,
              value: _config.allowCreditSale,
              onChanged: (v) => _update(_config.copyWith(allowCreditSale: v)),
            ),
            Divider(height: 1, color: AppColors.outlineVariant),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('السماح ببيع الأقساط (عقود التقسيط)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              subtitle: const Text('تمكين الكاشير من إنشاء وجدولة عقود أقساط جديدة للعميل من شاشة البيع', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              activeThumbColor: AppColors.primary,
              value: _config.allowInstallments,
              onChanged: (v) => _update(_config.copyWith(allowInstallments: v)),
            ),
            Divider(height: 1, color: AppColors.outlineVariant),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('السماح باستلام شحنات بضاعة للمخزن', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              subtitle: const Text('إظهار شاشة استلام البضاعة (الشحنة الجديدة) وتحديث كميات المخزن', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              activeThumbColor: AppColors.primary,
              value: _config.allowGoodsIntake,
              onChanged: (v) => _update(_config.copyWith(allowGoodsIntake: v)),
            ),
            Divider(height: 1, color: AppColors.outlineVariant),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('السماح بإضافة وتعديل بيانات العملاء', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              subtitle: const Text('إتاحة شاشة سجل العملاء للكاشير لتسجيل عميل جديد أو تحديث بياناته', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              activeThumbColor: AppColors.primary,
              value: _config.allowManageCustomers,
              onChanged: (v) => _update(_config.copyWith(allowManageCustomers: v)),
            ),
            Divider(height: 1, color: AppColors.outlineVariant),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('السماح بتسجيل مصروفات نثرية من الدرج', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              subtitle: const Text('تمكين الكاشير من إثبات مصاريف يومية صغيرة (بوفيه/نظافة) تخصم من الدرج', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              activeThumbColor: AppColors.primary,
              value: _config.allowCashExpenses,
              onChanged: (v) => _update(_config.copyWith(allowCashExpenses: v)),
            ),
            Divider(height: 1, color: AppColors.outlineVariant),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('السماح بالاطلاع على سجل الفواتير العامة', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              subtitle: const Text('إتاحة فواتير المحل والورديات السابقة كاملة (بدلاً من الاقتصار على فواتير ورديته)', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              activeThumbColor: AppColors.primary,
              value: _config.allowViewInvoicesHistory,
              onChanged: (v) => _update(_config.copyWith(allowViewInvoicesHistory: v)),
            ),
            Divider(height: 1, color: AppColors.outlineVariant),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('السماح بخصم يدوي استثنائي على الفاتورة', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              subtitle: const Text('تمكين الكاشير من إدخال خصم يدوي إضافي دون طلب موافقة المدير', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              activeThumbColor: AppColors.primary,
              value: _config.allowManualDiscount,
              onChanged: (v) => _update(_config.copyWith(allowManualDiscount: v)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Installment Settings Section ───
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
      return Card(
        key: const Key('installment_settings_section'),
        elevation: 0,
        margin: EdgeInsets.zero,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.outlineVariant),
        ),
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final pinSvc = getIt<ManagerPinService>();
    return Card(
      key: const Key('installment_settings_section'),
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            SwitchListTile(
              key: const Key('installment_pin_required_toggle'),
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'طلب الرقم السري للمدير (Manager PIN) في التقسيط',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
              ),
              subtitle: const Text(
                'تأكيد المدير عند إنشاء عقد تقسيط، تسجيل دفعة، التسوية المبكرة، أو الإلغاء',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              activeThumbColor: AppColors.primary,
              value: _pinRequired,
              onChanged: (v) async {
                final uid = _userId(context);
                await pinSvc.setPinRequired(required: v, userId: uid);
                if (mounted) {
                  setState(() => _pinRequired = v);
                }
              },
            ),
            Divider(height: 16, color: AppColors.outlineVariant),
            ListTile(
              contentPadding: EdgeInsets.zero,
              enabled: _pinRequired,
              title: const Text(
                'الرقم السري للمدير',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
              ),
              subtitle: Text(
                !_pinRequired
                    ? 'معطّل حالياً في التقسيط'
                    : (_pinSet ? 'الرقم السري مُعيَّن' : 'لم يتم تعيين الرقم السري بعد'),
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              trailing: OutlinedButton(
                onPressed: _pinRequired ? () => _showSetPinDialog(context) : null,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(_pinSet ? 'تغيير' : 'تعيين'),
              ),
            ),
          ],
        ),
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

// ─── Credit Sales Settings Section ───
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
      return Card(
        key: const Key('credit_settings_section'),
        elevation: 0,
        margin: EdgeInsets.zero,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.outlineVariant),
        ),
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final pinSvc = getIt<ManagerPinService>();
    final state = context.watch<SettingsCubit>().state;
    final creditEnabled = state.creditPaymentEnabled;

    return Card(
      key: const Key('credit_settings_section'),
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            SwitchListTile(
              key: const Key('credit_sales_enabled_toggle'),
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'تفعيل الدفع الآجل في الكاشير (نقطة البيع)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
              ),
              subtitle: const Text(
                'إظهار طريقة الدفع "آجل" في شاشة البيع، مع تسجيل الفواتير في ذمة العميل',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              activeThumbColor: AppColors.primary,
              value: creditEnabled,
              onChanged: (v) async {
                final err = await context
                    .read<SettingsCubit>()
                    .setPaymentMethod('payment.credit', v, widget.userId);
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
            Divider(height: 16, color: AppColors.outlineVariant),
            SwitchListTile(
              key: const Key('credit_sales_pin_required_toggle'),
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'طلب الرقم السري للمدير عند البيع الآجل',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
              ),
              subtitle: const Text(
                'طلب موافقة وتأكيد المدير برقم الـ PIN عند إتمام أي عملية بيع بالآجل',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              activeThumbColor: AppColors.primary,
              value: _creditPinRequired,
              onChanged: (v) async {
                await pinSvc.setCreditPinRequired(
                  required: v,
                  userId: widget.userId,
                );
                if (mounted) {
                  setState(() => _creditPinRequired = v);
                }
              },
            ),
            Divider(height: 16, color: AppColors.outlineVariant),
            ListTile(
              contentPadding: EdgeInsets.zero,
              enabled: _creditPinRequired,
              title: const Text(
                'الرقم السري للمدير (Manager PIN) للآجل',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
              ),
              subtitle: Text(
                !_creditPinRequired
                    ? 'معطّل حالياً في البيع الآجل — لن يُطلب الرقم السري'
                    : (_pinSet ? 'الرقم السري مُعيَّن' : 'لم يتم تعيين الرقم السري بعد'),
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              trailing: OutlinedButton(
                onPressed: _creditPinRequired ? () => _showSetPinDialog(context) : null,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(_pinSet ? 'تغيير' : 'تعيين'),
              ),
            ),
            Divider(height: 16, color: AppColors.outlineVariant),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'ملاحظة: يمكن للمدير تحديد "الحد الأقصى للآجل (الائتماني)" لكل عميل من شاشة سجل العملاء. في حال تجاوز العميل للحد الائتماني، يلزم النظام إدخال الرقم السري للمدير للموافقة على الاستثناء.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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

// ─── Branding Settings Card ───
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
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. System / Store Name
            TextField(
              key: const Key('branding_app_name_field'),
              controller: _nameCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'اسم النظام / المتجر',
                hintText: 'مثال: متجر بيعة',
                prefixIcon: Icon(Icons.storefront_rounded, color: _selectedPrimary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 20),

            // 2. Curated Theme Color Presets
            const Text(
              'اختر قالباً لونياً للهوية:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Color(0xFF0F172A),
              ),
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
                          ? preset.primary.withValues(alpha: 0.08)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? preset.primary
                            : AppColors.outlineVariant,
                        width: isSelected ? 1.8 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: preset.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, color: Colors.white, size: 13)
                              : null,
                        ),
                        const SizedBox(width: 4),
                        Container(
                          width: 15,
                          height: 15,
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
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

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
            const SizedBox(height: 18),

            // 4. Live Preview Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            const SizedBox(height: 20),

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
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  key: const Key('branding_save_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
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

// ─── Receipt Customizer Settings Card ───
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
          margin: EdgeInsets.zero,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppColors.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.receipt_long_rounded,
                    color: AppColors.primary,
                    size: 26,
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
                          fontSize: 14.5,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'مقاس: ${cfg.paperWidthMm} مم | هاتف: ${cfg.storePhone} | عنوان: ${cfg.storeAddress}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
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
                  label: const Text('تخصيص الفاتورة'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Barcode Customizer Settings Card ───
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
          margin: EdgeInsets.zero,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppColors.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.qr_code_2_rounded,
                    color: AppColors.primary,
                    size: 26,
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
                          fontSize: 14.5,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'المقاس: ${cfg.selectedSize.name} | السعر: ${cfg.showPrice ? "مفعل" : "معطل"} | المقاس واللون: ${cfg.showColorAndSize ? "مفعل" : "معطل"}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
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

// ─── Sector Mode Settings Card ───
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
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppColors.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.storefront_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'تخصيص نمط النظام لنشاط المحل',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'اختر نوع نشاط متجرك لتكييف شاشات إضافة المنتجات والكاشير وسلوك الماسح الضوئي تلقائياً.',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 16),
                for (final opt in options) ...[
                  InkWell(
                    key: Key('sector_tile_${opt.key}'),
                    borderRadius: BorderRadius.circular(10),
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
                            ? opt.color.withValues(alpha: 0.06)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: currentMode == opt.key
                              ? opt.color
                              : AppColors.outlineVariant,
                          width: currentMode == opt.key ? 1.8 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: currentMode == opt.key
                                  ? opt.color
                                  : const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              opt.icon,
                              color: currentMode == opt.key
                                  ? Colors.white
                                  : const Color(0xFF64748B),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      opt.title,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: currentMode == opt.key
                                            ? opt.color
                                            : const Color(0xFF0F172A),
                                      ),
                                    ),
                                    if (currentMode == opt.key)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: opt.color,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'النشط حالياً',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  opt.desc,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: Color(0xFF64748B),
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

// ─── Activities Master Settings Card ───
class _ActivitiesMasterSettingsCard extends StatefulWidget {
  final String userId;

  const _ActivitiesMasterSettingsCard({required this.userId});

  @override
  State<_ActivitiesMasterSettingsCard> createState() => _ActivitiesMasterSettingsCardState();
}

class _ActivitiesMasterSettingsCardState extends State<_ActivitiesMasterSettingsCard> {
  final _activityService = getIt<ActivitySettingsService>();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ActivityType>>(
      stream: _activityService.watchEnabledActivities(),
      builder: (context, snapshot) {
        final enabledActivities = snapshot.data ?? [ActivityType.clothing];

        return Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppColors.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.storefront_rounded, color: AppColors.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'أقسام المنتجات والأنشطة المتوفرة بالمحل',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'تفعيل أو إيقاف الأقسام يحدّث فورياً تبويبات الكاشير ونماذج إضافة المنتجات',
                            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        OutlinedButton.icon(
                          key: const Key('activities_select_all_btn'),
                          icon: const Icon(Icons.select_all_rounded, size: 16),
                          label: const Text(
                            'تحديد الكل',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () async {
                            await _activityService.setAllActivities(true, userId: widget.userId);
                          },
                        ),
                        OutlinedButton.icon(
                          key: const Key('activities_deselect_all_btn'),
                          icon: const Icon(Icons.deselect_rounded, size: 16),
                          label: const Text(
                            'إلغاء التحديد',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF64748B),
                            side: BorderSide(color: AppColors.outlineVariant),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () async {
                            await _activityService.setAllActivities(false, userId: widget.userId);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                Divider(height: 24, color: AppColors.outlineVariant),

                // Smart Store Presets Bar
                _buildPresetsSection(enabledActivities),
                const SizedBox(height: 20),

                // 6 Sectors with Checkbox Matrix
                for (final sector in ActivitySector.values) ...[
                  _buildSectorSection(
                    sector: sector,
                    enabledActivities: enabledActivities,
                  ),
                  if (sector != ActivitySector.values.last)
                    const SizedBox(height: 16),
                ],

                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.outlineVariant),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF64748B)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'قاعدة الأمان التجاري: يلزم النظام الإبقاء على قسم تجاري واحد مفعل على الأقل لضمان استقرار العمل.',
                          style: TextStyle(fontSize: 11.5, color: Color(0xFF475569)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPresetsSection(List<ActivityType> enabledActivities) {
    final activePreset = StorePreset.detect(enabledActivities.toSet());

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Text(
                    'القوالب التجارية الجاهزة (تجهيز المتجر بنقرة واحدة):',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'القالب الحالي: ${activePreset.title}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'اختر نوع نشاط محلك لتجهيز وتفعيل الأقسام المناسبة وإعداداتها فوراً، أو عدّل الأنشطة يدوياً من المصفوفة بالأسفل.',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final preset in StorePreset.values) ...[
                  _buildPresetCard(
                    preset: preset,
                    isActive: activePreset == preset,
                  ),
                  if (preset != StorePreset.values.last)
                    const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetCard({
    required StorePreset preset,
    required bool isActive,
  }) {
    return InkWell(
      key: Key('store_preset_${preset.code}'),
      onTap: () async {
        try {
          await _activityService.applyStorePreset(preset, userId: widget.userId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('تم تطبيق قالب ${preset.title} بنجاح!'),
                backgroundColor: AppColors.primary,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(e.toString().replaceAll('Exception: ', '')),
                backgroundColor: AppColors.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? AppColors.primary : AppColors.outlineVariant,
            width: isActive ? 1.6 : 1.0,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: isActive ? AppColors.primary : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                preset.icon,
                size: 16,
                color: isActive ? Colors.white : const Color(0xFF475569),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      preset.title,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                        color: isActive ? AppColors.primary : const Color(0xFF0F172A),
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'نشط',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  preset.description,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isActive ? AppColors.primary.withValues(alpha: 0.8) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectorSection({
    required ActivitySector sector,
    required List<ActivityType> enabledActivities,
  }) {
    final sectorActivities = ActivityType.values.where((a) => a.sector == sector).toList();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sector Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
              border: Border(bottom: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.7))),
            ),
            child: Row(
              children: [
                Icon(sector.icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  sector.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                Text(
                  '${sectorActivities.where((a) => enabledActivities.contains(a)).length} من ${sectorActivities.length} مفعل',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // Activities List with Checkboxes
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              children: [
                for (int i = 0; i < sectorActivities.length; i++) ...[
                  _buildActivityCheckboxRow(
                    act: sectorActivities[i],
                    isEnabled: enabledActivities.contains(sectorActivities[i]),
                  ),
                  if (i != sectorActivities.length - 1)
                    Divider(height: 1, color: AppColors.outlineVariant.withValues(alpha: 0.5)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityCheckboxRow({
    required ActivityType act,
    required bool isEnabled,
  }) {
    return InkWell(
      onTap: () => _toggleActivity(act, !isEnabled),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: isEnabled ? AppColors.primary.withValues(alpha: 0.08) : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isEnabled ? AppColors.primary.withValues(alpha: 0.3) : AppColors.outlineVariant,
                ),
              ),
              child: Icon(
                act.icon,
                size: 17,
                color: isEnabled ? AppColors.primary : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    act.labelArabic,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isEnabled ? FontWeight.bold : FontWeight.w600,
                      color: isEnabled ? const Color(0xFF0F172A) : const Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _activityDescription(act),
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            Checkbox(
              key: Key('activity_checkbox_${act.code}'),
              value: isEnabled,
              activeColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              onChanged: (val) => _toggleActivity(act, val ?? false),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleActivity(ActivityType act, bool enable) async {
    try {
      await _activityService.setActivityEnabled(act, enable, userId: widget.userId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  static String _activityDescription(ActivityType type) {
    switch (type) {
      case ActivityType.clothing:
        return 'إدارة المقاسات والألوان ومصفوفة أصناف الملابس الجاهزة';
      case ActivityType.footwearBags:
        return 'مقاسات الأحذية، كولكشن الحقائب والجلديات ومستلزماتها';
      case ActivityType.accessoriesBeauty:
        return 'المجوهرات والإكسسوارات الفردية وقطع الزينة';
      case ActivityType.perfumesCosmetics:
        return 'مستحضرات التجميل، العطور، السعة بالمللي، وتواريخ الصلاحية';
      case ActivityType.watchesEyewear:
        return 'الساعات، النظارات الشمسية والطبية، وفترات الضمان';
      case ActivityType.electronicsMobiles:
        return 'الهواتف، الأجهزة الذكية، تتبع السيريال والـ IMEI والتقسيط';
      case ActivityType.homeLiving:
        return 'الأجهزة الكهربائية، الأدوات المنزلية، الموديلات وفترات الضمان';
      case ActivityType.supermarketGroceries:
        return 'المواد الغذائية، البقالة، باركود الميزان، وتواريخ الصلاحية';
      case ActivityType.spicesNuts:
        return 'العطارة، التوابل، المكسرات والياميش بالوزن (كيلو/جرام)';
      case ActivityType.sweetsBakery:
        return 'الحلويات الشرقية والغربية، المخبوزات والقطع الطازجة';
      case ActivityType.restaurantsCafes:
        return 'المطاعم والكافيهات، الصالة والتيك أواي والدليفري وبون المطبخ';
      case ActivityType.kidsToys:
        return 'ألعاب الأطفال، الهدايا، ومستلزمات المواليد والرضع';
      case ActivityType.pharmacySupplies:
        return 'الصيدليات، المستلزمات الطبية، الباتشات وتواريخ الصلاحية';
      case ActivityType.sportsFitness:
        return 'الملابس الرياضية، الأجهزة، المكملات الغذائية ومعدات الجيم';
      case ActivityType.bookstoreStationery:
        return 'الكتب، الأدوات المدرسية والمكتبية، الروايات والمطبوعات';
      case ActivityType.textilesDecor:
        return 'المفروشات، الستائر، أقمشة الديكور، ومقاييس الأمتار';
      case ActivityType.petShop:
        return 'أغذية ومستلزمات الحيوانات الأليفة، الأوزان والتطعيمات';
      case ActivityType.general:
        return 'الأصناف العامة والمتنوعة والمنتجات غير المصنفة بنشاط خاص';
    }
  }
}

// ─── Telegram Bot Settings Card ───
class _TelegramBotSettingsCard extends StatefulWidget {
  final String userId;

  const _TelegramBotSettingsCard({required this.userId});

  @override
  State<_TelegramBotSettingsCard> createState() => _TelegramBotSettingsCardState();
}

class _TelegramBotSettingsCardState extends State<_TelegramBotSettingsCard> {
  final _botService = getIt<TelegramBotService>();
  final _tokenController = TextEditingController();
  bool _isLoading = false;
  bool _testingConnection = false;
  String? _statusMessage;
  bool _isSuccessStatus = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final token = await _botService.getBotToken();
    if (mounted) {
      setState(() {
        _tokenController.text = token ?? '';
        _isLoading = false;
      });
    }
  }

  Future<void> _testAndSave() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() {
        _statusMessage = 'يرجى إدخال توكن البوت';
        _isSuccessStatus = false;
      });
      return;
    }

    setState(() {
      _testingConnection = true;
      _statusMessage = null;
    });

    final res = await _botService.testBotToken(token);
    if (!mounted) return;

    res.fold(
      (err) {
        setState(() {
          _testingConnection = false;
          _statusMessage = 'فشل الاتصال: $err';
          _isSuccessStatus = false;
        });
      },
      (botData) async {
        final username = botData['username']?.toString() ?? '';
        final botName = botData['first_name']?.toString() ?? '';
        await _botService.saveBotToken(token, userId: widget.userId);
        if (username.isNotEmpty) {
          await _botService.saveBotUsername(username, userId: widget.userId);
        }
        if (mounted) {
          setState(() {
            _testingConnection = false;
            _statusMessage = 'تم الاتصال بنجاح بالبوت: $botName (@$username)';
            _isSuccessStatus = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('تم التحقق من البوت وحفظ الإعدادات بنجاح'),
              backgroundColor: AppColors.primary,
            ),
          );
        }
      },
    );
  }

  Future<void> _pullMessages() async {
    setState(() => _testingConnection = true);
    final res = await _botService.fetchNewMessages();
    if (!mounted) return;
    setState(() => _testingConnection = false);

    res.fold(
      (err) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: AppColors.error),
        );
      },
      (count) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(count > 0 ? 'تم سحب $count طلب جديد بنجاح' : 'صندوق الوارد محدث، لا توجد طلبات جديدة حالياً'),
            backgroundColor: AppColors.primary,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.send_rounded, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مجمع وارد تيليجرام المجاني المباشر',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14.5,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'استقبال حجوزات وطلبيات الزبائن مباشرة بدون وسطاء وبصفر تكلفة اشتراكات',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Divider(height: 24, color: AppColors.outlineVariant),

            const Text(
              'توكن البوت (Telegram Bot Token) *',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _tokenController,
              decoration: InputDecoration(
                hintText: '123456789:ABCdefGHIjklmNoPQRsTUVwxyZ',
                prefixIcon: const Icon(Icons.key_rounded, size: 18),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () => _tokenController.clear(),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.outlineVariant),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'احصل على التوكن مجاناً وبثوانٍ عبر مراسلة @BotFather داخل تطبيق تيليجرام وإنشاء بوت جديد.',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
            ),

            if (_statusMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _isSuccessStatus ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isSuccessStatus ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isSuccessStatus ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                      size: 18,
                      color: _isSuccessStatus ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: _isSuccessStatus ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _testingConnection ? null : _testAndSave,
                  icon: _testingConnection
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.verified_outlined, size: 16),
                  label: const Text('تحقق من صحة البوت وحفظ'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _testingConnection ? null : _pullMessages,
                  icon: const Icon(Icons.sync_rounded, size: 16),
                  label: const Text('سحب الرسائل الجديدة الآن'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => const TelegramInboxDialog(),
                    );
                  },
                  icon: const Icon(Icons.inbox_rounded, size: 16),
                  label: const Text('فتح صندوق وارد تيليجرام'),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
