import 'package:drift/drift.dart';

class PromotionTargets extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get promotionId => text()();
  TextColumn get targetType => text()(); // 'product' | 'category'
  TextColumn get targetId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK (target_type IN ('product', 'category'))",
      ];
}

