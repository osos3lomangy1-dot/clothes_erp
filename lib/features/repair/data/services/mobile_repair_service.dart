import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/database/tx_writer.dart';
import '../../../../core/theme/app_branding.dart';
import '../../../../core/utils/money.dart';
import '../../../invoices/data/services/receipt_settings_service.dart';

class RepairDeliveryResult {
  final String ticketId;
  final String ticketNumber;
  final int finalCostPiasters;
  final int depositPaidPiasters;
  final int remainingCollectedPiasters;
  final int partsCostPiasters;
  final int netProfitPiasters;

  const RepairDeliveryResult({
    required this.ticketId,
    required this.ticketNumber,
    required this.finalCostPiasters,
    required this.depositPaidPiasters,
    required this.remainingCollectedPiasters,
    required this.partsCostPiasters,
    required this.netProfitPiasters,
  });
}

@lazySingleton
class MobileRepairService {
  final AppDatabase _db;
  final BranchProvider _branchProvider;
  final TxWriter _txWriter;
  final _uuid = const Uuid();

  MobileRepairService(this._db, this._branchProvider, this._txWriter);

  static const List<String> statuses = [
    'pending',
    'diagnosing',
    'in_progress',
    'ready',
    'delivered',
    'cancelled',
  ];

  static String statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'في الانتظار';
      case 'diagnosing':
        return 'قيد الفحص';
      case 'in_progress':
        return 'قيد الإصلاح';
      case 'ready':
        return 'جاهز للتسليم';
      case 'delivered':
        return 'تم التسليم';
      case 'cancelled':
        return 'ملغاة';
      default:
        return status;
    }
  }

  Future<List<RepairTicket>> getTickets({String? status}) async {
    final branchId = await _branchProvider.getBranchId();
    final q = _db.select(_db.repairTickets)
      ..where(
        (t) =>
            t.branchId.equals(branchId) &
            t.deletedAt.isNull() &
            (status != null ? t.status.equals(status) : const Constant(true)),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return q.get();
  }

  Future<List<RepairTicketPart>> getPartsForTicket(String ticketId) async {
    return (_db.select(_db.repairTicketParts)
          ..where((p) => p.ticketId.equals(ticketId))
          ..orderBy([(p) => OrderingTerm.asc(p.createdAt)]))
        .get();
  }

  Future<String?> _getActiveShiftId() async {
    final activeShift = await (_db.select(_db.shifts)
          ..where((s) => s.closedAt.isNull() & s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.desc(s.openedAt)])
          ..limit(1))
        .getSingleOrNull();
    return activeShift?.id;
  }

  Future<RepairTicket> createTicket({
    String? customerId,
    required String customerName,
    String customerPhone = '',
    required String deviceModel,
    String? imei,
    required String issueDescription,
    String? intakeCondition,
    String? passcodeOrPattern,
    int estimatedCostPiasters = 0,
    int depositPaidPiasters = 0,
    String? technicianName,
    String userId = 'admin',
  }) async {
    if (customerName.trim().isEmpty) {
      throw Exception('يرجى إدخال اسم العميل');
    }
    if (deviceModel.trim().isEmpty) {
      throw Exception('يرجى إدخال موديل الجهاز');
    }
    if (issueDescription.trim().isEmpty) {
      throw Exception('يرجى إدخال وصف العطل');
    }
    if (estimatedCostPiasters < 0 || depositPaidPiasters < 0) {
      throw Exception('المبالغ لا يمكن أن تكون سالبة');
    }

    final branchId = await _branchProvider.getBranchId();
    final now = DateTime.now();
    final id = _uuid.v4();
    final ticketNumber =
        'REP-${(now.millisecondsSinceEpoch % 1000000).toString().padLeft(6, '0')}';
    final shiftId = await _getActiveShiftId();

    await _txWriter.write(
      branchId: branchId,
      entity: 'repair_tickets',
      entityId: id,
      operation: 'create_repair_ticket',
      userId: userId,
      writeFn: () async {
        await _db.into(_db.repairTickets).insert(
              RepairTicketsCompanion.insert(
                id: id,
                branchId: branchId,
                ticketNumber: ticketNumber,
                customerId: Value(customerId),
                customerName: customerName.trim(),
                customerPhone: Value(customerPhone.trim()),
                deviceModel: deviceModel.trim(),
                imei: Value(
                  imei != null && imei.trim().isNotEmpty ? imei.trim() : null,
                ),
                issueDescription: issueDescription.trim(),
                intakeCondition: Value(
                  intakeCondition != null && intakeCondition.trim().isNotEmpty
                      ? intakeCondition.trim()
                      : null,
                ),
                passcodeOrPattern: Value(
                  passcodeOrPattern != null &&
                          passcodeOrPattern.trim().isNotEmpty
                      ? passcodeOrPattern.trim()
                      : null,
                ),
                estimatedCost: Value(estimatedCostPiasters),
                depositPaid: Value(depositPaidPiasters),
                finalCost: const Value(0),
                partsCost: const Value(0),
                status: const Value('pending'),
                technicianName: Value(
                  technicianName != null && technicianName.trim().isNotEmpty
                      ? technicianName.trim()
                      : null,
                ),
                shiftId: Value(shiftId),
                createdAt: now,
                updatedAt: now,
              ),
            );

        if (depositPaidPiasters > 0) {
          final nowSec = now.millisecondsSinceEpoch ~/ 1000;
          await _db.into(_db.cashMovements).insert(
                CashMovementsCompanion.insert(
                  id: _uuid.v4(),
                  branchId: branchId,
                  shiftId: Value(shiftId),
                  type: 'deposit',
                  method: 'cash',
                  direction: 'in',
                  amountPiasters: depositPaidPiasters,
                  referenceId: Value(id),
                  notes: Value('عربون صيانة تذكرة $ticketNumber'),
                  createdAt: nowSec,
                  updatedAt: nowSec,
                ),
              );
        }
      },
    );

    return (_db.select(_db.repairTickets)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  Future<void> updateStatus({
    required String ticketId,
    required String status,
    String? technicianName,
    String userId = 'admin',
  }) async {
    if (!statuses.contains(status)) {
      throw Exception('حالة التذكرة غير صالحة');
    }
    final branchId = await _branchProvider.getBranchId();
    await _txWriter.write(
      branchId: branchId,
      entity: 'repair_tickets',
      entityId: ticketId,
      operation: 'update_repair_status',
      userId: userId,
      writeFn: () async {
        await (_db.update(_db.repairTickets)..where((t) => t.id.equals(ticketId)))
            .write(
          RepairTicketsCompanion(
            status: Value(status),
            technicianName: technicianName != null
                ? Value(technicianName.trim())
                : const Value.absent(),
            updatedAt: Value(DateTime.now()),
          ),
        );
      },
    );
  }

  Future<void> addPartToTicket({
    required String ticketId,
    required String variantId,
    int qty = 1,
    String userId = 'admin',
  }) async {
    if (qty <= 0) {
      throw Exception('الكمية يجب أن تكون أكبر من صفر');
    }
    final branchId = await _branchProvider.getBranchId();
    final now = DateTime.now();
    final partId = _uuid.v4();

    await _txWriter.write(
      branchId: branchId,
      entity: 'repair_ticket_parts',
      entityId: partId,
      operation: 'add_repair_part',
      userId: userId,
      writeFn: () async {
        final ticket = await (_db.select(_db.repairTickets)
              ..where((t) => t.id.equals(ticketId) & t.deletedAt.isNull()))
            .getSingleOrNull();
        if (ticket == null) {
          throw Exception('تذكرة الصيانة غير موجودة');
        }
        if (ticket.status == 'delivered' || ticket.status == 'cancelled') {
          throw Exception('لا يمكن إضافة قطع غيار لتذكرة مغلقة');
        }

        final row = await (_db.select(_db.productVariants).join([
          innerJoin(
            _db.products,
            _db.products.id.equalsExp(_db.productVariants.productId),
          ),
        ])
              ..where(_db.productVariants.id.equals(variantId)))
            .getSingleOrNull();
        if (row == null) {
          throw Exception('قطعة الغيار غير موجودة في المخزن');
        }

        final variant = row.readTable(_db.productVariants);
        final product = row.readTable(_db.products);
        if (variant.quantity < qty) {
          throw Exception(
            'الكمية المتاحة من (${product.name}) هي ${variant.quantity} فقط',
          );
        }

        await (_db.update(_db.productVariants)
              ..where((v) => v.id.equals(variantId)))
            .write(
          ProductVariantsCompanion(
            quantity: Value(variant.quantity - qty),
            updatedAt: Value(now),
          ),
        );

        await _db.into(_db.inventoryLogs).insert(
              InventoryLogsCompanion.insert(
                id: _uuid.v4(),
                branchId: branchId,
                variantId: variantId,
                qtyDelta: -qty,
                type: 'sale',
                reason: Value('صرف قطعة غيار لتذكرة صيانة ${ticket.ticketNumber}'),
                refType: 'repair_ticket',
                refId: Value(ticketId),
                userId: userId,
                createdAt: now,
              ),
            );

        final partLabel = '${product.name} (${variant.size})';
        await _db.into(_db.repairTicketParts).insert(
              RepairTicketPartsCompanion.insert(
                id: partId,
                branchId: branchId,
                ticketId: ticketId,
                variantId: variantId,
                partName: partLabel,
                qty: Value(qty),
                unitCost: Value(variant.costPrice),
                unitPrice: Value(variant.sellPrice),
                createdAt: now,
              ),
            );

        final addedCost = variant.costPrice * qty;
        await (_db.update(_db.repairTickets)..where((t) => t.id.equals(ticketId)))
            .write(
          RepairTicketsCompanion(
            partsCost: Value(ticket.partsCost + addedCost),
            updatedAt: Value(now),
          ),
        );
      },
    );
  }

  Future<RepairDeliveryResult> deliverAndCollect({
    required String ticketId,
    required int finalCostPiasters,
    String userId = 'admin',
  }) async {
    if (finalCostPiasters < 0) {
      throw Exception('التكلفة النهائية لا يمكن أن تكون سالبة');
    }
    final branchId = await _branchProvider.getBranchId();
    final now = DateTime.now();
    final shiftId = await _getActiveShiftId();

    late RepairDeliveryResult result;

    await _txWriter.write(
      branchId: branchId,
      entity: 'repair_tickets',
      entityId: ticketId,
      operation: 'deliver_repair_ticket',
      userId: userId,
      writeFn: () async {
        final ticket = await (_db.select(_db.repairTickets)
              ..where((t) => t.id.equals(ticketId) & t.deletedAt.isNull()))
            .getSingleOrNull();
        if (ticket == null) {
          throw Exception('تذكرة الصيانة غير موجودة');
        }
        if (ticket.status == 'delivered') {
          throw Exception('تم تسليم هذه التذكرة بالفعل');
        }

        final remaining = finalCostPiasters - ticket.depositPaid;
        await (_db.update(_db.repairTickets)..where((t) => t.id.equals(ticketId)))
            .write(
          RepairTicketsCompanion(
            status: const Value('delivered'),
            finalCost: Value(finalCostPiasters),
            shiftId: Value(shiftId ?? ticket.shiftId),
            deliveredAt: Value(now),
            updatedAt: Value(now),
          ),
        );

        final nowSec = now.millisecondsSinceEpoch ~/ 1000;
        if (remaining > 0) {
          await _db.into(_db.cashMovements).insert(
                CashMovementsCompanion.insert(
                  id: _uuid.v4(),
                  branchId: branchId,
                  shiftId: Value(shiftId),
                  type: 'deposit',
                  method: 'cash',
                  direction: 'in',
                  amountPiasters: remaining,
                  referenceId: Value(ticketId),
                  notes: Value('تحصيل صيانة عند التسليم ${ticket.ticketNumber}'),
                  createdAt: nowSec,
                  updatedAt: nowSec,
                ),
              );
        } else if (remaining < 0) {
          await _db.into(_db.cashMovements).insert(
                CashMovementsCompanion.insert(
                  id: _uuid.v4(),
                  branchId: branchId,
                  shiftId: Value(shiftId),
                  type: 'withdrawal',
                  method: 'cash',
                  direction: 'out',
                  amountPiasters: remaining.abs(),
                  referenceId: Value(ticketId),
                  notes: Value(
                    'رد فرق عربون صيانة ${ticket.ticketNumber}',
                  ),
                  createdAt: nowSec,
                  updatedAt: nowSec,
                ),
              );
        }

        result = RepairDeliveryResult(
          ticketId: ticket.id,
          ticketNumber: ticket.ticketNumber,
          finalCostPiasters: finalCostPiasters,
          depositPaidPiasters: ticket.depositPaid,
          remainingCollectedPiasters: remaining,
          partsCostPiasters: ticket.partsCost,
          netProfitPiasters: finalCostPiasters - ticket.partsCost,
        );
      },
    );

    return result;
  }

  static Future<pw.Font> _loadArabicFont() async {
    try {
      final data = await rootBundle.load('assets/fonts/static/Cairo-Regular.ttf');
      return pw.Font.ttf(data);
    } catch (_) {
      try {
        final f = File('assets/fonts/static/Cairo-Regular.ttf');
        if (await f.exists()) {
          final bytes = await f.readAsBytes();
          return pw.Font.ttf(ByteData.view(bytes.buffer));
        }
      } catch (_) {}
      return pw.Font.helvetica();
    }
  }

  static Future<pw.Font> _loadArabicBoldFont() async {
    try {
      final data = await rootBundle.load('assets/fonts/static/Cairo-Bold.ttf');
      return pw.Font.ttf(data);
    } catch (_) {
      try {
        final f = File('assets/fonts/static/Cairo-Bold.ttf');
        if (await f.exists()) {
          final bytes = await f.readAsBytes();
          return pw.Font.ttf(ByteData.view(bytes.buffer));
        }
      } catch (_) {}
      return pw.Font.helveticaBold();
    }
  }

  static Future<Uint8List> generateRepairReceiptPdf(
    RepairTicket ticket, {
    List<RepairTicketPart> parts = const [],
    String? storeName,
    String? storePhone,
  }) async {
    final font = await _loadArabicFont();
    final boldFont = await _loadArabicBoldFont();
    final cfg = ReceiptSettingsService.current;
    final effectiveStore = storeName ??
        (cfg.storeName.isNotEmpty ? cfg.storeName : AppBranding.current.appName);
    final effectivePhone = storePhone ?? cfg.storePhone;
    final dateStr = DateFormat('yyyy/MM/dd hh:mm a').format(ticket.createdAt);

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(10),
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(
                effectiveStore,
                style: pw.TextStyle(font: boldFont, fontSize: 13),
              ),
            ),
            if (effectivePhone.isNotEmpty)
              pw.Center(
                child: pw.Text(effectivePhone, style: const pw.TextStyle(fontSize: 9)),
              ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                'إيصال استلام صيانة',
                style: pw.TextStyle(font: boldFont, fontSize: 11),
              ),
            ),
            pw.Divider(thickness: 0.8),
            pw.Text('رقم التذكرة: ${ticket.ticketNumber}',
                style: pw.TextStyle(font: boldFont, fontSize: 10)),
            pw.Text('التاريخ: $dateStr', style: const pw.TextStyle(fontSize: 8.5)),
            pw.Text('العميل: ${ticket.customerName}',
                style: const pw.TextStyle(fontSize: 9)),
            if (ticket.customerPhone.isNotEmpty)
              pw.Text('الهاتف: ${ticket.customerPhone}',
                  style: const pw.TextStyle(fontSize: 9)),
            pw.Divider(thickness: 0.5),
            pw.Text('الجهاز: ${ticket.deviceModel}',
                style: pw.TextStyle(font: boldFont, fontSize: 9.5)),
            if (ticket.imei != null && ticket.imei!.isNotEmpty)
              pw.Text('IMEI: ${ticket.imei}',
                  style: const pw.TextStyle(fontSize: 8.5)),
            pw.Text('العطل: ${ticket.issueDescription}',
                style: const pw.TextStyle(fontSize: 9)),
            if (ticket.intakeCondition != null &&
                ticket.intakeCondition!.isNotEmpty)
              pw.Text('حالة الاستلام: ${ticket.intakeCondition}',
                  style: const pw.TextStyle(fontSize: 8.5)),
            if (parts.isNotEmpty) ...[
              pw.Divider(thickness: 0.5),
              pw.Text('قطع الغيار المصروفة:',
                  style: pw.TextStyle(font: boldFont, fontSize: 9)),
              for (final p in parts)
                pw.Text('- ${p.partName} x${p.qty}',
                    style: const pw.TextStyle(fontSize: 8.5)),
            ],
            pw.Divider(thickness: 0.5),
            pw.Text(
              'التكلفة التقديرية: ${Money(ticket.estimatedCost).toDisplay()} ج.م',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Text(
              'العربون المدفوع: ${Money(ticket.depositPaid).toDisplay()} ج.م',
              style: const pw.TextStyle(fontSize: 9),
            ),
            if (ticket.status == 'delivered')
              pw.Text(
                'الإجمالي النهائي: ${Money(ticket.finalCost).toDisplay()} ج.م',
                style: pw.TextStyle(font: boldFont, fontSize: 10),
              ),
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.code128(),
                data: ticket.ticketNumber,
                width: 140,
                height: 36,
                drawText: true,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Center(
              child: pw.Text(
                'يرجى إحضار هذا الإيصال عند الاستلام',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }
}

