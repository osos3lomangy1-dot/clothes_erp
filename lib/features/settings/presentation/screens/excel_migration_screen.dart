import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/excel_workbook_models.dart';
import '../../../../core/services/excel_workbook_service.dart';

enum _ImportMode { multiSheetAuto, customColumnMapper }

class ExcelMigrationScreen extends StatefulWidget {
  final String userId;
  final ExcelWorkbookService? serviceOverride;

  const ExcelMigrationScreen({
    super.key,
    required this.userId,
    this.serviceOverride,
  });

  @override
  State<ExcelMigrationScreen> createState() => _ExcelMigrationScreenState();
}

class _ExcelMigrationScreenState extends State<ExcelMigrationScreen> {
  // Step 0 = Pick File, 1 = Configure/Map, 2 = Review & Conflicts, 3 = Done
  int _step = 0;
  bool _busy = false;
  String? _busyMessage;

  String? _fileName;
  Uint8List? _fileBytes;
  ExcelWorkbookInspection? _inspection;

  _ImportMode _mode = _ImportMode.multiSheetAuto;
  ExcelSheetInfo? _selectedSheet;
  ExcelImportEntity _selectedEntity = ExcelImportEntity.products;
  ExcelColumnMapping? _mapping;
  bool _lenientMode = false;

  WorkbookImportPreview? _preview;
  WorkbookImportResult? _result;

  ExcelWorkbookService? get _service {
    if (widget.serviceOverride != null) return widget.serviceOverride;
    return getIt.isRegistered<ExcelWorkbookService>()
        ? getIt<ExcelWorkbookService>()
        : null;
  }

