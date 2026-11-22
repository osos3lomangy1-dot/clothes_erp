import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../data/services/telegram_bot_service.dart';
import '../../data/services/telegram_message_parser.dart';
import '../../domain/entities/telegram_inbox_message_entity.dart';
import '../cubits/pre_orders_cubit.dart';
import 'create_pre_order_dialog.dart';

class TelegramInboxDialog extends StatefulWidget {
  const TelegramInboxDialog({super.key});

  @override
  State<TelegramInboxDialog> createState() => _TelegramInboxDialogState();
}

class _TelegramInboxDialogState extends State<TelegramInboxDialog> {
  final _botService = getIt<TelegramBotService>();
  final _searchCtrl = TextEditingController();

  List<TelegramInboxMessageEntity> _messages = [];
  bool _isLoading = true;
  bool _isPulling = false;
  String _selectedStatus = 'pending'; // 'pending', 'converted', 'archived', 'all'
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    final msgs = await _botService.getMessages(
      status: _selectedStatus == 'all' ? null : _selectedStatus,
      searchQuery: _searchCtrl.text.trim(),
    );
    if (mounted) {
      setState(() {
        _messages = msgs;
        _isLoading = false;
      });
    }
  }

  Future<void> _pullNewMessages() async {
    setState(() {
      _isPulling = true;
      _statusMessage = null;
    });

    final result = await _botService.fetchNewMessages();
    if (!mounted) return;

    result.fold(
      (err) {
        setState(() {
          _isPulling = false;
          _statusMessage = err;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err, style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppColors.error,
          ),
        );
      },
      (count) async {
        await _loadMessages();
        if (!mounted) return;
        setState(() {
          _isPulling = false;
          _statusMessage = count > 0
              ? 'تم استلام $count طلب/رسالة جديدة بنجاح'
              : 'لا توجد رسائل واردة جديدة حالياً';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _statusMessage!,
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: count > 0 ? AppColors.success : AppColors.primary,
          ),
        );
      },
    );
  }

  Future<void> _convertToPreOrder(TelegramInboxMessageEntity msg) async {
    final parsed = TelegramMessageParser.parse(
      msg.messageText,
      senderName: msg.senderName,
      senderUsername: msg.senderUsername,
    );

    final customerName = (parsed.customerName != null && parsed.customerName!.isNotEmpty)
        ? parsed.customerName!
        : msg.senderName;
    final customerPhone = parsed.customerPhone ?? '';
    final initialDeposit = parsed.deposit != null
        ? (parsed.deposit! % 1 == 0
            ? parsed.deposit!.toInt().toString()
            : parsed.deposit!.toString())
        : null;

    final usernameTag = msg.senderUsername != null ? '@${msg.senderUsername}' : '';
    final notes = 'وارد من تيليجرام: $customerName $usernameTag\n${msg.messageText}';

    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        PreOrdersCubit? cubit;
        try {
          cubit = context.read<PreOrdersCubit>();
        } catch (_) {}

        final dialog = CreatePreOrderDialog(
          initialCustomerName: customerName,
          initialCustomerPhone: customerPhone,
          initialDeposit: initialDeposit,
          initialNotes: notes,
          initialPlatform: parsed.detectedPlatform,
          initialItems: parsed.suggestedItems,
        );

        if (cubit != null) {
          return BlocProvider<PreOrdersCubit>.value(
            value: cubit,
            child: dialog,
          );
        } else {
          return BlocProvider<PreOrdersCubit>(
            create: (_) => getIt<PreOrdersCubit>(),
            child: dialog,
          );
        }
      },
    );

    if (created == true) {
      await _botService.markMessageStatus(msg.id, 'converted');
      await _loadMessages();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم تحويل رسالة تيليجرام لأوردر حجز مسبق رسمي بنجاح',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _archiveMessage(TelegramInboxMessageEntity msg) async {
    await _botService.markMessageStatus(msg.id, 'archived');
    await _loadMessages();
  }

  Future<void> _deleteMessage(TelegramInboxMessageEntity msg) async {
    await _botService.deleteMessage(msg.id);
    await _loadMessages();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.inbox_rounded, color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'صندوق وارد حجوزات تيليجرام',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: AppColors.onSurface,
                          ),
                        ),
                        Text(
                          'استقبال ومعالجة طلبات الحجز المباشرة من قنوات وعملاء تيليجرام تلقائياً',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    onPressed: _isPulling ? null : _pullNewMessages,
                    icon: _isPulling
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.sync_rounded, size: 18),
                    label: Text(
                      _isPulling ? 'جاري السحب...' : 'سحب الرسائل الجديدة',
                      style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Filter & Search Bar
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'بحث في الرسائل، اسم العميل، اليوزر، أو الكود...',
                        hintStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (_) => _loadMessages(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildStatusFilterChip('قيد المعالجة', 'pending'),
                  const SizedBox(width: 6),
                  _buildStatusFilterChip('تم تحويلها', 'converted'),
                  const SizedBox(width: 6),
                  _buildStatusFilterChip('مؤرشفة', 'archived'),
                  const SizedBox(width: 6),
                  _buildStatusFilterChip('الكل', 'all'),
                ],
              ),
              const SizedBox(height: 14),

              // Messages List Area
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _messages.isEmpty
                        ? _buildEmptyState()
                        : ListView.separated(
                            itemCount: _messages.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              return _buildMessageCard(_messages[index]);
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusFilterChip(String label, String value) {
    final isSelected = _selectedStatus == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : AppColors.onSurface,
        ),
      ),
      selected: isSelected,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedStatus = value);
          _loadMessages();
        }
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mark_email_read_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            'لا توجد رسائل في هذا القسم حالياً',
            style: TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 4),
          Text(
            'اضغط على "سحب الرسائل الجديدة" لجلب أي طلبات واردة من تيليجرام',
            style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageCard(TelegramInboxMessageEntity msg) {
    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');
    final dateStr = dateFormat.format(msg.createdAt);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: msg.isPending ? AppColors.primary.withValues(alpha: 0.3) : AppColors.outlineVariant,
          width: msg.isPending ? 1.4 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Sender + Username + Date + Status Badge
          Row(
            children: [
              Icon(Icons.person_pin_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                msg.senderName,
                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
              ),
              if (msg.senderUsername != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Text(
                    '@${msg.senderUsername}',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.blue.shade800, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
              const Spacer(),
              Text(
                dateStr,
                style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.grey.shade600),
              ),
              const SizedBox(width: 8),
              _buildStatusBadge(msg.status),
            ],
          ),
          const SizedBox(height: 8),

          // Message Body
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Text(
              msg.messageText,
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5, height: 1.4),
            ),
          ),

          // Extracted Details Chips (Name, Phone, Deposit, Items count, Sku, Size, Color, Links)
          () {
            final parsed = TelegramMessageParser.parse(
              msg.messageText,
              senderName: msg.senderName,
              senderUsername: msg.senderUsername,
            );
            final realName = parsed.customerName;
            final phone = parsed.customerPhone;
            final deposit = parsed.deposit;

            return Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (realName != null && realName.isNotEmpty && realName != msg.senderName)
                  _buildDetailChip(Icons.person_outline_rounded, 'الاسم: $realName', const Color(0xFF1E293B)),
                if (phone != null && phone.isNotEmpty)
                  _buildDetailChip(Icons.phone_iphone_rounded, 'هاتف: $phone', const Color(0xFF047857)),
                if (deposit != null)
                  _buildDetailChip(Icons.payments_outlined, 'عربون: ${deposit % 1 == 0 ? deposit.toInt() : deposit} ج.م', const Color(0xFFB45309)),
                if (parsed.salePrice != null)
                  _buildDetailChip(Icons.sell_outlined, 'سعر: ${parsed.salePrice! % 1 == 0 ? parsed.salePrice!.toInt() : parsed.salePrice} ج.م', const Color(0xFF0369A1)),
                if (parsed.costPrice != null)
                  _buildDetailChip(Icons.receipt_outlined, 'جملة: ${parsed.costPrice! % 1 == 0 ? parsed.costPrice!.toInt() : parsed.costPrice} ج.م', const Color(0xFF475569)),
                if (parsed.suggestedItems.length > 1)
                  _buildDetailChip(Icons.format_list_bulleted_rounded, '${parsed.suggestedItems.length} أصناف', const Color(0xFF475569))
                else if (parsed.suggestedItems.isNotEmpty && parsed.suggestedItems.first.productName != 'طلب صنف خارجي')
                  _buildDetailChip(Icons.shopping_bag_outlined, parsed.suggestedItems.first.productName, const Color(0xFF475569)),
                if (parsed.sku != null && parsed.sku!.isNotEmpty)
                  _buildDetailChip(Icons.tag_rounded, 'كود: ${parsed.sku}', const Color(0xFF475569)),
                if (parsed.size != null && parsed.size!.isNotEmpty)
                  _buildDetailChip(Icons.straighten_rounded, 'مقاس: ${parsed.size}', const Color(0xFF475569)),
                if (parsed.color != null && parsed.color!.isNotEmpty)
                  _buildDetailChip(Icons.palette_outlined, 'لون: ${parsed.color}', const Color(0xFF475569)),
                if (parsed.qty > 1 && parsed.suggestedItems.length <= 1)
                  _buildDetailChip(Icons.shopping_basket_outlined, 'الكمية: ${parsed.qty}', const Color(0xFF475569)),
                ...parsed.links.map((url) => _buildDetailChip(Icons.link_rounded, url, const Color(0xFF475569))),
              ],
            );
          }(),
          const SizedBox(height: 10),

          // Action Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (msg.isPending) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.outlineVariant),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _archiveMessage(msg),
                  icon: const Icon(Icons.archive_outlined, size: 15, color: Colors.grey),
                  label: const Text('أرشفة', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.grey)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _convertToPreOrder(msg),
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                  label: const Text(
                    'اعتماد وتحويل لحجز رسمي',
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                tooltip: 'حذف الرسالة',
                onPressed: () => _deleteMessage(msg),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case 'converted':
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        label = 'تم التحويل لحجز';
        break;
      case 'archived':
        bg = Colors.grey.shade100;
        fg = Colors.grey.shade700;
        label = 'مؤرشفة';
        break;
      default:
        bg = Colors.amber.shade50;
        fg = Colors.amber.shade900;
        label = 'قيد المعالجة';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontFamily: 'Cairo', fontSize: 10, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  Widget _buildDetailChip(IconData icon, String text, [Color? textColor]) {
    final fg = textColor ?? const Color(0xFF334155);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                color: fg,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
