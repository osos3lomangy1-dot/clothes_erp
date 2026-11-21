import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/pre_order_batch_entity.dart';
import '../../domain/entities/pre_order_entity.dart';
import '../../domain/entities/pre_order_item_entity.dart';

class PreOrderExcelService {
  static const _uuid = Uuid();

  /// 1. إنشاء وتحميل قالب إكسيل فارغ للأصناف
  static Future<String?> downloadTemplate() async {
    final excel = Excel.createExcel();
    const sheetName = 'قالب_أصناف_الحجز';
    final sheet = excel[sheetName];
    excel.setDefaultSheet(sheetName);

    // الرأس (Headers)
    sheet.appendRow([
      TextCellValue('اسم الصنف أو كود شي إن *'),
      TextCellValue('المقاس واللون والمواصفات'),
      TextCellValue('الكمية'),
      TextCellValue('تكلفة المندوب (ج.م)'),
      TextCellValue('عمولة التاجر (ج.م)'),
      TextCellValue('سعر البيع للعميل (ج.م)'),
      TextCellValue('رابط المنتج (شي إن/المورد)'),
      TextCellValue('ملاحظات'),
    ]);

    // أمثلة توضيحية للمستخدم
    sheet.appendRow([
      TextCellValue('فستان سهرة مخملي تركي'),
      TextCellValue('L - أسود'),
      IntCellValue(1),
      DoubleCellValue(450.0),
      DoubleCellValue(50.0),
      DoubleCellValue(500.0),
      TextCellValue('https://shein.com/item-sample-1'),
      TextCellValue('مقاس مضبوط حسب الجدول'),
    ]);

    sheet.appendRow([
      TextCellValue('تيشيرت بولو كاجوال'),
      TextCellValue('XL - كحلي'),
      IntCellValue(2),
      DoubleCellValue(180.0),
      DoubleCellValue(40.0),
      DoubleCellValue(220.0),
      TextCellValue('https://shein.com/item-sample-2'),
      TextCellValue('قطن 100%'),
    ]);

    final bytes = excel.encode();
    if (bytes == null) return null;

    final fileName = 'نموذج_أصناف_الحجز_المسبق.xlsx';
    return await _saveFile(bytes, fileName, 'اختر مكان حفظ نموذج الإكسيل');
  }

  /// 2. استيراد وقراءة الأصناف من ملف إكسيل (.xlsx)
  static Future<List<PreOrderItemEntity>?> pickAndImportItems({
    int defaultCommissionPiasters = 0,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null) return null;

    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) return null;

    // العثور على الشيت المناسب
    Sheet? sheet;
    for (final key in excel.tables.keys) {
      if (key.contains('أصناف') || key.contains('حجز') || key.toLowerCase().contains('order')) {
        sheet = excel.tables[key];
        break;
      }
    }
    sheet ??= excel.tables.values.first;

    if (sheet.rows.isEmpty) return [];

    // التعرف التلقائي على الأعمدة
    int headerRowIndex = 0;
    int colName = -1;
    int colDesc = -1;
    int colQty = -1;
    int colCost = -1;
    int colCommission = -1;
    int colSale = -1;
    int colUrl = -1;
    int colNotes = -1;

    for (int r = 0; r < sheet.rows.length && r < 5; r++) {
      final row = sheet.rows[r];
      for (int c = 0; c < row.length; c++) {
        final val = _cellToString(row[c]).toLowerCase().trim();
        if (val.contains('صنف') || val.contains('اسم') || val.contains('name') || val.contains('منتج')) {
          if (colName == -1) colName = c;
        } else if (val.contains('مقاس') || val.contains('لون') || val.contains('وصف') || val.contains('size') || val.contains('color')) {
          if (colDesc == -1) colDesc = c;
        } else if (val.contains('كمية') || val.contains('عدد') || val.contains('qty') || val.contains('count')) {
          if (colQty == -1) colQty = c;
        } else if (val.contains('تكلفة') || val.contains('جملة') || val.contains('مندوب') || val.contains('cost')) {
          if (colCost == -1) colCost = c;
        } else if (val.contains('عمولة') || val.contains('markup') || val.contains('commission') || val.contains('ربح')) {
          if (colCommission == -1) colCommission = c;
        } else if (val.contains('بيع') || val.contains('سعر') || val.contains('price') || val.contains('sale')) {
          if (colSale == -1) colSale = c;
        } else if (val.contains('رابط') || val.contains('لينك') || val.contains('url') || val.contains('link') || val.contains('shein')) {
          if (colUrl == -1) colUrl = c;
        } else if (val.contains('ملاحظ') || val.contains('note')) {
          if (colNotes == -1) colNotes = c;
        }
      }
      if (colName != -1) {
        headerRowIndex = r;
        break;
      }
    }

    // تعيين قيم افتراضية في حال عدم وجود عناوين صريحة
    if (colName == -1) colName = 0;
    if (colDesc == -1) colDesc = 1;
    if (colQty == -1) colQty = 2;
    if (colCost == -1) colCost = 3;
    if (colCommission == -1) colCommission = 4;
    if (colSale == -1) colSale = 5;
    if (colUrl == -1) colUrl = 6;
    if (colNotes == -1) colNotes = 7;