  Future<void> _downloadTemplate() async {
    final svc = _service;
    if (svc == null) return;
    setState(() {
      _busy = true;
      _busyMessage = 'جارٍ تجهيز قالب نقل البيانات الجاهز...';
    });
    try {
      final path = await svc.exportMigrationTemplate();
      if (!mounted) return;
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade800,
            content: Text('تم حفظ القالب بنجاح في:\n$path'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showError('فشل إنشاء القالب: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyMessage = null;
        });
      }
    }
  }

  Future<void> _pickExcelFile() async {
    final svc = _service;
    if (svc == null) return;
    setState(() {
      _busy = true;
      _busyMessage = 'جارٍ قراءة وتحليل ملف الإكسيل...';
    });
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: 'اختر ملف إكسيل (.xlsx)',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final f = picked.files.first;
      Uint8List? bytes = f.bytes;
      if (bytes == null && f.path != null) {
        bytes = await File(f.path!).readAsBytes();
      }
      if (bytes == null) {
        _showError('تعذر قراءة محتوى الملف المختار.');
        return;
      }

      final inspection = svc.inspectWorkbook(bytes);
      if (inspection.sheets.isEmpty) {
        _showError('ملف الإكسيل فارغ أو لا يحتوي على شيتات بيانات صالحة.');
        return;
      }

      final firstSheet = inspection.sheets.first;
      final defaultEntity =
          firstSheet.detectedEntity ?? ExcelImportEntity.products;
      final defaultMode = inspection.hasMultiSheetTemplateMatch
          ? _ImportMode.multiSheetAuto
          : _ImportMode.customColumnMapper;

      if (!mounted) return;
      setState(() {
        _fileName = f.name;
        _fileBytes = bytes;
        _inspection = inspection;
        _mode = defaultMode;
        _selectedSheet = firstSheet;
        _selectedEntity = defaultEntity;
        _mapping = svc.suggestMapping(firstSheet, defaultEntity);
        _preview = null;
        _result = null;
        _step = 1;
      });
    } catch (e) {
      if (!mounted) return;
      _showError('حدث خطأ أثناء فتح الملف: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyMessage = null;
        });
      }
    }
  }

  Future<void> _analyzeNow() async {
    final svc = _service;
    final bytes = _fileBytes;
    if (svc == null || bytes == null) return;

    setState(() {
      _busy = true;
      _busyMessage = 'جارٍ فحص الصفوف والتحقق من التكرارات...';
    });
    try {
      final WorkbookImportPreview preview;
      if (_mode == _ImportMode.multiSheetAuto) {
        preview = await svc.analyzeMultiSheetWorkbook(
          bytes,
          lenientMode: _lenientMode,
        );
      } else {
        if (_mapping == null) return;
        preview = await svc.analyzeSheetWithMapping(
          bytes,
          _mapping!,
          lenientMode: _lenientMode,
        );
      }
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _step = 2;
      });
    } catch (e) {
      if (!mounted) return;
      _showError('فشل تحليل الملف: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyMessage = null;
        });
      }
    }
  }

  Future<void> _commitImport() async {
    final svc = _service;
    final preview = _preview;
    if (svc == null || preview == null) return;

    setState(() {
      _busy = true;
      _busyMessage = 'جارٍ حفظ البيانات داخل قاعدة البيانات بأمان...';
    });
    try {
      final res = await svc.executeWorkbookImport(
        preview: preview,
        userId: widget.userId,
      );
      if (!mounted) return;
      setState(() {
        _result = res;
        _step = 3;
      });
    } catch (e) {
      if (!mounted) return;
      _showError('فشل حفظ البيانات (لم يتم تغيير أي سجل): $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyMessage = null;
        });
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
      ),
    );
  }

  void _resetWizard() {
    setState(() {
      _step = 0;
      _fileName = null;
      _fileBytes = null;
      _inspection = null;
      _selectedSheet = null;
      _mapping = null;
      _preview = null;
      _result = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'معالج نقل واستيراد بيانات الإكسيل',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildStepIndicator(),
          if (_busy)
            Container(
              width: double.infinity,
              color: AppColors.primary.withValues(alpha: 0.08),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _busyMessage ?? 'جارٍ التنفيذ...',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: switch (_step) {
                    0 => _buildStepPickFile(),
                    1 => _buildStepConfigureMapping(),
                    2 => _buildStepPreviewConflicts(),
                    _ => _buildStepDone(),
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    const labels = [
      '1. اختيار الملف',
      '2. ربط الأعمدة',
      '3. المعاينة والتكرارات',
      '4. التمام',
    ];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                decoration: BoxDecoration(
                  color: i == _step
                      ? AppColors.primary
                      : i < _step
                          ? Colors.teal.shade50
                          : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: i == _step
                        ? Colors.white
                        : i < _step
                            ? Colors.teal.shade800
                            : Colors.grey.shade600,
                  ),
                ),
              ),
            ),
            if (i < labels.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  // ─── Step 0: Pick File ────────────────────────────────────────────────────

  Widget _buildStepPickFile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.table_view_rounded,
                        color: AppColors.primary, size: 28),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'انقل بيانات محلك من إكسيل إلى بيعة في دقائق',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'يدعم النظام طريقتين مرنتين لنقل البيانات بدون تعقيد:\n'
                  '• قالب بيعة الجاهز (متعدد الشيتات): استيراد المنتجات بالمخزون وسعر الجملة + العملاء + الموردين + عقود التقسيط القائمة دفعة واحدة.\n'
                  '• أي ملف إكسيل قديم خاص بالمحل: ارفعه كما هو وسيتيح لك النظام ربط أعمدتك بأعمدة بيعة تفاعلياً.',
                  style: TextStyle(height: 1.6, fontSize: 13.5),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ElevatedButton.icon(
                      key: const Key('pick_excel_file_btn'),
                      onPressed: _busy ? null : _pickExcelFile,
                      icon: const Icon(Icons.upload_file_rounded),
                      label: const Text('اختيار ملف إكسيل (.xlsx)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const Key('download_template_btn'),
                      onPressed: _busy ? null : _downloadTemplate,
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('تحميل قالب بيعة الجاهز'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: Colors.amber.shade50,
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.amber),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'ملاحظة محاسبية: يتم استيراد الكميات كرصيد افتتاحي للمخزون، وتُستورد عقود التقسيط القائمة كأرصدة مفتوحة دون ضخ مبالغ وهمية في درج الوردية الحالية. كما تُحفظ العملية بالكامل في عملية ذرية واحدة مع معاينة قبل الحفظ.',
                    style: TextStyle(fontSize: 12.5, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── Step 1: Configure Mode / Smart Column Mapper ─────────────────────────

  Widget _buildStepConfigureMapping() {
    final inspection = _inspection!;
    final detectedSheets =
        inspection.sheets.where((s) => s.detectedEntity != null).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.description_rounded, color: Colors.teal),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'الملف: ${_fileName ?? ''} (${inspection.sheets.length} شيت)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _pickExcelFile,
                      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                      label: const Text('تغيير الملف'),
                    ),
                  ],
                ),
                const Divider(),
                const Text(
                  'اختر طريقة القراءة:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('استيراد تلقائي متعدد الشيتات (قالب بيعة)'),
                      selected: _mode == _ImportMode.multiSheetAuto,
                      onSelected: detectedSheets.isEmpty
                          ? null
                          : (_) => setState(
                                () => _mode = _ImportMode.multiSheetAuto,
                              ),
                    ),
                    ChoiceChip(
                      label: const Text('ربط الأعمدة التفاعلي (شيت مخصص)'),
                      selected: _mode == _ImportMode.customColumnMapper,
                      onSelected: (_) => setState(
                        () => _mode = _ImportMode.customColumnMapper,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_mode == _ImportMode.multiSheetAuto)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'الشيتات التي تم التعرف عليها تلقائياً:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  for (final s in detectedSheets)
                    ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.teal,
                      ),
                      title: Text('${s.name}  ←  ${s.detectedEntity!.arabicLabel}'),
                      subtitle: Text('عدد الصفوف المكتشفة: ${s.dataRowCount}'),
                    ),
                ],
              ),
            ),
          )
        else
          _buildCustomMapperCard(inspection),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _resetWizard,
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('رجوع'),
            ),
            ElevatedButton.icon(
              key: const Key('analyze_workbook_btn'),
              onPressed: _busy ? null : _analyzeNow,
              icon: const Icon(Icons.fact_check_rounded),
              label: const Text('فحص ومعاينة البيانات قبل الحفظ'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCustomMapperCard(ExcelWorkbookInspection inspection) {
    final sheet = _selectedSheet ?? inspection.sheets.first;
    final specs = ExcelWorkbookService.fieldSpecsFor(_selectedEntity);
    final mapping = _mapping ??
        _service!.suggestMapping(sheet, _selectedEntity);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ربط أعمدة ملفك بحقول بيعة (Smart Column Mapper)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: sheet.name,
                    decoration: const InputDecoration(
                      labelText: 'الشيت داخل الملف',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: inspection.sheets
                        .map(
                          (s) => DropdownMenuItem(
                            value: s.name,
                            child: Text('${s.name} (${s.dataRowCount} صف)'),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val == null) return;
                      final chosen = inspection.sheets
                          .firstWhere((s) => s.name == val);
                      final entity =
                          chosen.detectedEntity ?? _selectedEntity;
                      setState(() {
                        _selectedSheet = chosen;
                        _selectedEntity = entity;
                        _mapping = _service!.suggestMapping(chosen, entity);
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<ExcelImportEntity>(
                    initialValue: _selectedEntity,
                    decoration: const InputDecoration(
                      labelText: 'نوع البيانات في هذا الشيت',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: ExcelImportEntity.values
                        .map(
                          (e) => DropdownMenuItem(
                            value: e,
                            child: Text(e.arabicLabel),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val == null) return;
                      setState(() {
                        _selectedEntity = val;
                        _mapping = _service!.suggestMapping(sheet, val);
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final spec in specs)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            spec.required
                                ? '${spec.arabicLabel} *'
                                : spec.arabicLabel,
                            style: TextStyle(
                              fontWeight: spec.required
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                            ),
                          ),
                          if (spec.hint != null)
                            Text(
                              spec.hint!,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<int?>(
                        initialValue: mapping.fieldToColumnIndex[spec.key],
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('— غير مربوط (تجاهل) —'),
                          ),
                          for (var i = 0; i < sheet.headers.length; i++)
                            DropdownMenuItem<int?>(
                              value: i,
                              child: Text(
                                '${sheet.headers[i]} (عمود ${i + 1})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (colIdx) {
                          setState(() {
                            _mapping = mapping.copyWithColumn(spec.key, colIdx);
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            if (sheet.sampleRows.isNotEmpty) ...[
              const Divider(height: 24),
              const Text(
                'معاينة أول 3 صفوف من الشيت:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 36,
                  dataRowMinHeight: 32,
                  dataRowMaxHeight: 38,
                  columns: sheet.headers
                      .map((h) => DataColumn(label: Text(h)))
                      .toList(),
                  rows: sheet.sampleRows
                      .map(
                        (r) => DataRow(
                          cells: r.map((v) => DataCell(Text(v))).toList(),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Step 2: Review Preview, Conflicts & Validation Issues ────────────────

  Widget _buildStepPreviewConflicts() {
    final preview = _preview!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _statBadge(
              'منتجات جديدة',
              preview.newProducts.length,
              Colors.teal,
            ),
            _statBadge(
              'عملاء جدد',
              preview.newCustomers.length,
              Colors.indigo,
            ),
            _statBadge(
              'موردين جدد',
              preview.newSuppliers.length,
              Colors.blueGrey,
            ),
            _statBadge(
              'عقود تقسيط',
              preview.newInstallments.length,
              Colors.deepPurple,
            ),
            if (preview.newExpenses.isNotEmpty)
              _statBadge(
                'مصروفات سابقة',
                preview.newExpenses.length,
                Colors.brown,
              ),
            if (preview.newHistoricalSales.isNotEmpty)
              _statBadge(
                'مبيعات سابقة',
                preview.newHistoricalSales.length,
                Colors.green,
              ),
            _statBadge(
              'تكرارات للمراجعة',
              preview.totalConflictCount,
              Colors.orange.shade800,
            ),
            _statBadge(
              'صفوف متخطاة/أخطاء',
              preview.issues.length,
              preview.errorCount > 0 ? AppColors.error : Colors.grey,
            ),
          ],
        ),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          key: const Key('excel_lenient_mode_switch'),
          value: _lenientMode,
          onChanged: (v) => setState(() => _lenientMode = v),
          title: const Text(
            'الاستيراد المرن للبيانات الناقصة',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
          ),
          subtitle: const Text(
            'تعبئة الحقول غير الأساسية الناقصة (مثل التاريخ، SKU، التكلفة، الهاتف) بقيم افتراضية آمنة مع إصدار تنبيه فقط.',
            style: TextStyle(fontSize: 12),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: AppColors.outlineVariant),
          ),
        ),
        const SizedBox(height: 14),
        if (preview.issues.isNotEmpty)
          Card(
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ملاحظات وأخطاء تم استبعادها تلقائياً (${preview.issues.length}):',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final issue in preview.issues.take(15))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• [${issue.sheetName} - صف ${issue.rowNumber}] ${issue.message}',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  if (preview.issues.length > 15)
                    Text(
                      '... و ${preview.issues.length - 15} ملاحظة إضافية.',
                      style: const TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (preview.productConflicts.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'أصناف موجودة مسبقاً (${preview.productConflicts.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Wrap(
                        spacing: 6,
                        children: [
                          TextButton(
                            onPressed: () => setState(() {
                              for (final c in preview.productConflicts) {
                                c.action = ExcelConflictAction.update;
                              }
                            }),
                            child: const Text('تحديث الكل'),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              for (final c in preview.productConflicts) {
                                c.action = ExcelConflictAction.addQuantity;
                              }
                            }),
                            child: const Text('جمع الكمية للكل'),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              for (final c in preview.productConflicts) {
                                c.action = ExcelConflictAction.skip;
                              }
                            }),
                            child: const Text('تخطي الكل'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(),
                  for (final c in preview.productConflicts.take(30))
                    ListTile(
                      dense: true,
                      title: Text('${c.row.productName} (${c.row.sku})'),
                      subtitle: Text(
                        'الحالي: كمية ${c.existingQty} — بالإكسيل: كمية ${c.row.quantity}',
                      ),
                      trailing: DropdownButton<ExcelConflictAction>(
                        value: c.action,
                        items: const [
                          DropdownMenuItem(
                            value: ExcelConflictAction.update,
                            child: Text('تحديث السعر والكمية'),
                          ),
                          DropdownMenuItem(
                            value: ExcelConflictAction.addQuantity,
                            child: Text('إضافة للكمية الحالية'),
                          ),
                          DropdownMenuItem(
                            value: ExcelConflictAction.skip,
                            child: Text('تخطي'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => c.action = v);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (preview.customerConflicts.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'عملاء مسجلون مسبقاً (${preview.customerConflicts.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  for (final c in preview.customerConflicts.take(20))
                    ListTile(
                      dense: true,
                      title: Text('${c.row.name} (${c.row.phone})'),
                      subtitle: Text('الاسم الحالي: ${c.existingName}'),
                      trailing: DropdownButton<ExcelConflictAction>(
                        value: c.action == ExcelConflictAction.addQuantity
                            ? ExcelConflictAction.update
                            : c.action,
                        items: const [
                          DropdownMenuItem(
                            value: ExcelConflictAction.update,
                            child: Text('تحديث بيانات العميل'),
                          ),
                          DropdownMenuItem(
                            value: ExcelConflictAction.skip,
                            child: Text('تخطي'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => c.action = v);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (preview.supplierConflicts.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'موردون مسجلون مسبقاً (${preview.supplierConflicts.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  for (final s in preview.supplierConflicts.take(20))
                    ListTile(
                      dense: true,
                      title: Text(s.row.name),
                      subtitle: Text('المسجل حالياً: ${s.existingName}'),
                      trailing: DropdownButton<ExcelConflictAction>(
                        value: s.action == ExcelConflictAction.addQuantity
                            ? ExcelConflictAction.update
                            : s.action,
                        items: const [
                          DropdownMenuItem(
                            value: ExcelConflictAction.update,
                            child: Text('تحديث بيانات المورد'),
                          ),
                          DropdownMenuItem(
                            value: ExcelConflictAction.skip,
                            child: Text('تخطي'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => s.action = v);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : () => setState(() => _step = 1),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('تعديل الربط'),
            ),
            ElevatedButton.icon(
              key: const Key('commit_workbook_import_btn'),
              onPressed: _busy || !preview.hasAnythingToImport
                  ? null
                  : _commitImport,
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: const Text('تأكيد وحفظ البيانات في بيعة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── Step 3: Done Summary ─────────────────────────────────────────────────

  Widget _buildStepDone() {
    final r = _result!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(
              Icons.verified_rounded,
              size: 64,
              color: Colors.teal,
            ),
            const SizedBox(height: 12),
            const Text(
              'تم استيراد ونقل البيانات بنجاح!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                _statBadge('منتجات أُضيفت', r.productsAdded, Colors.teal),
                _statBadge('منتجات حُدّثت', r.productsUpdated, Colors.blue),
                _statBadge('عملاء أُضيفوا', r.customersAdded, Colors.indigo),
                _statBadge('عملاء حُدّثوا', r.customersUpdated, Colors.blueGrey),
                _statBadge('موردين أُضيفوا', r.suppliersAdded, Colors.brown),
                _statBadge('عقود تقسيط', r.installmentsAdded, Colors.deepPurple),
              ],
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: _resetWizard,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('استيراد ملف آخر'),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.done_all_rounded),
                  label: const Text('العودة للإعدادات'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBadge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ],
      ),
    );
  }
}

