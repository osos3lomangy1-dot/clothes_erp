import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;
import '../database/app_database.dart';
import '../database/branch_provider.dart';
import '../database/tx_writer.dart';
import '../di/injection.dart';

class ExcelProductRow {
  final String productName;
  final String categoryName;
  final String sku;
  final String size;
  final String color;
  final double costPrice;
  final double salePrice;
  final int quantity;
  final int minStock;

  ExcelProductRow({
    required this.productName,
    required this.categoryName,
    required this.sku,
    required this.size,
    required this.color,
    required this.costPrice,
    required this.salePrice,
    required this.quantity,
    this.minStock = 5,
  });
}

enum DuplicateResolution {
  updatePricesAndQty, // تعيين الكمية والأسعار من ملف الإكسيل
  addQuantity, // زيادة كمية الإكسيل فوق الكمية الحالية
  skip, // تخطي صنف الإكسيل والإبقاء على الحالي
}

class DuplicateConflict {
  final ExcelProductRow excelRow;
  final ProductVariant existingVariant;
  final String existingProductName;
  DuplicateResolution resolution;

  DuplicateConflict({
    required this.excelRow,
    required this.existingVariant,
    required this.existingProductName,
    this.resolution = DuplicateResolution.updatePricesAndQty,
  });
}

class ExcelImportAnalysis {
  final List<ExcelProductRow> newRows;
  final List<DuplicateConflict> conflicts;
  final int totalRows;

  ExcelImportAnalysis({
    required this.newRows,
    required this.conflicts,
    required this.totalRows,
  });
}

class ExcelService {
  final _uuid = const Uuid();

  Future<String?> exportProducts() async {
    final db = getIt<AppDatabase>();
    final products = await (db.select(
      db.products,
    )..where((p) => p.deletedAt.isNull())).get();
    final variants = await (db.select(
      db.productVariants,
    )..where((v) => v.deletedAt.isNull())).get();
    final categories = await (db.select(
      db.categories,
    )..where((c) => c.deletedAt.isNull())).get();

    final catMap = {for (var c in categories) c.id: c.name};
    final prodMap = {for (var p in products) p.id: p};

    final excel = Excel.createExcel();
    const sheetName = 'المنتجات';
    final sheet = excel[sheetName];
    excel.setDefaultSheet(sheetName);

    sheet.appendRow([
      TextCellValue('اسم المنتج'),
      TextCellValue('التصنيف'),
      TextCellValue('كود الصنف (SKU)'),
      TextCellValue('المقاس'),
      TextCellValue('اللون'),
      TextCellValue('سعر التكلفة'),
      TextCellValue('سعر البيع'),
      TextCellValue('الكمية'),
      TextCellValue('حد الطلب'),
    ]);

    for (final v in variants) {
      final prod = prodMap[v.productId];
      final prodName = prod?.name ?? v.productId;
      final catName = prod != null ? (catMap[prod.categoryId] ?? '') : '';

      sheet.appendRow([
        TextCellValue(prodName),
        TextCellValue(catName),
        TextCellValue(v.sku),
        TextCellValue(v.size),
        TextCellValue(v.color),
        DoubleCellValue(v.costPrice / 100.0),
        DoubleCellValue(v.sellPrice / 100.0),
        IntCellValue(v.quantity),
        IntCellValue(prod?.minStock ?? 5),
      ]);
    }

    final bytes = excel.encode();
    if (bytes == null) throw Exception('فشل ترميز ملف الإكسيل');

    final nowStr = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')[0];
    final defaultFileName = 'منتجات_المتجر_$nowStr.xlsx';

    String? outputFile;
    try {
      outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'اختر مكان حفظ ملف المنتجات',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
    } catch (_) {}

    outputFile ??= await _getDefaultExportPath(defaultFileName);

    if (outputFile != null) {
      if (!outputFile.endsWith('.xlsx')) outputFile = '$outputFile.xlsx';
      final file = File(outputFile);
      await file.writeAsBytes(bytes);
      return outputFile;
    }
    return null;
  }