    final parsedItems = <PreOrderItemEntity>[];

    for (int r = headerRowIndex + 1; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      if (row.isEmpty) continue;

      final name = colName < row.length ? _cellToString(row[colName]) : '';
      if (name.trim().isEmpty) continue; // تخطي الصفوف الفارغة

      final desc = colDesc < row.length ? _cellToString(row[colDesc]) : '';
      final qtyRaw = colQty < row.length ? _cellToInt(row[colQty]) : 1;
      final quantity = qtyRaw > 0 ? qtyRaw : 1;

      final costNum = colCost < row.length ? _cellToDouble(row[colCost]) : 0.0;
      final commNum = colCommission < row.length ? _cellToDouble(row[colCommission]) : 0.0;
      final saleNum = colSale < row.length ? _cellToDouble(row[colSale]) : 0.0;
      final url = colUrl < row.length ? _cellToString(row[colUrl]) : '';
      final notes = colNotes < row.length ? _cellToString(row[colNotes]) : '';

      int costPiasters = (costNum * 100).round();
      int commPiasters = (commNum * 100).round();
      int salePiasters = (saleNum * 100).round();

      // الحساب اللحظي المتبادل في حال نقص أحد الحقول
      if (salePiasters <= 0) {
        if (costPiasters > 0 && commPiasters > 0) {
          salePiasters = costPiasters + commPiasters;
        } else if (costPiasters > 0) {
          commPiasters = defaultCommissionPiasters;
          salePiasters = costPiasters + commPiasters;
        }
      }

      if (commPiasters <= 0 && costPiasters > 0 && salePiasters > costPiasters) {
        commPiasters = salePiasters - costPiasters;
      }

      final totalPiasters = quantity * salePiasters;

      parsedItems.add(
        PreOrderItemEntity(
          id: _uuid.v4(),
          preOrderId: '',
          productName: name.trim(),
          variantDescription: desc.trim().isNotEmpty ? desc.trim() : null,
          quantity: quantity,
          unitPricePiasters: salePiasters,
          totalPricePiasters: totalPiasters,
          costPricePiasters: costPiasters,
          commissionPiasters: commPiasters,
          itemUrl: url.trim().isNotEmpty ? url.trim() : null,
          notes: notes.trim().isNotEmpty ? notes.trim() : null,
        ),
      );
    }

