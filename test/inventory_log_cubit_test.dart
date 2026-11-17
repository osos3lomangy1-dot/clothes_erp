import 'package:clothes_erp/core/errors/failures.dart';
import 'package:clothes_erp/features/inventory/domain/entities/inventory_log_entity.dart';
import 'package:clothes_erp/features/inventory/domain/repositories/inventory_log_repository.dart';
import 'package:clothes_erp/features/inventory/presentation/cubits/inventory_log_cubit.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

class MockInventoryLogRepository implements InventoryLogRepository {
  List<InventoryLogEntity> mockLogs = [];
  Failure? failure;

  @override
  Future<Either<Failure, List<InventoryLogEntity>>> getLogs() async {
    if (failure != null) {
      return Left(failure!);
    }
    return Right(mockLogs);
  }
}

void main() {
  late MockInventoryLogRepository mockRepo;
  late InventoryLogCubit cubit;

  final sampleLogs = [
    InventoryLogEntity(
      id: '1',
      productId: 'p1',
      variantId: 'v1',
      productName: 'تيشيرت بولو كلاسيك',
      variantSize: 'L',
      variantColor: 'أسود',
      userName: 'أحمد محمود',
      type: 'receive',
      quantity: 10,
      date: DateTime(2026, 1, 1),
      userId: 'u1',
    ),
    InventoryLogEntity(
      id: '2',
      productId: 'p2',
      variantId: 'v2',
      productName: 'بنطلون جينز سليم',
      variantSize: '32',
      variantColor: 'أزرق',
      userName: 'سارة علي',
      type: 'sale',
      quantity: 2,
      date: DateTime(2026, 1, 2),
      userId: 'u2',
    ),
    InventoryLogEntity(
      id: '3',
      productId: 'p3',
      variantId: 'v3',
      productName: 'فستان صيفي مشجر',
      variantSize: 'M',
      variantColor: 'أحمر',
      userName: 'أحمد محمود',
      type: 'return',
      quantity: 1,
      date: DateTime(2026, 1, 3),
      userId: 'u1',
    ),
  ];

  setUp(() {
    mockRepo = MockInventoryLogRepository();
    mockRepo.mockLogs = sampleLogs;
  });

  tearDown(() {
    cubit.close();
  });

  test('5. InventoryLogCubit loads logs automatically and emits success state', () async {
    cubit = InventoryLogCubit(mockRepo);
    await Future.delayed(const Duration(milliseconds: 50));

    expect(cubit.state.status, InventoryLogStatus.success);
    expect(cubit.state.allLogs.length, 3);
    expect(cubit.state.logs.length, 3);
  });

  test('6. InventoryLogCubit onSearchChanged filters logs by product, size, or user with debounce', () async {
    cubit = InventoryLogCubit(mockRepo);
    await Future.delayed(const Duration(milliseconds: 50));

    // Search by product name
    cubit.onSearchChanged('جينز');
    await Future.delayed(const Duration(milliseconds: 350)); // wait for 300ms debounce
    expect(cubit.state.logs.length, 1);
    expect(cubit.state.logs.first.productName, 'بنطلون جينز سليم');

    // Search by user name
    cubit.onSearchChanged('أحمد');
    await Future.delayed(const Duration(milliseconds: 350));
    expect(cubit.state.logs.length, 2);

    // Search by size
    cubit.onSearchChanged('M');
    await Future.delayed(const Duration(milliseconds: 350));
    expect(cubit.state.logs.length, 1);
    expect(cubit.state.logs.first.variantSize, 'M');
  });

  test('7. InventoryLogCubit onTypeFilterChanged filters logs by movement type', () async {
    cubit = InventoryLogCubit(mockRepo);
    await Future.delayed(const Duration(milliseconds: 50));

    // Filter 'sale'
    cubit.onTypeFilterChanged('sale');
    expect(cubit.state.logs.length, 1);
    expect(cubit.state.logs.first.type, 'sale');

    // Filter 'in' (matches 'receive' and 'return')
    cubit.onTypeFilterChanged('in');
    expect(cubit.state.logs.length, 2);

    // Filter 'out' (matches 'sale')
    cubit.onTypeFilterChanged('out');
    expect(cubit.state.logs.length, 1);

    // Filter 'all'
    cubit.onTypeFilterChanged('all');
    expect(cubit.state.logs.length, 3);
  });

  test('8. InventoryLogCubit matches return_ and purchase_return under return, in, and out filters', () async {
    mockRepo.mockLogs = [
      ...sampleLogs,
      InventoryLogEntity(
        id: '4',
        productId: 'p4',
        variantId: 'v4',
        productName: 'قميص كتان',
        variantSize: 'XL',
        variantColor: 'بيج',
        userName: 'أحمد محمود',
        type: 'return_',
        quantity: 2,
        date: DateTime(2026, 1, 4),
        userId: 'u1',
      ),
      InventoryLogEntity(
        id: '5',
        productId: 'p5',
        variantId: 'v5',
        productName: 'جاكيت جلد',
        variantSize: 'L',
        variantColor: 'بني',
        userName: 'أحمد محمود',
        type: 'purchase_return',
        quantity: 1,
        date: DateTime(2026, 1, 5),
        userId: 'u1',
      ),
    ];

    cubit = InventoryLogCubit(mockRepo);
    await Future.delayed(const Duration(milliseconds: 50));

    // 'return' filter matches return, return_, and purchase_return
    cubit.onTypeFilterChanged('return');
    expect(cubit.state.logs.length, 3);
    expect(cubit.state.logs.map((l) => l.type), containsAll(['return', 'return_', 'purchase_return']));

    // 'in' filter includes receive, return, return_
    cubit.onTypeFilterChanged('in');
    expect(cubit.state.logs.length, 3);

    // 'out' filter includes sale and purchase_return
    cubit.onTypeFilterChanged('out');
    expect(cubit.state.logs.length, 2);
  });
}

