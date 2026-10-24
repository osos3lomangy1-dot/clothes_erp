import 'package:equatable/equatable.dart';
import '../../domain/entities/variant_entity.dart';

abstract class VariantState extends Equatable {
  const VariantState();

  @override
  List<Object?> get props => [];
}

class VariantInitial extends VariantState {}

class VariantLoading extends VariantState {}

class VariantLoaded extends VariantState {
  final List<VariantEntity> variants;

  const VariantLoaded(this.variants);

  @override
  List<Object?> get props => [variants];
}

class VariantEmpty extends VariantState {}

class VariantError extends VariantState {
  final String message;

  const VariantError(this.message);

  @override
  List<Object?> get props => [message];
}
