import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/database/tx_writer.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/keyboard_focus_helper.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/standard_date_filter_chips.dart';
import '../../data/services/mobile_wallets_service.dart';

class WalletsScreen extends StatefulWidget {
  const WalletsScreen({super.key});

  @override
  State<WalletsScreen> createState() => _WalletsScreenState();
}

class _WalletsScreenState extends State<WalletsScreen> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  String? _selectedWalletId;
  List<CashWallet> _wallets = [];
  List<WalletTransaction> _transactions = [];
  bool _isLoading = true;
  String _activeDateFilter = 'all';
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  MobileWalletsService _resolveService() {
    if (getIt.isRegistered<MobileWalletsService>()) {
      return getIt<MobileWalletsService>();
    }
    final db = getIt<AppDatabase>();
    final bp = getIt.isRegistered<BranchProvider>()
        ? getIt<BranchProvider>()
        : BranchProvider(db);
    final tx = getIt.isRegistered<TxWriter>() ? getIt<TxWriter>() : TxWriter(db);
    return MobileWalletsService(db, bp, tx);
  }

  Future<void> _loadData() async {
    try {
      final svc = _resolveService();
      final wallets = await svc.getWallets();
      final txs = await svc.getRecentTransactions(
        walletId: _selectedWalletId,
        limit: 100,
      );
      if (!mounted) return;
      setState(() {
        _wallets = wallets;
        _transactions = txs;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<CashWallet> get _filteredWallets {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _wallets;
    return _wallets.where((w) {
      return w.name.toLowerCase().contains(q) ||
          w.phoneOrTerminal.toLowerCase().contains(q) ||
          MobileWalletsService.providerLabel(w.providerType)
              .toLowerCase()
              .contains(q);
    }).toList();
  }

  Future<void> _openAddWalletDialog() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AddWalletDialog(service: _resolveService()),
    );
    if (created == true) {
      await _loadData();
    }
  }

  Future<void> _openTransactionDialog({String? initialWalletId}) async {
    if (_wallets.isEmpty) {
      await _openAddWalletDialog();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _WalletOperationDialog(
        service: _resolveService(),
        wallets: _wallets.where((w) => w.isActive).toList(),
        initialWalletId: initialWalletId ?? _selectedWalletId,
      ),
    );
    if (ok == true) {
      await _loadData();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.f2) {
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f3 ||
        (key == LogicalKeyboardKey.numpadAdd && !isEditableTextFocused())) {
      _openTransactionDialog();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_searchCtrl.text.isNotEmpty || _selectedWalletId != null) {
        setState(() {
          _searchCtrl.clear();
          _query = '';
          _selectedWalletId = null;
        });
        _loadData();
        return KeyEventResult.handled;
      }
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final totalBalance = _wallets.fold<int>(0, (s, w) => s + w.currentBalance);
    final totalCommissions = _transactions
        .where((t) => t.type != 'topup_from_drawer')
        .fold<int>(0, (s, t) => s + t.commission);
    final filtered = _filteredWallets;
    final walletById = {for (final w in _wallets) w.id: w};
    final dateFmt = DateFormat('yyyy/MM/dd hh:mm a');

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('المحافظ الإلكترونية وشحن الكاش والتحويلات'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.onSurface,
          elevation: 0,
          actions: [
            OutlinedButton.icon(
              key: const Key('wallets_add_wallet_btn'),
              onPressed: _openAddWalletDialog,
              icon: Icon(Icons.add_card_rounded, color: AppColors.primary, size: 18),
              label: const Text('إضافة خط / محفظة'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              key: const Key('wallets_new_tx_btn'),
              onPressed: () => _openTransactionDialog(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: const Text('عملية جديدة [F3]'),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryMetricCard(
                            title: 'إجمالي أرصدة المحافظ',
                            value: '${Money(totalBalance).toDisplay()} ج.م',
                            icon: Icons.account_balance_wallet_rounded,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SummaryMetricCard(
                            title: 'عدد الخطوط النشطة',
                            value: '${_wallets.where((w) => w.isActive).length}',
                            icon: Icons.sim_card_rounded,
                            color: AppColors.secondary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SummaryMetricCard(
                            title: 'إجمالي العمولات (صافي الربح)',
                            value: '${Money(totalCommissions).toDisplay()} ج.م',
                            icon: Icons.trending_up_rounded,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const Key('wallets_search_field'),
                      controller: _searchCtrl,
                      focusNode: _searchFocus,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: 'ابحث باسم المحفظة أو رقم الخط أو المزود... [F2]',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: filtered.isEmpty
                                ? Center(
                                    child: Text(
                                      'لا توجد محافظ مسجلة بعد. اضغط "إضافة خط / محفظة".',
                                      style: TextStyle(color: AppColors.onSurfaceVariant),
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: filtered.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (context, index) {
                                      final w = filtered[index];
                                      final isSelected = _selectedWalletId == w.id;
                                      final hasLimit = w.monthlyLimit > 0;
                                      final ratio = hasLimit
                                          ? (w.monthlyUsed / w.monthlyLimit)
                                              .clamp(0.0, 1.0)
                                          : 0.0;
                                      final remaining = hasLimit
                                          ? (w.monthlyLimit - w.monthlyUsed)
                                          : 0;
                                      final barColor = ratio >= 0.95
                                          ? AppColors.error
                                          : (ratio >= 0.8
                                              ? AppColors.warning
                                              : AppColors.primary);

                                      return InkWell(
                                        onTap: () {
                                          setState(() {
                                            _selectedWalletId =
                                                isSelected ? null : w.id;
                                          });
                                          _loadData();
                                        },
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: AppColors.surface,
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: isSelected
                                                  ? AppColors.primary
                                                  : Colors.grey.shade300,
                                              width: isSelected ? 1.8 : 1,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.sim_card_outlined,
                                                    color: AppColors.primary,
                                                    size: 20,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      w.name,
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                  ),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.primary
                                                          .withValues(alpha: 0.1),
                                                      borderRadius:
                                                          BorderRadius.circular(8),
                                                    ),
                                                    child: Text(
                                                      MobileWalletsService
                                                          .providerLabel(
                                                        w.providerType,
                                                      ),
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w700,
                                                        color: AppColors.primary,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      w.phoneOrTerminal.isEmpty
                                                          ? 'بدون رقم خط'
                                                          : w.phoneOrTerminal,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: AppColors
                                                            .onSurfaceVariant,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Flexible(
                                                    child: Text(
                                                      'الرصيد: ${Money(w.currentBalance).toDisplay()} ج.م',
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: AppColors.success,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (hasLimit) ...[
                                                const SizedBox(height: 10),
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        'المتبقي من الحد الشهري: ${Money(remaining).toDisplay()} ج.م',
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: barColor,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      '${(ratio * 100).toStringAsFixed(0)}%',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: barColor,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  child: LinearProgressIndicator(
                                                    value: ratio,
                                                    minHeight: 7,
                                                    backgroundColor:
                                                        Colors.grey.shade200,
                                                    valueColor:
                                                        AlwaysStoppedAnimation<
                                                            Color>(barColor),
                                                  ),
                                                ),
                                              ],
                                              const SizedBox(height: 8),
                                              Align(
                                                alignment: Alignment.centerLeft,
                                                child: TextButton.icon(
                                                  onPressed: () =>
                                                      _openTransactionDialog(
                                                    initialWalletId: w.id,
                                                  ),
                                                  icon: const Icon(
                                                    Icons.flash_on_rounded,
                                                    size: 16,
                                                  ),
                                                  label: const Text('تنفيذ عملية'),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 6,
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedWalletId == null
                                        ? 'سجل عمليات المحافظ'
                                        : 'سجل عمليات: ${walletById[_selectedWalletId]?.name ?? ''}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const Divider(height: 18),
                                  StandardDateFilterChips(
                                    activeFilter: _activeDateFilter,
                                    customRange: _customRange,
                                    onFilterChanged: (v) =>
                                        setState(() => _activeDateFilter = v),
                                    onCustomRangePicked: (picked) => setState(() {
                                      _customRange = picked;
                                      _activeDateFilter = 'custom';
                                    }),
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: Builder(
                                      builder: (context) {
                                        final filteredTxs = _transactions
                                            .where(
                                              (tx) => StandardDateFilterChips.matchesDate(
                                                tx.createdAt,
                                                _activeDateFilter,
                                                _customRange,
                                              ),
                                            )
                                            .toList();
                                        if (filteredTxs.isEmpty) {
                                          return Center(
                                            child: Text(
                                              'لا توجد عمليات مسجلة',
                                              style: TextStyle(
                                                color: AppColors.onSurfaceVariant,
                                              ),
                                            ),
                                          );
                                        }
                                        return ListView.separated(
                                          itemCount: filteredTxs.length,
                                          separatorBuilder: (_, _) =>
                                              const Divider(height: 1),
                                          itemBuilder: (context, index) {
                                            final tx = filteredTxs[index];
                                              final walletName =
                                                  walletById[tx.walletId]?.name ??
                                                      'محفظة';
                                              return ListTile(
                                                dense: true,
                                                title: Text(
                                                  '${MobileWalletsService.transactionTypeLabel(tx.type)} - $walletName',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                subtitle: Text(
                                                  '${dateFmt.format(tx.createdAt)}'
                                                  '${tx.customerPhone != null ? ' | هاتف: ${tx.customerPhone}' : ''}'
                                                  '${tx.referenceNumber != null ? ' | مرجع: ${tx.referenceNumber}' : ''}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: AppColors.onSurfaceVariant,
                                                  ),
                                                ),
                                                trailing: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.end,
                                                  children: [
                                                    Text(
                                                      '${Money(tx.amount).toDisplay()} ج.م',
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                    if (tx.commission > 0)
                                                      Text(
                                                        'عمولة: +${Money(tx.commission).toDisplay()}',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: AppColors.success,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _SummaryMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryMetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
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

class _AddWalletDialog extends StatefulWidget {
  final MobileWalletsService service;

  const _AddWalletDialog({required this.service});

  @override
  State<_AddWalletDialog> createState() => _AddWalletDialogState();
}

class _AddWalletDialogState extends State<_AddWalletDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _balanceCtrl = TextEditingController(text: '0');
  final _limitCtrl = TextEditingController(text: '200000');
  String _providerType = 'vodafone_cash';
  bool _isSaving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _balanceCtrl.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSaving || _formKey.currentState?.validate() != true) return;
    setState(() => _isSaving = true);
    try {
      await widget.service.createWallet(
        name: _nameCtrl.text.trim(),
        providerType: _providerType,
        phoneOrTerminal: _phoneCtrl.text.trim(),
        initialBalancePiasters: Money.fromString(_balanceCtrl.text.trim()).piasters,
        monthlyLimitPiasters: Money.fromString(_limitCtrl.text.trim()).piasters,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(false),
        const SingleActivator(LogicalKeyboardKey.f12): _submit,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _submit,
      },
      child: AlertDialog(
        title: const Text('إضافة خط / محفظة إلكترونية'),
        content: SizedBox(
          width: 440,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    key: const Key('wallet_name_field'),
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم المحفظة / الخط *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _providerType,
                    decoration: const InputDecoration(
                      labelText: 'مزود الخدمة',
                      border: OutlineInputBorder(),
                    ),
                    items: MobileWalletsService.providerTypes
                        .map(
                          (p) => DropdownMenuItem(
                            value: p,
                            child: Text(MobileWalletsService.providerLabel(p)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _providerType = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('wallet_phone_field'),
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'رقم الخط أو كود الماكينة',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('wallet_balance_field'),
                    controller: _balanceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'الرصيد الافتتاحي (ج.م)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('wallet_limit_field'),
                    controller: _limitCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'الحد الشهري (ج.م، 0 = مفتوح)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
            child: const Text('إلغاء [Esc]'),
          ),
          ElevatedButton(
            key: const Key('wallet_save_btn'),
            onPressed: _isSaving ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('حفظ [F12]'),
          ),
        ],
      ),
    );
  }
}

class _WalletOperationDialog extends StatefulWidget {
  final MobileWalletsService service;
  final List<CashWallet> wallets;
  final String? initialWalletId;

  const _WalletOperationDialog({
    required this.service,
    required this.wallets,
    this.initialWalletId,
  });

  @override
  State<_WalletOperationDialog> createState() => _WalletOperationDialogState();
}

class _WalletOperationDialogState extends State<_WalletOperationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _commissionCtrl = TextEditingController(text: '0');
  final _phoneCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  late String _walletId;
  String _txType = 'deposit_out_transfer';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _walletId = widget.initialWalletId ??
        (widget.wallets.isNotEmpty ? widget.wallets.first.id : '');
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _commissionCtrl.dispose();
    _phoneCtrl.dispose();
    _refCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSaving || _formKey.currentState?.validate() != true) return;
    setState(() => _isSaving = true);
    try {
      await widget.service.executeTransaction(
        walletId: _walletId,
        type: _txType,
        amountPiasters: Money.fromString(_amountCtrl.text.trim()).piasters,
        commissionPiasters: _txType == 'topup_from_drawer'
            ? 0
            : Money.fromString(_commissionCtrl.text.trim()).piasters,
        customerPhone: _phoneCtrl.text.trim(),
        referenceNumber: _refCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(false),
        const SingleActivator(LogicalKeyboardKey.f12): _submit,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _submit,
      },
      child: AlertDialog(
        title: const Text('تنفيذ عملية محفظة إلكترونية'),
        content: SizedBox(
          width: 460,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _walletId,
                    decoration: const InputDecoration(
                      labelText: 'المحفظة / الخط *',
                      border: OutlineInputBorder(),
                    ),
                    items: widget.wallets
                        .map(
                          (w) => DropdownMenuItem(
                            value: w.id,
                            child: Text(
                              '${w.name} (${Money(w.currentBalance).toDisplay()} ج.م)',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _walletId = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _txType,
                    decoration: const InputDecoration(
                      labelText: 'نوع العملية *',
                      border: OutlineInputBorder(),
                    ),
                    items: MobileWalletsService.transactionTypes
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(
                              MobileWalletsService.transactionTypeLabel(t),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _txType = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const Key('wallet_tx_amount_field'),
                          controller: _amountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'المبلغ (ج.م) *',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            final p = Money.fromString(v ?? '').piasters;
                            return p <= 0 ? 'مبلغ غير صحيح' : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (_txType != 'topup_from_drawer')
                        Expanded(
                          child: TextFormField(
                            key: const Key('wallet_tx_commission_field'),
                            controller: _commissionCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'العمولة / الربح (ج.م)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('wallet_tx_phone_field'),
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'رقم هاتف العميل (اختياري)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('wallet_tx_ref_field'),
                    controller: _refCtrl,
                    decoration: const InputDecoration(
                      labelText: 'رقم المرجع (اختياري)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
            child: const Text('إلغاء [Esc]'),
          ),
          ElevatedButton(
            key: const Key('wallet_tx_submit_btn'),
            onPressed: _isSaving ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('تنفيذ [F12]'),
          ),
        ],
      ),
    );
  }
}

