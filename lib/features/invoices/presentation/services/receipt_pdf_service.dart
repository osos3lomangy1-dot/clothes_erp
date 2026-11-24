import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../../core/constants/retail_sector.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../../core/theme/app_branding.dart';
import '../../../../core/utils/money.dart';
import '../../../customers/domain/entities/customer_entity.dart';
import '../../../installments/domain/entities/customer_installment_entity.dart';
import '../../../installments/domain/entities/installment_schedule_entry.dart';
import '../../../products/domain/entities/activity_type.dart';
import '../../../settings/data/services/activity_settings_service.dart';
import '../../data/services/receipt_settings_service.dart';
import '../../domain/entities/invoice_details_entity.dart';
import '../../domain/entities/invoice_item_details_entity.dart';
import '../../domain/entities/receipt_config.dart';
import '../../../delivery/domain/entities/delivery_order_entity.dart';

class ReceiptPdfService {
  static pw.Font? _cairoRegular;
  static pw.Font? _cairoBold;

  static Future<void> _loadFonts() async {
    if (_cairoRegular != null && _cairoBold != null) return;
    try {
      final regData = await rootBundle.load(
        'assets/fonts/static/Cairo-Regular.ttf',
      );
      _cairoRegular = pw.Font.ttf(regData);

      final boldData = await rootBundle.load(
        'assets/fonts/static/Cairo-Bold.ttf',
      );
      _cairoBold = pw.Font.ttf(boldData);
      return;
    } catch (_) {}

    try {
      final localFont = File('assets/fonts/static/Cairo-Regular.ttf');
      final localBold = File('assets/fonts/static/Cairo-Bold.ttf');
      if (await localFont.exists() && await localBold.exists()) {
        final regBytes = await localFont.readAsBytes();
        final boldBytes = await localBold.readAsBytes();
        _cairoRegular = pw.Font.ttf(regBytes.buffer.asByteData());
        _cairoBold = pw.Font.ttf(boldBytes.buffer.asByteData());
        return;
      }
    } catch (_) {}

    _cairoRegular = pw.Font.helvetica();
    _cairoBold = pw.Font.helveticaBold();
  }

  static Future<pw.Font> _loadArabicFont() async {
    await _loadFonts();
    return _cairoRegular!;
  }

  static Future<pw.Font> _loadArabicBoldFont() async {
    await _loadFonts();
    return _cairoBold!;
  }

