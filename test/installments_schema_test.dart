import 'dart:io';

import 'package:clothes_erp/core/database/app_database.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Installments schema v5', () {
    test('installment tables exist and CHECK constraints enforced', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final now = DateTime.now();
      const branch = 'main';

      await db
          .into(db.installmentPlans)
          .insert(
            InstallmentPlansCompanion.insert(
              id: 'plan-1',
              branchId: branch,
              name: 'Plan A',
              durationMonths: 6,
              downPaymentPiasters: const Value(0),
              interestBp: const Value(1000),
              createdAt: now,
              updatedAt: now,
            ),
          );
      final plans = await db.select(db.installmentPlans).get();
      expect(plans.length, 1);
      expect(plans.first.name, 'Plan A');

      await db
          .into(db.customerInstallments)
          .insert(
            CustomerInstallmentsCompanion.insert(
              id: 'ci-1',
              branchId: branch,
              saleId: 'sale-1',
              customerId: 'cust-1',
              planId: const Value('plan-1'),
              totalPiasters: 1100,
              downPaymentPiasters: const Value(100),
              principalPiasters: 1000,
              interestBp: 1000,
              monthlyAmountPiasters: 200,
              remainingPiasters: 1000,
              durationMonths: 5,
              startDate: now,
              endDate: now.add(const Duration(days: 150)),
              status: const Value('active'),
              createdBy: 'user-1',
              createdAt: now,
              updatedAt: now,
            ),
          );

      await db
          .into(db.installmentPayments)
          .insert(
            InstallmentPaymentsCompanion.insert(
              id: 'pay-1',
              branchId: branch,
              customerInstallmentId: 'ci-1',
              amountPiasters: 200,
              paymentMethod: 'cash',
              paidAt: now,
              recordedBy: 'user-1',
              createdAt: now,
              updatedAt: now,
            ),
          );

      await expectLater(
        () => db
            .into(db.installmentPlans)
            .insert(
              InstallmentPlansCompanion.insert(
                id: 'bad-plan',
                branchId: branch,
                name: 'Bad',
                durationMonths: 0,
                createdAt: now,
                updatedAt: now,
              ),
            ),
        throwsA(anything),
      );

      await expectLater(
        () => db
            .into(db.installmentPayments)
            .insert(
              InstallmentPaymentsCompanion.insert(
                id: 'bad-pay',
                branchId: branch,
                customerInstallmentId: 'ci-1',
                amountPiasters: 0,
                paymentMethod: 'cash',
                paidAt: now,
                recordedBy: 'u',
                createdAt: now,
                updatedAt: now,
              ),
            ),
        throwsA(anything),
      );

      await expectLater(
        () => db
            .into(db.installmentPayments)
            .insert(
              InstallmentPaymentsCompanion.insert(
                id: 'bad-method',
                branchId: branch,
                customerInstallmentId: 'ci-1',
                amountPiasters: 10,
                paymentMethod: 'installment',
                paidAt: now,
                recordedBy: 'u',
                createdAt: now,
                updatedAt: now,
              ),
            ),
        throwsA(anything),
      );

      await expectLater(
        () => db
            .into(db.customerInstallments)
            .insert(
              CustomerInstallmentsCompanion.insert(
                id: 'bad-ci',
                branchId: branch,
                saleId: 's',
                customerId: 'c',
                totalPiasters: 1000,
                downPaymentPiasters: const Value(100),
                principalPiasters: 950,
                interestBp: 0,
                monthlyAmountPiasters: 100,
                remainingPiasters: 950,
                durationMonths: 10,
                startDate: now,
                endDate: now,
                status: const Value('active'),
                createdBy: 'u',
                createdAt: now,
                updatedAt: now,
              ),
            ),
        throwsA(anything),
      );
      await db.close();
    });

    test(
      'v4->v5 migration idempotent (onUpgrade twice does not error)',
      () async {
        final executor = NativeDatabase.memory();
        final db = AppDatabase(executor);
        await db.customSelect('SELECT 1').getSingle();
        final m = Migrator(db);
        await db.migration.onUpgrade(m, 4, 5);
        await db.migration.onUpgrade(m, 4, 5);
        final tables = await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('installment_plans','customer_installments','installment_payments')",
            )
            .get();
        expect(tables.length, 3);
        await db.close();
      },
    );

    test('v5 -> v5 open does not trigger onUpgrade', () async {
      final file = File(
        '${Directory.systemTemp.path}/installments_v5_${DateTime.now().microsecondsSinceEpoch}.db',
      );
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });
      final db1 = AppDatabase(NativeDatabase(file));
      expect(db1.schemaVersion, 12);
      await db1.customSelect('SELECT 1').getSingle();
      await db1.close();

      final db2 = AppDatabase(NativeDatabase(file));
      expect(db2.schemaVersion, 12);
      await db2.customSelect('SELECT 1').getSingle();
      final tables = await db2
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('installment_plans','customer_installments','installment_payments')",
          )
          .get();
      expect(tables.length, 3);
      final m = Migrator(db2);
      await db2.migration.onUpgrade(m, 5, 5);
      await db2.close();
    });
  });
}
