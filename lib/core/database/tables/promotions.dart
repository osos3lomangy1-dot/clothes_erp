import 'package:drift/drift.dart';

class Promotions extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get type => text()(); // 'percent' | 'fixed'
  TextColumn get scope => text()(); // 'product' | 'category' | 'all'
  TextColumn get targetId => text().nullable()();
  IntColumn get valueBp => integer().nullable()(); // basis points (1000 = 10%)
  IntColumn get valuePiasters => integer().nullable()(); // per-piece fixed
  IntColumn get minQuantity => integer().withDefault(const Constant(1))();
  DateTimeColumn get startsAt => dateTime()();
  DateTimeColumn get endsAt => dateTime()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK (ends_at > starts_at)",
        "CHECK (("
            "(type = 'percent' AND value_bp IS NOT NULL AND value_bp > 0 AND value_bp <= 10000 AND value_piasters IS NULL) "
            "OR (type = 'fixed' AND value_piasters IS NOT NULL AND value_piasters > 0 AND value_bp IS NULL)"
            "))",
        "CHECK (min_quantity >= 1)",
        "CHECK (scope IN ('product', 'category', 'all'))",
        "CHECK (type IN ('percent', 'fixed'))",
        "CHECK ((scope = 'all') OR (target_id IS NOT NULL))",
      ];
}

class PromotionApplications extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get promotionId => text()();
  TextColumn get saleId => text()();
  TextColumn get saleItemId => text()();
  IntColumn get discountPiasters => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK (discount_piasters > 0)",
      ];
}
