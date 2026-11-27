import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/custom_date_range_dialog.dart';
import '../../data/services/daily_audit_service.dart';
import '../../domain/services/date_range_presets.dart';
import '../widgets/quick_date_range_bar.dart';

class DailyAuditExplorerScreen extends StatefulWidget {
  final DateTime? initialDate;
  final DateTime? initialEndDate;
  final QuickDatePreset? initialPreset;
  final bool embedded;

  const DailyAuditExplorerScreen({
    super.key,
    this.initialDate,
    this.initialEndDate,
    this.initialPreset,
    this.embedded = false,
  });

  @override
  State<DailyAuditExplorerScreen> createState() =>
      _DailyAuditExplorerScreenState();
}

class _DailyAuditExplorerScreenState extends State<DailyAuditExplorerScreen> {
  late DateTime _startDate;
  late DateTime _endDate;
  late QuickDatePreset _selectedPreset;
  bool _loading = true;
  String? _error;
  DailyAuditSnapshot? _snapshot;

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _paymentFilter = 'all';

  @override
  void initState() {
    super.initState();
    final baseStart = widget.initialDate ?? DateTime.now();
    final baseEnd = widget.initialEndDate ?? baseStart;
    _startDate = DateTime(baseStart.year, baseStart.month, baseStart.day);
    _endDate = DateTime(baseEnd.year, baseEnd.month, baseEnd.day);
    _selectedPreset = widget.initialPreset ??
        (_isSingleDay ? QuickDatePreset.today : QuickDatePreset.custom);
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _isSingleDay =>
      _startDate.year == _endDate.year &&
      _startDate.month == _endDate.month &&
      _startDate.day == _endDate.day;

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = DailyAuditService(getIt<AppDatabase>());
      final snap = await service.loadRange(_startDate, _endDate);
      if (!mounted) return;
      setState(() {
        _snapshot = snap;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pickRange() async {
    final picked = await showCustomDateRangeDialog(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked == null) return;
    setState(() {
      _startDate = DateTime(
        picked.start.year,
        picked.start.month,
        picked.start.day,
      );
      _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day);
      _selectedPreset = QuickDatePreset.custom;
    });
    _loadData();
  }

  String _fmtMoney(int piasters) => '${Money(piasters).toDisplay()} ج.م';

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _fmtMethod(String m) {
    switch (m.toLowerCase()) {
      case 'cash':
        return 'نقدي';
      case 'card':
      case 'visa':
        return 'بطاقة / فيزا';
      case 'credit':
        return 'آجل';
      case 'installment':
        return 'أقساط';
      default:
        return m;
    }
  }

  @override
  Widget build(BuildContext context) {
    final subTabs = TabBar(
      isScrollable: true,
      labelColor: AppColors.primary,
      unselectedLabelColor: Colors.grey,
      indicatorColor: AppColors.primary,
      tabs: const [
        Tab(text: 'الفواتير'),
        Tab(text: 'المرتجعات'),
        Tab(text: 'المصروفات'),
        Tab(text: 'الأقساط'),
        Tab(text: 'المشتريات والموردين'),
        Tab(text: 'الورديات والدرج'),
      ],
    );

    final content = Column(
      children: [
        _buildNavigatorAndSearch(),
        if (_snapshot != null && !_loading) _buildSummaryStrip(_snapshot!),
        if (widget.embedded)
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(
                top: BorderSide(color: Colors.grey.shade200),
                bottom: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: subTabs,
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(child: Text('حدث خطأ: $_error'))
              : TabBarView(
                  children: [
                    _buildSalesTab(_snapshot!),
                    _buildReturnsTab(_snapshot!),
                    _buildExpensesTab(_snapshot!),
                    _buildInstallmentsTab(_snapshot!),
                    _buildPurchasesTab(_snapshot!),
                    _buildShiftsTab(_snapshot!),
                  ],
                ),
        ),
      ],
    );

    if (widget.embedded) {
      return DefaultTabController(length: 6, child: content);
    }

    return DefaultTabController(
      length: 6,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'كشف اليوم والتاريخ الشامل',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: AppColors.onSurface,
                ),
              ),
              Text(
                'استعراض تفصيلي لكل فواتير ومصروفات ومرتجعات وأقساط وورديات أي يوم',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          bottom: subTabs,
        ),
        body: content,
      ),
    );
  }

  Widget _buildNavigatorAndSearch() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              QuickDateRangeBar(
                selectedPreset: _selectedPreset,
                customRange: DateTimeRange(start: _startDate, end: _endDate),
                onPresetSelected: (preset) async {
                  if (preset == QuickDatePreset.custom) {
                    await _pickRange();
                    return;
                  }
                  final resolved = DateRangeEngine.resolveRange(preset);
                  setState(() {
                    _selectedPreset = preset;
                    _startDate = DateTime(
                      resolved.start.year,
                      resolved.start.month,
                      resolved.start.day,
                    );
                    _endDate = DateTime(
                      resolved.end.year,
                      resolved.end.month,
                      resolved.end.day,
                    );
                  });
                  _loadData();
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  decoration: InputDecoration(
                    hintText:
                        'بحث برقم الفاتورة، اسم العميل، الصنف، الكاشير، المصروف، أو المورد...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: _paymentFilter,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('كل طرق الدفع')),
                  DropdownMenuItem(value: 'cash', child: Text('نقدي')),
                  DropdownMenuItem(value: 'card', child: Text('بطاقة / فيزا')),
                  DropdownMenuItem(value: 'credit', child: Text('آجل')),
                  DropdownMenuItem(value: 'installment', child: Text('أقساط')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _paymentFilter = v);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStrip(DailyAuditSnapshot s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.surface,
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          _kpiChip(
            'المبيعات (${s.sales.length})',
            _fmtMoney(s.totalSalesAmount),
            AppColors.primary,
          ),
          _kpiChip(
            'المرتجعات (${s.returns.length})',
            _fmtMoney(s.totalReturnsAmount),
            AppColors.error,
          ),
          _kpiChip(
            'المصروفات (${s.expenses.length})',
            _fmtMoney(s.totalExpensesAmount),
            Colors.orange.shade700,
          ),
          _kpiChip(
            'الأقساط (${s.installmentPayments.length})',
            _fmtMoney(s.totalInstallmentsAmount),
            Colors.teal,
          ),
          _kpiChip(
            'المشتريات (${s.purchases.length})',
            _fmtMoney(s.totalPurchasesAmount),
            Colors.indigo,
          ),
          _kpiChip(
            'الورديات (${s.shifts.length})',
            '${s.shifts.length} وردية',
            Colors.blueGrey,
          ),
        ],
      ),
    );
  }

  Widget _kpiChip(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  bool _matchesSearch(List<String?> fields) {
    if (_searchQuery.isEmpty) return true;
    final q = _searchQuery.toLowerCase();
    return fields.any((f) => f != null && f.toLowerCase().contains(q));
  }

  Widget _emptyState(String label) {
    return Center(
      child: Text(
        label,
        style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
      ),
    );
  }

  Widget _buildSalesTab(DailyAuditSnapshot s) {
    final list = s.sales.where((e) {
      if (_paymentFilter != 'all' &&
          e.sale.paymentMethod.toLowerCase() != _paymentFilter) {
        return false;
      }
      final itemNames = e.items.map((i) => i.productName).join(' ');
      return _matchesSearch([
        e.sale.shortRef,
        e.cashierName,
        e.customerName,
        e.sale.note,
        itemNames,
      ]);
    }).toList();

    if (list.isEmpty) {
      return _emptyState('لا توجد فواتير مطابقة في هذا التاريخ');
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, idx) {
        final entry = list[idx];
        final sale = entry.sale;
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: ExpansionTile(
            title: Row(
              children: [
                Text(
                  'فاتورة #${sale.shortRef}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _fmtMethod(sale.paymentMethod),
                    style: TextStyle(fontSize: 11, color: AppColors.primary),
                  ),
                ),
                const Spacer(),
                Text(
                  _fmtMoney(sale.total),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
            subtitle: Text(
              '${_fmtDate(sale.date)} ${_fmtTime(sale.date)} | الكاشير: ${entry.cashierName}'
              '${entry.customerName != null ? ' | العميل: ${entry.customerName}' : ''}'
              '${sale.discountAmount > 0 ? ' | خصم: ${_fmtMoney(sale.discountAmount)}' : ''}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            children: [
              if (entry.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('لا توجد أصناف مسجلة'),
                )
              else
                ...entry.items.map(
                  (item) => ListTile(
                    dense: true,
                    title: Text(
                      '${item.productName} (${item.color} - ${item.size})',
                    ),
                    subtitle: Text('الكمية: ${item.qty}'),
                    trailing: Text(
                      _fmtMoney(item.lineTotal),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReturnsTab(DailyAuditSnapshot s) {
    final list = s.returns
        .where(
          (e) => _matchesSearch([e.ret.reason, e.cashierName, e.ret.saleId]),
        )
        .toList();
    if (list.isEmpty) {
      return _emptyState('لا توجد مرتجعات في هذا التاريخ');
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, idx) {
        final e = list[idx];
        return Card(
          elevation: 0,
          child: ListTile(
            leading: Icon(
              Icons.assignment_return_outlined,
              color: AppColors.error,
            ),
            title: Text('مرتجع بقيمة ${_fmtMoney(e.ret.refundAmount)}'),
            subtitle: Text(
              '${_fmtDate(e.ret.date)} ${_fmtTime(e.ret.date)} | السبب: ${e.ret.reason} | الكاشير: ${e.cashierName}',
            ),
            trailing: Text(_fmtMethod(e.ret.paymentMethod)),
          ),
        );
      },
    );
  }

  Widget _buildExpensesTab(DailyAuditSnapshot s) {
    final list = s.expenses
        .where(
          (e) =>
              _matchesSearch([e.expense.category, e.expense.note, e.userName]),
        )
        .toList();
    if (list.isEmpty) {
      return _emptyState('لا توجد مصروفات في هذا التاريخ');
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, idx) {
        final e = list[idx];
        return Card(
          elevation: 0,
          child: ListTile(
            leading: Icon(
              Icons.receipt_outlined,
              color: Colors.orange.shade700,
            ),
            title: Text(e.expense.category),
            subtitle: Text(
              '${_fmtDate(e.expense.expenseDate)} ${_fmtTime(e.expense.expenseDate)} | المسجل: ${e.userName}'
              '${e.expense.note != null && e.expense.note!.isNotEmpty ? ' | ملاحظة: ${e.expense.note}' : ''}',
            ),
            trailing: Text(
              _fmtMoney(e.expense.amount),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.orange.shade800,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInstallmentsTab(DailyAuditSnapshot s) {
    final list = s.installmentPayments
        .where(
          (e) => _matchesSearch([
            e.payment.receiptNumber,
            e.payment.notes,
            e.recordedByName,
          ]),
        )
        .toList();
    if (list.isEmpty) {
      return _emptyState('لا توجد تحصيلات أقساط في هذا التاريخ');
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, idx) {
        final e = list[idx];
        return Card(
          elevation: 0,
          child: ListTile(
            leading: const Icon(Icons.payments_outlined, color: Colors.teal),
            title: Text(
              'تحصيل قسط ${e.payment.receiptNumber != null ? '#${e.payment.receiptNumber}' : ''}',
            ),
            subtitle: Text(
              '${_fmtDate(e.payment.paidAt)} ${_fmtTime(e.payment.paidAt)} | بواسطة: ${e.recordedByName}'
              '${e.payment.notes != null && e.payment.notes!.isNotEmpty ? ' | ${e.payment.notes}' : ''}',
            ),
            trailing: Text(
              _fmtMoney(e.payment.amountPiasters),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPurchasesTab(DailyAuditSnapshot s) {
    final pList = s.purchases
        .where(
          (e) => _matchesSearch([
            e.supplierName,
            e.purchase.invoiceNumber,
            e.purchase.notes,
          ]),
        )
        .toList();
    final spList = s.supplierPayments
        .where(
          (e) => _matchesSearch([
            e.supplierName,
            e.payment.notes,
            e.createdByName,
          ]),
        )
        .toList();

    if (pList.isEmpty && spList.isEmpty) {
      return _emptyState('لا توجد مشتريات أو سداد موردين في هذا التاريخ');
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (pList.isNotEmpty) ...[
          const Text(
            'فواتير المشتريات',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          ...pList.map(
            (e) => Card(
              elevation: 0,
              child: ListTile(
                leading: const Icon(
                  Icons.inventory_2_outlined,
                  color: Colors.indigo,
                ),
                title: Text(
                  'مورد: ${e.supplierName} ${e.purchase.invoiceNumber != null ? '(#${e.purchase.invoiceNumber})' : ''}',
                ),
                subtitle: Text(
                  '${_fmtDate(e.purchase.purchaseDate)} | المدفوع: ${_fmtMoney(e.purchase.paidAmount)} | الحالة: ${e.purchase.paymentStatus}',
                ),
                trailing: Text(
                  _fmtMoney(e.purchase.totalAmount),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (spList.isNotEmpty) ...[
          const Text(
            'مدفوعات الموردين',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          ...spList.map(
            (e) => Card(
              elevation: 0,
              child: ListTile(
                leading: const Icon(
                  Icons.outbox_outlined,
                  color: Colors.deepPurple,
                ),
                title: Text('سداد للمورد: ${e.supplierName}'),
                subtitle: Text(
                  '${_fmtDate(e.payment.paymentDate)} ${_fmtTime(e.payment.paymentDate)} | ${_fmtMethod(e.payment.paymentMethod)} | بواسطة: ${e.createdByName}',
                ),
                trailing: Text(
                  _fmtMoney(e.payment.amount),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildShiftsTab(DailyAuditSnapshot s) {
    final list = s.shifts
        .where((e) => _matchesSearch([e.cashierName, e.shift.id]))
        .toList();
    if (list.isEmpty) {
      return _emptyState('لا توجد ورديات مفتوحة في هذا التاريخ');
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, idx) {
        final e = list[idx];
        final sh = e.shift;
        final diff = sh.difference;
        final isClosed = sh.closedAt != null;
        return Card(
          elevation: 0,
          child: ListTile(
            leading: Icon(
              isClosed ? Icons.lock_clock : Icons.lock_open,
              color: isClosed ? Colors.blueGrey : AppColors.success,
            ),
            title: Text('وردية الكاشير: ${e.cashierName}'),
            subtitle: Text(
              'فتح: ${_fmtDate(sh.openedAt)} ${_fmtTime(sh.openedAt)}'
              '${isClosed ? ' | إغلاق: ${_fmtTime(sh.closedAt!)}' : ' | مفتوحة الآن'}\n'
              'الافتتاحي: ${_fmtMoney(sh.openingBalance)}'
              '${sh.countedBalance != null ? ' | الجرد الفعلي: ${_fmtMoney(sh.countedBalance!)}' : ''}',
            ),
            trailing: diff == null
                ? const Text('جارية')
                : Text(
                    diff == 0
                        ? 'مطابق (0)'
                        : '${diff > 0 ? 'زيادة +' : 'عجز '}${_fmtMoney(diff.abs())}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: diff == 0
                          ? AppColors.success
                          : (diff > 0 ? Colors.blue : AppColors.error),
                    ),
                  ),
          ),
        );
      },
    );
  }
}
