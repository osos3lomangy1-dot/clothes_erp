import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/database/tx_writer.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/keyboard_focus_helper.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/utils/phone_validator.dart';
import '../../data/services/mobile_repair_service.dart';

class RepairCenterScreen extends StatefulWidget {
  const RepairCenterScreen({super.key});

  @override
  State<RepairCenterScreen> createState() => _RepairCenterScreenState();
}

class _RepairCenterScreenState extends State<RepairCenterScreen> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  String? _statusFilter;
  List<RepairTicket> _tickets = [];
  RepairTicket? _selectedTicket;
  List<RepairTicketPart> _selectedParts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTickets();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  MobileRepairService _resolveService() {
    if (getIt.isRegistered<MobileRepairService>()) {
      return getIt<MobileRepairService>();
    }
    final db = getIt<AppDatabase>();
    final bp = getIt.isRegistered<BranchProvider>()
        ? getIt<BranchProvider>()
        : BranchProvider(db);
    final tx = getIt.isRegistered<TxWriter>() ? getIt<TxWriter>() : TxWriter(db);
    return MobileRepairService(db, bp, tx);
  }

  Future<void> _loadTickets({String? selectTicketId}) async {
    try {
      final svc = _resolveService();
      final list = await svc.getTickets(status: _statusFilter);
      RepairTicket? selected;
      final targetId = selectTicketId ?? _selectedTicket?.id;
      if (targetId != null) {
        for (final t in list) {
          if (t.id == targetId) {
            selected = t;
            break;
          }
        }
      }
      selected ??= list.isNotEmpty ? list.first : null;
      final parts = selected != null
          ? await svc.getPartsForTicket(selected.id)
          : const <RepairTicketPart>[];
      if (!mounted) return;
      setState(() {
        _tickets = list;
        _selectedTicket = selected;
        _selectedParts = parts;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectTicket(RepairTicket ticket) async {
    final parts = await _resolveService().getPartsForTicket(ticket.id);
    if (!mounted) return;
    setState(() {
      _selectedTicket = ticket;
      _selectedParts = parts;
    });
  }

  List<RepairTicket> get _filteredTickets {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _tickets;
    return _tickets.where((t) {
      return t.ticketNumber.toLowerCase().contains(q) ||
          t.customerName.toLowerCase().contains(q) ||
          t.customerPhone.toLowerCase().contains(q) ||
          t.deviceModel.toLowerCase().contains(q) ||
          (t.imei?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Future<void> _openCreateTicketDialog() async {
    final created = await showDialog<RepairTicket>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateRepairTicketDialog(service: _resolveService()),
    );
    if (created != null) {
      await _loadTickets(selectTicketId: created.id);
    }
  }

  Future<void> _openAddPartDialog(RepairTicket ticket) async {
    final added = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AddSparePartDialog(
        service: _resolveService(),
        ticketId: ticket.id,
      ),
    );
    if (added == true) {
      await _loadTickets(selectTicketId: ticket.id);
    }
  }

  Future<void> _openDeliverDialog(RepairTicket ticket) async {
    final res = await showDialog<RepairDeliveryResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DeliverRepairDialog(
        service: _resolveService(),
        ticket: ticket,
      ),
    );
    if (res != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تسليم التذكرة ${res.ticketNumber} وتحصيل ${Money(res.remainingCollectedPiasters).toDisplay()} ج.م',
          ),
          backgroundColor: AppColors.success,
        ),
      );
      await _loadTickets(selectTicketId: ticket.id);
    }
  }

  Future<void> _printReceipt(RepairTicket ticket) async {
    try {
      final bytes = await MobileRepairService.generateRepairReceiptPdf(
        ticket,
        parts: _selectedParts,
      );
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر طباعة الإيصال: $e'),
          backgroundColor: AppColors.error,
        ),
      );
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
      _openCreateTicketDialog();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f12 && _selectedTicket != null) {
      final t = _selectedTicket!;
      if (t.status != 'delivered' && t.status != 'cancelled') {
        _openDeliverDialog(t);
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_searchCtrl.text.isNotEmpty || _statusFilter != null) {
        setState(() {
          _searchCtrl.clear();
          _query = '';
          _statusFilter = null;
        });
        _loadTickets();
        return KeyEventResult.handled;
      }
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'ready':
        return AppColors.success;
      case 'in_progress':
      case 'diagnosing':
        return AppColors.warning;
      case 'delivered':
        return AppColors.primary;
      case 'cancelled':
        return AppColors.error;
      default:
        return AppColors.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredTickets;
    final dateFmt = DateFormat('yyyy/MM/dd hh:mm a');

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('مركز الصيانة وتذاكر الإصلاح'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.onSurface,
          elevation: 0,
          actions: [
            ElevatedButton.icon(
              key: const Key('repair_new_ticket_btn'),
              onPressed: _openCreateTicketDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.build_circle_rounded, size: 18),
              label: const Text('تذكرة جديدة [F3]'),
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
                          child: TextField(
                            key: const Key('repair_search_field'),
                            controller: _searchCtrl,
                            focusNode: _searchFocus,
                            onChanged: (v) => setState(() => _query = v),
                            decoration: InputDecoration(
                              hintText:
                                  'ابحث برقم التذكرة أو العميل أو الموديل أو IMEI... [F2]',
                              prefixIcon: const Icon(Icons.search_rounded),
                              filled: true,
                              fillColor: AppColors.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('الكل'),
                            selected: _statusFilter == null,
                            onSelected: (_) {
                              setState(() => _statusFilter = null);
                              _loadTickets();
                            },
                          ),
                          const SizedBox(width: 6),
                          for (final st in MobileRepairService.statuses) ...[
                            ChoiceChip(
                              label: Text(MobileRepairService.statusLabel(st)),
                              selected: _statusFilter == st,
                              onSelected: (_) {
                                setState(() => _statusFilter = st);
                                _loadTickets();
                              },
                            ),
                            const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: filtered.isEmpty
                                ? Center(
                                    child: Text(
                                      'لا توجد تذاكر صيانة مطابقة',
                                      style: TextStyle(
                                        color: AppColors.onSurfaceVariant,
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: filtered.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 8),
                                    itemBuilder: (context, index) {
                                      final t = filtered[index];
                                      final isSelected =
                                          _selectedTicket?.id == t.id;
                                      final stColor = _statusColor(t.status);
                                      return InkWell(
                                        onTap: () => _selectTicket(t),
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: AppColors.surface,
                                            borderRadius:
                                                BorderRadius.circular(12),
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
                                                  Expanded(
                                                    child: Text(
                                                      '${t.ticketNumber} - ${t.deviceModel}',
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: stColor.withValues(
                                                        alpha: 0.12,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        8,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      MobileRepairService
                                                          .statusLabel(
                                                        t.status,
                                                      ),
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: stColor,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${t.customerName}${t.customerPhone.isNotEmpty ? ' | ${t.customerPhone}' : ''}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                      AppColors.onSurfaceVariant,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                t.issueDescription,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12,
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
                            child: _selectedTicket == null
                                ? Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'اختر تذكرة لعرض التفاصيل',
                                        style: TextStyle(
                                          color: AppColors.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  )
                                : _buildDetailPanel(
                                    _selectedTicket!,
                                    dateFmt,
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

  Widget _buildDetailPanel(RepairTicket t, DateFormat dateFmt) {
    final isClosed = t.status == 'delivered' || t.status == 'cancelled';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'تذكرة ${t.ticketNumber}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _printReceipt(t),
                  icon: const Icon(Icons.print_rounded, size: 17),
                  label: const Text('إيصال استلام'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'تاريخ الاستلام: ${dateFmt.format(t.createdAt)}',
              style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
            ),
            const Divider(height: 20),
            _infoRow('العميل:', '${t.customerName} (${t.customerPhone})'),
            _infoRow('الجهاز:', t.deviceModel),
            if (t.imei != null && t.imei!.isNotEmpty) _infoRow('IMEI:', t.imei!),
            _infoRow('العطل:', t.issueDescription),
            if (t.intakeCondition != null)
              _infoRow('حالة الاستلام:', t.intakeCondition!),
            if (t.passcodeOrPattern != null)
              _infoRow('الرمز السري:', t.passcodeOrPattern!),
            _infoRow(
              'التكلفة التقديرية:',
              '${Money(t.estimatedCost).toDisplay()} ج.م',
            ),
            _infoRow(
              'العربون المدفوع:',
              '${Money(t.depositPaid).toDisplay()} ج.م',
            ),
            _infoRow(
              'تكلفة قطع الغيار:',
              '${Money(t.partsCost).toDisplay()} ج.م',
            ),
            if (t.status == 'delivered') ...[
              _infoRow(
                'التكلفة النهائية:',
                '${Money(t.finalCost).toDisplay()} ج.م',
              ),
              _infoRow(
                'صافي ربح الصيانة:',
                '${Money(t.finalCost - t.partsCost).toDisplay()} ج.م',
              ),
            ],
            const Divider(height: 20),
            Row(
              children: [
                const Text(
                  'حالة التذكرة:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: t.status,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: MobileRepairService.statuses
                        .where((s) => s != 'delivered' || t.status == 'delivered')
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(
                              MobileRepairService.statusLabel(s),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: isClosed
                        ? null
                        : (val) async {
                            if (val != null) {
                              await _resolveService().updateStatus(
                                ticketId: t.id,
                                status: val,
                              );
                              await _loadTickets(selectTicketId: t.id);
                            }
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'قطع الغيار المصروفة',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                if (!isClosed)
                  OutlinedButton.icon(
                    key: const Key('repair_add_part_btn'),
                    onPressed: () => _openAddPartDialog(t),
                    icon: const Icon(Icons.memory_rounded, size: 17),
                    label: const Text('صرف قطعة غيار'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_selectedParts.isEmpty)
              Text(
                'لم تُصرف قطع غيار لهذه التذكرة',
                style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
              )
            else
              for (final p in _selectedParts)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(p.partName),
                  subtitle: Text(
                    'الكمية: ${p.qty} | التكلفة: ${Money(p.unitCost * p.qty).toDisplay()} ج.م',
                  ),
                ),
            if (!isClosed) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  key: const Key('repair_deliver_btn'),
                  onPressed: () => _openDeliverDialog(t),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.check_circle_rounded),
                  label: const Text('تسليم الجهاز وتحصيل المتبقي [F12]'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateRepairTicketDialog extends StatefulWidget {
  final MobileRepairService service;

  const _CreateRepairTicketDialog({required this.service});

  @override
  State<_CreateRepairTicketDialog> createState() =>
      _CreateRepairTicketDialogState();
}

class _CreateRepairTicketDialogState extends State<_CreateRepairTicketDialog> {
  final _formKey = GlobalKey<FormState>();
  final _customerCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _imeiCtrl = TextEditingController();
  final _issueCtrl = TextEditingController();
  final _conditionCtrl = TextEditingController();
  final _passcodeCtrl = TextEditingController();
  final _estimatedCtrl = TextEditingController(text: '0');
  final _depositCtrl = TextEditingController(text: '0');
  final _techCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _customerCtrl.dispose();
    _phoneCtrl.dispose();
    _modelCtrl.dispose();
    _imeiCtrl.dispose();
    _issueCtrl.dispose();
    _conditionCtrl.dispose();
    _passcodeCtrl.dispose();
    _estimatedCtrl.dispose();
    _depositCtrl.dispose();
    _techCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSaving || _formKey.currentState?.validate() != true) return;
    setState(() => _isSaving = true);
    try {
      final ticket = await widget.service.createTicket(
        customerName: _customerCtrl.text.trim(),
        customerPhone: _phoneCtrl.text.trim(),
        deviceModel: _modelCtrl.text.trim(),
        imei: _imeiCtrl.text.trim(),
        issueDescription: _issueCtrl.text.trim(),
        intakeCondition: _conditionCtrl.text.trim(),
        passcodeOrPattern: _passcodeCtrl.text.trim(),
        estimatedCostPiasters: Money.fromString(_estimatedCtrl.text).piasters,
        depositPaidPiasters: Money.fromString(_depositCtrl.text).piasters,
        technicianName: _techCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(ticket);
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
            Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.f12): _submit,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _submit,
      },
      child: AlertDialog(
        title: const Text('استلام جهاز صيانة جديد'),
        content: SizedBox(
          width: 480,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const Key('repair_customer_field'),
                          controller: _customerCtrl,
                          decoration: const InputDecoration(
                            labelText: 'اسم العميل *',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          key: const Key('repair_phone_field'),
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          validator: (v) =>
                              PhoneValidator.validate(v, required: false),
                          decoration: const InputDecoration(
                            labelText: 'رقم الهاتف',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const Key('repair_model_field'),
                          controller: _modelCtrl,
                          decoration: const InputDecoration(
                            labelText: 'موديل الجهاز *',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          key: const Key('repair_imei_field'),
                          controller: _imeiCtrl,
                          decoration: const InputDecoration(
                            labelText: 'IMEI / السيريال',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    key: const Key('repair_issue_field'),
                    controller: _issueCtrl,
                    decoration: const InputDecoration(
                      labelText: 'وصف العطل *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const Key('repair_condition_field'),
                          controller: _conditionCtrl,
                          decoration: const InputDecoration(
                            labelText: 'حالة الاستلام',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          key: const Key('repair_passcode_field'),
                          controller: _passcodeCtrl,
                          decoration: const InputDecoration(
                            labelText: 'الرمز السري / النمط',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const Key('repair_estimated_field'),
                          controller: _estimatedCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'التكلفة التقديرية (ج.م)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          key: const Key('repair_deposit_field'),
                          controller: _depositCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'العربون المدفوع (ج.م)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    key: const Key('repair_tech_field'),
                    controller: _techCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم الفني المسؤول',
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
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            child: const Text('إلغاء [Esc]'),
          ),
          ElevatedButton(
            key: const Key('repair_save_ticket_btn'),
            onPressed: _isSaving ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('حفظ التذكرة [F12]'),
          ),
        ],
      ),
    );
  }
}

class _AddSparePartDialog extends StatefulWidget {
  final MobileRepairService service;
  final String ticketId;

  const _AddSparePartDialog({required this.service, required this.ticketId});

  @override
  State<_AddSparePartDialog> createState() => _AddSparePartDialogState();
}

class _AddSparePartDialogState extends State<_AddSparePartDialog> {
  final _qtyCtrl = TextEditingController(text: '1');
  List<({String id, String label, int qty})> _variants = [];
  String? _selectedVariantId;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadVariants();
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadVariants() async {
    final db = getIt<AppDatabase>();
    final rows = await (db.select(db.productVariants).join([
      innerJoin(
        db.products,
        db.products.id.equalsExp(db.productVariants.productId),
      ),
    ])
          ..where(
            db.productVariants.deletedAt.isNull() &
                db.products.deletedAt.isNull() &
                db.productVariants.quantity.isBiggerThanValue(0),
          ))
        .get();
    final list = rows.map((r) {
      final v = r.readTable(db.productVariants);
      final p = r.readTable(db.products);
      return (id: v.id, label: '${p.name} (متاح: ${v.quantity})', qty: v.quantity);
    }).toList();
    if (!mounted) return;
    setState(() {
      _variants = list;
      _selectedVariantId = list.isNotEmpty ? list.first.id : null;
      _isLoading = false;
    });
  }

  Future<void> _submit() async {
    if (_isSaving || _selectedVariantId == null) return;
    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    if (qty <= 0) return;
    setState(() => _isSaving = true);
    try {
      await widget.service.addPartToTicket(
        ticketId: widget.ticketId,
        variantId: _selectedVariantId!,
        qty: qty,
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
        title: const Text('صرف قطعة غيار من المخزن'),
        content: _isLoading
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _selectedVariantId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'قطعة الغيار',
                      border: OutlineInputBorder(),
                    ),
                    items: _variants
                        .map(
                          (v) => DropdownMenuItem(
                            value: v.id,
                            child: Text(v.label, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedVariantId = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'الكمية',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
            child: const Text('إلغاء [Esc]'),
          ),
          ElevatedButton(
            onPressed: _isSaving || _selectedVariantId == null ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('صرف [F12]'),
          ),
        ],
      ),
    );
  }
}

class _DeliverRepairDialog extends StatefulWidget {
  final MobileRepairService service;
  final RepairTicket ticket;

  const _DeliverRepairDialog({required this.service, required this.ticket});

  @override
  State<_DeliverRepairDialog> createState() => _DeliverRepairDialogState();
}

class _DeliverRepairDialogState extends State<_DeliverRepairDialog> {
  late final TextEditingController _finalCostCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _finalCostCtrl = TextEditingController(
      text: Money(widget.ticket.estimatedCost).toDisplay(),
    );
  }

  @override
  void dispose() {
    _finalCostCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final finalPiasters = Money.fromString(_finalCostCtrl.text).piasters;
      final res = await widget.service.deliverAndCollect(
        ticketId: widget.ticket.id,
        finalCostPiasters: finalPiasters,
      );
      if (mounted) Navigator.of(context).pop(res);
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
    final finalPiasters = Money.fromString(_finalCostCtrl.text).piasters;
    final remaining = finalPiasters - widget.ticket.depositPaid;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.f12): _submit,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _submit,
      },
      child: AlertDialog(
        title: Text('تسليم وتحصيل ${widget.ticket.ticketNumber}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('repair_final_cost_field'),
              controller: _finalCostCtrl,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'التكلفة النهائية (ج.م)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'العربون المدفوع مسبقاً: ${Money(widget.ticket.depositPaid).toDisplay()} ج.م',
            ),
            const SizedBox(height: 4),
            Text(
              'المتبقي للتحصيل الآن: ${Money(remaining).toDisplay()} ج.م',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            child: const Text('إلغاء [Esc]'),
          ),
          ElevatedButton(
            key: const Key('repair_confirm_deliver_btn'),
            onPressed: _isSaving ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
            child: const Text('تأكيد التسليم [F12]'),
          ),
        ],
      ),
    );
  }
}