    return parsedItems;
  }

  /// 3. تصدير شيت إكسيل نظيف للمندوب (بدون أسعار بيع العميل وبدون أرباح التاجر)
  static Future<String?> exportAgentSheet(PreOrderEntity order) async {
    final excel = Excel.createExcel();
    final safeOrderNum = order.orderNumber.replaceAll(RegExp(r'[^\w-]'), '_');
    final sheetName = 'طلبية_$safeOrderNum';
    final sheet = excel[sheetName];
    excel.setDefaultSheet(sheetName);

    // ترويسة الطلبية للمندوب
    sheet.appendRow([TextCellValue('كشف طلبية وشحن للمندوب / وسيط الاستيراد')]);
    sheet.appendRow([TextCellValue('رقم الأوردر:'), TextCellValue(order.orderNumber)]);
    sheet.appendRow([TextCellValue('اسم المندوب:'), TextCellValue(order.agentName ?? 'غير محدد')]);
    sheet.appendRow([TextCellValue('رقم البوليصة / التتبع:'), TextCellValue(order.trackingNumber ?? 'غير محدد')]);
    sheet.appendRow([TextCellValue('اسم العميل المستلم:'), TextCellValue(order.customerName)]);
    sheet.appendRow([TextCellValue('رقم هاتف العميل:'), TextCellValue(order.customerPhone)]);
    sheet.appendRow([
      TextCellValue('تاريخ الطلب:'),
      TextCellValue('${order.createdAt.year}-${order.createdAt.month.toString().padLeft(2, '0')}-${order.createdAt.day.toString().padLeft(2, '0')}'),
    ]);
    sheet.appendRow([TextCellValue('')]); // سطر فارغ

    // رأس جدول الأصناف
    sheet.appendRow([
      TextCellValue('#'),
      TextCellValue('اسم الصنف أو كود شي إن'),
      TextCellValue('المقاس واللون والمواصفات'),
      TextCellValue('الكمية المطلوبة'),
      TextCellValue('رابط المنتج على الموقع'),
      TextCellValue('ملاحظات خاصة'),
    ]);

    // الأصناف (بدون سعر البيع وبدون الربح)
    for (int i = 0; i < order.items.length; i++) {
      final it = order.items[i];
      sheet.appendRow([
        IntCellValue(i + 1),
        TextCellValue(it.productName),
        TextCellValue(it.variantDescription ?? '-'),
        IntCellValue(it.quantity),
        TextCellValue(it.itemUrl ?? '-'),
        TextCellValue(it.notes ?? '-'),
      ]);
    }

    final bytes = excel.encode();
    if (bytes == null) return null;

    final fileName = 'اوردر_${safeOrderNum}_كشف_المندوب.xlsx';
    return await _saveFile(bytes, fileName, 'حفظ كشف الطلبية للمندوب');
  }

  /// 4. تصدير كشف كامل للشحنة المجمعة للمندوب / وسيط الشحن (بدون أسعار بيع العملاء وبدون أرباح التاجر)
  static Future<String?> exportBatchToExcel(PreOrderBatchEntity batch) async {
    final excel = Excel.createExcel();
    final safeBatchNum = batch.batchNumber.replaceAll(RegExp(r'[^\w-]'), '_');
    final sheetName = 'شحنة_$safeBatchNum';
    final sheet = excel[sheetName];
    excel.setDefaultSheet(sheetName);

    // ترويسة الشحنة للمندوب
    sheet.appendRow([TextCellValue('كشف شحنة مجمعة للمندوب / وسيط الاستيراد')]);
    sheet.appendRow([TextCellValue('كود / اسم الشحنة:'), TextCellValue(batch.batchNumber)]);
    sheet.appendRow([TextCellValue('اسم المندوب / الوسيط:'), TextCellValue(batch.agentName ?? 'غير محدد')]);
    sheet.appendRow([TextCellValue('رقم البوليصة / التتبع:'), TextCellValue(batch.trackingNumber ?? 'غير محدد')]);
    sheet.appendRow([TextCellValue('إجمالي عدد العملاء:'), IntCellValue(batch.totalOrdersCount)]);
    sheet.appendRow([TextCellValue('إجمالي عدد القطع:'), IntCellValue(batch.totalPiecesCount)]);
    sheet.appendRow([
      TextCellValue('تاريخ إنشاء الشحنة:'),
      TextCellValue(
        '${batch.createdAt.year}-${batch.createdAt.month.toString().padLeft(2, '0')}-${batch.createdAt.day.toString().padLeft(2, '0')}',
      ),
    ]);
    sheet.appendRow([TextCellValue('')]); // سطر فارغ

    // رأس جدول أصناف الشحنة
    sheet.appendRow([
      TextCellValue('#'),
      TextCellValue('اسم العميل'),
      TextCellValue('هاتف العميل'),
      TextCellValue('رقم الأوردر'),
      TextCellValue('اسم الصنف أو كود شي إن'),
      TextCellValue('المقاس واللون والمواصفات'),
      TextCellValue('الكمية المطلوبة'),
      TextCellValue('تكلفة المندوب للقطعة (ج.م)'),
      TextCellValue('إجمالي التكلفة (ج.م)'),
      TextCellValue('رابط المنتج على الموقع'),
      TextCellValue('ملاحظات خاصة'),
    ]);

    int itemIndex = 1;
    for (final order in batch.orders) {
      for (final it in order.items) {
        final costEach = it.costPricePiasters > 0 ? it.costPricePiasters / 100.0 : 0.0;
        final totalCost = it.totalCostPiasters > 0 ? it.totalCostPiasters / 100.0 : costEach * it.quantity;
        sheet.appendRow([
          IntCellValue(itemIndex++),
          TextCellValue(order.customerName),
          TextCellValue(order.customerPhone),
          TextCellValue(order.orderNumber),
          TextCellValue(it.productName),
          TextCellValue(it.variantDescription ?? '-'),
          IntCellValue(it.quantity),
          DoubleCellValue(costEach),
          DoubleCellValue(totalCost),
          TextCellValue(it.itemUrl ?? '-'),
          TextCellValue(it.notes ?? '-'),
        ]);
      }
    }

    final bytes = excel.encode();
    if (bytes == null) return null;

    final fileName = 'شحنة_${safeBatchNum}_كشف_المندوب.xlsx';
    return await _saveFile(bytes, fileName, 'حفظ كشف الشحنة للمندوب');
  }

  // --- دوال مساعدة لحفظ وقراءة الخلايا ---

  static Future<String?> _saveFile(List<int> bytes, String defaultFileName, String dialogTitle) async {
    String? outputFile;
    try {
      outputFile = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
    } catch (_) {}

    outputFile ??= await _getDefaultExportPath(defaultFileName);

    if (!outputFile.endsWith('.xlsx')) outputFile = '$outputFile.xlsx';
    final file = File(outputFile);
    await file.writeAsBytes(bytes);
    return outputFile;
  }

  static Future<String> _getDefaultExportPath(String defaultFileName) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return '${dir.path}/$defaultFileName';
    } catch (_) {
      final dir = Directory.current;
      return '${dir.path}/$defaultFileName';
    }
  }

  static String _cellToString(Data? cell) {
    if (cell == null || cell.value == null) return '';
    final val = cell.value;
    if (val is TextCellValue) return val.value.text ?? '';
    return val.toString().trim();
  }

  static double _cellToDouble(Data? cell) {
    if (cell == null || cell.value == null) return 0.0;
    final str = _cellToString(cell).replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(str) ?? 0.0;
  }

  static int _cellToInt(Data? cell) {
    if (cell == null || cell.value == null) return 0;
    final str = _cellToString(cell).replaceAll(RegExp(r'[^\d]'), '');
    return int.tryParse(str) ?? 0;
  }
}

