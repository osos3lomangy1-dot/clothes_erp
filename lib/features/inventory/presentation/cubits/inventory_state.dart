import 'package:equatable/equatable.dart';
import '../../../product_variants/domain/entities/variant_entity.dart';

abstract class InventoryState extends Equatable {
  const InventoryState();

  @override
  List<Object?> get props => [];
}

class InventoryInitial extends InventoryState {}

class InventoryLoading extends InventoryState {}

class InventoryLoaded extends InventoryState {
  final List<VariantEntity> items;
  final bool showLowStockOnly;

  const InventoryLoaded(this.items, {this.showLowStockOnly = false});

  @override
  List<Object?> get props => [items, showLowStockOnly];
}

class InventoryError extends InventoryState {
  final String message;

  const InventoryError(this.message);

  @override
  List<Object?> get props => [message];
}