  Future<String> _getDefaultExportPath(String defaultFileName) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return '${dir.path}/$defaultFileName';
    } catch (_) {
      final dir = Directory.current;
      return '${dir.path}/$defaultFileName';
    }
  }

  Future<ExcelImportAnalysis> analyzeExcel(Uint8List bytes) async {
    final db = getIt<AppDatabase>();
    final excel = Excel.decodeBytes(bytes);

    Sheet? targetSheet;
    for (final table in excel.tables.keys) {
      if (table == 'المنتجات' || table.toLowerCase().contains('product')) {
        targetSheet = excel.tables[table];
        break;
      }
    }
    targetSheet ??= excel.tables.values.firstOrNull;

    if (targetSheet == null || targetSheet.rows.isEmpty) {
      throw Exception('ملف الإكسيل فارغ أو لا يحتوي على أوراق عمل صالحة');
    }

    // Determine column indices from header row
    final headerRow = targetSheet.rows.first;
    int colProd = -1;
    int colCat = -1;
    int colSku = -1;
    int colSize = -1;
    int colColor = -1;
    int colCost = -1;
    int colSell = -1;
    int colQty = -1;
    int colMin = -1;

    for (int i = 0; i < headerRow.length; i++) {
      final h = _cellToString(headerRow[i]).toLowerCase();
      if (h.contains('منتج') ||
          h.contains('product') ||
          h.contains('name') ||
          h.contains('اسم'))
        colProd = i;
      if (h.contains('تصنيف') || h.contains('category') || h.contains('قسم'))
        colCat = i;
      if (h.contains('sku') ||
          h.contains('كود') ||
          h.contains('code') ||
          h.contains('باركود'))
        colSku = i;
      if (h.contains('مقاس') || h.contains('size')) colSize = i;
      if (h.contains('لون') || h.contains('color')) colColor = i;
      if (h.contains('تكلفة') || h.contains('cost')) colCost = i;
      if (h.contains('بيع') ||
          h.contains('sale') ||
          h.contains('sell') ||
          h.contains('سعر')) {
        if (!h.contains('تكلفة')) colSell = i;
      }
      if (h.contains('كمية') ||
          h.contains('qty') ||
          h.contains('quantity') ||
          h.contains('رصيد'))
        colQty = i;
      if (h.contains('طلب') || h.contains('min')) colMin = i;
    }

    // Fallbacks if headers weren't named
    if (colProd == -1) colProd = 0;
    if (colCat == -1) colCat = 1;
    if (colSku == -1) colSku = 2;
    if (colSize == -1) colSize = 3;
    if (colColor == -1) colColor = 4;
    if (colCost == -1) colCost = 5;
    if (colSell == -1) colSell = 6;
    if (colQty == -1) colQty = 7;

    final parsedRows = <ExcelProductRow>[];
    for (int r = 1; r < targetSheet.rows.length; r++) {
      final row = targetSheet.rows[r];
      if (row.isEmpty) continue;

      final name = colProd < row.length ? _cellToString(row[colProd]) : '';
      if (name.trim().isEmpty) continue; // skip empty rows

      final cat = colCat < row.length ? _cellToString(row[colCat]) : 'عام';
      final sku = colSku < row.length ? _cellToString(row[colSku]) : '';
      final size = colSize < row.length ? _cellToString(row[colSize]) : 'Free';
      final color = colColor < row.length
          ? _cellToString(row[colColor])
          : 'افتراضي';
      final cost = colCost < row.length ? _cellToDouble(row[colCost]) : 0.0;
      final sell = colSell < row.length ? _cellToDouble(row[colSell]) : 0.0;
      final qty = colQty < row.length ? _cellToInt(row[colQty]) : 0;
      final minStock = colMin >= 0 && colMin < row.length
          ? _cellToInt(row[colMin])
          : 5;

      final effectiveSku = sku.trim().isNotEmpty
          ? sku.trim()
          : 'SKU-${r + 1000}';

      parsedRows.add(
        ExcelProductRow(
          productName: name.trim(),
          categoryName: cat.trim().isNotEmpty ? cat.trim() : 'عام',
          sku: effectiveSku,
          size: size.trim().isNotEmpty ? size.trim() : 'Free',
          color: color.trim().isNotEmpty ? color.trim() : 'افتراضي',
          costPrice: cost,
          salePrice: sell,
          quantity: qty,
          minStock: minStock,
        ),
      );
    }

    // Query existing variants and products from Drift
    final existingVariants = await (db.select(
      db.productVariants,
    )..where((v) => v.deletedAt.isNull())).get();
    final existingProducts = await (db.select(
      db.products,
    )..where((p) => p.deletedAt.isNull())).get();
    final prodMap = {for (var p in existingProducts) p.id: p};

    final variantBySku = <String, ProductVariant>{};
    for (final v in existingVariants) {
      variantBySku[v.sku.toLowerCase().trim()] = v;
    }

    final newRows = <ExcelProductRow>[];
    final conflicts = <DuplicateConflict>[];

    for (final row in parsedRows) {
      final match = variantBySku[row.sku.toLowerCase().trim()];
      if (match != null) {
        final prod = prodMap[match.productId];
        conflicts.add(
          DuplicateConflict(
            excelRow: row,
            existingVariant: match,
            existingProductName: prod?.name ?? match.productId,
            resolution: DuplicateResolution.updatePricesAndQty,
          ),
        );
      } else {
        newRows.add(row);
      }
    }

    return ExcelImportAnalysis(
      newRows: newRows,
      conflicts: conflicts,
      totalRows: parsedRows.length,
    );
  }

  Future<void> executeImport({
    required List<ExcelProductRow> newRows,
    required List<DuplicateConflict> conflicts,
    required bool replaceExisting,
    required String userId,
  }) async {
    final db = getIt<AppDatabase>();
    final tx = getIt<TxWriter>();
    final branchProvider = getIt<BranchProvider>();
    final branchId = await branchProvider.getBranchId();
    final now = DateTime.now();

    await tx.write(
      writeFn: () async {
        // 1. If replace existing is selected, soft delete products without sales
        if (replaceExisting) {
          final variantIdsWithSales = await db
              .select(db.saleItems)
              .map((s) => s.variantId)
              .get();
          await (db.update(
            db.productVariants,
          )..where((v) => v.id.isNotIn(variantIdsWithSales))).write(
            ProductVariantsCompanion(
              deletedAt: drift.Value(now),
              updatedAt: drift.Value(now),
            ),
          );
        }

        // 2. Fetch or create categories cache
        final existingCats = await (db.select(
          db.categories,
        )..where((c) => c.deletedAt.isNull())).get();
        final catMapByName = <String, String>{};
        for (final c in existingCats) {
          catMapByName[c.name.trim().toLowerCase()] = c.id;
        }

        Future<String> getOrCreateCategory(String catName) async {
          final norm = catName.trim().toLowerCase();
          if (catMapByName.containsKey(norm)) return catMapByName[norm]!;

          final newCatId = _uuid.v4();
          await db
              .into(db.categories)
              .insert(
                CategoriesCompanion.insert(
                  id: newCatId,
                  branchId: branchId,
                  name: catName.trim(),
                  createdAt: now,
                  updatedAt: now,
                ),
              );
          catMapByName[norm] = newCatId;
          return newCatId;
        }

        // 3. Process newRows grouped by (productName, categoryName)
        final Map<String, List<ExcelProductRow>> grouped = {};
        for (final row in newRows) {
          final key = '${row.productName.trim()}|||${row.categoryName.trim()}';
          grouped.putIfAbsent(key, () => []).add(row);
        }

        for (final entry in grouped.entries) {
          final parts = entry.key.split('|||');
          final prodName = parts[0];
          final catName = parts[1];
          final catId = await getOrCreateCategory(catName);

          final prodId = _uuid.v4();
          await db
              .into(db.products)
              .insert(
                ProductsCompanion.insert(
                  id: prodId,
                  branchId: branchId,
                  name: prodName,
                  categoryId: catId,
                  description: const drift.Value('مستورد من ملف إكسيل'),
                  minStock: drift.Value(entry.value.first.minStock),
                  createdAt: now,
                  updatedAt: now,
                ),
              );

          for (final variantRow in entry.value) {
            final variantId = _uuid.v4();
            await db
                .into(db.productVariants)
                .insert(
                  ProductVariantsCompanion.insert(
                    id: variantId,
                    branchId: branchId,
                    productId: prodId,
                    sku: variantRow.sku,
                    color: variantRow.color,
                    size: variantRow.size,
                    costPrice: (variantRow.costPrice * 100).toInt(),
                    sellPrice: (variantRow.salePrice * 100).toInt(),
                    quantity: drift.Value(variantRow.quantity),
                    createdAt: now,
                    updatedAt: now,
                  ),
                );

            if (variantRow.quantity > 0) {
              await db
                  .into(db.inventoryLogs)
                  .insert(
                    InventoryLogsCompanion.insert(
                      id: _uuid.v4(),
                      branchId: branchId,
                      variantId: variantId,
                      type: 'receive',
                      qtyDelta: variantRow.quantity,
                      reason: const drift.Value('استيراد أولي من ملف إكسيل'),
                      refType: 'excel_import',
                      userId: userId,
                      createdAt: now,
                    ),
                  );
            }
          }
        }

        // 4. Process Conflicts
        for (final conflict in conflicts) {
          final row = conflict.excelRow;
          final existing = conflict.existingVariant;

          if (conflict.resolution == DuplicateResolution.skip) {
            continue;
          }

          if (conflict.resolution == DuplicateResolution.updatePricesAndQty) {
            final costPiasters = (row.costPrice * 100).toInt();
            final sellPiasters = (row.salePrice * 100).toInt();

            await (db.update(
              db.productVariants,
            )..where((v) => v.id.equals(existing.id))).write(
              ProductVariantsCompanion(
                costPrice: drift.Value(costPiasters),
                sellPrice: drift.Value(sellPiasters),
                quantity: drift.Value(row.quantity),
                color: drift.Value(row.color),
                size: drift.Value(row.size),
                updatedAt: drift.Value(now),
              ),
            );

            final delta = row.quantity - existing.quantity;
            if (delta != 0) {
              await db
                  .into(db.inventoryLogs)
                  .insert(
                    InventoryLogsCompanion.insert(
                      id: _uuid.v4(),
                      branchId: branchId,
                      variantId: existing.id,
                      type: delta > 0 ? 'receive' : 'adjustment',
                      qtyDelta: delta,
                      reason: const drift.Value('تحديث الرصيد من ملف إكسيل'),
                      refType: 'excel_import_update',
                      userId: userId,
                      createdAt: now,
                    ),
                  );
            }
          } else if (conflict.resolution == DuplicateResolution.addQuantity) {
            final newQty = existing.quantity + row.quantity;
            await (db.update(
              db.productVariants,
            )..where((v) => v.id.equals(existing.id))).write(
              ProductVariantsCompanion(
                quantity: drift.Value(newQty),
                updatedAt: drift.Value(now),
              ),
            );

            if (row.quantity > 0) {
              await db
                  .into(db.inventoryLogs)
                  .insert(
                    InventoryLogsCompanion.insert(
                      id: _uuid.v4(),
                      branchId: branchId,
                      variantId: existing.id,
                      type: 'receive',
                      qtyDelta: row.quantity,
                      reason: const drift.Value(
                        'إضافة كمية توريد من ملف إكسيل',
                      ),
                      refType: 'excel_import_add_qty',
                      userId: userId,
                      createdAt: now,
                    ),
                  );
            }
          }
        }
      },
      branchId: branchId,
      entity: 'products_excel',
      entityId: 'batch_import',
      operation: 'excel_import',
      userId: userId,
    );
  }

  String _cellToString(Data? cell) {
    if (cell == null || cell.value == null) return '';
    final val = cell.value;
    if (val is TextCellValue) return val.value.text ?? '';
    return val.toString().trim();
  }

  double _cellToDouble(Data? cell) {
    if (cell == null || cell.value == null) return 0.0;
    final str = _cellToString(cell).replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(str) ?? 0.0;
  }

  int _cellToInt(Data? cell) {
    if (cell == null || cell.value == null) return 0;
    final str = _cellToString(cell).replaceAll(RegExp(r'[^\d]'), '');
    return int.tryParse(str) ?? 0;
  }
}
