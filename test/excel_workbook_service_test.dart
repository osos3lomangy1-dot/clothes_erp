import 'dart:convert';
import 'dart:typed_data';

import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/services/excel_workbook_models.dart';
import 'package:clothes_erp/core/services/excel_workbook_service.dart';
import 'package:clothes_erp/features/partners/domain/entities/partner_entity.dart';
import 'package:clothes_erp/features/settings/presentation/screens/excel_migration_screen.dart';
import 'package:clothes_erp/features/settings/presentation/widgets/excel_migration_card.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late BranchProvider branchProvider;
  late TxWriter txWriter;
  late ExcelWorkbookService service;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    branchProvider = BranchProvider(db);
    txWriter = TxWriter(db);
    service = ExcelWorkbookService(db, branchProvider, txWriter);
  });

  tearDown(() async {
    await db.close();
  });

  group('Full Linked Workbook Export', () {
    test('exports 19 linked sheets with valid live Excel formulas', () async {
      final now = DateTime(2026, 6, 15, 14, 30);
      const branchId = 'branch-1';

      // Seed category, product, variant (with wholesalePrice)
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: 'cat-1',
              branchId: branchId,
              name: 'تيشيرتات',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'prod-1',
              branchId: branchId,
              name: 'تيشيرت بولو',
              categoryId: 'cat-1',
              minStock: const drift.Value(5),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              id: 'var-1',
              branchId: branchId,
              productId: 'prod-1',
              sku: 'SKU-POLO-1',
              color: 'أسود',
              size: 'L',
              quantity: const drift.Value(10),
              costPrice: 20000,
              sellPrice: 35000,
              wholesalePrice: const drift.Value(29000),
              createdAt: now,
              updatedAt: now,
            ),
          );

      // Seed customer, supplier, partner
      await db.into(db.customers).insert(
            CustomersCompanion.insert(
              id: 'cust-1',
              branchId: branchId,
              name: 'أحمد علي',
              phone: '01011112222',
              customerType: const drift.Value('wholesale'),
              discountPercent: const drift.Value(5),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.suppliers).insert(
            SuppliersCompanion.insert(
              id: 'sup-1',
              branchId: branchId,
              name: 'مصنع الدلتا',
              phone: const drift.Value('01233334444'),
              balance: const drift.Value(500000),
              createdAt: now,
              updatedAt: now,
            ),
          );
      final partner = PartnerEntity(
        id: 'p-1',
        name: 'شريك أول',
        phone: '01500000000',
        percentage: 50.0,
        capital: 10000000,
        createdAt: now,
      );
      await db.into(db.appMeta).insert(
            AppMetaCompanion.insert(
              key: 'partners_registry',
              value: jsonEncode([partner.toJson()]),
              updatedAt: now,
            ),
          );

      // Seed sale + item + installment + payment + expense + purchase + return
      await db.into(db.sales).insert(
            SalesCompanion.insert(
              id: 'sale-1',
              branchId: branchId,
              shortRef: 'INV-1001',
              cashierId: 'admin',
              customerId: const drift.Value('cust-1'),
              subtotal: 70000,
              discountType: 'none',
              total: 70000,
              paymentMethod: 'cash',
              date: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.saleItems).insert(
            SaleItemsCompanion.insert(
              id: 'si-1',
              branchId: branchId,
              saleId: 'sale-1',
              variantId: 'var-1',
              productName: 'تيشيرت بولو',
              color: 'أسود',
              size: 'L',
              qty: 2,
              priceSnapshot: 35000,
              costSnapshot: 20000,
              lineTotal: 70000,
              createdAt: now,
            ),
          );
      await db.into(db.customerInstallments).insert(
            CustomerInstallmentsCompanion.insert(
              id: 'inst-1',
              branchId: branchId,
              saleId: 'sale-1',
              customerId: 'cust-1',
              totalPiasters: 120000,
              downPaymentPiasters: const drift.Value(20000),
              principalPiasters: 100000,
              interestBp: 1000,
              monthlyAmountPiasters: 22000,
              remainingPiasters: 88000,
              durationMonths: 5,
              startDate: now,
              endDate: DateTime(2026, 11, 15),
              createdBy: 'admin',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.installmentPayments).insert(
            InstallmentPaymentsCompanion.insert(
              id: 'pay-1',
              branchId: branchId,
              customerInstallmentId: 'inst-1',
              amountPiasters: 22000,
              paymentMethod: 'cash',
              paidAt: now,
              recordedBy: 'admin',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.expenses).insert(
            ExpensesCompanion.insert(
              id: 'exp-1',
              branchId: branchId,
              category: 'إيجار',
              amount: 15000,
              userId: 'admin',
              expenseDate: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.purchases).insert(
            PurchasesCompanion.insert(
              id: 'pur-1',
              branchId: branchId,
              supplierId: 'sup-1',
              purchaseDate: now,
              totalAmount: 100000,
              paidAmount: const drift.Value(40000),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.returns).insert(
            ReturnsCompanion.insert(
              id: 'ret-1',
              branchId: branchId,
              saleId: const drift.Value('sale-1'),
              cashierId: 'admin',
              reason: 'مقاس غير مناسب',
              refundAmount: 35000,
              paymentMethod: 'cash',
              date: now,
              createdAt: now,
              updatedAt: now,
            ),
          );

      final result = await service.buildFullWorkbookBytes();
      expect(result.meta.sheetCount, 19);
      expect(result.meta.productsCount, 1);
      expect(result.meta.customersCount, 1);
      expect(result.meta.suppliersCount, 1);
      expect(result.meta.salesCount, 1);
      expect(result.meta.installmentsCount, 1);
      expect(result.meta.expensesCount, 1);

      final decoded = Excel.decodeBytes(result.bytes);
      expect(decoded.tables.containsKey('Sheet1'), isFalse);
      expect(decoded.tables.keys, containsAll([
        ExcelWorkbookService.sheetDashboard,
        ExcelWorkbookService.sheetProducts,
        ExcelWorkbookService.sheetCustomers,
        ExcelWorkbookService.sheetSuppliers,
        ExcelWorkbookService.sheetPartners,
        ExcelWorkbookService.sheetSales,
        ExcelWorkbookService.sheetSaleItems,
        ExcelWorkbookService.sheetInstallments,
        ExcelWorkbookService.sheetInstallmentPayments,
        ExcelWorkbookService.sheetExpenses,
        ExcelWorkbookService.sheetPurchases,
        ExcelWorkbookService.sheetReturns,
      ]));

      // Verify live formulas exist across linked sheets
      final dash = decoded.tables[ExcelWorkbookService.sheetDashboard]!;
      expect(dash.rows[1][1]?.value, isA<FormulaCellValue>());
      expect(
        (dash.rows[1][1]!.value as FormulaCellValue).formula,
        contains(ExcelWorkbookService.sheetSales),
      );
      expect(
        (dash.rows[5][1]!.value as FormulaCellValue).formula,
        'B4-B5',
      );

      final prod = decoded.tables[ExcelWorkbookService.sheetProducts]!;
      expect(
        prod.rows[1][7]?.value,
        anyOf(IntCellValue(290), DoubleCellValue(290.0)),
      ); // wholesale price
      expect(
        (prod.rows[1][10]!.value as FormulaCellValue).formula,
        'F2*I2',
      );

      final cust = decoded.tables[ExcelWorkbookService.sheetCustomers]!;
      expect(
        (cust.rows[1][6]!.value as FormulaCellValue).formula,
        contains("SUMIF('${ExcelWorkbookService.sheetSales}'"),
      );

      final partnerSheet = decoded.tables[ExcelWorkbookService.sheetPartners]!;
      expect(
        (partnerSheet.rows[1][5]!.value as FormulaCellValue).formula,
        "'${ExcelWorkbookService.sheetDashboard}'!B6*(C2/100)",
      );
    });

    test('exports cleanly on empty DB without invalid inverted ranges', () async {
      final result = await service.buildFullWorkbookBytes();
      final decoded = Excel.decodeBytes(result.bytes);
      final dash = decoded.tables[ExcelWorkbookService.sheetDashboard]!;
      // Empty sales should be numeric 0, not SUMIF(J2:J1)
      expect(
        dash.rows[1][1]?.value,
        anyOf(IntCellValue(0), DoubleCellValue(0.0)),
      );
      expect(dash.rows[12][1]?.value, IntCellValue(0));
    });
  });

  group('Migration Template & Multi-Sheet Import', () {
    test('template round-trip imports products, wholesale, customers, suppliers, and installments atomically', () async {
      final templateBytes = service.buildMigrationTemplateBytes();
      final inspection = service.inspectWorkbook(templateBytes);

      expect(inspection.hasMultiSheetTemplateMatch, isTrue);
      expect(
        inspection.sheets.map((s) => s.detectedEntity).toSet(),
        containsAll([
          ExcelImportEntity.products,
          ExcelImportEntity.customers,
          ExcelImportEntity.suppliers,
          ExcelImportEntity.installments,
        ]),
      );

      final preview = await service.analyzeMultiSheetWorkbook(templateBytes);
      expect(preview.errorCount, 0);
      expect(preview.newProducts.length, 2);
      expect(preview.newProducts.first.wholesalePricePiasters, 30000);
      expect(preview.newCustomers.length, 2);
      expect(preview.newSuppliers.length, 1);
      expect(preview.newInstallments.length, 1);

      final committed = await service.executeWorkbookImport(
        preview: preview,
        userId: 'admin-1',
      );
      expect(committed.productsAdded, 2);
      expect(committed.customersAdded, 2);
      expect(committed.suppliersAdded, 1);
      expect(committed.installmentsAdded, 1);

      // Verify DB rows
      final variants = await db.select(db.productVariants).get();
      expect(variants.length, 2);
      expect(
        variants.firstWhere((v) => v.sku == 'POLO-BLK-L').wholesalePrice,
        30000,
      );

      final customers = await db.select(db.customers).get();
      expect(customers.length, 2);
      expect(
        customers.firstWhere((c) => c.phone == '01198765432').customerType,
        'wholesale',
      );

      final contracts = await db.select(db.customerInstallments).get();
      expect(contracts.length, 1);
      expect(contracts.first.principalPiasters, 200000); // 2400 - 400
      expect(contracts.first.remainingPiasters, 110000);
      expect(contracts.first.saleId, startsWith('MIGRATED_EXCEL_'));

      // Verify NO phantom cash movements injected into live drawer
      final cashMovements = await db.select(db.cashMovements).get();
      expect(cashMovements, isEmpty);

      // Verify inventory logs and audit log recorded
      final invLogs = await db.select(db.inventoryLogs).get();
      expect(invLogs.length, 2);
      final audits = await db.select(db.auditLogs).get();
      expect(audits.any((a) => a.entity == 'excel_migration'), isTrue);
    });

    test('conflict resolution supports addQuantity, update, and skip', () async {
      final templateBytes = service.buildMigrationTemplateBytes();
      final firstPreview = await service.analyzeMultiSheetWorkbook(templateBytes);
      await service.executeWorkbookImport(
        preview: firstPreview,
        userId: 'admin-1',
      );

      // Re-analyze same template -> all products/customers/suppliers are conflicts
      final secondPreview = await service.analyzeMultiSheetWorkbook(templateBytes);
      expect(secondPreview.newProducts, isEmpty);
      expect(secondPreview.productConflicts.length, 2);
      expect(secondPreview.customerConflicts.length, 2);
      expect(secondPreview.supplierConflicts.length, 1);

      secondPreview.productConflicts[0].action = ExcelConflictAction.addQuantity;
      secondPreview.productConflicts[1].action = ExcelConflictAction.skip;
      for (final c in secondPreview.customerConflicts) {
        c.action = ExcelConflictAction.skip;
      }
      for (final s in secondPreview.supplierConflicts) {
        s.action = ExcelConflictAction.skip;
      }

      final res = await service.executeWorkbookImport(
        preview: WorkbookImportPreview(
          productConflicts: secondPreview.productConflicts,
          customerConflicts: secondPreview.customerConflicts,
          supplierConflicts: secondPreview.supplierConflicts,
        ),
        userId: 'admin-1',
      );
      expect(res.productsUpdated, 1);
      expect(res.productsSkipped, 1);
      expect(res.customersSkipped, 2);
      expect(res.suppliersSkipped, 1);

      final polo = await (db.select(db.productVariants)
            ..where((v) => v.sku.equals('POLO-BLK-L')))
          .getSingle();
      expect(polo.quantity, 50); // 25 + 25
    });
  });

  group('Smart Column Mapper & Validation', () {
    test('maps arbitrary shop Excel sheet with Arabic numerals and auto-generates SKU', () async {
      final excel = Excel.createExcel();
      final sheet = excel['شيت_المحل'];
      excel.setDefaultSheet('شيت_المحل');
      excel.delete('Sheet1');

      sheet.appendRow([
        TextCellValue('الموديل'),
        TextCellValue('القطاعي'),
        TextCellValue('الجملة'),
        TextCellValue('الجرد'),
      ]);
      sheet.appendRow([
        TextCellValue('جاكيت شتوي'),
        TextCellValue('٩٥٠'),
        TextCellValue('٨٠٠'),
        TextCellValue('١٢'),
      ]);
      // Invalid negative price row should be flagged as an issue, not crash
      sheet.appendRow([
        TextCellValue('صنف خطأ'),
        TextCellValue('-50'),
        TextCellValue('0'),
        TextCellValue('5'),
      ]);

      final bytes = Uint8List.fromList(excel.encode()!);
      final inspection = service.inspectWorkbook(bytes);
      expect(inspection.sheets.length, 1);

      final sheetInfo = inspection.sheets.first;
      final mapping = service.suggestMapping(
        sheetInfo,
        ExcelImportEntity.products,
      );
      expect(mapping.fieldToColumnIndex['productName'], 0);
      expect(mapping.fieldToColumnIndex['sellPrice'], 1);
      expect(mapping.fieldToColumnIndex['wholesalePrice'], 2);
      expect(mapping.fieldToColumnIndex['quantity'], 3);

      final preview = await service.analyzeSheetWithMapping(bytes, mapping);
      expect(preview.newProducts.length, 1);
      expect(preview.errorCount, 1);
      expect(preview.newProducts.first.sellPricePiasters, 95000);
      expect(preview.newProducts.first.wholesalePricePiasters, 80000);
      expect(preview.newProducts.first.quantity, 12);
      expect(preview.newProducts.first.sku, startsWith('MIG-'));

      final res = await service.executeWorkbookImport(
        preview: preview,
        userId: 'admin-1',
      );
      expect(res.productsAdded, 1);
    });

    test('full export bytes can be re-imported into a fresh empty DB', () async {
      // Seed original DB from template
      final tpl = service.buildMigrationTemplateBytes();
      final p1 = await service.analyzeMultiSheetWorkbook(tpl);
      await service.executeWorkbookImport(preview: p1, userId: 'admin-1');

      // Export full 19-sheet linked workbook
      final exported = await service.buildFullWorkbookBytes();

      // Open a brand new empty DB and import from the full export workbook!
      final db2 = AppDatabase(NativeDatabase.memory());
      addTearDown(db2.close);
      final service2 = ExcelWorkbookService(
        db2,
        BranchProvider(db2),
        TxWriter(db2),
      );
      final preview2 = await service2.analyzeMultiSheetWorkbook(exported.bytes);
      expect(preview2.errorCount, 0);
      expect(preview2.newProducts.length, 2);
      expect(preview2.newCustomers.length, 2);
      expect(preview2.newSuppliers.length, 1);
      expect(preview2.newInstallments.length, 1);

      final res2 = await service2.executeWorkbookImport(
        preview: preview2,
        userId: 'admin-2',
      );
      expect(res2.productsAdded, 2);
      expect(res2.customersAdded, 2);
      expect(res2.suppliersAdded, 1);
      expect(res2.installmentsAdded, 1);
    });
  });

  group('Excel Migration UI Widget Tests', () {
    testWidgets('ExcelMigrationCard renders all actions and opens wizard', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: ExcelMigrationCard(
                userId: 'admin-1',
                serviceOverride: service,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('export_full_excel_btn')), findsOneWidget);
      expect(find.byKey(const Key('open_excel_wizard_btn')), findsOneWidget);
      expect(
        find.byKey(const Key('download_excel_template_btn')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('open_excel_wizard_btn')));
      await tester.pumpAndSettle();

      expect(find.byType(ExcelMigrationScreen), findsOneWidget);
      expect(find.byKey(const Key('pick_excel_file_btn')), findsOneWidget);
      expect(find.byKey(const Key('download_template_btn')), findsOneWidget);
    });
  });
}
