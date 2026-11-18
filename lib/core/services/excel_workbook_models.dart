/// Models for Bay3ah's Full Linked Excel Workbook Export & Shop Migration Center.
library;

enum ExcelImportEntity {
  products,
  customers,
  suppliers,
  installments,
}

extension ExcelImportEntityX on ExcelImportEntity {
  String get arabicLabel {
    switch (this) {
      case ExcelImportEntity.products:
        return 'المنتجات والمخزون';
      case ExcelImportEntity.customers:
        return 'العملاء';
      case ExcelImportEntity.suppliers:
        return 'الموردين';
      case ExcelImportEntity.installments:
        return 'عقود التقسيط القائمة';
    }
  }
}

/// Resolution choice when an imported row matches an existing record.
enum ExcelConflictAction {
  update, // تحديث السجل الموجود بالبيانات الجديدة
  addQuantity, // زيادة الكمية (للمنتجات فقط)
  skip, // تخطي الصف والإبقاء على السجل الموجود
}

/// Severity of a row-level validation issue.
enum ExcelIssueSeverity { error, warning }

class ExcelRowIssue {
  final ExcelImportEntity entity;
  final String sheetName;
  final int rowNumber; // 1-based Excel row number
  final String message;
  final ExcelIssueSeverity severity;

  const ExcelRowIssue({
    required this.entity,
    required this.sheetName,
    required this.rowNumber,
    required this.message,
    this.severity = ExcelIssueSeverity.error,
  });
}

/// Describes one field in the Smart Column Mapper.
class ExcelFieldSpec {
  final String key;
  final String arabicLabel;
  final bool required;
  final String? hint;

  const ExcelFieldSpec({
    required this.key,
    required this.arabicLabel,
    this.required = false,
    this.hint,
  });
}

/// Metadata extracted when inspecting an arbitrary Excel file before mapping.
class ExcelSheetInfo {
  final String name;
  final List<String> headers;
  final List<List<String>> sampleRows; // up to 3 preview data rows
  final int dataRowCount;
  final ExcelImportEntity? detectedEntity;

  const ExcelSheetInfo({
    required this.name,
    required this.headers,
    required this.sampleRows,
    required this.dataRowCount,
    this.detectedEntity,
  });
}

class ExcelWorkbookInspection {
  final List<ExcelSheetInfo> sheets;

  const ExcelWorkbookInspection({required this.sheets});

  bool get hasMultiSheetTemplateMatch =>
      sheets.where((s) => s.detectedEntity != null).length >= 2 ||
      sheets.any(
        (s) =>
            s.name == 'المنتجات_والمخزون' ||
            s.name == 'العملاء' ||
            s.name == 'الموردين' ||
            s.name == 'عقود_التقسيط',
      );
}

/// Maps logical field keys (e.g. 'productName', 'sellPrice') to 0-based column indices.
class ExcelColumnMapping {
  final String sheetName;
  final ExcelImportEntity entity;
  final Map<String, int?> fieldToColumnIndex;

  const ExcelColumnMapping({
    required this.sheetName,
    required this.entity,
    required this.fieldToColumnIndex,
  });

  ExcelColumnMapping copyWithColumn(String fieldKey, int? columnIndex) {
    final next = Map<String, int?>.from(fieldToColumnIndex);
    next[fieldKey] = columnIndex;
    return ExcelColumnMapping(
      sheetName: sheetName,
      entity: entity,
      fieldToColumnIndex: next,
    );
  }
}

// ─── Parsed Migration Rows ───────────────────────────────────────────────────

class MigrationProductRow {
  final int rowNumber;
  final String productName;
  final String categoryName;
  final String sku;
  final String size;
  final String color;
  final int costPricePiasters;
  final int sellPricePiasters;
  final int wholesalePricePiasters;
  final int quantity;
  final int minStock;

  const MigrationProductRow({
    required this.rowNumber,
    required this.productName,
    required this.categoryName,
    required this.sku,
    required this.size,
    required this.color,
    required this.costPricePiasters,
    required this.sellPricePiasters,
    required this.wholesalePricePiasters,
    required this.quantity,
    required this.minStock,
  });
}

class MigrationProductConflict {
  final MigrationProductRow row;
  final String existingVariantId;
  final String existingProductId;
  final String existingProductName;
  final int existingQty;
  final int existingSellPiasters;
  ExcelConflictAction action;

  MigrationProductConflict({
    required this.row,
    required this.existingVariantId,
    required this.existingProductId,
    required this.existingProductName,
    required this.existingQty,
    required this.existingSellPiasters,
    this.action = ExcelConflictAction.update,
  });
}

class MigrationCustomerRow {
  final int rowNumber;
  final String name;
  final String phone;
  final String customerType; // 'retail' or 'wholesale'
  final int discountPercent;
  final int loyaltyPoints;