  static Future<Uint8List> generateReceiptPdf(
    InvoiceDetailsEntity invoice, {
    ReceiptConfig? config,
    DeliveryOrderEntity? deliveryOrder,
    String? storeName,
    String? storePhone,
    String? storeAddress,
    String? returnPolicy,
    bool? isHospitality,
    String? orderType,
    String? tableNumber,
    String? orderNumber,
    String? wifiInfo,
    int? paidAmount,
    int? changeAmount,
  }) async {
    final cfg = config ?? ReceiptSettingsService.current;
    final effectiveStoreName =
        storeName ??
        (cfg.storeName.isNotEmpty
            ? cfg.storeName
            : AppBranding.current.appName);
    final effectiveStorePhone = storePhone ?? cfg.storePhone;
    final effectiveStoreAddress = storeAddress ?? cfg.storeAddress;

    String resolvedSectorMode = RetailSector.apparel;
    if (getIt.isRegistered<FeatureGate>()) {
      try {
        resolvedSectorMode =
            await getIt<FeatureGate>().getMeta(RetailSector.metaKey) ??
                RetailSector.apparel;
      } catch (_) {}
    }

    List<ActivityType> enabledActs = const <ActivityType>[];
    if (getIt.isRegistered<ActivitySettingsService>()) {
      final actService = getIt<ActivitySettingsService>();
      try {
        enabledActs = await actService.getEnabledActivities();
      } catch (_) {
        enabledActs = actService.cachedEnabledActivities;
      }
    }

    final bool isHospitalityMode =
        isHospitality ??
        (invoice.orderType != null ||
            invoice.tableNumber != null ||
            invoice.orderNumber != null ||
            cfg.storeActivity.contains('مطاعم') ||
            cfg.storeActivity.contains('كافيه') ||
            cfg.returnPolicy.contains('الأطعمة والمشروبات') ||
            ActivitySettingsService.isHospitalityResolved(
              sectorMode: resolvedSectorMode,
              enabledActivities: enabledActs,
            ));

    final effectiveOrderType = orderType ?? invoice.orderType ?? 'dineIn';
    final effectiveTableNumber = tableNumber ?? invoice.tableNumber ?? '1';
    final rawOrderNumber =
        orderNumber ?? invoice.orderNumber ?? invoice.shortRef;
    final effectiveOrderNumber = rawOrderNumber.startsWith('#')
        ? rawOrderNumber.substring(1)
        : rawOrderNumber;

    final String orderBadgeLabel;
    if (effectiveOrderType == 'dineIn' ||
        effectiveOrderType == 'dine_in' ||
        effectiveOrderType == 'صالة') {
      final tblStr = effectiveTableNumber.startsWith('رقم')
          ? effectiveTableNumber
          : 'رقم $effectiveTableNumber';
      orderBadgeLabel = '[ صالة - طاولة: $tblStr ]';
    } else if (effectiveOrderType == 'delivery' ||
        effectiveOrderType == 'توصيل' ||
        deliveryOrder != null) {
      final custName =
          invoice.customerName ?? deliveryOrder?.customerName ?? '';
      final custPhone =
          invoice.customerPhone ?? deliveryOrder?.customerPhone ?? '';
      if (custName.isNotEmpty && custPhone.isNotEmpty) {
        orderBadgeLabel = '[ دليفري - العميل: $custName - الهاتف: $custPhone ]';
      } else if (custName.isNotEmpty) {
        orderBadgeLabel = '[ دليفري - العميل: $custName ]';
      } else {
        orderBadgeLabel = '[ دليفري / توصيل طلبات ]';
      }
    } else {
      orderBadgeLabel = '[ تك أواي / سفري ]';
    }

    String effectiveReturnPolicy = returnPolicy ?? cfg.returnPolicy;
    String effectiveFooterGreeting = cfg.footerGreeting;
    final effectiveWifi =
        wifiInfo ??
        (cfg.wifiInfo.isNotEmpty ? cfg.wifiInfo : (invoice.wifiInfo ?? ''));

    if (isHospitalityMode) {
      if (effectiveReturnPolicy.contains('14 يوماً') ||
          effectiveReturnPolicy.contains('الملابس') ||
          effectiveReturnPolicy.contains('التكت') ||
          effectiveReturnPolicy == ReceiptConfig.defaults.returnPolicy) {
        effectiveReturnPolicy =
            'الأطعمة والمشروبات الطازجة غير قابلة للاسترجاع بعد مغادرة الطاولة أو استلام الأوردر لسلامة الغذاء.';
      }
      if (effectiveFooterGreeting == ReceiptConfig.defaults.footerGreeting ||
          effectiveFooterGreeting.isEmpty) {
        effectiveFooterGreeting = 'شكراً لزيارتكم ونتمنى لكم وجبة شهية!';
      }
    }

    final bool isCash =
        invoice.paymentMethod.contains('نقد') ||
        invoice.paymentMethod.toLowerCase().contains('cash');
    final effectivePaidAmount =
        paidAmount ?? invoice.paidAmount ?? (isCash ? invoice.total : null);
    final effectiveChangeAmount =
        changeAmount ?? invoice.changeAmount ?? (isCash ? 0 : null);

    final doc = pw.Document();
    final font = await _loadArabicFont();
    final boldFont = await _loadArabicBoldFont();

    final bool is58mm = cfg.paperWidthMm == 58;
    final rollFormat = PdfPageFormat(
      (is58mm ? 48 : 72) * PdfPageFormat.mm,
      double.infinity,
      marginAll: (is58mm ? 1.0 : 1.5) * PdfPageFormat.mm,
    );

    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');

    doc.addPage(
      pw.Page(
        pageFormat: rollFormat,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                // Store Header
                pw.Text(
                  effectiveStoreName,
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
                if (cfg.storeActivity.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    cfg.storeActivity,
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey700,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
                if (effectiveStoreAddress.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(
                    effectiveStoreAddress,
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey700,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
                if (effectiveStorePhone.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(
                    'هاتف: $effectiveStorePhone',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey700,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
                if (cfg.storePhoneSecondary.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(
                    'هاتف إضافي: ${cfg.storePhoneSecondary}',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey700,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
                if (cfg.taxNumber.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(
                    'س.ت / ضريبي: ${cfg.taxNumber}',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey700,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ],

                if (isHospitalityMode) ...[
                  pw.SizedBox(height: 6),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 6,
                    ),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: PdfColors.grey800,
                        width: 1.5,
                      ),
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(4),
                      ),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          (effectiveOrderType == 'dineIn' || effectiveOrderType == 'dine_in')
                              ? 'طلب رقم: #$effectiveOrderNumber'
                              : '#$effectiveOrderNumber',
                          style: pw.TextStyle(
                            font: boldFont,
                            fontSize: (effectiveOrderType == 'dineIn' || effectiveOrderType == 'dine_in') ? 16 : 22,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          orderBadgeLabel,
                          style: pw.TextStyle(
                            font: boldFont,
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],

                pw.SizedBox(height: 6),
                _dashedLine(),
                pw.SizedBox(height: 6),

                // Invoice Meta
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'رقم الفاتورة:',
                      style: pw.TextStyle(fontSize: 9, font: boldFont),
                    ),
                    pw.Text(
                      '#${invoice.shortRef}',
                      style: pw.TextStyle(fontSize: 10, font: boldFont),
                    ),
                  ],
                ),
                pw.SizedBox(height: 3),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('التاريخ:', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text(
                      dateFormat.format(invoice.date),
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ],
                ),
                if (cfg.showCashierName) ...[
                  pw.SizedBox(height: 3),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'الكاشير:',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                      pw.Text(
                        invoice.cashierName.isNotEmpty
                            ? invoice.cashierName
                            : invoice.cashierId,
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ],
                if (cfg.showCustomerInfo &&
                    invoice.customerName != null &&
                    invoice.customerName!.isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'العميل:',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                      pw.Text(
                        invoice.customerName!,
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ],
                if (cfg.showPaymentMethod) ...[
                  pw.SizedBox(height: 3),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'طريقة الدفع:',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                      pw.Text(
                        invoice.paymentMethod,
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ],

                pw.SizedBox(height: 6),
                _dashedLine(),
                pw.SizedBox(height: 6),

                // Table Header (2-Tier Layout)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'الصنف',
                      style: pw.TextStyle(font: boldFont, fontSize: 8.5),
                    ),
                    pw.Text(
                      'الكمية × السعر / الإجمالي',
                      style: pw.TextStyle(font: boldFont, fontSize: 8.5),
                    ),
                  ],
                ),
                pw.SizedBox(height: 3),
                _dottedLine(),
                pw.SizedBox(height: 3),

                // Items Rows
                ..._buildReceiptItemRows(
                  invoice.items,
                  cfg,
                  boldFont,
                  isHospitality: isHospitalityMode,
                ),

                pw.SizedBox(height: 4),
                _dashedLine(),
                pw.SizedBox(height: 3),

                // Total items and pieces count (Addendum 30.7)
                pw.Text(
                  'عدد الأصناف: ${invoice.items.length}  |  إجمالي القطع: ${invoice.totalQuantity}',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey800,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 3),
                _dashedLine(),
                pw.SizedBox(height: 4),

                // Financial Summary
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'المجموع الفرعي:',
                      style: const pw.TextStyle(fontSize: 8.5),
                    ),
                    pw.Text(
                      '${Money(invoice.subtotal).toDisplay()} ج.م',
                      style: const pw.TextStyle(fontSize: 8.5),
                    ),
                  ],
                ),
                if (invoice.totalPromotionDiscount > 0) ...[
                  pw.SizedBox(height: 2),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'خصم العروض:',
                        style: const pw.TextStyle(
                          fontSize: 8.5,
                          color: PdfColors.green700,
                        ),
                      ),
                      pw.Text(
                        '-${Money(invoice.totalPromotionDiscount).toDisplay()} ج.م',
                        style: const pw.TextStyle(
                          fontSize: 8.5,
                          color: PdfColors.green700,
                        ),
                      ),
                    ],
                  ),
                ],
                if (invoice.discountAmount > 0) ...[
                  pw.SizedBox(height: 2),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'خصم إضافي:',
                        style: const pw.TextStyle(
                          fontSize: 8.5,
                          color: PdfColors.red700,
                        ),
                      ),
                      pw.Text(
                        '-${Money(invoice.discountAmount).toDisplay()} ج.م',
                        style: const pw.TextStyle(
                          fontSize: 8.5,
                          color: PdfColors.red700,
                        ),
                      ),
                    ],
                  ),
                ],
                if (isHospitalityMode) ...[
                  if ((effectiveOrderType == 'dineIn' || effectiveOrderType == 'dine_in') && cfg.dineInServiceChargeEnabled) ...[
                    pw.SizedBox(height: 2),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'خدمة صالة (${cfg.dineInServiceChargeRate}%):',
                          style: const pw.TextStyle(fontSize: 8.5),
                        ),
                        pw.Text(
                          '+${Money((invoice.subtotal * (cfg.dineInServiceChargeRate / 100)).round()).toDisplay()} ج.م',
                          style: const pw.TextStyle(fontSize: 8.5),
                        ),
                      ],
                    ),
                  ],
                  if (cfg.taxEnabled) ...[
                    pw.SizedBox(height: 2),
                    if (cfg.taxInclusive)
                      pw.Text(
                        '* الأسعار شاملة ضريبة القيمة المضافة ${cfg.taxRate}%',
                        style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
                      )
                    else
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'ضريبة القيمة المضافة (${cfg.taxRate}%):',
                            style: const pw.TextStyle(fontSize: 8.5),
                          ),
                          pw.Text(
                            '+${Money((invoice.subtotal * (cfg.taxRate / 100)).round()).toDisplay()} ج.م',
                            style: const pw.TextStyle(fontSize: 8.5),
                          ),
                        ],
                      ),
                  ],
                ],
                pw.SizedBox(height: 4),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'الإجمالي المطلوب:',
                        style: pw.TextStyle(
                          font: boldFont,
                          fontSize: 10.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        '${Money(invoice.total).toDisplay()} ج.م',
                        style: pw.TextStyle(
                          font: boldFont,
                          fontSize: 11.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                if (effectivePaidAmount != null && effectivePaidAmount > 0) ...[
                  pw.SizedBox(height: 3),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'المبلغ المدفوع (نقداً):',
                        style: const pw.TextStyle(fontSize: 8.5),
                      ),
                      pw.Text(
                        '${Money(effectivePaidAmount).toDisplay()} ج.م',
                        style: const pw.TextStyle(fontSize: 8.5),
                      ),
                    ],
                  ),
                ],
                if (effectiveChangeAmount != null) ...[
                  pw.SizedBox(height: 2),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'الباقي المسترد للعميل:',
                        style: pw.TextStyle(
                          font: boldFont,
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        '${Money(effectiveChangeAmount).toDisplay()} ج.م',
                        style: pw.TextStyle(
                          font: boldFont,
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],

                if (cfg.showBarcode) ...[
                  pw.SizedBox(height: 8),
                  pw.Center(
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: invoice.shortRef,
                      width: 45,
                      height: 45,
                      drawText: false,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '#${invoice.shortRef}',
                    style: const pw.TextStyle(
                      fontSize: 7,
                      color: PdfColors.grey700,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ],

                // ── Delivery Slip Attachment (Task 21) ──
                if (deliveryOrder != null) ...[
                  pw.SizedBox(height: 8),
                  _dashedLine(),
                  pw.SizedBox(height: 4),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(
                      vertical: 3,
                      horizontal: 4,
                    ),
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey300,
                    ),
                    child: pw.Text(
                      deliveryOrder.isShippingCompany
                          ? 'إشعار شحن خارجي - ${deliveryOrder.courierName ?? "شركة الشحن"}'
                          : 'قسيمة توصيل دليفري (كابتن المتجر)',
                      style: pw.TextStyle(
                        font: boldFont,
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  if (deliveryOrder.waybillNumber != null &&
                      deliveryOrder.waybillNumber!.isNotEmpty) ...[
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'رقم البوليصة (Waybill):',
                          style: pw.TextStyle(font: boldFont, fontSize: 8),
                        ),
                        pw.Text(
                          deliveryOrder.waybillNumber!,
                          style: pw.TextStyle(font: boldFont, fontSize: 9),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 2),
                  ],
                  if (deliveryOrder.courierName != null &&
                      deliveryOrder.courierName!.isNotEmpty) ...[
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          deliveryOrder.isShippingCompany
                              ? 'شركة الشحن:'
                              : 'كابتن التوصيل:',
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                        pw.Text(
                          deliveryOrder.courierName!,
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 2),
                  ],
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'العميل المستلم:',
                        style: pw.TextStyle(font: boldFont, fontSize: 8),
                      ),
                      pw.Text(
                        deliveryOrder.customerName,
                        style: pw.TextStyle(font: boldFont, fontSize: 8),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 2),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'هاتف العميل:',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                      pw.Text(
                        deliveryOrder.customerPhone,
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 2),
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text(
                      'العنوان: ${deliveryOrder.deliveryAddress}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ),
                  if (deliveryOrder.notes != null &&
                      deliveryOrder.notes!.isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text(
                        'ملاحظات: ${deliveryOrder.notes!}',
                        style: const pw.TextStyle(
                          fontSize: 7,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ),
                  ],
                  pw.SizedBox(height: 4),
                  _dottedLine(),
                  pw.SizedBox(height: 4),
                  if (deliveryOrder.shippingFeePayer == 'customer_direct') ...[
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'قيمة المشتريات (للمحل):',
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                        pw.Text(
                          '${Money(deliveryOrder.orderTotalPiasters).toDisplay()} ج.م',
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ],
                    ),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'مصاريف الشحن (تدفع للشركة):',
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                        pw.Text(
                          '${Money(deliveryOrder.deliveryFeePiasters).toDisplay()} ج.م',
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 2),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey200,
                      ),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'المبلغ الإجمالي المطلوب:',
                            style: pw.TextStyle(font: boldFont, fontSize: 9),
                          ),
                          pw.Text(
                            '${Money(deliveryOrder.grandTotalPiasters).toDisplay()} ج.م',
                            style: pw.TextStyle(font: boldFont, fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey200,
                      ),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'المبلغ المطلوب تحصيله (COD):',
                            style: pw.TextStyle(
                              font: boldFont,
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.Text(
                            '${Money(deliveryOrder.grandTotalPiasters).toDisplay()} ج.م',
                            style: pw.TextStyle(
                              font: boldFont,
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],

                pw.SizedBox(height: 8),
                _dashedLine(),
                pw.SizedBox(height: 6),

                // Footer Policy & Greeting
                if (effectiveReturnPolicy.isNotEmpty) ...[
                  pw.Text(
                    effectiveReturnPolicy,
                    style: const pw.TextStyle(
                      fontSize: 7,
                      color: PdfColors.grey700,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 4),
                ],
                if (effectiveFooterGreeting.isNotEmpty) ...[
                  pw.Text(
                    effectiveFooterGreeting,
                    style: pw.TextStyle(font: boldFont, fontSize: 8),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 4),
                ],
                if (isHospitalityMode) ...[
                  if (effectiveWifi.isNotEmpty) ...[
                    pw.Text(
                      effectiveWifi,
                      style: const pw.TextStyle(
                        fontSize: 7,
                        color: PdfColors.grey700,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.SizedBox(height: 2),
                  ],
                  if (effectiveStorePhone.isNotEmpty) ...[
                    pw.Text(
                      'خدمة التوصيل والطلبات: $effectiveStorePhone',
                      style: const pw.TextStyle(
                        fontSize: 7,
                        color: PdfColors.grey700,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.SizedBox(height: 2),
                  ],
                ],
                pw.SizedBox(height: 6),
              ],
            ),
          );
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _dashedLine() {
    return pw.Divider(
      borderStyle: pw.BorderStyle.dashed,
      color: PdfColors.grey500,
      thickness: 0.8,
    );
  }

  static pw.Widget _dottedLine() {
    return pw.Divider(
      borderStyle: pw.BorderStyle.dotted,
      color: PdfColors.grey400,
      thickness: 0.8,
    );
  }

  static String _formatItemQty(InvoiceItemDetailsEntity it) {
    if (it.decimalQty != null && it.decimalQty! > 0) {
      final formatted = (it.decimalQty! % 1 == 0)
          ? it.decimalQty!.toInt().toString()
          : it.decimalQty!.toString();
      return '$formatted ${it.unit ?? "م"}';
    }
    return '${it.qty}';
  }

  static List<pw.Widget> _buildReceiptItemRows(
    List<InvoiceItemDetailsEntity> items,
    ReceiptConfig cfg,
    pw.Font boldFont, {
    bool isHospitality = false,
  }) {
    if (cfg.groupVariantsOnReceipt) {
      final Map<String, List<InvoiceItemDetailsEntity>> grouped = {};
      for (final it in items) {
        grouped.putIfAbsent(it.productName, () => []).add(it);
      }

      return grouped.values.map((group) {
        if (group.length == 1) {
          final it = group.first;
          final itemLabel =
              (!isHospitality &&
                  cfg.showItemDetails &&
                  (it.color.isNotEmpty || it.size.isNotEmpty))
              ? '${it.productName} (${it.color} - ${it.size})'
              : it.productName;
          final noteText =
              (it.kitchenNotes != null && it.kitchenNotes!.trim().isNotEmpty)
              ? it.kitchenNotes!.trim()
              : (it.modifiers.isNotEmpty ? it.modifiers.join(' - ') : null);

          return pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  itemLabel,
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    font: boldFont,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  softWrap: true,
                ),
                if (noteText != null) ...[
                  pw.SizedBox(height: 1),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(right: 4),
                    child: pw.Text(
                      '* ملاحظة: ($noteText)',
                      style: const pw.TextStyle(
                        fontSize: 7.5,
                        color: PdfColors.grey700,
                      ),
                      softWrap: true,
                    ),
                  ),
                ],
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '${_formatItemQty(it)} × ${Money(it.price).toDisplay()} ج.م',
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey800,
                      ),
                    ),
                    pw.Text(
                      '${Money(it.lineTotal).toDisplay()} ج.م',
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        font: boldFont,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        } else {
          final first = group.first;
          final totalQty = group.fold<int>(0, (sum, i) => sum + i.qty);
          final totalLine = group.fold<int>(0, (sum, i) => sum + i.lineTotal);

          final groupNotes = group
              .map(
                (i) =>
                    (i.kitchenNotes != null &&
                        i.kitchenNotes!.trim().isNotEmpty)
                    ? i.kitchenNotes!.trim()
                    : (i.modifiers.isNotEmpty ? i.modifiers.join(' - ') : null),
              )
              .whereType<String>()
              .toSet()
              .join('، ');

          final variantsSummary = group
              .map((i) {
                final desc = [
                  if (i.size.isNotEmpty && i.size != '-') i.size,
                  if (i.color.isNotEmpty && i.color != '-') i.color,
                ].join(' ');
                return '${_formatItemQty(i)}× ${desc.isNotEmpty ? desc : 'افتراضي'}';
              })
              .join('، ');

          return pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  first.productName,
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    font: boldFont,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  softWrap: true,
                ),
                if (!isHospitality) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(
                    '($variantsSummary)',
                    style: const pw.TextStyle(
                      fontSize: 7.5,
                      color: PdfColors.grey700,
                    ),
                    softWrap: true,
                  ),
                ],
                if (groupNotes.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(right: 4),
                    child: pw.Text(
                      '* ملاحظة: ($groupNotes)',
                      style: const pw.TextStyle(
                        fontSize: 7.5,
                        color: PdfColors.grey700,
                      ),
                      softWrap: true,
                    ),
                  ),
                ],
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '$totalQty قطع',
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey800,
                      ),
                    ),
                    pw.Text(
                      '${Money(totalLine).toDisplay()} ج.م',
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        font: boldFont,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }
      }).toList();
    }

    return items.map((it) {
      final itemLabel =
          (!isHospitality &&
              cfg.showItemDetails &&
              (it.color.isNotEmpty || it.size.isNotEmpty))
          ? '${it.productName} (${it.color} - ${it.size})'
          : it.productName;
      final noteText =
          (it.kitchenNotes != null && it.kitchenNotes!.trim().isNotEmpty)
          ? it.kitchenNotes!.trim()
          : (it.modifiers.isNotEmpty ? it.modifiers.join(' - ') : null);

      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              itemLabel,
              style: pw.TextStyle(
                fontSize: 8.5,
                font: boldFont,
                fontWeight: pw.FontWeight.bold,
              ),
              softWrap: true,
            ),
            if (noteText != null) ...[
              pw.SizedBox(height: 1),
              pw.Padding(
                padding: const pw.EdgeInsets.only(right: 4),
                child: pw.Text(
                  '* ملاحظة: ($noteText)',
                  style: const pw.TextStyle(
                    fontSize: 7.5,
                    color: PdfColors.grey700,
                  ),
                  softWrap: true,
                ),
              ),
            ],
            pw.SizedBox(height: 2),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${_formatItemQty(it)} × ${Money(it.price).toDisplay()} ج.م',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey800,
                  ),
                ),
                pw.Text(
                  '${Money(it.lineTotal).toDisplay()} ج.م',
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    font: boldFont,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }).toList();
  }

  static List<pw.Widget> _buildInstallmentItemRows(
    List<InvoiceItemDetailsEntity> items,
    ReceiptConfig cfg,
    pw.Font boldFont,
  ) {
    if (cfg.groupVariantsOnReceipt) {
      final Map<String, List<InvoiceItemDetailsEntity>> grouped = {};
      for (final it in items) {
        grouped.putIfAbsent(it.productName, () => []).add(it);
      }

      return grouped.values.map((group) {
        if (group.length == 1) {
          final it = group.first;
          final itemLabel = (it.color.isNotEmpty || it.size.isNotEmpty)
              ? '${it.productName} (${it.color} - ${it.size})'
              : it.productName;
          return pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Row(
              children: [
                pw.Expanded(
                  flex: 5,
                  child: pw.Text(
                    itemLabel,
                    style: pw.TextStyle(fontSize: 8, font: boldFont),
                  ),
                ),
                pw.Expanded(
                  flex: 2,
                  child: pw.Text(
                    _formatItemQty(it),
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ),
                pw.Expanded(
                  flex: 3,
                  child: pw.Text(
                    Money(it.price).toDisplay(),
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ),
                pw.Expanded(
                  flex: 3,
                  child: pw.Text(
                    Money(it.lineTotal).toDisplay(),
                    textAlign: pw.TextAlign.left,
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ),
              ],
            ),
          );
        } else {
          final first = group.first;
          final totalQty = group.fold<int>(0, (sum, i) => sum + i.qty);
          final totalLine = group.fold<int>(0, (sum, i) => sum + i.lineTotal);
          final variantsSummary = group
              .map((i) {
                final desc = [
                  if (i.size.isNotEmpty && i.size != '-') i.size,
                  if (i.color.isNotEmpty && i.color != '-') i.color,
                ].join(' ');
                return '${_formatItemQty(i)}× ${desc.isNotEmpty ? desc : 'افتراضي'}';
              })
              .join('، ');

          return pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Row(
              children: [
                pw.Expanded(
                  flex: 5,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        first.productName,
                        style: pw.TextStyle(fontSize: 8, font: boldFont),
                      ),
                      pw.Text(
                        '($variantsSummary)',
                        style: const pw.TextStyle(
                          fontSize: 7,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Expanded(
                  flex: 2,
                  child: pw.Text(
                    '$totalQty',
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ),
                pw.Expanded(
                  flex: 3,
                  child: pw.Text(
                    '-',
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ),
                pw.Expanded(
                  flex: 3,
                  child: pw.Text(
                    Money(totalLine).toDisplay(),
                    textAlign: pw.TextAlign.left,
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ),
              ],
            ),
          );
        }
      }).toList();
    }

    return items.map((it) {
      final itemLabel = (it.color.isNotEmpty || it.size.isNotEmpty)
          ? '${it.productName} (${it.color} - ${it.size})'
          : it.productName;
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          children: [
            pw.Expanded(
              flex: 5,
              child: pw.Text(
                itemLabel,
                style: pw.TextStyle(fontSize: 8, font: boldFont),
              ),
            ),
            pw.Expanded(
              flex: 2,
              child: pw.Text(
                _formatItemQty(it),
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
            pw.Expanded(
              flex: 3,
              child: pw.Text(
                Money(it.price).toDisplay(),
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
            pw.Expanded(
              flex: 3,
              child: pw.Text(
                Money(it.lineTotal).toDisplay(),
                textAlign: pw.TextAlign.left,
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  /// Direct print to physical printer or Windows print dialog
  static Future<void> printReceipt(
    InvoiceDetailsEntity invoice, {
    DeliveryOrderEntity? deliveryOrder,
  }) async {
    final pdfBytes = await generateReceiptPdf(
      invoice,
      deliveryOrder: deliveryOrder,
    );
    await Printing.layoutPdf(
      name: 'فاتورة_${invoice.shortRef}',
      onLayout: (PdfPageFormat format) async => pdfBytes,
    );
  }

  /// Save invoice as a PDF file to user-chosen location
  static Future<String?> saveReceiptAsPdf(
    InvoiceDetailsEntity invoice, {
    DeliveryOrderEntity? deliveryOrder,
  }) async {
    final pdfBytes = await generateReceiptPdf(
      invoice,
      deliveryOrder: deliveryOrder,
    );

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'تنزيل الفاتورة كملف PDF',
      fileName: 'فاتورة_${invoice.shortRef}.pdf',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (savePath != null) {
      final finalPath = savePath.toLowerCase().endsWith('.pdf')
          ? savePath
          : '$savePath.pdf';
      final file = File(finalPath);
      await file.writeAsBytes(pdfBytes);
      return file.path;
    }
    return null;
  }

  /// Generate complete Installment Contract & Schedule PDF (80mm thermal roll)
  static Future<Uint8List> generateInstallmentContractPdf({
    required InvoiceDetailsEntity invoice,
    required CustomerInstallmentEntity contract,
    required List<InstallmentScheduleEntry> schedule,
    CustomerEntity? customer,
    ReceiptConfig? config,
    String? storeName,
    String? storePhone,
    String? storeAddress,
    String? returnPolicy,
  }) async {
    final cfg = config ?? ReceiptSettingsService.current;
    final effectiveStoreName =
        storeName ??
        (cfg.storeName.isNotEmpty
            ? cfg.storeName
            : AppBranding.current.appName);
    final effectiveStorePhone = storePhone ?? cfg.storePhone;
    final effectiveStoreAddress = storeAddress ?? cfg.storeAddress;
    final effectiveReturnPolicy = returnPolicy ?? cfg.returnPolicy;
    final effectiveFooterGreeting = cfg.footerGreeting;

    final doc = pw.Document();
    final font = await _loadArabicFont();
    final boldFont = await _loadArabicBoldFont();

    final bool is58mm = cfg.paperWidthMm == 58;
    final rollFormat = PdfPageFormat(
      (is58mm ? 48 : 72) * PdfPageFormat.mm,
      double.infinity,
      marginAll: (is58mm ? 1.0 : 1.5) * PdfPageFormat.mm,
    );

    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');
    final shortContractId = contract.id.length >= 8
        ? contract.id.substring(0, 8).toUpperCase()
        : contract.id.toUpperCase();

    final totalFinancedWithInterest =
        contract.monthlyAmountPiasters * contract.durationMonths;
    final totalClientObligation =
        totalFinancedWithInterest + contract.downPaymentPiasters;
    final totalInterestPiasters =
        (totalFinancedWithInterest - contract.principalPiasters).clamp(
          0,
          999999999,
        );

    doc.addPage(
      pw.Page(
        pageFormat: rollFormat,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                // Store Header
                pw.Text(
                  effectiveStoreName,
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
                if (cfg.storeActivity.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    cfg.storeActivity,
                    style: const pw.TextStyle(
                      fontSize: 8.5,
                      color: PdfColors.grey700,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
                if (effectiveStoreAddress.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(
                    effectiveStoreAddress,
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey700,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
                if (effectiveStorePhone.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(
                    'هاتف: $effectiveStorePhone',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey700,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ],

                pw.SizedBox(height: 6),
                _dashedLine(),
                pw.SizedBox(height: 4),

                // Contract & Invoice Title Banner
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    vertical: 3,
                    horizontal: 8,
                  ),
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  child: pw.Text(
                    'فاتورة وعقد بيع بالتقسيط',
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.SizedBox(height: 4),

                // Metadata Rows
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'رقم الفاتورة:',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                    pw.Text(
                      '#${invoice.shortRef}',
                      style: pw.TextStyle(font: boldFont, fontSize: 8),
                    ),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'رقم عقد التقسيط:',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                    pw.Text(
                      '#$shortContractId',
                      style: pw.TextStyle(font: boldFont, fontSize: 8),
                    ),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'التاريخ والوقت:',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                    pw.Text(
                      dateFormat.format(invoice.date),
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'الكاشير / المحرر:',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                    pw.Text(
                      invoice.cashierName.isNotEmpty
                          ? invoice.cashierName
                          : invoice.cashierId,
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ],
                ),

                // Customer Info
                pw.SizedBox(height: 4),
                _dottedLine(),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'العميل / المدين:',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                    pw.Text(
                      customer?.name ?? invoice.customerName ?? 'عميل مسجل',
                      style: pw.TextStyle(font: boldFont, fontSize: 8),
                    ),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'رقم الهاتف:',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                    pw.Text(
                      customer?.phone ?? invoice.customerPhone ?? '-',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ],
                ),

                pw.SizedBox(height: 6),
                _dashedLine(),
                pw.SizedBox(height: 4),

                // Items Table Header
                pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 5,
                      child: pw.Text(
                        'الصنف',
                        style: pw.TextStyle(font: boldFont, fontSize: 8),
                      ),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text(
                        'ك',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(font: boldFont, fontSize: 8),
                      ),
                    ),
                    pw.Expanded(
                      flex: 3,
                      child: pw.Text(
                        'السعر',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(font: boldFont, fontSize: 8),
                      ),
                    ),
                    pw.Expanded(
                      flex: 3,
                      child: pw.Text(
                        'الإجمالي',
                        textAlign: pw.TextAlign.left,
                        style: pw.TextStyle(font: boldFont, fontSize: 8),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 3),
                _dottedLine(),
                pw.SizedBox(height: 3),

                // Items List
                ..._buildInstallmentItemRows(invoice.items, cfg, boldFont),

                pw.SizedBox(height: 6),
                _dashedLine(),
                pw.SizedBox(height: 4),

                // Installment Financial Statement Box
                pw.Container(
                  padding: const pw.EdgeInsets.all(5),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(4),
                    ),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        'البيان المالي للتقسيط',
                        style: pw.TextStyle(
                          font: boldFont,
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'إجمالي المشتريات (أصل الفاتورة):',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                          pw.Text(
                            '${Money(invoice.total).toDisplay()} ج.م',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 2),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'الدفعة المقدمة (المسددة نقداً):',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                          pw.Text(
                            '${Money(contract.downPaymentPiasters).toDisplay()} ج.م',
                            style: pw.TextStyle(font: boldFont, fontSize: 8),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 2),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'المبلغ الممول (أصل الدين):',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                          pw.Text(
                            '${Money(contract.principalPiasters).toDisplay()} ج.م',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 2),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'نسبة الفائدة المقررة:',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                          pw.Text(
                            '${contract.interestBp / 100}%',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ],
                      ),
                      if (totalInterestPiasters > 0) ...[
                        pw.SizedBox(height: 2),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              'إجمالي الفائدة المحسوبة:',
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                            pw.Text(
                              '${Money(totalInterestPiasters).toDisplay()} ج.م',
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                          ],
                        ),
                      ],
                      pw.SizedBox(height: 2),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'مدة التقسيط:',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                          pw.Text(
                            '${contract.durationMonths} شهراً',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 2),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'قيمة القسط الشهري:',
                            style: pw.TextStyle(font: boldFont, fontSize: 8.5),
                          ),
                          pw.Text(
                            '${Money(contract.monthlyAmountPiasters).toDisplay()} ج.م / شهر',
                            style: pw.TextStyle(font: boldFont, fontSize: 9),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 3),
                      _dottedLine(),
                      pw.SizedBox(height: 2),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'إجمالي التزام العميل (مقدم + أقساط):',
                            style: pw.TextStyle(font: boldFont, fontSize: 8.5),
                          ),
                          pw.Text(
                            '${Money(totalClientObligation).toDisplay()} ج.م',
                            style: pw.TextStyle(font: boldFont, fontSize: 9.5),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Schedule Table (جدول استحقاق الأقساط)
                if (schedule.isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  _dashedLine(),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'جدول استحقاق الأقساط الشهرية',
                    style: pw.TextStyle(font: boldFont, fontSize: 9),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text(
                          'م',
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(font: boldFont, fontSize: 7.5),
                        ),
                      ),
                      pw.Expanded(
                        flex: 5,
                        child: pw.Text(
                          'تاريخ الاستحقاق',
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(font: boldFont, fontSize: 7.5),
                        ),
                      ),
                      pw.Expanded(
                        flex: 4,
                        child: pw.Text(
                          'المبلغ',
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(font: boldFont, fontSize: 7.5),
                        ),
                      ),
                      pw.Expanded(
                        flex: 3,
                        child: pw.Text(
                          'الحالة',
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(font: boldFont, fontSize: 7.5),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 2),
                  _dottedLine(),
                  ...schedule.map((entry) {
                    final dueStr = DateFormat(
                      'yyyy/MM/dd',
                    ).format(entry.dueDate);
                    return pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                      child: pw.Row(
                        children: [
                          pw.Expanded(
                            flex: 2,
                            child: pw.Text(
                              '${entry.installmentNumber}',
                              textAlign: pw.TextAlign.center,
                              style: const pw.TextStyle(fontSize: 7.5),
                            ),
                          ),
                          pw.Expanded(
                            flex: 5,
                            child: pw.Text(
                              dueStr,
                              textAlign: pw.TextAlign.center,
                              style: const pw.TextStyle(fontSize: 7.5),
                            ),
                          ),
                          pw.Expanded(
                            flex: 4,
                            child: pw.Text(
                              Money(entry.amountPiasters).toDisplay(),
                              textAlign: pw.TextAlign.center,
                              style: const pw.TextStyle(fontSize: 7.5),
                            ),
                          ),
                          pw.Expanded(
                            flex: 3,
                            child: pw.Text(
                              'مستحق',
                              textAlign: pw.TextAlign.center,
                              style: const pw.TextStyle(fontSize: 7),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],

                pw.SizedBox(height: 6),
                _dashedLine(),
                pw.SizedBox(height: 4),

                // Customer Legal Acknowledgment & Commitment
                pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(4),
                    ),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Center(
                        child: pw.Text(
                          'إقرار استلام السلع وتعهد بالسداد',
                          style: pw.TextStyle(font: boldFont, fontSize: 8.5),
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'أقر أنا الموقع أدناه باستلام السلع الموضحة أعلاه بحالة جيدة وسليمة ومطابقة للمواصفات، وأتعهد بالتزامي الكامل بسداد الأقساط الشهرية الموضحة في جدول الاستحقاق في مواعيدها دون أي تأخير، ويُعد هذا الإيصال سندا تنفيذيا وقانونيا ملزما.',
                        style: const pw.TextStyle(fontSize: 7, height: 1.3),
                        textAlign: pw.TextAlign.justify,
                      ),
                      pw.SizedBox(height: 8),
                      pw.Row(
                        children: [
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  'اسم العميل: _____________________',
                                  style: const pw.TextStyle(fontSize: 7),
                                ),
                                pw.SizedBox(height: 4),
                                pw.Text(
                                  'الرقم القومي: ___________________',
                                  style: const pw.TextStyle(fontSize: 7),
                                ),
                              ],
                            ),
                          ),
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  'التوقيع: _______________________',
                                  style: const pw.TextStyle(fontSize: 7),
                                ),
                                pw.SizedBox(height: 4),
                                pw.Text(
                                  'البصمة: [                     ]',
                                  style: const pw.TextStyle(fontSize: 7),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                pw.SizedBox(height: 6),
                _dashedLine(),
                pw.SizedBox(height: 4),

                // Footer Return Policy & Greeting
                if (effectiveReturnPolicy.isNotEmpty) ...[
                  pw.Text(
                    effectiveReturnPolicy,
                    style: const pw.TextStyle(
                      fontSize: 7,
                      color: PdfColors.grey700,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 3),
                ],
                if (effectiveFooterGreeting.isNotEmpty) ...[
                  pw.Text(
                    effectiveFooterGreeting,
                    style: pw.TextStyle(font: boldFont, fontSize: 7.5),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 6),
                ],
              ],
            ),
          );
        },
      ),
    );

    return doc.save();
  }

  /// Print installment contract & payment schedule to thermal printer
  static Future<void> printInstallmentContractReceipt({
    required InvoiceDetailsEntity invoice,
    required CustomerInstallmentEntity contract,
    required List<InstallmentScheduleEntry> schedule,
    CustomerEntity? customer,
  }) async {
    final pdfBytes = await generateInstallmentContractPdf(
      invoice: invoice,
      contract: contract,
      schedule: schedule,
      customer: customer,
    );
    await Printing.layoutPdf(
      name: 'عقد_تقسيط_${invoice.shortRef}',
      onLayout: (PdfPageFormat format) async => pdfBytes,
    );
  }

  /// Save installment contract & payment schedule as PDF
  static Future<String?> saveInstallmentContractReceiptAsPdf({
    required InvoiceDetailsEntity invoice,
    required CustomerInstallmentEntity contract,
    required List<InstallmentScheduleEntry> schedule,
    CustomerEntity? customer,
  }) async {
    final pdfBytes = await generateInstallmentContractPdf(
      invoice: invoice,
      contract: contract,
      schedule: schedule,
      customer: customer,
    );

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'تنزيل عقد التقسيط كملف PDF',
      fileName: 'عقد_تقسيط_${invoice.shortRef}.pdf',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (savePath != null) {
      final finalPath = savePath.toLowerCase().endsWith('.pdf')
          ? savePath
          : '$savePath.pdf';
      final file = File(finalPath);
      await file.writeAsBytes(pdfBytes);
      return file.path;
    }
    return null;
  }
}