  const MigrationCustomerRow({
    required this.rowNumber,
    required this.name,
    required this.phone,
    required this.customerType,
    required this.discountPercent,
    required this.loyaltyPoints,
  });
}

class MigrationCustomerConflict {
  final MigrationCustomerRow row;
  final String existingCustomerId;
  final String existingName;
  ExcelConflictAction action;

  MigrationCustomerConflict({
    required this.row,
    required this.existingCustomerId,
    required this.existingName,
    this.action = ExcelConflictAction.update,
  });
}

class MigrationSupplierRow {
  final int rowNumber;
  final String name;
  final String? phone;
  final String? companyName;
  final String? address;
  final int balancePiasters;

  const MigrationSupplierRow({
    required this.rowNumber,
    required this.name,
    this.phone,
    this.companyName,
    this.address,
    required this.balancePiasters,
  });
}

class MigrationSupplierConflict {
  final MigrationSupplierRow row;
  final String existingSupplierId;
  final String existingName;
  ExcelConflictAction action;

  MigrationSupplierConflict({
    required this.row,
    required this.existingSupplierId,
    required this.existingName,
    this.action = ExcelConflictAction.update,
  });
}

class MigrationInstallmentRow {
  final int rowNumber;
  final String customerPhone;
  final String customerName;
  final int totalPiasters;
  final int downPaymentPiasters;
  final int interestBp; // basis points (e.g. 10% = 1000)
  final int durationMonths;
  final int remainingPiasters;
  final DateTime startDate;
  final String status; // active, completed, overdue, cancelled
  final String? referenceCode;

  const MigrationInstallmentRow({
    required this.rowNumber,
    required this.customerPhone,
    required this.customerName,
    required this.totalPiasters,
    required this.downPaymentPiasters,
    required this.interestBp,
    required this.durationMonths,
    required this.remainingPiasters,
    required this.startDate,
    required this.status,
    this.referenceCode,
  });

  int get principalPiasters => totalPiasters - downPaymentPiasters;
}

// ─── Preview & Result Summaries ──────────────────────────────────────────────

class WorkbookImportPreview {
  final List<MigrationProductRow> newProducts;
  final List<MigrationProductConflict> productConflicts;
  final List<MigrationCustomerRow> newCustomers;
  final List<MigrationCustomerConflict> customerConflicts;
  final List<MigrationSupplierRow> newSuppliers;
  final List<MigrationSupplierConflict> supplierConflicts;
  final List<MigrationInstallmentRow> newInstallments;
  final List<ExcelRowIssue> issues;

  const WorkbookImportPreview({
    this.newProducts = const [],
    this.productConflicts = const [],
    this.newCustomers = const [],
    this.customerConflicts = const [],
    this.newSuppliers = const [],
    this.supplierConflicts = const [],
    this.newInstallments = const [],
    this.issues = const [],
  });

  int get totalNewCount =>
      newProducts.length +
      newCustomers.length +
      newSuppliers.length +
      newInstallments.length;

  int get totalConflictCount =>
      productConflicts.length +
      customerConflicts.length +
      supplierConflicts.length;

  int get errorCount =>
      issues.where((i) => i.severity == ExcelIssueSeverity.error).length;

  int get warningCount =>
      issues.where((i) => i.severity == ExcelIssueSeverity.warning).length;

  bool get hasAnythingToImport => totalNewCount > 0 || totalConflictCount > 0;
}

class WorkbookImportResult {
  final int productsAdded;
  final int productsUpdated;
  final int productsSkipped;
  final int customersAdded;
  final int customersUpdated;
  final int customersSkipped;
  final int suppliersAdded;
  final int suppliersUpdated;
  final int suppliersSkipped;
  final int installmentsAdded;

  const WorkbookImportResult({
    this.productsAdded = 0,
    this.productsUpdated = 0,
    this.productsSkipped = 0,
    this.customersAdded = 0,
    this.customersUpdated = 0,
    this.customersSkipped = 0,
    this.suppliersAdded = 0,
    this.suppliersUpdated = 0,
    this.suppliersSkipped = 0,
    this.installmentsAdded = 0,
  });

  int get totalWritten =>
      productsAdded +
      productsUpdated +
      customersAdded +
      customersUpdated +
      suppliersAdded +
      suppliersUpdated +
      installmentsAdded;
}

class ExcelFullExportResult {
  final String filePath;
  final int sizeBytes;
  final int sheetCount;
  final int productsCount;
  final int customersCount;
  final int suppliersCount;
  final int salesCount;
  final int installmentsCount;
  final int expensesCount;

  const ExcelFullExportResult({
    required this.filePath,
    required this.sizeBytes,
    required this.sheetCount,
    required this.productsCount,
    required this.customersCount,
    required this.suppliersCount,
    required this.salesCount,
    required this.installmentsCount,
    required this.expensesCount,
  });
}

